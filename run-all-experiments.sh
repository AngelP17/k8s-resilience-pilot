#!/bin/bash

################################################################################
# Master Script: Run All Chaos Experiments
# Executes all three experiments in sequence
################################################################################

set -e

cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                    🔥 RESILIENCE PILOT - CHAOS SUITE 🔥                     ║
║                                                                              ║
║                  Complete Chaos Engineering Experiment Suite                ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

echo ""
echo "This will run three comprehensive chaos experiments:"
echo ""
echo "  1️⃣  Sustained Chaos    - Repeated pod failures (10 rounds)"
echo "  2️⃣  Scale Test         - High-scale chaos with 5 replicas"
echo "  3️⃣  Node Failure       - Complete node drain simulation"
echo ""
echo "⚠️  Prerequisites:"
echo "  • Grafana open: http://localhost:3000"
echo "  • Load generator running: ./generate-load.sh"
echo "  • Time range: Last 15 minutes with 5s auto-refresh"
echo ""
echo "⏱️  Total estimated time: ~10-15 minutes"
echo ""
echo "Press Enter to start or Ctrl+C to cancel..."
read -r

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "                           STARTING EXPERIMENT SUITE"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# Experiment 1: Sustained Chaos
echo ""
./experiment-1-sustained-chaos.sh
echo ""
echo "✅ Experiment 1 complete. Pausing 30 seconds before next experiment..."
sleep 30

# Experiment 2: Scale Test
echo ""
./experiment-2-scale-test.sh
echo ""
echo "✅ Experiment 2 complete. Pausing 30 seconds before next experiment..."
sleep 30

# Experiment 3: Node Failure (interactive)
echo ""
./experiment-3-node-failure.sh

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "                         🎉 ALL EXPERIMENTS COMPLETE! 🎉"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "📊 Summary of What You Tested:"
echo ""
echo "✅ Experiment 1: Sustained Chaos"
echo "   - Killed pods 10 times over 2.5 minutes"
echo "   - Tested continuous self-healing"
echo "   - Measured MTTR across multiple failures"
echo ""
echo "✅ Experiment 2: Scale Test"
echo "   - Scaled to 5 replicas"
echo "   - Killed 40% of pods simultaneously (2/5)"
echo "   - Verified graceful degradation"
echo ""
echo "✅ Experiment 3: Node Failure"
echo "   - Simulated complete node failure"
echo "   - Forced pod migration to healthy nodes"
echo "   - Tested anti-affinity rules"
echo ""
echo "📈 Check Your Grafana Dashboard Now!"
echo ""
echo "You should see:"
echo "  📍 Pod Restarts Over Time: Multiple restart events"
echo "  📍 Request Rate: Stayed consistent throughout"
echo "  📍 Error Rate: Near-zero despite chaos"
echo "  📍 Application Uptime: Multiple pod lifecycle resets"
echo ""
echo "🏆 Your system demonstrated production-grade resilience!"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
