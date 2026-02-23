#!/bin/bash
################################################################################
# Metrics Collector
# Collects real metrics from all system components and aggregates into unified store
################################################################################

set -euo pipefail

# Directories
CLAUDE_DIR="$HOME/.claude"
DATA_DIR="$CLAUDE_DIR/data"
METRICS_FILE="$DATA_DIR/metrics.json"

# Initialize metrics file if it doesn't exist
init_metrics_store() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        cat > "$METRICS_FILE" <<EOF
{
  "version": "1.0.0",
  "initialized_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_collection": "",
  "collection_count": 0,
  "cache_metrics": {
    "current": {},
    "history": []
  },
  "parallel_metrics": {
    "current": {},
    "history": []
  },
  "learning_metrics": {
    "current": {},
    "history": []
  },
  "session_metrics": {
    "current": {},
    "history": []
  },
  "system_health": {
    "components": {},
    "overall_status": "unknown"
  }
}
EOF
    fi
}

# Collect cache metrics from cache-metrics.json
collect_cache_metrics() {
    local cache_metrics_file="$DATA_DIR/cache-metrics.json"

    if [[ ! -f "$cache_metrics_file" ]]; then
        echo '{"status": "no_data", "error": "cache-metrics.json not found"}'
        return
    fi

    local prompt_requests=$(jq -r '.prompt_cache.total_requests // 0' "$cache_metrics_file")
    local prompt_hits=$(jq -r '.prompt_cache.cache_hits // 0' "$cache_metrics_file")
    local prompt_misses=$(jq -r '.prompt_cache.cache_misses // 0' "$cache_metrics_file")
    local tokens_saved=$(jq -r '.prompt_cache.tokens_saved // 0' "$cache_metrics_file")
    local prompt_cost_saved=$(jq -r '.prompt_cache.cost_saved_usd // 0' "$cache_metrics_file")

    local semantic_requests=$(jq -r '.semantic_cache.total_requests // 0' "$cache_metrics_file")
    local semantic_hits=$(jq -r '.semantic_cache.cache_hits // 0' "$cache_metrics_file")
    local semantic_misses=$(jq -r '.semantic_cache.cache_misses // 0' "$cache_metrics_file")
    local semantic_cost_saved=$(jq -r '.semantic_cache.cost_saved_usd // 0' "$cache_metrics_file")
    local avg_similarity=$(jq -r '.semantic_cache.avg_similarity_score // 0' "$cache_metrics_file")

    local avg_latency=$(jq -r '.performance.avg_latency_ms // 0' "$cache_metrics_file")
    local avg_latency_cached=$(jq -r '.performance.avg_latency_with_cache_ms // 0' "$cache_metrics_file")
    local latency_reduction=$(jq -r '.performance.latency_reduction_pct // 0' "$cache_metrics_file")

    # Calculate combined hit rate
    local total_requests=$((prompt_requests + semantic_requests))
    local total_hits=$((prompt_hits + semantic_hits))
    local hit_rate=0
    if [[ $total_requests -gt 0 ]]; then
        hit_rate=$(echo "scale=4; $total_hits / $total_requests" | bc -l)
    fi

    # Total cost saved (handle empty/null values)
    prompt_cost_saved=${prompt_cost_saved:-0}
    semantic_cost_saved=${semantic_cost_saved:-0}
    local total_cost_saved=$(echo "$prompt_cost_saved + $semantic_cost_saved" | bc -l)

    cat <<EOF
{
  "status": "active",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "prompt_cache": {
    "requests": $prompt_requests,
    "hits": $prompt_hits,
    "misses": $prompt_misses,
    "hit_rate": $(if [[ $prompt_requests -gt 0 ]]; then echo "scale=4; $prompt_hits / $prompt_requests" | bc -l; else echo "0"; fi),
    "tokens_saved": $tokens_saved,
    "cost_saved_usd": $prompt_cost_saved
  },
  "semantic_cache": {
    "requests": $semantic_requests,
    "hits": $semantic_hits,
    "misses": $semantic_misses,
    "hit_rate": $(if [[ $semantic_requests -gt 0 ]]; then echo "scale=4; $semantic_hits / $semantic_requests" | bc -l; else echo "0"; fi),
    "avg_similarity": $avg_similarity,
    "cost_saved_usd": $semantic_cost_saved
  },
  "combined": {
    "total_requests": $total_requests,
    "total_hits": $total_hits,
    "hit_rate": $hit_rate,
    "total_cost_saved_usd": $total_cost_saved
  },
  "performance": {
    "avg_latency_ms": $avg_latency,
    "avg_latency_cached_ms": $avg_latency_cached,
    "latency_reduction_pct": $latency_reduction
  }
}
EOF
}

# Collect parallel execution metrics from parallel-metrics.json
collect_parallel_metrics() {
    local parallel_metrics_file="$DATA_DIR/parallel-metrics.json"

    if [[ ! -f "$parallel_metrics_file" ]]; then
        echo '{"status": "no_data", "error": "parallel-metrics.json not found"}'
        return
    fi

    local total_executions=$(jq -r '.total_executions // 0' "$parallel_metrics_file")
    local total_parallel_tasks=$(jq -r '.total_parallel_tasks // 0' "$parallel_metrics_file")
    local avg_execution_time=$(jq -r '.avg_execution_time_ms // 0' "$parallel_metrics_file")
    local avg_parallelism=$(jq -r '.avg_parallelism // 0' "$parallel_metrics_file")
    local time_saved=$(jq -r '.total_time_saved_ms // 0' "$parallel_metrics_file")
    local success_rate=$(jq -r '.success_rate // 100' "$parallel_metrics_file")

    # Calculate speedup factor
    local speedup=1.0
    if [[ $(echo "$avg_execution_time > 0 && $time_saved > 0" | bc) -eq 1 ]]; then
        speedup=$(echo "scale=2; 1 + ($time_saved / $avg_execution_time)" | bc)
    fi

    cat <<EOF
{
  "status": "active",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "executions": $total_executions,
  "parallel_tasks": $total_parallel_tasks,
  "avg_execution_time_ms": $avg_execution_time,
  "avg_parallelism": $avg_parallelism,
  "time_saved_ms": $time_saved,
  "success_rate_pct": $success_rate,
  "speedup_factor": $speedup
}
EOF
}

# Collect learning system metrics from learning-data.json
collect_learning_metrics() {
    local learning_data_file="$DATA_DIR/learning-data.json"

    if [[ ! -f "$learning_data_file" ]]; then
        echo '{"status": "no_data", "error": "learning-data.json not found"}'
        return
    fi

    # Use head to read only the beginning of the file (first 200 lines should contain summary data)
    local learning_summary=$(head -200 "$learning_data_file" | jq -c '. | {
        cache_outcomes: .cache_outcomes,
        parallel_outcomes: .parallel_outcomes,
        learned_patterns: .learned_patterns,
        adaptation_log: .adaptation_log
    }' 2>/dev/null || echo '{}')

    # Extract key metrics
    local cache_samples=$(echo "$learning_summary" | jq -r '.cache_outcomes.hit_rate_history | length // 0')
    local parallel_samples=$(echo "$learning_summary" | jq -r '.parallel_outcomes.success_rate_history | length // 0')
    local adaptations=$(echo "$learning_summary" | jq -r '.adaptation_log | length // 0')

    # Get latest learned patterns
    local optimal_cache_threshold=$(echo "$learning_summary" | jq -r '.learned_patterns.optimal_cache_threshold // 0')
    local optimal_concurrent=$(echo "$learning_summary" | jq -r '.learned_patterns.optimal_concurrent_processes // 0')
    local learning_confidence=$(echo "$learning_summary" | jq -r '.learned_patterns.confidence // 0')

    cat <<EOF
{
  "status": "active",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "samples": {
    "cache_outcomes": $cache_samples,
    "parallel_outcomes": $parallel_samples
  },
  "adaptations": {
    "total_count": $adaptations
  },
  "learned_patterns": {
    "optimal_cache_threshold": $optimal_cache_threshold,
    "optimal_concurrent_processes": $optimal_concurrent,
    "confidence": $learning_confidence
  }
}
EOF
}

# Collect session metrics from user-profile.json and session-history.json
collect_session_metrics() {
    local user_profile_file="$DATA_DIR/user-profile.json"
    local session_history_file="$DATA_DIR/session-history.json"

    if [[ ! -f "$user_profile_file" ]]; then
        echo '{"status": "no_data", "error": "user-profile.json not found"}'
        return
    fi

    local interaction_count=$(jq -r '.profile.interaction_count // 0' "$user_profile_file")
    local learning_stage=$(jq -r '.profile.learning_stage // "unknown"' "$user_profile_file")
    local satisfaction_signals=$(jq -r '.profile.quality_metrics.satisfaction_signals // 0' "$user_profile_file")
    local retry_rate=$(jq -r '.profile.quality_metrics.retry_rate // 0' "$user_profile_file")
    local clarification_rate=$(jq -r '.profile.quality_metrics.clarification_rate // 0' "$user_profile_file")
    local success_rate=$(jq -r '.profile.quality_metrics.success_rate // 0' "$user_profile_file")

    # Session history if available
    local active_sessions=0
    local completed_sessions=0
    if [[ -f "$session_history_file" ]]; then
        active_sessions=$(jq '[.sessions[] | select(.status == "active")] | length' "$session_history_file" 2>/dev/null || echo "0")
        completed_sessions=$(jq '[.sessions[] | select(.status == "completed")] | length' "$session_history_file" 2>/dev/null || echo "0")
    fi

    cat <<EOF
{
  "status": "active",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "interactions": {
    "total_count": $interaction_count,
    "learning_stage": "$learning_stage"
  },
  "quality": {
    "satisfaction_signals": $satisfaction_signals,
    "retry_rate_pct": $retry_rate,
    "clarification_rate_pct": $clarification_rate,
    "success_rate_pct": $success_rate
  },
  "sessions": {
    "active": $active_sessions,
    "completed": $completed_sessions
  }
}
EOF
}

# Check system health for all components
check_system_health() {
    local cache_status="unknown"
    local parallel_status="unknown"
    local learning_status="unknown"
    local session_status="unknown"

    # Check cache system
    if [[ -f "$DATA_DIR/cache-metrics.json" ]]; then
        cache_status="healthy"
    else
        cache_status="no_data"
    fi

    # Check parallel system
    if [[ -f "$DATA_DIR/parallel-metrics.json" ]]; then
        parallel_status="healthy"
    else
        parallel_status="no_data"
    fi

    # Check learning system
    if [[ -f "$DATA_DIR/learning-data.json" ]]; then
        learning_status="healthy"
    else
        learning_status="no_data"
    fi

    # Check session system
    if [[ -f "$DATA_DIR/user-profile.json" ]]; then
        session_status="healthy"
    else
        session_status="no_data"
    fi

    # Overall health
    local overall_status="healthy"
    if [[ "$cache_status" == "no_data" && "$parallel_status" == "no_data" && \
          "$learning_status" == "no_data" && "$session_status" == "no_data" ]]; then
        overall_status="critical"
    elif [[ "$cache_status" == "no_data" || "$parallel_status" == "no_data" || \
            "$learning_status" == "no_data" || "$session_status" == "no_data" ]]; then
        overall_status="degraded"
    fi

    cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "components": {
    "cache_system": "$cache_status",
    "parallel_execution": "$parallel_status",
    "learning_system": "$learning_status",
    "session_management": "$session_status"
  },
  "overall_status": "$overall_status"
}
EOF
}

# Collect all metrics and update unified store
collect_all_metrics() {
    init_metrics_store

    echo "Collecting metrics from all systems..."

    # Collect from each system
    local cache_data=$(collect_cache_metrics)
    local parallel_data=$(collect_parallel_metrics)
    local learning_data=$(collect_learning_metrics)
    local session_data=$(collect_session_metrics)
    local health_data=$(check_system_health)

    # Update metrics file
    local tmp_file=$(mktemp)
    jq --argjson cache "$cache_data" \
       --argjson parallel "$parallel_data" \
       --argjson learning "$learning_data" \
       --argjson session "$session_data" \
       --argjson health "$health_data" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '
       .last_collection = $timestamp |
       .collection_count += 1 |
       .cache_metrics.current = $cache |
       .cache_metrics.history += [$cache] |
       .cache_metrics.history = (.cache_metrics.history | if length > 100 then .[-100:] else . end) |
       .parallel_metrics.current = $parallel |
       .parallel_metrics.history += [$parallel] |
       .parallel_metrics.history = (.parallel_metrics.history | if length > 100 then .[-100:] else . end) |
       .learning_metrics.current = $learning |
       .learning_metrics.history += [$learning] |
       .learning_metrics.history = (.learning_metrics.history | if length > 100 then .[-100:] else . end) |
       .session_metrics.current = $session |
       .session_metrics.history += [$session] |
       .session_metrics.history = (.session_metrics.history | if length > 100 then .[-100:] else . end) |
       .system_health = $health
       ' "$METRICS_FILE" > "$tmp_file"

    mv "$tmp_file" "$METRICS_FILE"

    echo "✓ Metrics collected successfully"
    echo "  Collection count: $(jq -r '.collection_count' "$METRICS_FILE")"
    echo "  Last collection: $(jq -r '.last_collection' "$METRICS_FILE")"
    echo "  Overall health: $(jq -r '.system_health.overall_status' "$METRICS_FILE")"
}

# Show current metrics summary
show_summary() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "No metrics data available. Run 'collect' first."
        exit 1
    fi

    echo "=== Metrics Summary ==="
    echo ""
    echo "Collection Info:"
    echo "  Total collections: $(jq -r '.collection_count' "$METRICS_FILE")"
    echo "  Last collection: $(jq -r '.last_collection' "$METRICS_FILE")"
    echo ""

    echo "System Health: $(jq -r '.system_health.overall_status' "$METRICS_FILE" | tr '[:lower:]' '[:upper:]')"
    jq -r '.system_health.components | to_entries[] | "  \(.key): \(.value)"' "$METRICS_FILE"
    echo ""

    echo "Cache Metrics:"
    jq -r '.cache_metrics.current |
        if .status == "active" then
            "  Total requests: \(.combined.total_requests)\n" +
            "  Hit rate: \(.combined.hit_rate * 100 | floor)%\n" +
            "  Cost saved: $\(.combined.total_cost_saved_usd)\n" +
            "  Latency reduction: \(.performance.latency_reduction_pct | floor)%"
        else
            "  Status: \(.status)"
        end' "$METRICS_FILE"
    echo ""

    echo "Parallel Execution:"
    jq -r '.parallel_metrics.current |
        if .status == "active" then
            "  Total executions: \(.executions)\n" +
            "  Speedup factor: \(.speedup_factor)x\n" +
            "  Success rate: \(.success_rate_pct)%"
        else
            "  Status: \(.status)"
        end' "$METRICS_FILE"
    echo ""

    echo "Learning System:"
    jq -r '.learning_metrics.current |
        if .status == "active" then
            "  Cache samples: \(.samples.cache_outcomes)\n" +
            "  Parallel samples: \(.samples.parallel_outcomes)\n" +
            "  Adaptations: \(.adaptations.total_count)\n" +
            "  Confidence: \(.learned_patterns.confidence * 100 | floor)%"
        else
            "  Status: \(.status)"
        end' "$METRICS_FILE"
    echo ""

    echo "Session Management:"
    jq -r '.session_metrics.current |
        if .status == "active" then
            "  Total interactions: \(.interactions.total_count)\n" +
            "  Learning stage: \(.interactions.learning_stage)\n" +
            "  Success rate: \(.quality.success_rate_pct)%"
        else
            "  Status: \(.status)"
        end' "$METRICS_FILE"
}

# Main command handler
main() {
    local command="${1:-}"

    case "$command" in
        collect)
            collect_all_metrics
            ;;
        summary|status)
            show_summary
            ;;
        cache)
            collect_cache_metrics | jq .
            ;;
        parallel)
            collect_parallel_metrics | jq .
            ;;
        learning)
            collect_learning_metrics | jq .
            ;;
        session)
            collect_session_metrics | jq .
            ;;
        health)
            check_system_health | jq .
            ;;
        *)
            cat <<EOF
Metrics Collector - Collect real metrics from all system components

Usage: $(basename "$0") <command>

Commands:
  collect         Collect metrics from all systems and update unified store
  summary         Show current metrics summary
  cache           Show cache system metrics only
  parallel        Show parallel execution metrics only
  learning        Show learning system metrics only
  session         Show session management metrics only
  health          Show system health status

Examples:
  $(basename "$0") collect          # Collect all metrics
  $(basename "$0") summary          # View summary
  $(basename "$0") health           # Check system health
EOF
            exit 1
            ;;
    esac
}

main "$@"
