#!/usr/bin/env bash
# pattern-analyzer.sh - Analyzes outcome patterns for active learning
# Identifies trends, calculates optimal configurations, generates insights

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
LEARNING_CONFIG="$HOME/.claude/data/learning-config.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"

# Check if we have enough data for analysis
has_sufficient_data() {
  local data_type="$1"
  local min_samples=$(jq -r '.learning_thresholds.min_samples_for_learning // 10' "$LEARNING_CONFIG")

  local sample_count=0
  if [[ "$data_type" == "cache" ]]; then
    sample_count=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")
  elif [[ "$data_type" == "parallel" ]]; then
    sample_count=$(jq '.parallel_outcomes.execution_history | length' "$LEARNING_DATA")
  fi

  [[ $sample_count -ge $min_samples ]]
}

# Analyze cache performance patterns
analyze_cache_patterns() {
  echo "=== Analyzing Cache Patterns ==="
  echo

  if ! has_sufficient_data "cache"; then
    echo "Insufficient data for cache analysis (need 10+ samples)"
    return 1
  fi

  python3 <<'EOF'
import json
import sys
from statistics import mean, stdev

with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
    data = json.load(f)

with open('/Users/wallonwalusayi/.claude/data/learning-config.json') as f:
    config = json.load(f)

cache_data = data['cache_outcomes']
hit_rates = [h['hit_rate'] for h in cache_data['hit_rate_history']]
similarities = [s['avg_similarity'] for s in cache_data['similarity_score_history']]
latencies = [l['avg_latency_ms'] for l in cache_data['latency_history']]

if not hit_rates:
    print("No cache data available")
    sys.exit(0)

# Calculate statistics
avg_hit_rate = mean(hit_rates)
recent_hit_rate = mean(hit_rates[-5:]) if len(hit_rates) >= 5 else avg_hit_rate
trend = "improving" if recent_hit_rate > avg_hit_rate else "declining" if recent_hit_rate < avg_hit_rate else "stable"

avg_similarity = mean(similarities) if similarities else 0
avg_latency = mean(latencies) if latencies else 0

print(f"Cache Performance Analysis:")
print(f"  Total samples: {len(hit_rates)}")
print(f"  Average hit rate: {avg_hit_rate:.2%}")
print(f"  Recent hit rate (last 5): {recent_hit_rate:.2%}")
print(f"  Trend: {trend}")
print(f"  Average similarity: {avg_similarity:.4f}")
print(f"  Average latency: {avg_latency:.1f}ms")
print()

# Identify patterns
target_hit_rate = config['cache_learning']['target_hit_rate']
current_threshold = None
with open('/Users/wallonwalusayi/.claude/data/cache-config.json') as f:
    current_threshold = json.load(f)['similarity_threshold']

print(f"Pattern Analysis:")
print(f"  Target hit rate: {target_hit_rate:.2%}")
print(f"  Current threshold: {current_threshold}")

if recent_hit_rate < target_hit_rate:
    recommended_threshold = max(
        current_threshold - 0.02,
        config['cache_learning']['min_similarity_threshold']
    )
    print(f"  Recommendation: LOWER threshold to {recommended_threshold:.2f}")
    print(f"  Reason: Hit rate below target ({recent_hit_rate:.2%} < {target_hit_rate:.2%})")
elif recent_hit_rate > target_hit_rate + 0.10:
    recommended_threshold = min(
        current_threshold + 0.02,
        config['cache_learning']['max_similarity_threshold']
    )
    print(f"  Recommendation: RAISE threshold to {recommended_threshold:.2f}")
    print(f"  Reason: Hit rate well above target - can be more selective")
else:
    print(f"  Recommendation: MAINTAIN threshold at {current_threshold:.2f}")
    print(f"  Reason: Hit rate within acceptable range")

print()

# Calculate confidence
confidence = min(1.0, len(hit_rates) / 50.0)
print(f"Analysis confidence: {confidence:.2%}")

EOF
}

# Analyze parallel execution patterns
analyze_parallel_patterns() {
  echo "=== Analyzing Parallel Execution Patterns ==="
  echo

  if ! has_sufficient_data "parallel"; then
    echo "Insufficient data for parallel analysis (need 10+ samples)"
    return 1
  fi

  python3 <<'EOF'
import json
import sys
from statistics import mean

with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
    data = json.load(f)

with open('/Users/wallonwalusayi/.claude/data/learning-config.json') as f:
    config = json.load(f)

parallel_data = data['parallel_outcomes']
success_rates = [s['success_rate'] for s in parallel_data['success_rate_history']]
parallelism = [p['avg_parallelism'] for p in parallel_data['parallelism_history'] if p['avg_parallelism'] > 0]

if not success_rates:
    print("No parallel execution data available")
    sys.exit(0)

# Calculate statistics
avg_success = mean(success_rates)
recent_success = mean(success_rates[-5:]) if len(success_rates) >= 5 else avg_success
avg_parallelism = mean(parallelism) if parallelism else 0

print(f"Parallel Execution Analysis:")
print(f"  Total samples: {len(success_rates)}")
print(f"  Average success rate: {avg_success:.1f}%")
print(f"  Recent success rate: {recent_success:.1f}%")
print(f"  Average parallelism: {avg_parallelism:.1f} tasks")
print()

# Pattern analysis
target_success = config['parallel_learning']['target_success_rate']
current_concurrent = None
with open('/Users/wallonwalusayi/.claude/data/parallel-config.json') as f:
    current_concurrent = json.load(f)['max_concurrent_processes']

print(f"Pattern Analysis:")
print(f"  Target success rate: {target_success:.1%}")
print(f"  Current concurrent limit: {current_concurrent}")

if recent_success < target_success * 100:
    recommended_concurrent = max(
        current_concurrent - 1,
        config['parallel_learning']['min_concurrent_processes']
    )
    print(f"  Recommendation: DECREASE to {recommended_concurrent} concurrent processes")
    print(f"  Reason: Success rate below target ({recent_success:.1f}% < {target_success*100:.1f}%)")
elif recent_success >= target_success * 100 and avg_parallelism >= current_concurrent * 0.8:
    recommended_concurrent = min(
        current_concurrent + 1,
        config['parallel_learning']['max_concurrent_processes']
    )
    print(f"  Recommendation: INCREASE to {recommended_concurrent} concurrent processes")
    print(f"  Reason: High success rate and high utilization")
else:
    print(f"  Recommendation: MAINTAIN at {current_concurrent} concurrent processes")
    print(f"  Reason: Performance within acceptable range")

print()

# Calculate confidence
confidence = min(1.0, len(success_rates) / 30.0)
print(f"Analysis confidence: {confidence:.2%}")

EOF
}

# Generate comprehensive insights
generate_insights() {
  echo "=== Learning System Insights ==="
  echo

  local total_cycles=$(jq -r '.total_learning_cycles' "$LEARNING_DATA")
  local cache_samples=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")
  local parallel_samples=$(jq '.parallel_outcomes.execution_history | length' "$LEARNING_DATA")

  echo "System Overview:"
  echo "  Total learning cycles: $total_cycles"
  echo "  Cache data points: $cache_samples"
  echo "  Parallel data points: $parallel_samples"
  echo

  if [[ $cache_samples -ge 10 ]]; then
    analyze_cache_patterns
  else
    echo "Cache: Need $((10 - cache_samples)) more samples for analysis"
    echo
  fi

  if [[ $parallel_samples -ge 10 ]]; then
    analyze_parallel_patterns
  else
    echo "Parallel: Need $((10 - parallel_samples)) more samples for analysis"
    echo
  fi

  # Show learned patterns
  echo "=== Learned Optimal Configurations ==="
  echo

  local optimal_cache=$(jq -r '.learned_patterns.optimal_cache_threshold // "not yet determined"' "$LEARNING_DATA")
  local optimal_parallel=$(jq -r '.learned_patterns.optimal_concurrent_processes // "not yet determined"' "$LEARNING_DATA")

  echo "Optimal cache threshold: $optimal_cache"
  echo "Optimal concurrent processes: $optimal_parallel"
  echo
}

# Identify performance trends
identify_trends() {
  echo "=== Performance Trends ==="
  echo

  python3 <<'EOF'
import json
from statistics import mean

with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
    data = json.load(f)

# Cache trends
cache_data = data['cache_outcomes']
if len(cache_data['hit_rate_history']) >= 5:
    hit_rates = [h['hit_rate'] for h in cache_data['hit_rate_history']]
    first_quarter = mean(hit_rates[:len(hit_rates)//4]) if len(hit_rates) >= 4 else hit_rates[0]
    last_quarter = mean(hit_rates[-len(hit_rates)//4:]) if len(hit_rates) >= 4 else hit_rates[-1]

    change = ((last_quarter - first_quarter) / first_quarter * 100) if first_quarter > 0 else 0

    print(f"Cache Hit Rate Trend:")
    print(f"  Early average: {first_quarter:.2%}")
    print(f"  Recent average: {last_quarter:.2%}")
    print(f"  Change: {change:+.1f}%")
    print()

# Parallel trends
parallel_data = data['parallel_outcomes']
if len(parallel_data['success_rate_history']) >= 5:
    success_rates = [s['success_rate'] for s in parallel_data['success_rate_history']]
    first_quarter = mean(success_rates[:len(success_rates)//4]) if len(success_rates) >= 4 else success_rates[0]
    last_quarter = mean(success_rates[-len(success_rates)//4:]) if len(success_rates) >= 4 else success_rates[-1]

    change = last_quarter - first_quarter

    print(f"Parallel Success Rate Trend:")
    print(f"  Early average: {first_quarter:.1f}%")
    print(f"  Recent average: {last_quarter:.1f}%")
    print(f"  Change: {change:+.1f}%")
    print()

# Adjustment effectiveness
adjustments = data['cache_outcomes']['threshold_adjustments']
if adjustments:
    print(f"Configuration Adjustments:")
    print(f"  Total adjustments made: {len(adjustments)}")
    print(f"  Last adjustment: {adjustments[-1]['timestamp']}")
    print(f"  {adjustments[-1]['parameter']}: {adjustments[-1]['old_value']} → {adjustments[-1]['new_value']}")
    print(f"  Reason: {adjustments[-1]['reason']}")

EOF
}

# Calculate optimal configurations
calculate_optimal_configs() {
  echo "=== Calculating Optimal Configurations ==="
  echo

  python3 <<'EOF'
import json
from statistics import mean
from collections import defaultdict

with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
    data = json.load(f)

# Analyze cache threshold effectiveness
threshold_performance = defaultdict(list)
for adjustment in data['cache_outcomes']['threshold_adjustments']:
    threshold = float(adjustment['new_value'])
    # Find subsequent hit rates after this adjustment
    adjustment_time = adjustment['timestamp']
    for hr in data['cache_outcomes']['hit_rate_history']:
        if hr['timestamp'] > adjustment_time:
            threshold_performance[threshold].append(hr['hit_rate'])
            break

if threshold_performance:
    print("Cache Threshold Performance:")
    best_threshold = None
    best_hit_rate = 0

    for threshold, hit_rates in threshold_performance.items():
        avg_hit_rate = mean(hit_rates)
        print(f"  Threshold {threshold:.2f}: {avg_hit_rate:.2%} avg hit rate")
        if avg_hit_rate > best_hit_rate:
            best_hit_rate = avg_hit_rate
            best_threshold = threshold

    if best_threshold:
        print(f"\nOptimal cache threshold: {best_threshold:.2f} ({best_hit_rate:.2%} hit rate)")

        # Update learned patterns
        data['learned_patterns']['optimal_cache_threshold'] = best_threshold

        with open('/Users/wallonwalusayi/.claude/data/learning-data.json', 'w') as f:
            json.dump(data, f, indent=2)

print()

# Analyze concurrent process effectiveness
concurrent_performance = defaultdict(list)
for adjustment in data['parallel_outcomes']['concurrent_adjustments']:
    concurrent = int(adjustment['new_value'])
    adjustment_time = adjustment['timestamp']
    for sr in data['parallel_outcomes']['success_rate_history']:
        if sr['timestamp'] > adjustment_time:
            concurrent_performance[concurrent].append(sr['success_rate'])
            break

if concurrent_performance:
    print("Concurrent Process Performance:")
    best_concurrent = None
    best_success = 0

    for concurrent, success_rates in concurrent_performance.items():
        avg_success = mean(success_rates)
        print(f"  {concurrent} processes: {avg_success:.1f}% success rate")
        if avg_success > best_success:
            best_success = avg_success
            best_concurrent = concurrent

    if best_concurrent:
        print(f"\nOptimal concurrent processes: {best_concurrent} ({best_success:.1f}% success)")

        # Update learned patterns
        with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
            data = json.load(f)

        data['learned_patterns']['optimal_concurrent_processes'] = best_concurrent

        with open('/Users/wallonwalusayi/.claude/data/learning-data.json', 'w') as f:
            json.dump(data, f, indent=2)

EOF
}

# Main command dispatcher
case "${1:-analyze}" in
  analyze)
    generate_insights
    ;;
  cache)
    analyze_cache_patterns
    ;;
  parallel)
    analyze_parallel_patterns
    ;;
  trends)
    identify_trends
    ;;
  optimal)
    calculate_optimal_configs
    ;;
  *)
    echo "Usage: $0 {analyze|cache|parallel|trends|optimal}"
    echo
    echo "Commands:"
    echo "  analyze  - Generate comprehensive insights (default)"
    echo "  cache    - Analyze cache patterns only"
    echo "  parallel - Analyze parallel execution patterns only"
    echo "  trends   - Identify performance trends over time"
    echo "  optimal  - Calculate optimal configurations"
    exit 1
    ;;
esac
