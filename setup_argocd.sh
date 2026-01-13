#!/bin/bash
################################################################################
# The Resilience Pilot - ArgoCD GitOps Setup
#
# Deploys ArgoCD and configures it to manage the resilience-pilot application.
# Enables automatic synchronization with self-healing.
#
# GitOps Concepts:
# - Single source of truth: Git repository contains desired state
# - Automatic sync: Changes in Git trigger deployments
# - Self-heal: Drift from Git state is automatically corrected
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="argocd"
ARGOCD_VERSION="v2.9.3"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Is k3d running?"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# ============================================================================
# NAMESPACE CREATION
# ============================================================================
create_namespace() {
    log_info "Creating ArgoCD namespace..."
    
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Namespace '${NAMESPACE}' ready"
}

# ============================================================================
# DEPLOY ARGOCD
# ============================================================================
deploy_argocd() {
    log_info "Deploying ArgoCD ${ARGOCD_VERSION}..."
    
    # Install ArgoCD using the official manifest
    kubectl apply -n ${NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=available deployment/argocd-server -n ${NAMESPACE} --timeout=300s
    
    log_success "ArgoCD deployed successfully"
}

# ============================================================================
# CREATE APPLICATION MANIFEST
# ============================================================================
create_application() {
    log_info "Creating ArgoCD Application for resilience-pilot..."
    
    # Get the repository URL from git remote (or use placeholder)
    REPO_URL=$(git remote get-url origin 2>/dev/null || echo "https://github.com/YOUR_USERNAME/k8s-resilience-pilot.git")
    
    cat << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: resilience-pilot
  namespace: ${NAMESPACE}
  # Finalizer ensures resources are cleaned up when app is deleted
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  # Project assignment
  project: default
  
  # Source repository configuration
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: manifests
  
  # Destination cluster and namespace
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  
  # Sync policy configuration
  syncPolicy:
    # ========================================================================
    # AUTOMATED SYNC
    # ArgoCD will automatically sync when Git changes are detected
    # ========================================================================
    automated:
      # Prune: Delete resources that are no longer in Git
      prune: true
      # Self-heal: Revert manual changes made to cluster resources
      selfHeal: true
      # Allow empty: Sync even if there are no resources
      allowEmpty: false
    
    # Sync options
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    
    # Retry configuration
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
    
    log_success "ArgoCD Application created"
}

# ============================================================================
# GET INITIAL ADMIN PASSWORD
# ============================================================================
get_admin_password() {
    log_info "Retrieving initial admin password..."
    
    # Wait for the secret to be created
    sleep 5
    
    ADMIN_PASSWORD=$(kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Unable to retrieve password")
    
    echo "${ADMIN_PASSWORD}"
}

# ============================================================================
# PRINT ACCESS INFORMATION
# ============================================================================
print_access_info() {
    ADMIN_PASSWORD=$(get_admin_password)
    
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}🎉 ArgoCD Deployed Successfully!${NC}"
    echo "============================================================================"
    echo ""
    echo -e "${BLUE}ArgoCD UI Access:${NC}"
    echo "  URL:      https://localhost:8443"
    echo "  Username: admin"
    echo "  Password: ${ADMIN_PASSWORD}"
    echo ""
    echo "  Port-forward command:"
    echo "  kubectl port-forward svc/argocd-server 8443:443 -n ${NAMESPACE}"
    echo ""
    echo -e "${BLUE}ArgoCD CLI Login:${NC}"
    echo "  argocd login localhost:8443 --username admin --password '${ADMIN_PASSWORD}' --insecure"
    echo ""
    echo -e "${YELLOW}Note:${NC} The password shown above is the initial admin password."
    echo "      It's recommended to change it after first login."
    echo ""
    echo -e "${BLUE}Application Status:${NC}"
    echo "  kubectl get applications -n ${NAMESPACE}"
    echo ""
    echo "============================================================================"
    echo -e "${BLUE}GitOps Workflow:${NC}"
    echo ""
    echo "  1. Make changes to manifests/ directory"
    echo "  2. Commit and push to Git"
    echo "  3. ArgoCD automatically detects changes"
    echo "  4. ArgoCD syncs cluster state to match Git"
    echo "  5. Self-heal reverts any manual cluster changes"
    echo ""
    echo "============================================================================"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo ""
    echo "============================================================================"
    echo "  The Resilience Pilot - ArgoCD GitOps Setup"
    echo "============================================================================"
    echo ""
    
    check_prerequisites
    create_namespace
    deploy_argocd
    create_application
    print_access_info
}

main "$@"
