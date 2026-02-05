#!/usr/bin/env bash
# outcome-tracker.sh - Tracks execution outcomes for active learning
# Collects cache performance, parallel execution results, and patterns

set -euo pipefail

CACHE_METRICS="$HOME/.claude/data/cache-metrics.json"
PARALLEL_METRICS="$HOME/.claude/data/parallel-metrics.json"
LEARNING_DATA="$HOME/.claude/data/learning-data.json"
LEARNING_CONFIG="$HOME/.claude/data/learning-config.json"

# Ensure learning data exists
initialize_learning_data() {
  if [[ ! -f "$LEARNING_DATA" ]]; then
    cat > "$LEARNING_DATA" <<'EOF'
{
  "version": "1.0.0",
  "initialized_at": "",
  "cache_outcomes": {
    "hit_rate_history": [],
    "similarity_score_history": [],
    "latency_history": [],
    "threshold_adjustments": []
  },
  "parallel_outcomes": {
    "execution_history": [],
    "success_rate_history": [],
    "parallelism_history": [],
    "concurrent_adjustments": []
  },
  "learned_patterns": {
    "optimal_cache_threshold": null,
    "optimal_concurrent_processes": null,
    "best_performing_strategies": []
  },
  "adaptation_log": [],
  "last_analysis": null,
  "total_learning_cycles": 0
}
EOF

    # Set initialized_at timestamp
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg ts "$now" '.initialized_at = $ts' "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
    mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"
  fi
}

# Check if learning is enabled
is_learning_enabled() {
  if [[ ! -f "$LEARNING_CONFIG" ]]; then
    return 1
  fi

  local enabled=$(jq -r '.learning_enabled // false' "$LEARNING_CONFIG")
  [[ "$enabled" == "true" ]]
}

# Track cache outcome
track_cache_outcome() {
  if ! is_learning_enabled; then
    return 0
  fi

  if [[ ! -f "$CACHE_METRICS" ]]; then
    return 0
  fi

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Extract current metrics
  local total_requests=$(jq -r '.semantic_cache.total_requests' "$CACHE_METRICS")
  local cache_hits=$(jq -r '.semantic_cache.cache_hits' "$CACHE_METRICS")
  local hit_rate=$(echo "scale=4; $cache_hits / ($total_requests + 0.001)" | bc)
  local avg_similarity=$(jq -r '.semantic_cache.avg_similarity_score' "$CACHE_METRICS")
  local avg_latency=$(jq -r '.performance.avg_latency_with_cache_ms' "$CACHE_METRICS")
  local reduction_pct=$(jq -r '.performance.latency_reduction_pct' "$CACHE_METRICS")

  # Add to history
  jq --arg ts "$now" \
     --argjson hr "$hit_rate" \
     --argjson sim "$avg_similarity" \
     --argjson lat "$avg_latency" \
     --argjson red "$reduction_pct" \
     '.cache_outcomes.hit_rate_history += [{
       timestamp: $ts,
       hit_rate: $hr,
       total_requests: '"$total_requests"',
       cache_hits: '"$cache_hits"'
     }] |
     .cache_outcomes.similarity_score_history += [{
       timestamp: $ts,
       avg_similarity: $sim
     }] |
     .cache_outcomes.latency_history += [{
       timestamp: $ts,
       avg_latency_ms: $lat,
       reduction_pct: $red
     }]' "$LEARNING_DATA" > "$LEARNING_DATA.tmp"

  mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"

  echo "Cache outcome tracked: hit_rate=$hit_rate, similarity=$avg_similarity"
}

# Track parallel execution outcome
track_parallel_outcome() {
  if ! is_learning_enabled; then
    return 0
  fi

  if [[ ! -f "$PARALLEL_METRICS" ]]; then
    return 0
  fi

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Extract current metrics
  local total_executions=$(jq -r '.total_executions' "$PARALLEL_METRICS")
  local total_tasks=$(jq -r '.total_parallel_tasks' "$PARALLEL_METRICS")
  local avg_time=$(jq -r '.avg_execution_time_ms' "$PARALLEL_METRICS")
  local success_rate=$(jq -r '.success_rate' "$PARALLEL_METRICS")
  local avg_parallelism=$(jq -r '.avg_parallelism // 0' "$PARALLEL_METRICS")

  # Add to history
  jq --arg ts "$now" \
     --argjson exec "$total_executions" \
     --argjson tasks "$total_tasks" \
     --argjson time "$avg_time" \
     --argjson rate "$success_rate" \
     --argjson par "$avg_parallelism" \
     '.parallel_outcomes.execution_history += [{
       timestamp: $ts,
       total_executions: $exec,
       total_tasks: $tasks,
       avg_execution_time_ms: $time
     }] |
     .parallel_outcomes.success_rate_history += [{
       timestamp: $ts,
       success_rate: $rate
     }] |
     .parallel_outcomes.parallelism_history += [{
       timestamp: $ts,
       avg_parallelism: $par
     }]' "$LEARNING_DATA" > "$LEARNING_DATA.tmp"

  mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"

  echo "Parallel outcome tracked: executions=$total_executions, success_rate=$success_rate"
}

# Track configuration adjustment
track_config_adjustment() {
  local config_type="$1"
  local parameter="$2"
  local old_value="$3"
  local new_value="$4"
  local reason="$5"

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ "$config_type" == "cache" ]]; then
    jq --arg ts "$now" \
       --arg param "$parameter" \
       --arg old "$old_value" \
       --arg new "$new_value" \
       --arg reason "$reason" \
       '.cache_outcomes.threshold_adjustments += [{
         timestamp: $ts,
         parameter: $param,
         old_value: $old,
         new_value: $new,
         reason: $reason
       }]' "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
  elif [[ "$config_type" == "parallel" ]]; then
    jq --arg ts "$now" \
       --arg param "$parameter" \
       --arg old "$old_value" \
       --arg new "$new_value" \
       --arg reason "$reason" \
       '.parallel_outcomes.concurrent_adjustments += [{
         timestamp: $ts,
         parameter: $param,
         old_value: $old,
         new_value: $new,
         reason: $reason
       }]' "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
  fi

  mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"

  echo "Adjustment tracked: $config_type.$parameter: $old_value → $new_value ($reason)"
}

# Log adaptation decision
log_adaptation() {
  local adaptation_type="$1"
  local description="$2"
  local confidence="$3"
  local action_taken="$4"

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg ts "$now" \
     --arg type "$adaptation_type" \
     --arg desc "$description" \
     --argjson conf "$confidence" \
     --arg action "$action_taken" \
     '.adaptation_log += [{
       timestamp: $ts,
       type: $type,
       description: $desc,
       confidence: $conf,
       action_taken: $action
     }] |
     .total_learning_cycles += 1 |
     .last_analysis = $ts' "$LEARNING_DATA" > "$LEARNING_DATA.tmp"

  mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"

  echo "Adaptation logged: $adaptation_type - $description (confidence: $confidence)"
}

# Get learning statistics
get_learning_stats() {
  if [[ ! -f "$LEARNING_DATA" ]]; then
    echo "Learning data not initialized"
    return 1
  fi

  echo "=== Learning Statistics ==="
  echo

  local total_cycles=$(jq -r '.total_learning_cycles' "$LEARNING_DATA")
  local last_analysis=$(jq -r '.last_analysis // "never"' "$LEARNING_DATA")

  echo "Total learning cycles: $total_cycles"
  echo "Last analysis: $last_analysis"
  echo

  # Cache learning
  local cache_samples=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")
  local cache_adjustments=$(jq '.cache_outcomes.threshold_adjustments | length' "$LEARNING_DATA")

  echo "Cache Learning:"
  echo "  Samples collected: $cache_samples"
  echo "  Adjustments made: $cache_adjustments"

  if [[ $cache_samples -gt 0 ]]; then
    local latest_hit_rate=$(jq -r '.cache_outcomes.hit_rate_history[-1].hit_rate' "$LEARNING_DATA")
    local latest_similarity=$(jq -r '.cache_outcomes.similarity_score_history[-1].avg_similarity' "$LEARNING_DATA")
    echo "  Latest hit rate: $(echo "$latest_hit_rate * 100" | bc | cut -d. -f1)%"
    echo "  Latest similarity: $latest_similarity"
  fi

  echo

  # Parallel learning
  local parallel_samples=$(jq '.parallel_outcomes.execution_history | length' "$LEARNING_DATA")
  local parallel_adjustments=$(jq '.parallel_outcomes.concurrent_adjustments | length' "$LEARNING_DATA")

  echo "Parallel Learning:"
  echo "  Samples collected: $parallel_samples"
  echo "  Adjustments made: $parallel_adjustments"

  if [[ $parallel_samples -gt 0 ]]; then
    local latest_success=$(jq -r '.parallel_outcomes.success_rate_history[-1].success_rate' "$LEARNING_DATA")
    echo "  Latest success rate: ${latest_success}%"
  fi

  echo

  # Learned patterns
  local optimal_threshold=$(jq -r '.learned_patterns.optimal_cache_threshold // "not yet learned"' "$LEARNING_DATA")
  local optimal_concurrent=$(jq -r '.learned_patterns.optimal_concurrent_processes // "not yet learned"' "$LEARNING_DATA")

  echo "Learned Patterns:"
  echo "  Optimal cache threshold: $optimal_threshold"
  echo "  Optimal concurrent processes: $optimal_concurrent"
}

# Show recent adaptations
show_recent_adaptations() {
  local limit="${1:-10}"

  echo "=== Recent Adaptations (last $limit) ==="
  echo

  jq -r --argjson limit "$limit" '
    .adaptation_log | .[-$limit:] | reverse | .[] |
    "\(.timestamp) | \(.type) | \(.description) | confidence: \(.confidence) | \(.action_taken)"
  ' "$LEARNING_DATA" | while IFS='|' read -r timestamp type desc confidence action; do
    echo "[$timestamp]"
    echo "  Type: $type"
    echo "  Description: $desc"
    echo "  Confidence: $confidence"
    echo "  Action: $action"
    echo
  done
}

# Export learning data for analysis
export_learning_data() {
  local output_file="${1:-/tmp/learning-data-export.json}"

  jq '.' "$LEARNING_DATA" > "$output_file"
  echo "Learning data exported to: $output_file"
}

# Main command dispatcher
case "${1:-track}" in
  track)
    initialize_learning_data
    track_cache_outcome
    track_parallel_outcome
    ;;
  track-cache)
    initialize_learning_data
    track_cache_outcome
    ;;
  track-parallel)
    initialize_learning_data
    track_parallel_outcome
    ;;
  stats)
    get_learning_stats
    ;;
  adaptations)
    show_recent_adaptations "${2:-10}"
    ;;
  export)
    export_learning_data "${2:-}"
    ;;
  *)
    echo "Usage: $0 {track|track-cache|track-parallel|stats|adaptations|export}"
    echo
    echo "Commands:"
    echo "  track          - Track both cache and parallel outcomes"
    echo "  track-cache    - Track cache outcomes only"
    echo "  track-parallel - Track parallel outcomes only"
    echo "  stats          - Show learning statistics"
    echo "  adaptations    - Show recent adaptation decisions"
    echo "  export [file]  - Export learning data to file"
    exit 1
    ;;
esac
