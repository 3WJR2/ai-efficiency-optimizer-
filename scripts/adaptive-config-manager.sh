#!/usr/bin/env bash
# adaptive-config-manager.sh - Automatically adjusts configurations based on learned patterns
# Applies insights from pattern analysis to optimize system performance

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
LEARNING_CONFIG="$HOME/.claude/data/learning-config.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"
OUTCOME_TRACKER="$HOME/.claude/scripts/outcome-tracker.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check if auto-tuning is enabled
is_auto_tuning_enabled() {
  local enabled=$(jq -r '.learning_features.auto_tuning // false' "$LEARNING_CONFIG")
  [[ "$enabled" == "true" ]]
}

# Get confidence threshold
get_confidence_threshold() {
  jq -r '.learning_thresholds.confidence_threshold // 0.70' "$LEARNING_CONFIG"
}

# Calculate adaptation aggressiveness
get_adaptation_aggressiveness() {
  jq -r '.learning_thresholds.adaptation_aggressiveness // 0.2' "$LEARNING_CONFIG"
}

# Adapt cache configuration
adapt_cache_config() {
  local dry_run="${1:-false}"

  echo -e "${BLUE}=== Cache Configuration Adaptation ===${NC}"
  echo

  # Get current configuration
  local current_threshold=$(jq -r '.similarity_threshold' "$CACHE_CONFIG")
  local current_ttl=$(jq -r '.cache_ttl_seconds' "$CACHE_CONFIG")

  echo "Current configuration:"
  echo "  Similarity threshold: $current_threshold"
  echo "  Cache TTL: ${current_ttl}s"
  echo

  # Analyze patterns
  local cache_samples=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")

  if [[ $cache_samples -lt 10 ]]; then
    echo -e "${YELLOW}Insufficient data for adaptation (need 10+ samples, have $cache_samples)${NC}"
    return 1
  fi

  # Calculate recommended threshold
  python3 <<EOF | while IFS='|' read -r recommendation confidence reason; do
import json
from statistics import mean

with open('$LEARNING_DATA') as f:
    data = json.load(f)

with open('$LEARNING_CONFIG') as f:
    config = json.load(f)

cache_data = data['cache_outcomes']
hit_rates = [h['hit_rate'] for h in cache_data['hit_rate_history']]
recent_hit_rate = mean(hit_rates[-5:]) if len(hit_rates) >= 5 else mean(hit_rates)

target_hit_rate = config['cache_learning']['target_hit_rate']
min_threshold = config['cache_learning']['min_similarity_threshold']
max_threshold = config['cache_learning']['max_similarity_threshold']
step = config['cache_learning']['similarity_adjustment_step']
aggressiveness = config['learning_thresholds']['adaptation_aggressiveness']

current_threshold = float('$current_threshold')

# Determine recommendation
if recent_hit_rate < target_hit_rate:
    # Hit rate too low - lower threshold
    adjustment = step * (1 + aggressiveness)
    new_threshold = max(current_threshold - adjustment, min_threshold)
    reason = f"Hit rate {recent_hit_rate:.2%} below target {target_hit_rate:.2%}"
elif recent_hit_rate > target_hit_rate + 0.15:
    # Hit rate way too high - raise threshold for quality
    adjustment = step * (1 + aggressiveness)
    new_threshold = min(current_threshold + adjustment, max_threshold)
    reason = f"Hit rate {recent_hit_rate:.2%} well above target - improving quality"
else:
    # Within acceptable range
    new_threshold = current_threshold
    reason = f"Hit rate {recent_hit_rate:.2%} within acceptable range"

# Calculate confidence based on sample size and variance
confidence = min(1.0, len(hit_rates) / 50.0)

print(f"{new_threshold}|{confidence}|{reason}")
EOF

    local new_threshold="$recommendation"
    local confidence="$confidence"
    local reason="$reason"

    echo "Analysis results:"
    echo "  Recommended threshold: $new_threshold"
    echo "  Confidence: $(echo "$confidence * 100" | bc | cut -d. -f1)%"
    echo "  Reason: $reason"
    echo

    # Check if adaptation should be applied
    local confidence_threshold=$(get_confidence_threshold)
    local should_adapt=$(echo "$confidence >= $confidence_threshold" | bc -l)

    if [[ "$should_adapt" == "1" ]] && [[ "$new_threshold" != "$current_threshold" ]]; then
      echo -e "${GREEN}✓ Adaptation recommended${NC}"

      if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN - Changes not applied${NC}"
      else
        # Apply adaptation
        jq --argjson threshold "$new_threshold" \
           '.similarity_threshold = $threshold' \
           "$CACHE_CONFIG" > "$CACHE_CONFIG.tmp"
        mv "$CACHE_CONFIG.tmp" "$CACHE_CONFIG"

        # Track adjustment
        "$OUTCOME_TRACKER" track-config-adjustment \
          "cache" "similarity_threshold" "$current_threshold" "$new_threshold" "$reason" 2>/dev/null || true

        # Log adaptation
        "$OUTCOME_TRACKER" log-adaptation \
          "cache_threshold" "$reason" "$confidence" "adjusted from $current_threshold to $new_threshold" 2>/dev/null || true

        echo -e "${GREEN}✓ Configuration updated${NC}"
        echo "  similarity_threshold: $current_threshold → $new_threshold"
      fi
    elif [[ "$new_threshold" == "$current_threshold" ]]; then
      echo -e "${GREEN}✓ No changes needed - configuration optimal${NC}"
    else
      echo -e "${YELLOW}⚠ Confidence too low for adaptation (${confidence} < ${confidence_threshold})${NC}"
      echo "  Will adapt once more data is collected"
    fi

  done
}

# Adapt parallel execution configuration
adapt_parallel_config() {
  local dry_run="${1:-false}"

  echo -e "${BLUE}=== Parallel Execution Configuration Adaptation ===${NC}"
  echo

  # Get current configuration
  local current_concurrent=$(jq -r '.max_concurrent_processes' "$PARALLEL_CONFIG")
  local current_timeout=$(jq -r '.process_timeout_seconds' "$PARALLEL_CONFIG")

  echo "Current configuration:"
  echo "  Max concurrent processes: $current_concurrent"
  echo "  Process timeout: ${current_timeout}s"
  echo

  # Analyze patterns
  local parallel_samples=$(jq '.parallel_outcomes.execution_history | length' "$LEARNING_DATA")

  if [[ $parallel_samples -lt 10 ]]; then
    echo -e "${YELLOW}Insufficient data for adaptation (need 10+ samples, have $parallel_samples)${NC}"
    return 1
  fi

  # Calculate recommended concurrent limit
  python3 <<EOF | while IFS='|' read -r recommendation confidence reason; do
import json
from statistics import mean

with open('$LEARNING_DATA') as f:
    data = json.load(f)

with open('$LEARNING_CONFIG') as f:
    config = json.load(f)

parallel_data = data['parallel_outcomes']
success_rates = [s['success_rate'] for s in parallel_data['success_rate_history']]
parallelism = [p['avg_parallelism'] for p in parallel_data['parallelism_history'] if p['avg_parallelism'] > 0]

recent_success = mean(success_rates[-5:]) if len(success_rates) >= 5 else mean(success_rates)
avg_parallelism = mean(parallelism) if parallelism else 0

target_success = config['parallel_learning']['target_success_rate']
min_concurrent = config['parallel_learning']['min_concurrent_processes']
max_concurrent = config['parallel_learning']['max_concurrent_processes']
step = config['parallel_learning']['concurrent_adjustment_step']

current_concurrent = int('$current_concurrent')

# Determine recommendation
if recent_success < target_success * 100:
    # Success rate too low - reduce concurrency
    new_concurrent = max(current_concurrent - step, min_concurrent)
    reason = f"Success rate {recent_success:.1f}% below target {target_success*100:.1f}%"
elif recent_success >= target_success * 100 and avg_parallelism >= current_concurrent * 0.8:
    # High success and high utilization - can increase
    new_concurrent = min(current_concurrent + step, max_concurrent)
    reason = f"High success ({recent_success:.1f}%) and utilization ({avg_parallelism:.1f}/{current_concurrent})"
else:
    # Stable performance
    new_concurrent = current_concurrent
    reason = f"Performance stable at {recent_success:.1f}% success"

# Calculate confidence
confidence = min(1.0, len(success_rates) / 30.0)

print(f"{new_concurrent}|{confidence}|{reason}")
EOF

    local new_concurrent="$recommendation"
    local confidence="$confidence"
    local reason="$reason"

    echo "Analysis results:"
    echo "  Recommended concurrent limit: $new_concurrent"
    echo "  Confidence: $(echo "$confidence * 100" | bc | cut -d. -f1)%"
    echo "  Reason: $reason"
    echo

    # Check if adaptation should be applied
    local confidence_threshold=$(get_confidence_threshold)
    local should_adapt=$(echo "$confidence >= $confidence_threshold" | bc -l)

    if [[ "$should_adapt" == "1" ]] && [[ "$new_concurrent" != "$current_concurrent" ]]; then
      echo -e "${GREEN}✓ Adaptation recommended${NC}"

      if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN - Changes not applied${NC}"
      else
        # Apply adaptation
        jq --argjson concurrent "$new_concurrent" \
           '.max_concurrent_processes = $concurrent' \
           "$PARALLEL_CONFIG" > "$PARALLEL_CONFIG.tmp"
        mv "$PARALLEL_CONFIG.tmp" "$PARALLEL_CONFIG"

        # Track adjustment (create dummy function if outcome-tracker doesn't support it yet)
        if [[ -f "$OUTCOME_TRACKER" ]]; then
          # Use function name without dashes for bash
          bash -c "source '$OUTCOME_TRACKER'; track_config_adjustment 'parallel' 'max_concurrent_processes' '$current_concurrent' '$new_concurrent' '$reason'" 2>/dev/null || true
        fi

        echo -e "${GREEN}✓ Configuration updated${NC}"
        echo "  max_concurrent_processes: $current_concurrent → $new_concurrent"
      fi
    elif [[ "$new_concurrent" == "$current_concurrent" ]]; then
      echo -e "${GREEN}✓ No changes needed - configuration optimal${NC}"
    else
      echo -e "${YELLOW}⚠ Confidence too low for adaptation (${confidence} < ${confidence_threshold})${NC}"
      echo "  Will adapt once more data is collected"
    fi

  done
}

# Run full adaptation cycle
run_adaptation_cycle() {
  local dry_run="${1:-false}"

  echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║         Adaptive Configuration Manager                  ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
  echo

  if ! is_auto_tuning_enabled && [[ "$dry_run" != "true" ]]; then
    echo -e "${RED}✗ Auto-tuning is disabled${NC}"
    echo "Enable with: jq '.learning_features.auto_tuning = true' $LEARNING_CONFIG"
    return 1
  fi

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "Adaptation cycle started: $now"
  echo

  # Adapt cache configuration
  adapt_cache_config "$dry_run"
  echo

  # Adapt parallel configuration
  adapt_parallel_config "$dry_run"
  echo

  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo "Adaptation cycle complete"

  if [[ "$dry_run" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes were applied${NC}"
    echo "Run without --dry-run to apply adaptations"
  fi
}

# Show current learned optimizations
show_learned_optimizations() {
  echo -e "${BLUE}=== Learned Optimizations ===${NC}"
  echo

  local optimal_cache=$(jq -r '.learned_patterns.optimal_cache_threshold' "$LEARNING_DATA")
  local optimal_parallel=$(jq -r '.learned_patterns.optimal_concurrent_processes' "$LEARNING_DATA")

  local current_cache=$(jq -r '.similarity_threshold' "$CACHE_CONFIG")
  local current_parallel=$(jq -r '.max_concurrent_processes' "$PARALLEL_CONFIG")

  echo "Cache Threshold:"
  echo "  Current: $current_cache"
  echo "  Learned optimal: $optimal_cache"

  if [[ "$optimal_cache" != "null" ]] && [[ "$optimal_cache" != "$current_cache" ]]; then
    echo -e "  ${YELLOW}⚠ Configuration differs from learned optimal${NC}"
  fi

  echo

  echo "Concurrent Processes:"
  echo "  Current: $current_parallel"
  echo "  Learned optimal: $optimal_parallel"

  if [[ "$optimal_parallel" != "null" ]] && [[ "$optimal_parallel" != "$current_parallel" ]]; then
    echo -e "  ${YELLOW}⚠ Configuration differs from learned optimal${NC}"
  fi

  echo
}

# Apply learned optimizations
apply_learned_optimizations() {
  echo -e "${BLUE}=== Applying Learned Optimizations ===${NC}"
  echo

  local optimal_cache=$(jq -r '.learned_patterns.optimal_cache_threshold' "$LEARNING_DATA")
  local optimal_parallel=$(jq -r '.learned_patterns.optimal_concurrent_processes' "$LEARNING_DATA")

  local changes=0

  # Apply cache optimization
  if [[ "$optimal_cache" != "null" ]]; then
    local current_cache=$(jq -r '.similarity_threshold' "$CACHE_CONFIG")

    if [[ "$optimal_cache" != "$current_cache" ]]; then
      jq --argjson threshold "$optimal_cache" \
         '.similarity_threshold = $threshold' \
         "$CACHE_CONFIG" > "$CACHE_CONFIG.tmp"
      mv "$CACHE_CONFIG.tmp" "$CACHE_CONFIG"

      echo -e "${GREEN}✓ Cache threshold updated: $current_cache → $optimal_cache${NC}"
      changes=$((changes + 1))
    else
      echo "✓ Cache threshold already optimal"
    fi
  else
    echo "⚠ Optimal cache threshold not yet learned"
  fi

  # Apply parallel optimization
  if [[ "$optimal_parallel" != "null" ]]; then
    local current_parallel=$(jq -r '.max_concurrent_processes' "$PARALLEL_CONFIG")

    if [[ "$optimal_parallel" != "$current_parallel" ]]; then
      jq --argjson concurrent "$optimal_parallel" \
         '.max_concurrent_processes = $concurrent' \
         "$PARALLEL_CONFIG" > "$PARALLEL_CONFIG.tmp"
      mv "$PARALLEL_CONFIG.tmp" "$PARALLEL_CONFIG"

      echo -e "${GREEN}✓ Concurrent processes updated: $current_parallel → $optimal_parallel${NC}"
      changes=$((changes + 1))
    else
      echo "✓ Concurrent processes already optimal"
    fi
  else
    echo "⚠ Optimal concurrent processes not yet learned"
  fi

  echo
  echo "Total changes applied: $changes"
}

# Enable/disable auto-tuning
configure_auto_tuning() {
  local action="$1"

  if [[ "$action" == "enable" ]]; then
    jq '.learning_features.auto_tuning = true' "$LEARNING_CONFIG" > "$LEARNING_CONFIG.tmp"
    mv "$LEARNING_CONFIG.tmp" "$LEARNING_CONFIG"
    echo -e "${GREEN}✓ Auto-tuning enabled${NC}"
  elif [[ "$action" == "disable" ]]; then
    jq '.learning_features.auto_tuning = false' "$LEARNING_CONFIG" > "$LEARNING_CONFIG.tmp"
    mv "$LEARNING_CONFIG.tmp" "$LEARNING_CONFIG"
    echo -e "${YELLOW}⚠ Auto-tuning disabled${NC}"
  else
    echo "Usage: $0 auto-tuning {enable|disable}"
    return 1
  fi
}

# Main command dispatcher
case "${1:-run}" in
  run)
    run_adaptation_cycle "${2:-false}"
    ;;
  dry-run)
    run_adaptation_cycle "true"
    ;;
  cache)
    adapt_cache_config "${2:-false}"
    ;;
  parallel)
    adapt_parallel_config "${2:-false}"
    ;;
  show)
    show_learned_optimizations
    ;;
  apply)
    apply_learned_optimizations
    ;;
  auto-tuning)
    configure_auto_tuning "${2:-}"
    ;;
  *)
    echo "Usage: $0 {run|dry-run|cache|parallel|show|apply|auto-tuning}"
    echo
    echo "Commands:"
    echo "  run             - Run full adaptation cycle (applies changes)"
    echo "  dry-run         - Simulate adaptation without applying changes"
    echo "  cache [dry-run] - Adapt cache configuration only"
    echo "  parallel [dry-run] - Adapt parallel configuration only"
    echo "  show            - Show learned optimizations"
    echo "  apply           - Apply all learned optimizations immediately"
    echo "  auto-tuning {enable|disable} - Control auto-tuning feature"
    exit 1
    ;;
esac
