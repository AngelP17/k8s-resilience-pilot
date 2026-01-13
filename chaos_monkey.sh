#!/bin/bash
################################################################################
# The Resilience Pilot - Chaos Monkey Script
#
# Demonstrates Kubernetes self-healing by randomly killing pods and measuring
# Mean Time To Recovery (MTTR).
#
# Chaos Engineering Principles:
# - Start with a hypothesis: Kubernetes will recover within SLO (30s)
# - Minimize blast radius: Only affect one pod at a time
# - Measure impact: Track recovery time for each experiment
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-resilience-pilot}"
NAMESPACE="${NAMESPACE:-default}"
SLO_RECOVERY_SECONDS=30

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_chaos() { echo -e "${MAGENTA}[CHAOS]${NC} $1"; }

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if deployment exists
    if ! kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} &> /dev/null; then
        log_error "Deployment '${DEPLOYMENT_NAME}' not found in namespace '${NAMESPACE}'"
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# ============================================================================
# GET RANDOM POD
# ============================================================================
get_random_pod() {
    local pods=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [[ -z "${pods}" ]]; then
        log_error "No pods found for deployment '${DEPLOYMENT_NAME}'"
        exit 1
    fi
    
    # Convert to array and select random
    local pod_array=(${pods})
    local count=${#pod_array[@]}
    local random_index=$((RANDOM % count))
    
    echo "${pod_array[${random_index}]}"
}

# ============================================================================
# GET POD COUNT
# ============================================================================
get_ready_pod_count() {
    kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | \
        wc -w | tr -d ' '
}

# ============================================================================
# WAIT FOR RECOVERY
# ============================================================================
wait_for_recovery() {
    local expected_count=$1
    local start_time=$(date +%s)
    local timeout=120  # Maximum wait time in seconds
    
    log_info "Waiting for recovery (expecting ${expected_count} running pods)..."
    
    while true; do
        local current_count=$(get_ready_pod_count)
        local elapsed=$(($(date +%s) - start_time))
        
        echo -ne "\r  ⏳ Running pods: ${current_count}/${expected_count} | Elapsed: ${elapsed}s   "
        
        if [[ "${current_count}" -ge "${expected_count}" ]]; then
            # Verify all pods are actually ready by counting "True" values
            # The jsonpath returns space-separated values like "True True True"
            local ready_statuses=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} \
                -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
            local all_ready=$(echo "${ready_statuses}" | tr ' ' '\n' | grep -c "True" 2>/dev/null || echo "0")
            
            if [[ "${all_ready}" -ge "${expected_count}" ]]; then
                echo ""  # Newline after the progress
                return ${elapsed}
            fi
        fi
        
        if [[ ${elapsed} -gt ${timeout} ]]; then
            echo ""
            log_error "Timeout waiting for recovery after ${timeout}s"
            return ${timeout}
        fi
        
        sleep 1
    done
}

# ============================================================================
# INJECT CHAOS
# ============================================================================
inject_chaos() {
    echo ""
    echo "============================================================================"
    echo -e "${MAGENTA}  🐒 CHAOS MONKEY - Kubernetes Self-Healing Demo${NC}"
    echo "============================================================================"
    echo ""
    
    # Get initial state
    local initial_count=$(get_ready_pod_count)
    log_info "Initial state: ${initial_count} running pods"
    
    # Select a random victim
    local victim_pod=$(get_random_pod)
    log_chaos "🎯 Selected victim: ${victim_pod}"
    
    # Record start time
    local start_time=$(date +%s)
    
    # Kill the pod
    echo ""
    log_chaos "💥 Terminating pod: ${victim_pod}"
    kubectl delete pod ${victim_pod} -n ${NAMESPACE} --grace-period=0 --force 2>/dev/null
    
    echo ""
    
    # Wait for recovery
    wait_for_recovery ${initial_count}
    local recovery_time=$?
    
    # Report results
    echo ""
    echo "============================================================================"
    echo -e "${GREEN}  📊 CHAOS EXPERIMENT RESULTS${NC}"
    echo "============================================================================"
    echo ""
    echo -e "  ${BLUE}Victim Pod:${NC}        ${victim_pod}"
    echo -e "  ${BLUE}Recovery Time:${NC}     ${recovery_time} seconds"
    echo -e "  ${BLUE}SLO Target:${NC}        < ${SLO_RECOVERY_SECONDS} seconds"
    echo ""
    
    if [[ ${recovery_time} -le ${SLO_RECOVERY_SECONDS} ]]; then
        echo -e "  ${GREEN}✅ SLO MET: MTTR (${recovery_time}s) ≤ Target (${SLO_RECOVERY_SECONDS}s)${NC}"
        echo ""
        echo -e "  ${GREEN}🎉 Self-healing successful! Kubernetes automatically replaced"
        echo -e "     the terminated pod and restored service availability.${NC}"
    else
        echo -e "  ${RED}❌ SLO BREACHED: MTTR (${recovery_time}s) > Target (${SLO_RECOVERY_SECONDS}s)${NC}"
        echo ""
        echo -e "  ${YELLOW}⚠️  Recovery took longer than expected. Investigate potential issues"
        echo -e "     with resource constraints, image pull times, or probe settings.${NC}"
    fi
    
    echo ""
    echo "============================================================================"
    echo ""
    
    # Print current state
    log_info "Current pod state:"
    kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o wide
    echo ""
}

# ============================================================================
# CONTINUOUS CHAOS MODE
# ============================================================================
continuous_chaos() {
    local interval=${1:-60}
    local count=0
    
    echo ""
    log_warn "Starting continuous chaos mode (interval: ${interval}s)"
    log_warn "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        count=$((count + 1))
        echo ""
        echo "═══════════════════════════════════════════════════════════════════════════"
        echo -e "${MAGENTA}  CHAOS ITERATION #${count}${NC}"
        echo "═══════════════════════════════════════════════════════════════════════════"
        
        inject_chaos
        
        log_info "Waiting ${interval}s before next chaos injection..."
        sleep ${interval}
    done
}

# ============================================================================
# HELP
# ============================================================================
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --continuous [SEC]  Run continuously with interval (default: 60s)"
    echo "  -d, --deployment NAME   Target deployment (default: resilience-pilot)"
    echo "  -n, --namespace NS      Target namespace (default: default)"
    echo ""
    echo "Examples:"
    echo "  $0                      # Single chaos injection"
    echo "  $0 -c 30                # Continuous mode, 30s interval"
    echo "  $0 -d my-app -n prod    # Target specific deployment"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    local continuous=false
    local interval=60
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--continuous)
                continuous=true
                if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                    interval=$2
                    shift
                fi
                shift
                ;;
            -d|--deployment)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    
    if [[ "${continuous}" == "true" ]]; then
        continuous_chaos ${interval}
    else
        inject_chaos
    fi
}

main "$@"
