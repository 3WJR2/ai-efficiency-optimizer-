#!/usr/bin/env bash
# check-phase-3b-status.sh - Check status of all Phase 3B systems

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Phase 3B System Status Report                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo

echo "1️⃣  Multi-Objective Optimization"
echo "══════════════════════════════════"
~/.claude/scripts/multi-objective-optimization.sh status
echo
echo "────────────────────────────────────────────────────────────"
echo

echo "2️⃣  Workload Classification"
echo "══════════════════════════════════"
~/.claude/scripts/workload-classifier.sh status
echo
echo "────────────────────────────────────────────────────────────"
echo

echo "3️⃣  Config Multi-Armed Bandit"
echo "══════════════════════════════════"
~/.claude/scripts/config-mab.sh status
echo
echo "────────────────────────────────────────────────────────────"
echo

echo "4️⃣  A/B Testing Framework"
echo "══════════════════════════════════"
~/.claude/scripts/ab-testing.sh status
echo
echo "────────────────────────────────────────────────────────────"
echo

echo "5️⃣  Smart Caching"
echo "══════════════════════════════════"
~/.claude/scripts/smart-cache.sh performance
echo
echo "────────────────────────────────────────────────────────────"
echo

# Summary
echo "📊 Quick Summary"
echo "══════════════════════════════════"

# Current config
cache=$(jq -r '.similarity_threshold' ~/.claude/data/cache-config.json)
concurrent=$(jq -r '.max_concurrent_processes' ~/.claude/data/parallel-config.json)
echo "Current Config: cache=$cache, concurrent=$concurrent"

# Workload
workload=$(jq -r '.current_workload' ~/.claude/data/workload-data.json)
echo "Workload: $workload"

# MOO evaluations
eval_count=$(jq '.evaluations | length' ~/.claude/data/moo-history.json)
echo "MOO Evaluations: $eval_count"

# MAB best arm
best_arm=$(jq -r '.best_arm' ~/.claude/data/config-mab-data.json)
if [[ "$best_arm" != "null" ]]; then
  echo "MAB Best Arm: $best_arm"
else
  echo "MAB Best Arm: not determined yet"
fi

# A/B tests
active_tests=$(jq '.active_tests | length' ~/.claude/data/ab-test-data.json)
echo "Active A/B Tests: $active_tests"

# Smart cache
smart_hits=$(jq -r '.performance_metrics.smart_hits' ~/.claude/data/smart-cache-data.json)
smart_misses=$(jq -r '.performance_metrics.smart_misses' ~/.claude/data/smart-cache-data.json)
smart_total=$((smart_hits + smart_misses))
if [[ $smart_total -gt 0 ]]; then
  hit_rate=$(echo "scale=1; $smart_hits * 100 / $smart_total" | bc)
  echo "Smart Cache Hit Rate: ${hit_rate}%"
else
  echo "Smart Cache Hit Rate: no data yet"
fi

echo
echo "────────────────────────────────────────────────────────────"
echo "Report generated: $(date)"
