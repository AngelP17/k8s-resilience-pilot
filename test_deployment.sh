#!/bin/bash
################################################################################
# The Resilience Pilot - Deployment Smoke Tests
#
# Validates the deployment by checking:
# - Pod health status
# - Application endpoints
# - Prometheus metrics exposure
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-default}"
DEPLOYMENT="resilience-pilot"
ENDPOINT_URL="http://localhost:8080"
MAX_RETRIES=30
RETRY_INTERVAL=2

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_test() { echo -e "${YELLOW}[TEST]${NC} $1"; }

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# TEST FUNCTIONS
# ============================================================================

test_pods_running() {
    log_test "Checking if pods are running..."
    
    local ready_pods=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT} \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w | tr -d ' ')
    
    if [[ ${ready_pods} -ge 1 ]]; then
        log_success "Pods running: ${ready_pods}"
        ((TESTS_PASSED++))
        return 0
    else
        log_fail "No pods running"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_pods_ready() {
    log_test "Checking if pods are ready (passing readiness probes)..."
    
    local all_ready=$(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    local desired=$(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "3")
    
    if [[ "${all_ready}" -ge "${desired}" ]]; then
        log_success "All ${all_ready}/${desired} replicas ready"
        ((TESTS_PASSED++))
        return 0
    else
        log_fail "Only ${all_ready}/${desired} replicas ready"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_health_endpoint() {
    log_test "Testing /health endpoint..."
    
    local retry=0
    while [[ ${retry} -lt ${MAX_RETRIES} ]]; do
        local response=$(curl -s -o /dev/null -w "%{http_code}" "${ENDPOINT_URL}/health" 2>/dev/null || echo "000")
        
        if [[ "${response}" == "200" ]]; then
            local body=$(curl -s "${ENDPOINT_URL}/health" 2>/dev/null)
            if echo "${body}" | grep -q '"status".*"healthy"'; then
                log_success "Health endpoint responding (HTTP ${response})"
                ((TESTS_PASSED++))
                return 0
            fi
        fi
        
        ((retry++))
        sleep ${RETRY_INTERVAL}
    done
    
    log_fail "Health endpoint not responding after ${MAX_RETRIES} retries"
    ((TESTS_FAILED++))
    return 1
}

test_metrics_endpoint() {
    log_test "Testing /metrics endpoint (Prometheus format)..."
    
    local response=$(curl -s "${ENDPOINT_URL}/metrics" 2>/dev/null)
    
    if echo "${response}" | grep -q "http_requests_total"; then
        log_success "Metrics endpoint exposing Prometheus metrics"
        ((TESTS_PASSED++))
        return 0
    else
        log_fail "Metrics endpoint not returning expected format"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_service_exists() {
    log_test "Checking if Kubernetes Service exists..."
    
    if kubectl get service ${DEPLOYMENT} -n ${NAMESPACE} &>/dev/null; then
        log_success "Service '${DEPLOYMENT}' exists"
        ((TESTS_PASSED++))
        return 0
    else
        log_fail "Service '${DEPLOYMENT}' not found"
        ((TESTS_FAILED++))
        return 1
    fi
}

test_ingress_exists() {
    log_test "Checking if Ingress is configured..."
    
    if kubectl get ingress ${DEPLOYMENT} -n ${NAMESPACE} &>/dev/null; then
        log_success "Ingress '${DEPLOYMENT}' configured"
        ((TESTS_PASSED++))
        return 0
    else
        log_fail "Ingress '${DEPLOYMENT}' not found"
        ((TESTS_FAILED++))
        return 1
    fi
}

# ============================================================================
# WAIT FOR DEPLOYMENT
# ============================================================================
wait_for_deployment() {
    log_info "Waiting for deployment to be ready..."
    
    local retry=0
    while [[ ${retry} -lt ${MAX_RETRIES} ]]; do
        if kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} &>/dev/null; then
            local available=$(kubectl get deployment ${DEPLOYMENT} -n ${NAMESPACE} \
                -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
            
            if [[ "${available}" -ge 1 ]]; then
                log_success "Deployment is available"
                return 0
            fi
        fi
        
        ((retry++))
        echo -ne "\r  Waiting... (${retry}/${MAX_RETRIES})"
        sleep ${RETRY_INTERVAL}
    done
    
    echo ""
    log_fail "Deployment not available after ${MAX_RETRIES} retries"
    return 1
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo ""
    echo "============================================================================"
    echo "  The Resilience Pilot - Smoke Tests"
    echo "============================================================================"
    echo ""
    
    # Wait for deployment first
    if ! wait_for_deployment; then
        log_fail "Deployment not ready, aborting tests"
        exit 1
    fi
    
    echo ""
    echo "Running tests..."
    echo ""
    
    # Kubernetes tests
    test_pods_running
    test_pods_ready
    test_service_exists
    test_ingress_exists
    
    # Endpoint tests
    test_health_endpoint
    test_metrics_endpoint
    
    # Summary
    echo ""
    echo "============================================================================"
    echo "  Test Results"
    echo "============================================================================"
    echo ""
    echo -e "  ${GREEN}Passed:${NC} ${TESTS_PASSED}"
    echo -e "  ${RED}Failed:${NC} ${TESTS_FAILED}"
    echo ""
    
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}✅ All smoke tests passed!${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}❌ Some tests failed. Check the output above.${NC}"
        echo ""
        exit 1
    fi
}

main "$@"
