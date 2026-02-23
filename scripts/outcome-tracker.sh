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

# Session-level tracking (Phase B enhancement)
SESSION_HISTORY="$HOME/.claude/data/session-history.json"

# Initialize session history file
initialize_session_history() {
  if [[ ! -f "$SESSION_HISTORY" ]]; then
    cat > "$SESSION_HISTORY" <<'EOF'
{
  "version": "1.0.0",
  "sessions": [],
  "total_sessions": 0,
  "last_updated": ""
}
EOF
  fi
}

# Start tracking a new session
initialize_session_tracking() {
  local session_id="${1:-session-$(date +%s)}"
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  initialize_session_history
  initialize_learning_data

  # Add session to history
  jq --arg sid "$session_id" \
     --arg ts "$now" \
     '.sessions += [{
       session_id: $sid,
       started_at: $ts,
       ended_at: null,
       outcome: "in_progress",
       satisfaction_score: null,
       insights_injected: false,
       operations: [],
       feedback: null
     }] |
     .total_sessions += 1 |
     .last_updated = $ts' "$SESSION_HISTORY" > "$SESSION_HISTORY.tmp"

  mv "$SESSION_HISTORY.tmp" "$SESSION_HISTORY"

  echo "Session tracking initialized: $session_id"
  echo "$session_id"
}

# Track an operation within a session
track_session_outcome() {
  local session_id="$1"
  local outcome="$2"
  local details="${3:-}"
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ -z "$session_id" ]]; then
    echo "Error: session_id required"
    return 1
  fi

  initialize_session_history

  # Add operation to session
  jq --arg sid "$session_id" \
     --arg ts "$now" \
     --arg out "$outcome" \
     --arg det "$details" \
     '(.sessions[] | select(.session_id == $sid) | .operations) += [{
       timestamp: $ts,
       outcome: $out,
       details: $det
     }] |
     .last_updated = $ts' "$SESSION_HISTORY" > "$SESSION_HISTORY.tmp"

  mv "$SESSION_HISTORY.tmp" "$SESSION_HISTORY"

  echo "Session outcome tracked: $session_id - $outcome"
}

# Finalize session tracking
finalize_session_tracking() {
  local session_id="$1"
  local outcome="${2:-success}"
  local satisfaction="${3:-0}"
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ -z "$session_id" ]]; then
    echo "Error: session_id required"
    return 1
  fi

  initialize_session_history

  # Update session with final data
  jq --arg sid "$session_id" \
     --arg ts "$now" \
     --arg out "$outcome" \
     --argjson sat "$satisfaction" \
     '(.sessions[] | select(.session_id == $sid)) |= {
       session_id: .session_id,
       started_at: .started_at,
       ended_at: $ts,
       outcome: $out,
       satisfaction_score: $sat,
       insights_injected: .insights_injected,
       operations: .operations,
       feedback: .feedback
     } |
     .last_updated = $ts' "$SESSION_HISTORY" > "$SESSION_HISTORY.tmp"

  mv "$SESSION_HISTORY.tmp" "$SESSION_HISTORY"

  # Update global learning data with session outcome
  if [[ "$outcome" == "success" && $satisfaction -gt 0 ]]; then
    log_adaptation "session_success" "Session completed successfully" "$satisfaction" "Positive feedback incorporated"
  fi

  echo "Session finalized: $session_id - $outcome (satisfaction: $satisfaction)"
}

# List recent sessions
list_session_history() {
  local count="${1:-10}"

  initialize_session_history

  echo "=== Recent Sessions ==="
  echo

  jq -r --argjson cnt "$count" \
    '.sessions | reverse | limit($cnt; .[]) |
     "Session: \(.session_id)\n  Started: \(.started_at)\n  Ended: \(.ended_at // "in progress")\n  Outcome: \(.outcome)\n  Satisfaction: \(.satisfaction_score // "N/A")\n  Operations: \(.operations | length)\n"' \
    "$SESSION_HISTORY"
}

# Get session statistics
get_session_statistics() {
  initialize_session_history

  echo "=== Session Statistics ==="
  echo

  local total_sessions=$(jq '.total_sessions' "$SESSION_HISTORY")
  local completed_sessions=$(jq '[.sessions[] | select(.ended_at != null)] | length' "$SESSION_HISTORY")
  local successful_sessions=$(jq '[.sessions[] | select(.outcome == "success")] | length' "$SESSION_HISTORY")

  echo "Total sessions: $total_sessions"
  echo "Completed sessions: $completed_sessions"
  echo "Successful sessions: $successful_sessions"

  if [[ $completed_sessions -gt 0 ]]; then
    local success_rate=$(echo "scale=2; $successful_sessions * 100 / $completed_sessions" | bc)
    echo "Success rate: ${success_rate}%"

    local avg_satisfaction=$(jq '[.sessions[] | select(.satisfaction_score != null) | .satisfaction_score] | add / length' "$SESSION_HISTORY")
    echo "Average satisfaction: $(printf "%.2f" "$avg_satisfaction")/10"

    local avg_operations=$(jq '[.sessions[] | .operations | length] | add / length' "$SESSION_HISTORY")
    echo "Average operations per session: $(printf "%.1f" "$avg_operations")"
  fi
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
  track-session-start)
    initialize_session_tracking "${2:-}"
    ;;
  track-session-end)
    finalize_session_tracking "${2:-}" "${3:-unknown}" "${4:-0}"
    ;;
  track-session-outcome)
    track_session_outcome "${2:-}" "${3:-success}" "${4:-}"
    ;;
  list-sessions)
    list_session_history "${2:-10}"
    ;;
  session-stats)
    get_session_statistics
    ;;
  *)
    echo "Usage: $0 {track|track-cache|track-parallel|stats|adaptations|export|track-session-start|track-session-end|track-session-outcome|list-sessions|session-stats}"
    echo
    echo "Commands:"
    echo "  track                     - Track both cache and parallel outcomes"
    echo "  track-cache               - Track cache outcomes only"
    echo "  track-parallel            - Track parallel outcomes only"
    echo "  stats                     - Show learning statistics"
    echo "  adaptations               - Show recent adaptation decisions"
    echo "  export [file]             - Export learning data to file"
    echo "  track-session-start [id]  - Initialize session tracking"
    echo "  track-session-end [id] [outcome] [satisfaction] - Finalize session"
    echo "  track-session-outcome [id] [outcome] [details] - Track session outcome"
    echo "  list-sessions [count]     - List recent sessions"
    echo "  session-stats             - Show session statistics"
    exit 1
    ;;
esac
