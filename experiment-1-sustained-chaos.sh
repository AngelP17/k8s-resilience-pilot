#!/bin/bash

################################################################################
# Experiment 1: Sustained Chaos
# Repeatedly kills pods to test continuous resilience
################################################################################

set -e

echo "🔥 Experiment 1: Sustained Chaos"
echo "=================================="
echo ""
echo "This will kill a pod every 15 seconds, 10 times"
echo "Keep your Grafana dashboard open to watch the chaos unfold!"
echo ""
sleep 3

for i in {1..10}; do
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔥 Chaos Round $i/10"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Show current pods
  echo "📊 Current pods:"
  kubectl get pods -l app=resilience-pilot --no-headers | awk '{print "  - " $1 " [" $3 "]"}'

  # Kill a random pod
  POD_NAME=$(kubectl get pods -l app=resilience-pilot -o jsonpath='{.items[0].metadata.name}')
  echo ""
  echo "💥 Killing pod: $POD_NAME"
  kubectl delete pod $POD_NAME --grace-period=0 --force 2>/dev/null || true

  # Wait 15 seconds
  echo ""
  echo "⏱️  Waiting 15 seconds before next round..."
  for j in {15..1}; do
    READY=$(kubectl get pods -l app=resilience-pilot --no-headers | grep "1/1" | wc -l | tr -d ' ')
    TOTAL=$(kubectl get pods -l app=resilience-pilot --no-headers | wc -l | tr -d ' ')
    printf "\r  Pods ready: ${READY}/${TOTAL} | Next chaos in: ${j}s  "
    sleep 1
  done
  echo ""
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Experiment 1 Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Final pod status:"
kubectl get pods -l app=resilience-pilot
echo ""
echo "📈 Check Grafana for:"
echo "  - Multiple pod restarts in 'Pod Restarts Over Time'"
echo "  - Consistent request rate despite chaos"
echo "  - Zero or near-zero error rate"
echo "  - Multiple uptime resets in 'Application Uptime'"
