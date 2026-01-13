#!/bin/bash
################################################################################
# The Resilience Pilot - Monitoring Stack Setup
#
# Deploys Prometheus and Grafana using the kube-prometheus-stack Helm chart.
# Includes pre-configured dashboards and alerting rules.
#
# SRE Concepts:
# - Golden signals monitoring (Latency, Traffic, Errors, Saturation)
# - Pre-built dashboards for immediate visibility
# - Alert rules for proactive incident detection
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="monitoring"
RELEASE_NAME="prometheus"
CHART_VERSION="55.5.0"  # kube-prometheus-stack version

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
    
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed. Please install Helm first."
        log_info "Install with: brew install helm"
        exit 1
    fi
    
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
# HELM REPOSITORY SETUP
# ============================================================================
setup_helm_repo() {
    log_info "Adding Prometheus community Helm repository..."
    
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update
    
    log_success "Helm repository ready"
}

# ============================================================================
# NAMESPACE CREATION
# ============================================================================
create_namespace() {
    log_info "Creating monitoring namespace..."
    
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Namespace '${NAMESPACE}' ready"
}

# ============================================================================
# DEPLOY KUBE-PROMETHEUS-STACK
# ============================================================================
deploy_prometheus_stack() {
    log_info "Deploying kube-prometheus-stack (Prometheus + Grafana)..."
    
    # Create values file for custom configuration
    cat > /tmp/prometheus-values.yaml << 'EOF'
# Grafana configuration
grafana:
  enabled: true
  adminPassword: admin
  
  # Default dashboards
  defaultDashboardsEnabled: true
  defaultDashboardsTimezone: browser
  
  # Persistence (optional for demo)
  persistence:
    enabled: false
  
  # Ingress for Grafana (optional)
  ingress:
    enabled: false
  
  # Sidecar for dashboard provisioning
  sidecar:
    dashboards:
      enabled: true
      searchNamespace: ALL
      label: grafana_dashboard
      folderAnnotation: grafana_folder
      provider:
        foldersFromFilesStructure: true

# Prometheus configuration
prometheus:
  prometheusSpec:
    # Resource limits for k3d
    resources:
      requests:
        memory: 400Mi
        cpu: 200m
      limits:
        memory: 1Gi
        cpu: 500m
    
    # Retention
    retention: 24h
    
    # Service monitor selectors
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    
    # Additional scrape configs for our app
    additionalScrapeConfigs:
      - job_name: 'resilience-pilot'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_label_app]
            regex: resilience-pilot
            action: keep
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            regex: "true"
            action: keep
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__

# Alertmanager configuration
alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: 50Mi
        cpu: 50m
      limits:
        memory: 100Mi
        cpu: 100m

# Disable components not needed for demo
kubeStateMetrics:
  enabled: true
nodeExporter:
  enabled: true
kubeApiServer:
  enabled: true
kubelet:
  enabled: true
kubeControllerManager:
  enabled: false  # Not exposed in k3d
kubeScheduler:
  enabled: false  # Not exposed in k3d
kubeProxy:
  enabled: false  # Not exposed in k3d
kubeEtcd:
  enabled: false  # Not exposed in k3d
EOF
    
    # Install or upgrade the stack
    helm upgrade --install ${RELEASE_NAME} prometheus-community/kube-prometheus-stack \
        --namespace ${NAMESPACE} \
        --version ${CHART_VERSION} \
        --values /tmp/prometheus-values.yaml \
        --wait \
        --timeout 10m
    
    log_success "kube-prometheus-stack deployed"
}

# ============================================================================
# DEPLOY CUSTOM DASHBOARD
# ============================================================================
deploy_custom_dashboard() {
    log_info "Deploying custom Grafana dashboard..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ -f "${SCRIPT_DIR}/monitoring/grafana-dashboard.json" ]]; then
        # Create ConfigMap for the dashboard
        kubectl create configmap resilience-pilot-dashboard \
            --from-file=resilience-pilot.json="${SCRIPT_DIR}/monitoring/grafana-dashboard.json" \
            --namespace ${NAMESPACE} \
            --dry-run=client -o yaml | \
            kubectl label --local -f - grafana_dashboard=1 -o yaml | \
            kubectl apply -f -
        
        log_success "Custom dashboard deployed"
    else
        log_warn "Dashboard file not found at ${SCRIPT_DIR}/monitoring/grafana-dashboard.json"
    fi
}

# ============================================================================
# DEPLOY ALERTING RULES
# ============================================================================
deploy_alerting_rules() {
    log_info "Deploying alerting rules..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ -f "${SCRIPT_DIR}/monitoring/prometheus-rules.yaml" ]]; then
        kubectl apply -f "${SCRIPT_DIR}/monitoring/prometheus-rules.yaml"
        log_success "Alerting rules deployed"
    else
        log_warn "Alerting rules file not found"
    fi
}

# ============================================================================
# PRINT ACCESS INFORMATION
# ============================================================================
print_access_info() {
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}🎉 Monitoring Stack Deployed Successfully!${NC}"
    echo "============================================================================"
    echo ""
    echo -e "${BLUE}Grafana Access:${NC}"
    echo "  URL:      http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin"
    echo ""
    echo "  Port-forward command:"
    echo "  kubectl port-forward svc/prometheus-grafana 3000:80 -n ${NAMESPACE}"
    echo ""
    echo -e "${BLUE}Prometheus Access:${NC}"
    echo "  URL:      http://localhost:9090"
    echo ""
    echo "  Port-forward command:"
    echo "  kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n ${NAMESPACE}"
    echo ""
    echo -e "${BLUE}Alertmanager Access:${NC}"
    echo "  URL:      http://localhost:9093"
    echo ""
    echo "  Port-forward command:"
    echo "  kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n ${NAMESPACE}"
    echo ""
    echo "============================================================================"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo ""
    echo "============================================================================"
    echo "  The Resilience Pilot - Monitoring Stack Setup"
    echo "============================================================================"
    echo ""
    
    check_prerequisites
    setup_helm_repo
    create_namespace
    deploy_prometheus_stack
    deploy_custom_dashboard
    deploy_alerting_rules
    print_access_info
}

main "$@"
