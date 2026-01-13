#!/bin/bash

################################################################################
# Resilience Pilot - Chaos Engineering Demo
# This script demonstrates how to test application resilience
################################################################################

set -e

echo "🎯 Resilience Pilot - Chaos Engineering Demo"
echo "=============================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}📊 Current Application Status:${NC}"
kubectl get pods -l app=resilience-pilot
echo ""

echo -e "${YELLOW}💉 Generating background load...${NC}"
echo "This will send requests to your app so you can see metrics in Grafana"
(
  for i in {1..60}; do
    curl -s http://localhost:8080/health > /dev/null
    sleep 1
  done
) &
LOAD_PID=$!
echo "Load generation started (PID: $LOAD_PID)"
echo ""

sleep 3

echo -e "${RED}🔥 Triggering Chaos: Killing a random pod...${NC}"
POD_NAME=$(kubectl get pods -l app=resilience-pilot -o jsonpath='{.items[0].metadata.name}')
echo "Target pod: $POD_NAME"
kubectl delete pod $POD_NAME --grace-period=0 --force
echo ""

echo -e "${YELLOW}⏱️  Monitoring recovery (30 seconds)...${NC}"
echo "Watch how Kubernetes automatically recovers:"
for i in {1..30}; do
  READY=$(kubectl get pods -l app=resilience-pilot --no-headers | grep "1/1" | wc -l | tr -d ' ')
  TOTAL=$(kubectl get pods -l app=resilience-pilot --no-headers | wc -l | tr -d ' ')
  echo -ne "Pods ready: ${READY}/${TOTAL}\r"
  sleep 1
done
echo ""

echo -e "${GREEN}✅ Recovery Status:${NC}"
kubectl get pods -l app=resilience-pilot
echo ""

echo -e "${GREEN}📈 Now check Grafana to see:${NC}"
echo "  1. The pod restart in the 'Pod Status' panel"
echo "  2. Any brief spike in error rate"
echo "  3. Recovery time (should be ~8 seconds)"
echo ""
echo "Grafana: http://localhost:3000"
echo "Dashboard: Dashboards → Resilience Pilot Dashboard"
echo ""

# Stop background load
kill $LOAD_PID 2>/dev/null || true
echo -e "${YELLOW}🛑 Load generation stopped${NC}"
