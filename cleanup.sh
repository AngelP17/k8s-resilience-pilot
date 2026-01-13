#!/bin/bash
################################################################################
# The Resilience Pilot - Cleanup Script
#
# Tears down the entire environment, removing:
# - k3d cluster (via Terraform)
# - Any orphaned Docker resources
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# CONFIRMATION
# ============================================================================
confirm_cleanup() {
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will destroy the entire Resilience Pilot environment!${NC}"
    echo ""
    echo "The following will be deleted:"
    echo "  - k3d cluster 'resilience-pilot'"
    echo "  - All Kubernetes resources"
    echo "  - Terraform state"
    echo ""
    
    if [[ "${FORCE:-false}" != "true" ]]; then
        read -p "Are you sure you want to continue? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
}

# ============================================================================
# TERRAFORM DESTROY
# ============================================================================
terraform_destroy() {
    log_info "Destroying k3d cluster via Terraform..."
    
    if [[ -d "${SCRIPT_DIR}/terraform" ]]; then
        cd "${SCRIPT_DIR}/terraform"
        
        if [[ -f "terraform.tfstate" ]] || [[ -d ".terraform" ]]; then
            terraform destroy -auto-approve || true
        else
            log_warn "No Terraform state found, skipping Terraform destroy"
        fi
        
        cd "${SCRIPT_DIR}"
    fi
}

# ============================================================================
# K3D CLUSTER DELETE (Fallback)
# ============================================================================
k3d_delete() {
    log_info "Ensuring k3d cluster is deleted..."
    
    if command -v k3d &> /dev/null; then
        if k3d cluster list 2>/dev/null | grep -q "resilience-pilot"; then
            k3d cluster delete resilience-pilot || true
        fi
    fi
}

# ============================================================================
# CLEANUP DOCKER RESOURCES
# ============================================================================
cleanup_docker() {
    log_info "Cleaning up Docker resources..."
    
    # Remove resilience-pilot images
    docker images --filter "reference=resilience-pilot*" -q | xargs -r docker rmi -f 2>/dev/null || true
    
    # Remove dangling images (optional, commented out by default)
    # docker image prune -f 2>/dev/null || true
    
    log_success "Docker cleanup complete"
}

# ============================================================================
# CLEANUP TERRAFORM FILES
# ============================================================================
cleanup_terraform_files() {
    log_info "Cleaning up Terraform files..."
    
    if [[ -d "${SCRIPT_DIR}/terraform" ]]; then
        cd "${SCRIPT_DIR}/terraform"
        rm -rf .terraform terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl 2>/dev/null || true
        cd "${SCRIPT_DIR}"
    fi
    
    log_success "Terraform files cleaned"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -f, --force   Skip confirmation prompt"
                echo "  -h, --help    Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "============================================================================"
    echo "  The Resilience Pilot - Environment Cleanup"
    echo "============================================================================"
    
    confirm_cleanup
    terraform_destroy
    k3d_delete
    cleanup_docker
    cleanup_terraform_files
    
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}✅ Cleanup complete!${NC}"
    echo "============================================================================"
    echo ""
    echo "To recreate the environment, run: ./setup.sh"
    echo ""
}

main "$@"
