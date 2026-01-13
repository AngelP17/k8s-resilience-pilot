#!/bin/bash
################################################################################
# The Resilience Pilot - Master Setup Script
#
# Orchestrates the complete environment setup:
# 1. Prerequisites check
# 2. Terraform k3d cluster provisioning
# 3. Docker image build and import
# 4. Application deployment
# 5. Monitoring stack deployment
# 6. ArgoCD GitOps deployment
# 7. Smoke tests
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# ============================================================================
# BANNER
# ============================================================================
print_banner() {
    echo ""
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║   ████████╗██╗  ██╗███████╗    ██████╗ ███████╗███████╗██╗██╗         ║"
    echo "║      ██╔══╝██║  ██║██╔════╝    ██╔══██╗██╔════╝██╔════╝██║██║         ║"
    echo "║      ██║   ███████║█████╗      ██████╔╝█████╗  ███████╗██║██║         ║"
    echo "║      ██║   ██╔══██║██╔══╝      ██╔══██╗██╔══╝  ╚════██║██║██║         ║"
    echo "║      ██║   ██║  ██║███████╗    ██║  ██║███████╗███████║██║███████╗    ║"
    echo "║      ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝╚══════╝    ║"
    echo "║                                                                       ║"
    echo "║               ██╗     ██╗███████╗███╗   ██╗ ██████╗███████╗           ║"
    echo "║               ██║     ██║██╔════╝████╗  ██║██╔════╝██╔════╝           ║"
    echo "║               ██║     ██║█████╗  ██╔██╗ ██║██║     █████╗             ║"
    echo "║               ██║     ██║██╔══╝  ██║╚██╗██║██║     ██╔══╝             ║"
    echo "║               ███████╗██║███████╗██║ ╚████║╚██████╗███████╗           ║"
    echo "║               ╚══════╝╚═╝╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝           ║"
    echo "║                                                                       ║"
    echo "║           Production-Grade SRE Lab with Self-Healing K8s              ║"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing=()
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    elif ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing+=("terraform (brew install terraform)")
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing+=("kubectl (brew install kubectl)")
    fi
    
    # Check Helm
    if ! command -v helm &> /dev/null; then
        missing+=("helm (brew install helm)")
    fi
    
    # Check k3d
    if ! command -v k3d &> /dev/null; then
        missing+=("k3d (brew install k3d)")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools:"
        for tool in "${missing[@]}"; do
            echo "  - ${tool}"
        done
        echo ""
        log_info "Install missing tools and re-run this script."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# ============================================================================
# TERRAFORM CLUSTER PROVISIONING
# ============================================================================
provision_cluster() {
    log_step "Provisioning k3d cluster with Terraform..."
    
    cd "${SCRIPT_DIR}/terraform"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init -upgrade
    
    # Apply configuration
    log_info "Creating k3d cluster (this may take a few minutes)..."
    terraform apply -auto-approve
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster nodes to be ready..."
    sleep 10
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
    
    cd "${SCRIPT_DIR}"
    log_success "k3d cluster provisioned"
}

# ============================================================================
# BUILD AND IMPORT DOCKER IMAGE
# ============================================================================
build_and_import_image() {
    log_step "Building and importing Docker image..."
    
    cd "${SCRIPT_DIR}/app"
    
    # Build the Docker image
    log_info "Building Docker image..."
    docker build -t resilience-pilot:latest .
    
    # Import into k3d cluster
    log_info "Importing image into k3d cluster..."
    k3d image import resilience-pilot:latest -c resilience-pilot
    
    cd "${SCRIPT_DIR}"
    log_success "Docker image built and imported"
}

# ============================================================================
# DEPLOY APPLICATION
# ============================================================================
deploy_application() {
    log_step "Deploying application to Kubernetes..."
    
    # Apply manifests
    kubectl apply -f "${SCRIPT_DIR}/manifests/"
    
    # Wait for deployment to be ready
    log_info "Waiting for pods to be ready..."
    kubectl wait --for=condition=available deployment/resilience-pilot --timeout=120s
    
    log_success "Application deployed"
}

# ============================================================================
# DEPLOY MONITORING STACK
# ============================================================================
deploy_monitoring() {
    log_step "Deploying monitoring stack (Prometheus + Grafana)..."
    
    chmod +x "${SCRIPT_DIR}/setup_monitoring.sh"
    "${SCRIPT_DIR}/setup_monitoring.sh"
    
    log_success "Monitoring stack deployed"
}

# ============================================================================
# DEPLOY ARGOCD
# ============================================================================
deploy_argocd() {
    log_step "Deploying ArgoCD GitOps..."
    
    chmod +x "${SCRIPT_DIR}/setup_argocd.sh"
    "${SCRIPT_DIR}/setup_argocd.sh"
    
    log_success "ArgoCD deployed"
}

# ============================================================================
# RUN SMOKE TESTS
# ============================================================================
run_smoke_tests() {
    log_step "Running smoke tests..."
    
    chmod +x "${SCRIPT_DIR}/test_deployment.sh"
    "${SCRIPT_DIR}/test_deployment.sh"
    
    log_success "Smoke tests passed"
}

# ============================================================================
# PRINT SUMMARY
# ============================================================================
print_summary() {
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}🎉 THE RESILIENCE PILOT IS READY!${NC}"
    echo "============================================================================"
    echo ""
    echo -e "${BLUE}Application Access:${NC}"
    echo "  Health Check:  http://localhost:8080/health"
    echo "  Metrics:       http://localhost:8080/metrics"
    echo "  Chaos Inject:  curl -X POST http://localhost:8080/simulate-crash"
    echo ""
    echo -e "${BLUE}Monitoring:${NC}"
    echo "  Grafana:       kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring"
    echo "                 → http://localhost:3000 (admin/admin)"
    echo "  Prometheus:    kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring"
    echo "                 → http://localhost:9090"
    echo ""
    echo -e "${BLUE}GitOps:${NC}"
    echo "  ArgoCD:        kubectl port-forward svc/argocd-server 8443:443 -n argocd"
    echo "                 → https://localhost:8443"
    echo ""
    echo -e "${BLUE}Demo Commands:${NC}"
    echo "  Chaos Monkey:  ./chaos_monkey.sh"
    echo "  Cleanup:       ./cleanup.sh"
    echo ""
    echo "============================================================================"
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Open Grafana and view the 'Resilience Pilot' dashboard"
    echo "  2. Run ./chaos_monkey.sh to see self-healing in action"
    echo "  3. Watch the Grafana dashboard update in real-time"
    echo "============================================================================"
    echo ""
}

# ============================================================================
# QUICK MODE (Skip optional components)
# ============================================================================
quick_setup() {
    print_banner
    check_prerequisites
    provision_cluster
    build_and_import_image
    deploy_application
    run_smoke_tests
    
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}Quick setup complete!${NC}"
    echo "============================================================================"
    echo ""
    echo "To complete the full setup, run:"
    echo "  ./setup_monitoring.sh   # Add Prometheus & Grafana"
    echo "  ./setup_argocd.sh       # Add GitOps with ArgoCD"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    local quick=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quick)
                quick=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -q, --quick   Quick setup (skip monitoring and ArgoCD)"
                echo "  -h, --help    Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ "${quick}" == "true" ]]; then
        quick_setup
    else
        print_banner
        check_prerequisites
        provision_cluster
        build_and_import_image
        deploy_application
        deploy_monitoring
        deploy_argocd
        run_smoke_tests
        print_summary
    fi
}

main "$@"
