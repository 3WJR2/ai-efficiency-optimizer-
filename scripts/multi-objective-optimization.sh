#!/usr/bin/env bash
# multi-objective-optimization.sh - Balance multiple performance metrics
# Uses weighted scoring and Pareto frontier analysis

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
MOO_CONFIG="$HOME/.claude/data/moo-config.json"
MOO_HISTORY="$HOME/.claude/data/moo-history.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize MOO configuration
initialize_moo() {
  if [[ ! -f "$MOO_CONFIG" ]]; then
    cat > "$MOO_CONFIG" <<'EOF'
{
  "version": "1.0.0",
  "weights": {
    "cache_hit_rate": 0.4,
    "cache_latency": 0.3,
    "parallel_success_rate": 0.2,
    "parallel_throughput": 0.1
  },
  "normalization": {
    "cache_hit_rate": {"min": 0.0, "max": 1.0, "higher_better": true},
    "cache_latency": {"min": 0.0, "max": 100.0, "higher_better": false},
    "parallel_success_rate": {"min": 0.0, "max": 1.0, "higher_better": true},
    "parallel_throughput": {"min": 0.0, "max": 10.0, "higher_better": true}
  },
  "pareto_enabled": true,
  "adaptive_weights": false
}
EOF
  fi

  if [[ ! -f "$MOO_HISTORY" ]]; then
    cat > "$MOO_HISTORY" <<'EOF'
{
  "version": "1.0.0",
  "evaluations": [],
  "pareto_frontier": [],
  "best_solutions": []
}
EOF
  fi
}

# Calculate composite score for current configuration
calculate_composite_score() {
  echo -e "${BLUE}Calculating multi-objective composite score...${NC}"

  if [[ ! -f "$LEARNING_DATA" ]]; then
    echo "No learning data available"
    return 1
  fi

  # Get weights
  local w_hit=$(jq -r '.weights.cache_hit_rate' "$MOO_CONFIG")
  local w_latency=$(jq -r '.weights.cache_latency' "$MOO_CONFIG")
  local w_success=$(jq -r '.weights.parallel_success_rate' "$MOO_CONFIG")
  local w_throughput=$(jq -r '.weights.parallel_throughput' "$MOO_CONFIG")

  # Get current metrics (average of last 10 samples)
  local cache_samples=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")
  local parallel_samples=$(jq '.parallel_outcomes.success_rate_history | length' "$LEARNING_DATA")

  if [[ $cache_samples -lt 5 ]] || [[ $parallel_samples -lt 5 ]]; then
    echo "Not enough samples (need 5+, have cache:$cache_samples parallel:$parallel_samples)"
    return 1
  fi

  # Calculate metrics using Python for better floating point handling
  local metrics=$(python3 <<EOF
import json
import sys

with open('$LEARNING_DATA') as f:
    data = json.load(f)

# Get recent samples
cache_history = data['cache_outcomes']['hit_rate_history'][-10:]
latency_history = data['cache_outcomes']['latency_history'][-10:]
success_history = data['parallel_outcomes']['success_rate_history'][-10:]

# Calculate averages
hit_rate = sum(s['hit_rate'] for s in cache_history) / len(cache_history)
latency = sum(s['avg_latency_ms'] for s in latency_history) / len(latency_history) if latency_history else 0
success_rate = sum(s['success_rate'] for s in success_history) / len(success_history)

# Throughput: successful tasks per second (approximation)
throughput = success_rate / 100.0 * 5.0  # Assuming ~5 tasks/sec baseline

print(json.dumps({
    'hit_rate': hit_rate,
    'latency': latency,
    'success_rate': success_rate / 100.0,
    'throughput': throughput
}))
EOF
)

  local hit_rate=$(echo "$metrics" | jq -r '.hit_rate')
  local latency=$(echo "$metrics" | jq -r '.latency')
  local success_rate=$(echo "$metrics" | jq -r '.success_rate')
  local throughput=$(echo "$metrics" | jq -r '.throughput')

  # Normalize and calculate weighted score
  local score=$(python3 <<EOF
import json

# Metrics
hit_rate = $hit_rate
latency = $latency
success_rate = $success_rate
throughput = $throughput

# Weights
w_hit = $w_hit
w_latency = $w_latency
w_success = $w_success
w_throughput = $w_throughput

# Normalization (min-max scaling)
# Hit rate: already 0-1, higher is better
norm_hit = hit_rate

# Latency: 0-100ms, lower is better (invert)
norm_latency = max(0, 1.0 - (latency / 100.0))

# Success rate: already 0-1, higher is better
norm_success = success_rate

# Throughput: 0-10 tasks/sec, higher is better
norm_throughput = min(1.0, throughput / 10.0)

# Weighted composite score
composite = (w_hit * norm_hit +
             w_latency * norm_latency +
             w_success * norm_success +
             w_throughput * norm_throughput)

print(json.dumps({
    'composite_score': composite,
    'normalized': {
        'hit_rate': norm_hit,
        'latency': norm_latency,
        'success_rate': norm_success,
        'throughput': norm_throughput
    },
    'raw': {
        'hit_rate': hit_rate,
        'latency': latency,
        'success_rate': success_rate,
        'throughput': throughput
    }
}))
EOF
)

  local composite=$(echo "$score" | jq -r '.composite_score')

  echo -e "${GREEN}✓ Composite Score: $(echo "$composite * 100" | bc | cut -d. -f1)%${NC}"
  echo
  echo "Component Breakdown:"
  echo "  Cache Hit Rate:     $(echo "$hit_rate * 100" | bc | cut -d. -f1)% (weight: $(echo "$w_hit * 100" | bc | cut -d. -f1)%)"
  echo "  Cache Latency:      ${latency}ms (weight: $(echo "$w_latency * 100" | bc | cut -d. -f1)%)"
  echo "  Parallel Success:   $(echo "$success_rate * 100" | bc | cut -d. -f1)% (weight: $(echo "$w_success * 100" | bc | cut -d. -f1)%)"
  echo "  Parallel Throughput: ${throughput} tasks/s (weight: $(echo "$w_throughput * 100" | bc | cut -d. -f1)%)"

  # Record evaluation
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local cache_threshold=$(jq -r '.similarity_threshold' "$HOME/.claude/data/cache-config.json")
  local max_concurrent=$(jq -r '.max_concurrent_processes' "$HOME/.claude/data/parallel-config.json")

  jq --arg ts "$now" \
     --argjson composite "$composite" \
     --argjson cache_threshold "$cache_threshold" \
     --argjson max_concurrent "$max_concurrent" \
     --argjson full_score "$score" \
     '.evaluations += [{
       timestamp: $ts,
       config: {cache_threshold: $cache_threshold, max_concurrent: $max_concurrent},
       composite_score: $composite,
       metrics: $full_score.raw,
       normalized: $full_score.normalized
     }] | .evaluations = .evaluations[-100:]' "$MOO_HISTORY" > "$MOO_HISTORY.tmp"
  mv "$MOO_HISTORY.tmp" "$MOO_HISTORY"

  echo "$composite"
}

# Find Pareto frontier (non-dominated solutions)
find_pareto_frontier() {
  echo -e "${BLUE}Finding Pareto frontier...${NC}"

  local eval_count=$(jq '.evaluations | length' "$MOO_HISTORY")
  if [[ $eval_count -lt 10 ]]; then
    echo "Not enough evaluations for Pareto analysis (need 10+, have $eval_count)"
    return 1
  fi

  # Use Python for Pareto frontier calculation
  local frontier=$(python3 <<'PYEOF'
import json

with open('/Users/wallonwalusayi/.claude/data/moo-history.json') as f:
    data = json.load(f)

evals = data['evaluations']

# For Pareto frontier, we want to maximize all metrics
# (latency is already inverted in normalized form)
def dominates(a, b):
    """Check if solution a dominates solution b"""
    norm_a = a['normalized']
    norm_b = b['normalized']

    better_in_any = False
    worse_in_any = False

    for metric in ['hit_rate', 'latency', 'success_rate', 'throughput']:
        if norm_a[metric] > norm_b[metric]:
            better_in_any = True
        elif norm_a[metric] < norm_b[metric]:
            worse_in_any = True

    return better_in_any and not worse_in_any

# Find non-dominated solutions
pareto = []
for candidate in evals:
    dominated = False
    for other in evals:
        if other != candidate and dominates(other, candidate):
            dominated = True
            break
    if not dominated:
        pareto.append(candidate)

# Sort by composite score
pareto.sort(key=lambda x: x['composite_score'], reverse=True)

print(json.dumps(pareto[:10]))  # Keep top 10
PYEOF
)

  # Update Pareto frontier in history
  jq --argjson frontier "$frontier" \
     '.pareto_frontier = $frontier' \
     "$MOO_HISTORY" > "$MOO_HISTORY.tmp"
  mv "$MOO_HISTORY.tmp" "$MOO_HISTORY"

  local frontier_size=$(echo "$frontier" | jq 'length')
  echo -e "${GREEN}✓ Found $frontier_size non-dominated solutions${NC}"

  if [[ $frontier_size -gt 0 ]]; then
    echo
    echo "Top Pareto-optimal solutions:"
    echo "$frontier" | jq -r '.[:3][] |
      "  Score: \(.composite_score | tonumber | . * 100 | floor)% | " +
      "Cache: \(.config.cache_threshold) | " +
      "Concurrent: \(.config.max_concurrent) | " +
      "Hit: \(.metrics.hit_rate | tonumber | . * 100 | floor)% | " +
      "Latency: \(.metrics.latency | floor)ms"'
  fi
}

# Get best configuration based on multi-objective optimization
get_best_config() {
  local frontier_size=$(jq '.pareto_frontier | length' "$MOO_HISTORY")

  if [[ $frontier_size -eq 0 ]]; then
    echo "No Pareto frontier available"
    return 1
  fi

  # Best solution is the one with highest composite score on frontier
  local best=$(jq '.pareto_frontier[0]' "$MOO_HISTORY")

  echo "$best" | jq '{
    composite_score,
    config,
    metrics
  }'
}

# Adjust weights based on current priorities
adjust_weights() {
  local metric="$1"
  local new_weight="$2"

  echo -e "${BLUE}Adjusting weight for $metric to $new_weight${NC}"

  # Normalize weights to sum to 1.0
  jq --arg metric "$metric" \
     --argjson weight "$new_weight" \
     '.weights[$metric] = $weight |
      .weights as $w |
      ($w.cache_hit_rate + $w.cache_latency + $w.parallel_success_rate + $w.parallel_throughput) as $sum |
      .weights = {
        cache_hit_rate: ($w.cache_hit_rate / $sum),
        cache_latency: ($w.cache_latency / $sum),
        parallel_success_rate: ($w.parallel_success_rate / $sum),
        parallel_throughput: ($w.parallel_throughput / $sum)
      }' "$MOO_CONFIG" > "$MOO_CONFIG.tmp"
  mv "$MOO_CONFIG.tmp" "$MOO_CONFIG"

  echo -e "${GREEN}✓ Weights adjusted and normalized${NC}"
  jq '.weights' "$MOO_CONFIG"
}

# Show current configuration and scores
show_status() {
  echo -e "${BLUE}=== Multi-Objective Optimization Status ===${NC}"
  echo

  echo "Current Weights:"
  jq -r '.weights | to_entries | .[] | "  \(.key): \(.value | . * 100 | floor)%"' "$MOO_CONFIG"
  echo

  local eval_count=$(jq '.evaluations | length' "$MOO_HISTORY")
  echo "Evaluations: $eval_count"

  if [[ $eval_count -gt 0 ]]; then
    echo
    echo "Recent Composite Scores:"
    jq -r '.evaluations[-5:] | reverse | .[] |
      "  \(.timestamp): \(.composite_score | . * 100 | floor)% " +
      "(cache: \(.config.cache_threshold), concurrent: \(.config.max_concurrent))"' \
      "$MOO_HISTORY"
  fi

  local frontier_size=$(jq '.pareto_frontier | length' "$MOO_HISTORY")
  if [[ $frontier_size -gt 0 ]]; then
    echo
    echo "Pareto Frontier: $frontier_size solutions"
    echo
    echo "Best Solution:"
    jq -r '.pareto_frontier[0] |
      "  Composite Score: \(.composite_score | . * 100 | floor)%\n" +
      "  Cache Threshold: \(.config.cache_threshold)\n" +
      "  Max Concurrent: \(.config.max_concurrent)\n" +
      "  Hit Rate: \(.metrics.hit_rate | . * 100 | floor)%\n" +
      "  Latency: \(.metrics.latency | floor)ms\n" +
      "  Success Rate: \(.metrics.success_rate | . * 100 | floor)%\n" +
      "  Throughput: \(.metrics.throughput | floor) tasks/s"' \
      "$MOO_HISTORY"
  fi
}

# Compare two configurations
compare_configs() {
  local config1="$1"
  local config2="$2"

  echo -e "${BLUE}Comparing configurations...${NC}"
  echo

  local score1=$(jq --arg cfg "$config1" '.evaluations[] | select(.config | tostring == $cfg) | .composite_score' "$MOO_HISTORY" | tail -1)
  local score2=$(jq --arg cfg "$config2" '.evaluations[] | select(.config | tostring == $cfg) | .composite_score' "$MOO_HISTORY" | tail -1)

  if [[ -z "$score1" ]] || [[ -z "$score2" ]]; then
    echo "Configuration not found in evaluation history"
    return 1
  fi

  echo "Config 1: $config1"
  echo "  Score: $(echo "$score1 * 100" | bc | cut -d. -f1)%"
  echo
  echo "Config 2: $config2"
  echo "  Score: $(echo "$score2 * 100" | bc | cut -d. -f1)%"
  echo

  local diff=$(echo "$score1 - $score2" | bc -l)
  if [[ $(echo "$diff > 0" | bc -l) -eq 1 ]]; then
    echo -e "${GREEN}Config 1 is better by $(echo "$diff * 100" | bc | cut -d. -f1)%${NC}"
  elif [[ $(echo "$diff < 0" | bc -l) -eq 1 ]]; then
    echo -e "${GREEN}Config 2 is better by $(echo "$diff * -100" | bc | cut -d. -f1)%${NC}"
  else
    echo "Configurations are equally good"
  fi
}

# Main command dispatcher
case "${1:-}" in
  init)
    initialize_moo
    echo -e "${GREEN}✓ Multi-objective optimization initialized${NC}"
    ;;
  score)
    initialize_moo
    calculate_composite_score
    ;;
  pareto)
    initialize_moo
    find_pareto_frontier
    ;;
  best)
    initialize_moo
    get_best_config
    ;;
  status)
    initialize_moo
    show_status
    ;;
  adjust-weight)
    initialize_moo
    adjust_weights "$2" "$3"
    ;;
  compare)
    initialize_moo
    compare_configs "$2" "$3"
    ;;
  evaluate)
    # Full evaluation: score + pareto + show best
    initialize_moo
    calculate_composite_score >/dev/null
    find_pareto_frontier
    echo
    echo -e "${YELLOW}Best Configuration:${NC}"
    get_best_config
    ;;
  *)
    echo "Usage: $0 {init|score|pareto|best|status|adjust-weight|compare|evaluate}"
    echo
    echo "Commands:"
    echo "  init              - Initialize MOO system"
    echo "  score             - Calculate current composite score"
    echo "  pareto            - Find Pareto frontier"
    echo "  best              - Get best configuration"
    echo "  status            - Show current status"
    echo "  adjust-weight <metric> <weight> - Adjust metric weight"
    echo "  compare <cfg1> <cfg2> - Compare two configs"
    echo "  evaluate          - Full evaluation (score + pareto + best)"
    exit 1
    ;;
esac
