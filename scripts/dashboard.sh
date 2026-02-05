#!/usr/bin/env bash
# dashboard.sh - Real-time Phase 3B dashboard

while true; do
  clear

  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║           Phase 3B Real-Time Dashboard                     ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo

  # Current Configuration
  echo "📊 Current Configuration"
  echo "────────────────────────"
  cache=$(jq -r '.similarity_threshold' ~/.claude/data/cache-config.json)
  concurrent=$(jq -r '.max_concurrent_processes' ~/.claude/data/parallel-config.json)
  echo "Cache threshold: $cache"
  echo "Max concurrent:  $concurrent"
  echo

  # Workload Status
  echo "🔄 Workload Classification"
  echo "────────────────────────"
  workload=$(jq -r '.current_workload' ~/.claude/data/workload-data.json)
  confidence=$(jq -r '.confidence' ~/.claude/data/workload-data.json)
  auto_switch=$(jq -r '.auto_switch_enabled' ~/.claude/data/workload-data.json)

  echo "Current: $workload"
  if [[ "$confidence" != "null" ]] && [[ "$confidence" != "0" ]]; then
    echo "Confidence: $(echo "$confidence * 100" | bc | cut -d. -f1)%"
  else
    echo "Confidence: 0%"
  fi
  echo "Auto-switch: $auto_switch"
  echo

  # MOO Score
  echo "🎯 Multi-Objective Score"
  echo "────────────────────────"
  eval_count=$(jq '.evaluations | length' ~/.claude/data/moo-history.json)
  if [[ $eval_count -gt 0 ]]; then
    latest_score=$(jq -r '.evaluations[-1].composite_score' ~/.claude/data/moo-history.json)
    echo "Latest: $(echo "$latest_score * 100" | bc | cut -d. -f1)%"
    echo "Evaluations: $eval_count"

    # Show Pareto frontier size
    frontier_size=$(jq '.pareto_frontier | length' ~/.claude/data/moo-history.json)
    echo "Pareto frontier: $frontier_size solutions"
  else
    echo "No evaluations yet"
    echo "(Need cache + parallel samples)"
  fi
  echo

  # MAB Status
  echo "🎰 Multi-Armed Bandit"
  echo "────────────────────────"
  best_arm=$(jq -r '.best_arm' ~/.claude/data/config-mab-data.json)
  current_arm=$(jq -r '.current_arm' ~/.claude/data/config-mab-data.json)

  echo "Current arm: ${current_arm:-none}"

  if [[ "$best_arm" != "null" ]]; then
    reward=$(jq -r --arg arm "$best_arm" '.arms[$arm].avg_reward' ~/.claude/data/config-mab-data.json)
    pulls=$(jq -r --arg arm "$best_arm" '.arms[$arm].total_pulls' ~/.claude/data/config-mab-data.json)
    echo "Best arm: $best_arm"
    echo "Reward: $(echo "$reward * 100" | bc | cut -d. -f1)% ($pulls pulls)"
  else
    echo "Best arm: exploring..."
    total_pulls=$(jq '[.arms[].total_pulls] | add' ~/.claude/data/config-mab-data.json)
    min_pulls=$(jq -r '.min_pulls_per_arm' ~/.claude/data/config-mab-data.json)
    echo "Total pulls: $total_pulls (need $(echo "$min_pulls * 5" | bc) min)"
  fi
  echo

  # Smart Cache
  echo "🧠 Smart Caching"
  echo "────────────────────────"
  enabled=$(jq -r '.enabled' ~/.claude/data/smart-cache-data.json)
  smart_hits=$(jq -r '.performance_metrics.smart_hits' ~/.claude/data/smart-cache-data.json)
  smart_misses=$(jq -r '.performance_metrics.smart_misses' ~/.claude/data/smart-cache-data.json)
  smart_total=$((smart_hits + smart_misses))

  echo "Status: $enabled"

  if [[ $smart_total -gt 0 ]]; then
    hit_rate=$(echo "scale=1; $smart_hits * 100 / $smart_total" | bc)
    echo "Hit rate: ${hit_rate}%"
    echo "Hits: $smart_hits | Misses: $smart_misses"

    entry_count=$(jq '.cache_entries | length' ~/.claude/data/smart-cache-data.json)
    echo "Entries: $entry_count"
  else
    echo "Hit rate: no data yet"
  fi
  echo

  # A/B Tests
  echo "🧪 A/B Tests"
  echo "────────────────────────"
  active_tests=$(jq '.active_tests | length' ~/.claude/data/ab-test-data.json)
  completed_tests=$(jq '.completed_tests | length' ~/.claude/data/ab-test-data.json)

  echo "Active: $active_tests"
  echo "Completed: $completed_tests"

  if [[ $active_tests -gt 0 ]]; then
    echo
    echo "Active tests:"
    jq -r '.active_tests[] | "  • \(.test_name) (\(.variant_a.samples | length)/\(.variant_b.samples | length) samples)"' \
      ~/.claude/data/ab-test-data.json
  fi
  echo

  # Learning Data Summary
  echo "📚 Learning Data"
  echo "────────────────────────"
  if [[ -f ~/.claude/data/learning-data.json ]]; then
    cache_samples=$(jq '.cache_outcomes.hit_rate_history | length' ~/.claude/data/learning-data.json)
    parallel_samples=$(jq '.parallel_outcomes.success_rate_history | length' ~/.claude/data/learning-data.json)
    learning_cycles=$(jq -r '.learning_cycles // 0' ~/.claude/data/learning-data.json)

    echo "Cache samples: $cache_samples"
    echo "Parallel samples: $parallel_samples"
    echo "Learning cycles: $learning_cycles"

    if [[ $cache_samples -gt 0 ]]; then
      recent_hit_rate=$(jq -r '[.cache_outcomes.hit_rate_history[-5:][].hit_rate] | add / length' \
        ~/.claude/data/learning-data.json)
      echo "Recent hit rate: $(echo "$recent_hit_rate * 100" | bc | cut -d. -f1)%"
    fi
  else
    echo "No learning data yet"
  fi

  echo
  echo "────────────────────────────────────────────────────────────"
  echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Press Ctrl+C to exit | Refreshing every 10s..."

  sleep 10
done
