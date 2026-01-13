#!/bin/bash

################################################################################
# Generate HTTP Load for Grafana Metrics
# This sends continuous requests to populate Grafana dashboards
################################################################################

echo "🚀 Starting load generator..."
echo "Press Ctrl+C to stop"
echo ""

# Counter for statistics
SUCCESS=0
FAILED=0
TOTAL=0

# Trap Ctrl+C to show statistics
trap 'echo ""; echo "📊 Statistics:"; echo "Total: $TOTAL | Success: $SUCCESS | Failed: $FAILED"; exit 0' INT

while true; do
  # Make request to health endpoint
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health | grep -q "200"; then
    ((SUCCESS++))
    STATUS="✅"
  else
    ((FAILED++))
    STATUS="❌"
  fi
  ((TOTAL++))

  # Print status every 10 requests
  if [ $((TOTAL % 10)) -eq 0 ]; then
    echo "[$TOTAL requests] Success: $SUCCESS | Failed: $FAILED"
  fi

  # Wait 0.5 seconds between requests (2 req/sec)
  sleep 0.5
done
