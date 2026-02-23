#!/bin/bash
################################################################################
# Effectiveness Tracker
# Tracks before/after measurements for adaptations and calculates ROI
################################################################################

set -euo pipefail

# Directories
CLAUDE_DIR="$HOME/.claude"
DATA_DIR="$CLAUDE_DIR/data"
EFFECTIVENESS_FILE="$DATA_DIR/effectiveness.json"
METRICS_FILE="$DATA_DIR/metrics.json"
LEARNING_DATA_FILE="$DATA_DIR/learning-data.json"

# Initialize effectiveness tracking file
init_effectiveness_store() {
    if [[ ! -f "$EFFECTIVENESS_FILE" ]]; then
        cat > "$EFFECTIVENESS_FILE" <<EOF
{
  "version": "1.0.0",
  "initialized_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_updated": "",
  "adaptation_effectiveness": {
    "cache_adaptations": [],
    "parallel_adaptations": [],
    "learning_adaptations": []
  },
  "roi_metrics": {
    "total_adaptations": 0,
    "successful_adaptations": 0,
    "failed_adaptations": 0,
    "avg_improvement_pct": 0,
    "total_cost_savings_usd": 0,
    "total_time_savings_ms": 0
  },
  "quality_trends": {
    "cache_hit_rate": [],
    "parallel_success_rate": [],
    "response_quality": [],
    "user_satisfaction": []
  },
  "baseline_metrics": {
    "cache_hit_rate": 0,
    "parallel_success_rate": 0,
    "avg_latency_ms": 0,
    "cost_per_request": 0,
    "recorded_at": ""
  }
}
EOF
    fi
}

# Record baseline metrics (before any adaptations)
record_baseline() {
    init_effectiveness_store

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "Error: No metrics data available. Run 'metrics-collector.sh collect' first."
        exit 1
    fi

    # Extract current metrics as baseline
    local cache_hit_rate=$(jq -r '.cache_metrics.current.combined.hit_rate // 0' "$METRICS_FILE")
    local parallel_success_rate=$(jq -r '.parallel_metrics.current.success_rate_pct // 100' "$METRICS_FILE")
    local avg_latency=$(jq -r '.cache_metrics.current.performance.avg_latency_ms // 0' "$METRICS_FILE")

    # Calculate average cost per request from cache metrics
    local total_requests=$(jq -r '.cache_metrics.current.combined.total_requests // 1' "$METRICS_FILE")
    local total_cost_saved=$(jq -r '.cache_metrics.current.combined.total_cost_saved_usd // 0' "$METRICS_FILE")

    # Update effectiveness file with baseline
    local tmp_file=$(mktemp)
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --argjson hit_rate "$cache_hit_rate" \
       --argjson success_rate "$parallel_success_rate" \
       --argjson latency "$avg_latency" \
       '
       .baseline_metrics.cache_hit_rate = $hit_rate |
       .baseline_metrics.parallel_success_rate = $success_rate |
       .baseline_metrics.avg_latency_ms = $latency |
       .baseline_metrics.recorded_at = $timestamp
       ' "$EFFECTIVENESS_FILE" > "$tmp_file"

    mv "$tmp_file" "$EFFECTIVENESS_FILE"

    echo "✓ Baseline metrics recorded"
    echo "  Cache hit rate: $(echo "$cache_hit_rate * 100" | bc | cut -d. -f1)%"
    echo "  Parallel success rate: $parallel_success_rate%"
    echo "  Avg latency: $avg_latency ms"
}

# Track a cache adaptation's effectiveness
track_cache_adaptation() {
    local adaptation_type="$1"
    local old_value="$2"
    local new_value="$3"

    init_effectiveness_store

    # Get metrics before and after (current state is "after")
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "Error: No metrics available"
        return 1
    fi

    local before_hit_rate="${4:-0}"  # Should be passed from adaptation event
    local after_hit_rate=$(jq -r '.cache_metrics.current.combined.hit_rate // 0' "$METRICS_FILE")
    local improvement=$(echo "($after_hit_rate - $before_hit_rate) * 100" | bc)

    # Determine if successful (improvement > 0)
    local success="true"
    if [[ $(echo "$improvement <= 0" | bc) -eq 1 ]]; then
        success="false"
    fi

    # Create adaptation record
    local adaptation_record=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "$adaptation_type",
  "old_value": $old_value,
  "new_value": $new_value,
  "before_hit_rate": $before_hit_rate,
  "after_hit_rate": $after_hit_rate,
  "improvement_pct": $improvement,
  "success": $success
}
EOF
)

    # Update effectiveness file
    local tmp_file=$(mktemp)
    jq --argjson record "$adaptation_record" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '
       .adaptation_effectiveness.cache_adaptations += [$record] |
       .roi_metrics.total_adaptations += 1 |
       .roi_metrics.successful_adaptations += (if $record.success then 1 else 0 end) |
       .roi_metrics.failed_adaptations += (if $record.success then 0 else 1 end) |
       .last_updated = $timestamp
       ' "$EFFECTIVENESS_FILE" > "$tmp_file"

    mv "$tmp_file" "$EFFECTIVENESS_FILE"

    if [[ "$success" == "true" ]]; then
        echo "✓ Cache adaptation tracked (${improvement}% improvement)"
    else
        echo "! Cache adaptation tracked (${improvement}% change)"
    fi
}

# Track a parallel execution adaptation's effectiveness
track_parallel_adaptation() {
    local adaptation_type="$1"
    local old_value="$2"
    local new_value="$3"

    init_effectiveness_store

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "Error: No metrics available"
        return 1
    fi

    local before_success_rate="${4:-100}"
    local after_success_rate=$(jq -r '.parallel_metrics.current.success_rate_pct // 100' "$METRICS_FILE")
    local before_speedup="${5:-1.0}"
    local after_speedup=$(jq -r '.parallel_metrics.current.speedup_factor // 1.0' "$METRICS_FILE")

    local improvement=$(echo "($after_success_rate - $before_success_rate)" | bc)
    local speedup_improvement=$(echo "($after_speedup - $before_speedup) * 100" | bc)

    local success="true"
    if [[ $(echo "$improvement < 0 && $speedup_improvement < 0" | bc) -eq 1 ]]; then
        success="false"
    fi

    local adaptation_record=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "$adaptation_type",
  "old_value": $old_value,
  "new_value": $new_value,
  "before_success_rate": $before_success_rate,
  "after_success_rate": $after_success_rate,
  "before_speedup": $before_speedup,
  "after_speedup": $after_speedup,
  "improvement_pct": $improvement,
  "speedup_improvement_pct": $speedup_improvement,
  "success": $success
}
EOF
)

    local tmp_file=$(mktemp)
    jq --argjson record "$adaptation_record" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '
       .adaptation_effectiveness.parallel_adaptations += [$record] |
       .roi_metrics.total_adaptations += 1 |
       .roi_metrics.successful_adaptations += (if $record.success then 1 else 0 end) |
       .roi_metrics.failed_adaptations += (if $record.success then 0 else 1 end) |
       .last_updated = $timestamp
       ' "$EFFECTIVENESS_FILE" > "$tmp_file"

    mv "$tmp_file" "$EFFECTIVENESS_FILE"

    if [[ "$success" == "true" ]]; then
        echo "✓ Parallel adaptation tracked (${improvement}% improvement)"
    else
        echo "! Parallel adaptation tracked (${improvement}% change)"
    fi
}

# Calculate overall ROI metrics
calculate_roi() {
    init_effectiveness_store

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "Error: No metrics available"
        return 1
    fi

    # Get current metrics
    local current_cost_saved=$(jq -r '.cache_metrics.current.combined.total_cost_saved_usd // 0' "$METRICS_FILE")
    local current_time_saved=$(jq -r '.parallel_metrics.current.time_saved_ms // 0' "$METRICS_FILE")

    # Calculate average improvement from all adaptations
    local cache_improvements=$(jq -r '[.adaptation_effectiveness.cache_adaptations[].improvement_pct] | add // 0' "$EFFECTIVENESS_FILE")
    local parallel_improvements=$(jq -r '[.adaptation_effectiveness.parallel_adaptations[].improvement_pct] | add // 0' "$EFFECTIVENESS_FILE")
    local total_adaptations=$(jq -r '.roi_metrics.total_adaptations // 1' "$EFFECTIVENESS_FILE")

    local avg_improvement=0
    if [[ $total_adaptations -gt 0 ]]; then
        avg_improvement=$(echo "scale=2; ($cache_improvements + $parallel_improvements) / $total_adaptations" | bc)
    fi

    # Update ROI metrics
    local tmp_file=$(mktemp)
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --argjson avg_improvement "$avg_improvement" \
       --argjson cost_saved "$current_cost_saved" \
       --argjson time_saved "$current_time_saved" \
       '
       .roi_metrics.avg_improvement_pct = $avg_improvement |
       .roi_metrics.total_cost_savings_usd = $cost_saved |
       .roi_metrics.total_time_savings_ms = $time_saved |
       .last_updated = $timestamp
       ' "$EFFECTIVENESS_FILE" > "$tmp_file"

    mv "$tmp_file" "$EFFECTIVENESS_FILE"

    echo "✓ ROI calculated"
    echo "  Avg improvement: ${avg_improvement}%"
    echo "  Total cost saved: \$$current_cost_saved"
    echo "  Total time saved: $current_time_saved ms"
}

# Record quality trend data point
record_quality_trend() {
    local trend_type="$1"  # cache_hit_rate, parallel_success_rate, response_quality, user_satisfaction

    init_effectiveness_store

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "Error: No metrics available"
        return 1
    fi

    local value=0
    case "$trend_type" in
        cache_hit_rate)
            value=$(jq -r '.cache_metrics.current.combined.hit_rate // 0' "$METRICS_FILE")
            ;;
        parallel_success_rate)
            value=$(jq -r '.parallel_metrics.current.success_rate_pct // 100' "$METRICS_FILE")
            ;;
        response_quality)
            value=$(jq -r '.session_metrics.current.quality.success_rate_pct // 0' "$METRICS_FILE")
            ;;
        user_satisfaction)
            value=$(jq -r '.session_metrics.current.quality.satisfaction_signals // 0' "$METRICS_FILE")
            ;;
        *)
            echo "Error: Unknown trend type: $trend_type"
            return 1
            ;;
    esac

    local trend_record=$(cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "value": $value
}
EOF
)

    local tmp_file=$(mktemp)
    jq --argjson record "$trend_record" \
       --arg type "$trend_type" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '
       .quality_trends[$type] += [$record] |
       .quality_trends[$type] = (.quality_trends[$type] | if length > 1000 then .[-1000:] else . end) |
       .last_updated = $timestamp
       ' "$EFFECTIVENESS_FILE" > "$tmp_file"

    mv "$tmp_file" "$EFFECTIVENESS_FILE"

    echo "✓ Quality trend recorded: $trend_type = $value"
}

# Collect all quality trends
collect_all_trends() {
    echo "Collecting quality trends..."
    record_quality_trend "cache_hit_rate"
    record_quality_trend "parallel_success_rate"
    record_quality_trend "response_quality"
    record_quality_trend "user_satisfaction"
    calculate_roi
    echo "✓ All trends collected"
}

# Show effectiveness summary
show_effectiveness_summary() {
    if [[ ! -f "$EFFECTIVENESS_FILE" ]]; then
        echo "No effectiveness data available. Run 'init' or 'baseline' first."
        exit 1
    fi

    echo "=== Effectiveness Summary ==="
    echo ""

    echo "Baseline Metrics (recorded at: $(jq -r '.baseline_metrics.recorded_at // "never"' "$EFFECTIVENESS_FILE")):"
    echo "  Cache hit rate: $(jq -r '(.baseline_metrics.cache_hit_rate * 100 | floor)' "$EFFECTIVENESS_FILE")%"
    echo "  Parallel success rate: $(jq -r '.baseline_metrics.parallel_success_rate' "$EFFECTIVENESS_FILE")%"
    echo "  Avg latency: $(jq -r '.baseline_metrics.avg_latency_ms' "$EFFECTIVENESS_FILE") ms"
    echo ""

    echo "ROI Metrics:"
    jq -r '.roi_metrics |
        "  Total adaptations: \(.total_adaptations)\n" +
        "  Successful: \(.successful_adaptations)\n" +
        "  Failed: \(.failed_adaptations)\n" +
        "  Avg improvement: \(.avg_improvement_pct)%\n" +
        "  Total cost saved: $\(.total_cost_savings_usd)\n" +
        "  Total time saved: \(.total_time_savings_ms) ms"
        ' "$EFFECTIVENESS_FILE"
    echo ""

    echo "Cache Adaptations: $(jq '.adaptation_effectiveness.cache_adaptations | length' "$EFFECTIVENESS_FILE")"
    echo "Parallel Adaptations: $(jq '.adaptation_effectiveness.parallel_adaptations | length' "$EFFECTIVENESS_FILE")"
    echo ""

    echo "Quality Trends:"
    echo "  Cache hit rate samples: $(jq '.quality_trends.cache_hit_rate | length' "$EFFECTIVENESS_FILE")"
    echo "  Parallel success rate samples: $(jq '.quality_trends.parallel_success_rate | length' "$EFFECTIVENESS_FILE")"
    echo "  Response quality samples: $(jq '.quality_trends.response_quality | length' "$EFFECTIVENESS_FILE")"
    echo "  User satisfaction samples: $(jq '.quality_trends.user_satisfaction | length' "$EFFECTIVENESS_FILE")"
}

# Show recent adaptations with effectiveness
show_recent_adaptations() {
    local count="${1:-10}"

    if [[ ! -f "$EFFECTIVENESS_FILE" ]]; then
        echo "No effectiveness data available."
        exit 1
    fi

    echo "=== Recent Adaptations (last $count) ==="
    echo ""

    echo "Cache Adaptations:"
    jq -r --argjson count "$count" '
        .adaptation_effectiveness.cache_adaptations[-$count:] | reverse | .[] |
        "  [\(.timestamp)] \(.type): \(.old_value) → \(.new_value)\n" +
        "    Hit rate: \(.before_hit_rate * 100 | floor)% → \(.after_hit_rate * 100 | floor)%\n" +
        "    Improvement: \(.improvement_pct | floor)% [\(if .success then "✓" else "✗" end)]"
        ' "$EFFECTIVENESS_FILE"
    echo ""

    echo "Parallel Adaptations:"
    jq -r --argjson count "$count" '
        .adaptation_effectiveness.parallel_adaptations[-$count:] | reverse | .[] |
        "  [\(.timestamp)] \(.type): \(.old_value) → \(.new_value)\n" +
        "    Success rate: \(.before_success_rate)% → \(.after_success_rate)%\n" +
        "    Speedup: \(.before_speedup)x → \(.after_speedup)x\n" +
        "    Improvement: \(.improvement_pct | floor)% [\(if .success then "✓" else "✗" end)]"
        ' "$EFFECTIVENESS_FILE"
}

# Show trend analysis
show_trend_analysis() {
    local trend_type="${1:-all}"

    if [[ ! -f "$EFFECTIVENESS_FILE" ]]; then
        echo "No effectiveness data available."
        exit 1
    fi

    if [[ "$trend_type" == "all" ]]; then
        echo "=== Trend Analysis (All Metrics) ==="
        echo ""

        for type in cache_hit_rate parallel_success_rate response_quality user_satisfaction; do
            echo "$type:"
            local count=$(jq ".quality_trends.$type | length" "$EFFECTIVENESS_FILE")
            if [[ $count -gt 0 ]]; then
                local first=$(jq -r ".quality_trends.$type[0].value // 0" "$EFFECTIVENESS_FILE")
                local last=$(jq -r ".quality_trends.$type[-1].value // 0" "$EFFECTIVENESS_FILE")
                local change=$(echo "scale=2; $last - $first" | bc)
                echo "  Samples: $count"
                echo "  First: $first"
                echo "  Latest: $last"
                echo "  Change: $change"
            else
                echo "  No data"
            fi
            echo ""
        done
    else
        echo "=== Trend Analysis: $trend_type ==="
        echo ""

        jq -r --arg type "$trend_type" '
            .quality_trends[$type] |
            if length > 0 then
                "Total samples: \(length)\n" +
                "First value: \(.[0].value) at \(.[0].timestamp)\n" +
                "Latest value: \(.[-1].value) at \(.[-1].timestamp)\n" +
                "Change: \((.[-1].value - .[0].value) | tostring)"
            else
                "No data available for \($type)"
            end
            ' "$EFFECTIVENESS_FILE"
    fi
}

# Main command handler
main() {
    local command="${1:-}"

    case "$command" in
        init)
            init_effectiveness_store
            echo "✓ Effectiveness tracking initialized"
            ;;
        baseline)
            record_baseline
            ;;
        track-cache)
            shift
            track_cache_adaptation "$@"
            ;;
        track-parallel)
            shift
            track_parallel_adaptation "$@"
            ;;
        collect-trends)
            collect_all_trends
            ;;
        roi)
            calculate_roi
            ;;
        summary)
            show_effectiveness_summary
            ;;
        adaptations)
            show_recent_adaptations "${2:-10}"
            ;;
        trends)
            show_trend_analysis "${2:-all}"
            ;;
        *)
            cat <<EOF
Effectiveness Tracker - Track adaptation effectiveness and ROI

Usage: $(basename "$0") <command> [options]

Commands:
  init                Initialize effectiveness tracking
  baseline            Record baseline metrics (before adaptations)
  track-cache         Track cache adaptation effectiveness
                      Args: type old_value new_value [before_hit_rate]
  track-parallel      Track parallel adaptation effectiveness
                      Args: type old_value new_value [before_success] [before_speedup]
  collect-trends      Collect all quality trend data points
  roi                 Calculate overall ROI metrics
  summary             Show effectiveness summary
  adaptations [n]     Show recent n adaptations (default: 10)
  trends [type]       Show trend analysis (all, cache_hit_rate, parallel_success_rate, etc.)

Examples:
  $(basename "$0") baseline                    # Record baseline
  $(basename "$0") collect-trends              # Collect trends
  $(basename "$0") summary                     # View summary
  $(basename "$0") adaptations 5               # Show last 5 adaptations
  $(basename "$0") trends cache_hit_rate       # Analyze cache hit rate trend
EOF
            exit 1
            ;;
    esac
}

main "$@"
