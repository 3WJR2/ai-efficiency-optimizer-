#!/bin/bash
################################################################################
# Report Generator
# Generates comprehensive markdown reports with visualizations
################################################################################

set -euo pipefail

# Directories
CLAUDE_DIR="$HOME/.claude"
DATA_DIR="$CLAUDE_DIR/data"
REPORTS_DIR="$CLAUDE_DIR/reports"
METRICS_FILE="$DATA_DIR/metrics.json"
EFFECTIVENESS_FILE="$DATA_DIR/effectiveness.json"

# Ensure reports directory exists
mkdir -p "$REPORTS_DIR"

# Generate a simple text-based bar chart
generate_bar_chart() {
    local title="$1"
    local max_value="$2"
    shift 2
    local -a data=("$@")

    echo "$title"
    echo ""

    for item in "${data[@]}"; do
        local label=$(echo "$item" | cut -d: -f1)
        local value=$(echo "$item" | cut -d: -f2)
        local pct=$(echo "scale=0; ($value / $max_value) * 50" | bc)
        local bar=$(printf '█%.0s' $(seq 1 $pct 2>/dev/null || echo ""))
        printf "%-20s %s %s\n" "$label" "$bar" "$value"
    done
    echo ""
}

# Generate a sparkline from an array of values
generate_sparkline() {
    local -a values=("$@")
    local sparkline=""
    local chars="▁▂▃▄▅▆▇█"

    # Find min and max
    local min=${values[0]}
    local max=${values[0]}
    for val in "${values[@]}"; do
        if [[ $(echo "$val < $min" | bc) -eq 1 ]]; then min=$val; fi
        if [[ $(echo "$val > $max" | bc) -eq 1 ]]; then max=$val; fi
    done

    # Generate sparkline
    local range=$(echo "$max - $min" | bc)
    if [[ $(echo "$range == 0" | bc) -eq 1 ]]; then
        range=1
    fi

    for val in "${values[@]}"; do
        local normalized=$(echo "scale=2; ($val - $min) / $range" | bc)
        local index=$(echo "scale=0; $normalized * 7" | bc)
        sparkline+="${chars:$index:1}"
    done

    echo "$sparkline"
}

# Generate daily summary report
generate_daily_report() {
    local report_file="$REPORTS_DIR/daily-$(date +%Y%m%d).md"

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "Error: No metrics data available. Run 'metrics-collector.sh collect' first."
        exit 1
    fi

    cat > "$report_file" <<EOF
# Daily System Report
**Date**: $(date +"%Y-%m-%d")
**Generated**: $(date +"%Y-%m-%d %H:%M:%S")

---

## System Health

**Overall Status**: $(jq -r '.system_health.overall_status' "$METRICS_FILE" | tr '[:lower:]' '[:upper:]')

| Component | Status |
|-----------|--------|
| Cache System | $(jq -r '.system_health.components.cache_system' "$METRICS_FILE") |
| Parallel Execution | $(jq -r '.system_health.components.parallel_execution' "$METRICS_FILE") |
| Learning System | $(jq -r '.system_health.components.learning_system' "$METRICS_FILE") |
| Session Management | $(jq -r '.system_health.components.session_management' "$METRICS_FILE") |

---

## Cache System Metrics

EOF

    # Cache metrics
    local cache_status=$(jq -r '.cache_metrics.current.status' "$METRICS_FILE")
    if [[ "$cache_status" == "active" ]]; then
        cat >> "$report_file" <<EOF
**Status**: ✅ Active

### Performance
- **Total Requests**: $(jq -r '.cache_metrics.current.combined.total_requests' "$METRICS_FILE")
- **Cache Hits**: $(jq -r '.cache_metrics.current.combined.total_hits' "$METRICS_FILE")
- **Hit Rate**: $(jq -r '(.cache_metrics.current.combined.hit_rate * 100 | floor)' "$METRICS_FILE")%
- **Latency Reduction**: $(jq -r '(.cache_metrics.current.performance.latency_reduction_pct | floor)' "$METRICS_FILE")%

### Cost Savings
- **Prompt Cache Saved**: \$$(jq -r '.cache_metrics.current.prompt_cache.cost_saved_usd' "$METRICS_FILE")
- **Semantic Cache Saved**: \$$(jq -r '.cache_metrics.current.semantic_cache.cost_saved_usd' "$METRICS_FILE")
- **Total Saved**: \$$(jq -r '.cache_metrics.current.combined.total_cost_saved_usd' "$METRICS_FILE")

### Cache Breakdown

| Type | Requests | Hits | Hit Rate |
|------|----------|------|----------|
| Prompt Cache | $(jq -r '.cache_metrics.current.prompt_cache.requests' "$METRICS_FILE") | $(jq -r '.cache_metrics.current.prompt_cache.hits' "$METRICS_FILE") | $(jq -r '(.cache_metrics.current.prompt_cache.hit_rate * 100 | floor)' "$METRICS_FILE")% |
| Semantic Cache | $(jq -r '.cache_metrics.current.semantic_cache.requests' "$METRICS_FILE") | $(jq -r '.cache_metrics.current.semantic_cache.hits' "$METRICS_FILE") | $(jq -r '(.cache_metrics.current.semantic_cache.hit_rate * 100 | floor)' "$METRICS_FILE")% |

EOF
    else
        cat >> "$report_file" <<EOF
**Status**: ⚠️ $cache_status

EOF
    fi

    cat >> "$report_file" <<EOF
---

## Parallel Execution Metrics

EOF

    # Parallel metrics
    local parallel_status=$(jq -r '.parallel_metrics.current.status' "$METRICS_FILE")
    if [[ "$parallel_status" == "active" ]]; then
        cat >> "$report_file" <<EOF
**Status**: ✅ Active

### Performance
- **Total Executions**: $(jq -r '.parallel_metrics.current.executions' "$METRICS_FILE")
- **Parallel Tasks**: $(jq -r '.parallel_metrics.current.parallel_tasks' "$METRICS_FILE")
- **Avg Parallelism**: $(jq -r '.parallel_metrics.current.avg_parallelism' "$METRICS_FILE")
- **Speedup Factor**: $(jq -r '.parallel_metrics.current.speedup_factor' "$METRICS_FILE")x
- **Success Rate**: $(jq -r '.parallel_metrics.current.success_rate_pct' "$METRICS_FILE")%

### Time Savings
- **Total Time Saved**: $(jq -r '.parallel_metrics.current.time_saved_ms' "$METRICS_FILE") ms

EOF
    else
        cat >> "$report_file" <<EOF
**Status**: ⚠️ $parallel_status

EOF
    fi

    cat >> "$report_file" <<EOF
---

## Learning System Metrics

EOF

    # Learning metrics
    local learning_status=$(jq -r '.learning_metrics.current.status' "$METRICS_FILE")
    if [[ "$learning_status" == "active" ]]; then
        cat >> "$report_file" <<EOF
**Status**: ✅ Active

### Data Collection
- **Cache Outcome Samples**: $(jq -r '.learning_metrics.current.samples.cache_outcomes' "$METRICS_FILE")
- **Parallel Outcome Samples**: $(jq -r '.learning_metrics.current.samples.parallel_outcomes' "$METRICS_FILE")
- **Total Adaptations**: $(jq -r '.learning_metrics.current.adaptations.total_count' "$METRICS_FILE")

### Learned Patterns
- **Optimal Cache Threshold**: $(jq -r '.learning_metrics.current.learned_patterns.optimal_cache_threshold' "$METRICS_FILE")
- **Optimal Concurrent Processes**: $(jq -r '.learning_metrics.current.learned_patterns.optimal_concurrent_processes' "$METRICS_FILE")
- **Confidence**: $(jq -r '(.learning_metrics.current.learned_patterns.confidence * 100 | floor)' "$METRICS_FILE")%

EOF
    else
        cat >> "$report_file" <<EOF
**Status**: ⚠️ $learning_status

EOF
    fi

    cat >> "$report_file" <<EOF
---

## Session Metrics

EOF

    # Session metrics
    local session_status=$(jq -r '.session_metrics.current.status' "$METRICS_FILE")
    if [[ "$session_status" == "active" ]]; then
        cat >> "$report_file" <<EOF
**Status**: ✅ Active

### Interactions
- **Total Count**: $(jq -r '.session_metrics.current.interactions.total_count' "$METRICS_FILE")
- **Learning Stage**: $(jq -r '.session_metrics.current.interactions.learning_stage' "$METRICS_FILE")

### Quality Metrics
- **Success Rate**: $(jq -r '.session_metrics.current.quality.success_rate_pct' "$METRICS_FILE")%
- **Retry Rate**: $(jq -r '.session_metrics.current.quality.retry_rate_pct' "$METRICS_FILE")%
- **Clarification Rate**: $(jq -r '.session_metrics.current.quality.clarification_rate_pct' "$METRICS_FILE")%
- **Satisfaction Signals**: $(jq -r '.session_metrics.current.quality.satisfaction_signals' "$METRICS_FILE")

### Sessions
- **Active**: $(jq -r '.session_metrics.current.sessions.active' "$METRICS_FILE")
- **Completed**: $(jq -r '.session_metrics.current.sessions.completed' "$METRICS_FILE")

EOF
    else
        cat >> "$report_file" <<EOF
**Status**: ⚠️ $session_status

EOF
    fi

    cat >> "$report_file" <<EOF
---

## Data Quality Indicators

**Real vs Aspirational Metrics**:
- ✅ **Real**: Cache hit rates, latency measurements, cost savings
- ✅ **Real**: Parallel execution times, speedup factors
- ✅ **Real**: Learning sample counts, adaptation counts
- ⚠️ **Limited**: Session quality metrics (need more user feedback signals)

---

*Report generated by Claude Adaptive Intelligence System*
*Next report: $(date -v+1d +"%Y-%m-%d")*
EOF

    echo "✓ Daily report generated: $report_file"
}

# Generate weekly trend report
generate_weekly_report() {
    local report_file="$REPORTS_DIR/weekly-$(date +%Y-W%V).md"

    if [[ ! -f "$METRICS_FILE" ]] || [[ ! -f "$EFFECTIVENESS_FILE" ]]; then
        echo "Error: Required data files not available."
        exit 1
    fi

    cat > "$report_file" <<EOF
# Weekly Trend Report
**Week**: $(date +"%Y Week %V")
**Generated**: $(date +"%Y-%m-%d %H:%M:%S")

---

## Executive Summary

### Key Metrics
- **Total Collections**: $(jq -r '.collection_count' "$METRICS_FILE")
- **System Health**: $(jq -r '.system_health.overall_status' "$METRICS_FILE" | tr '[:lower:]' '[:upper:]')
- **Total Adaptations**: $(jq -r '.roi_metrics.total_adaptations' "$EFFECTIVENESS_FILE" 2>/dev/null || echo "0")
- **Successful Adaptations**: $(jq -r '.roi_metrics.successful_adaptations' "$EFFECTIVENESS_FILE" 2>/dev/null || echo "0")

---

## Cache System Trends

EOF

    # Get cache history for trend analysis
    local cache_history_count=$(jq '.cache_metrics.history | length' "$METRICS_FILE")
    if [[ $cache_history_count -gt 0 ]]; then
        local first_hit_rate=$(jq -r '.cache_metrics.history[0].combined.hit_rate // 0' "$METRICS_FILE")
        local last_hit_rate=$(jq -r '.cache_metrics.history[-1].combined.hit_rate // 0' "$METRICS_FILE")
        local hit_rate_change=$(echo "scale=2; ($last_hit_rate - $first_hit_rate) * 100" | bc)

        cat >> "$report_file" <<EOF
### Hit Rate Trend
- **Samples**: $cache_history_count
- **First**: $(echo "$first_hit_rate * 100" | bc | cut -d. -f1)%
- **Latest**: $(echo "$last_hit_rate * 100" | bc | cut -d. -f1)%
- **Change**: ${hit_rate_change}%

### Cost Savings Trend
- **Total Saved**: \$$(jq -r '.cache_metrics.current.combined.total_cost_saved_usd' "$METRICS_FILE")

EOF
    else
        cat >> "$report_file" <<EOF
**Status**: Insufficient data for trend analysis

EOF
    fi

    cat >> "$report_file" <<EOF
---

## Parallel Execution Trends

EOF

    local parallel_history_count=$(jq '.parallel_metrics.history | length' "$METRICS_FILE")
    if [[ $parallel_history_count -gt 0 ]]; then
        local first_speedup=$(jq -r '.parallel_metrics.history[0].speedup_factor // 1' "$METRICS_FILE")
        local last_speedup=$(jq -r '.parallel_metrics.history[-1].speedup_factor // 1' "$METRICS_FILE")
        local speedup_change=$(echo "scale=2; $last_speedup - $first_speedup" | bc)

        cat >> "$report_file" <<EOF
### Speedup Trend
- **Samples**: $parallel_history_count
- **First**: ${first_speedup}x
- **Latest**: ${last_speedup}x
- **Change**: ${speedup_change}x

### Success Rate
- **Current**: $(jq -r '.parallel_metrics.current.success_rate_pct' "$METRICS_FILE")%

EOF
    else
        cat >> "$report_file" <<EOF
**Status**: Insufficient data for trend analysis

EOF
    fi

    cat >> "$report_file" <<EOF
---

## Learning System Trends

EOF

    local learning_history_count=$(jq '.learning_metrics.history | length' "$METRICS_FILE")
    if [[ $learning_history_count -gt 0 ]]; then
        local first_confidence=$(jq -r '.learning_metrics.history[0].learned_patterns.confidence // 0' "$METRICS_FILE")
        local last_confidence=$(jq -r '.learning_metrics.history[-1].learned_patterns.confidence // 0' "$METRICS_FILE")
        local confidence_change=$(echo "scale=2; ($last_confidence - $first_confidence) * 100" | bc)

        cat >> "$report_file" <<EOF
### Learning Progress
- **Samples**: $learning_history_count
- **Cache Samples**: $(jq -r '.learning_metrics.current.samples.cache_outcomes' "$METRICS_FILE")
- **Parallel Samples**: $(jq -r '.learning_metrics.current.samples.parallel_outcomes' "$METRICS_FILE")
- **Confidence Change**: ${confidence_change}%

### Adaptation Effectiveness
EOF

        if [[ -f "$EFFECTIVENESS_FILE" ]]; then
            cat >> "$report_file" <<EOF
- **Total Adaptations**: $(jq -r '.roi_metrics.total_adaptations' "$EFFECTIVENESS_FILE")
- **Success Rate**: $(jq -r 'if .roi_metrics.total_adaptations > 0 then (.roi_metrics.successful_adaptations / .roi_metrics.total_adaptations * 100 | floor) else 0 end' "$EFFECTIVENESS_FILE")%
- **Avg Improvement**: $(jq -r '.roi_metrics.avg_improvement_pct' "$EFFECTIVENESS_FILE")%

EOF
        fi
    else
        cat >> "$report_file" <<EOF
**Status**: Insufficient data for trend analysis

EOF
    fi

    cat >> "$report_file" <<EOF
---

## Recommendations

EOF

    # Generate recommendations based on data
    local cache_hit_rate=$(jq -r '.cache_metrics.current.combined.hit_rate // 0' "$METRICS_FILE")
    local parallel_success=$(jq -r '.parallel_metrics.current.success_rate_pct // 100' "$METRICS_FILE")
    local learning_confidence=$(jq -r '.learning_metrics.current.learned_patterns.confidence // 0' "$METRICS_FILE")

    if [[ $(echo "$cache_hit_rate < 0.5" | bc) -eq 1 ]]; then
        cat >> "$report_file" <<EOF
- ⚠️ **Cache hit rate is low** ($(echo "$cache_hit_rate * 100" | bc | cut -d. -f1)%). Consider adjusting similarity threshold.
EOF
    else
        cat >> "$report_file" <<EOF
- ✅ **Cache performance is good** ($(echo "$cache_hit_rate * 100" | bc | cut -d. -f1)% hit rate).
EOF
    fi

    if [[ $(echo "$parallel_success < 90" | bc) -eq 1 ]]; then
        cat >> "$report_file" <<EOF
- ⚠️ **Parallel execution success rate is below target** ($parallel_success%). Check for resource constraints.
EOF
    else
        cat >> "$report_file" <<EOF
- ✅ **Parallel execution is performing well** ($parallel_success% success rate).
EOF
    fi

    if [[ $(echo "$learning_confidence < 0.7" | bc) -eq 1 ]]; then
        cat >> "$report_file" <<EOF
- 📊 **Learning system needs more data** ($(echo "$learning_confidence * 100" | bc | cut -d. -f1)% confidence). Continue collecting samples.
EOF
    else
        cat >> "$report_file" <<EOF
- ✅ **Learning system has high confidence** ($(echo "$learning_confidence * 100" | bc | cut -d. -f1)%).
EOF
    fi

    cat >> "$report_file" <<EOF

---

*Report generated by Claude Adaptive Intelligence System*
*Next weekly report: $(date -v+7d +"%Y-%m-%d")*
EOF

    echo "✓ Weekly report generated: $report_file"
}

# Generate learning effectiveness report
generate_learning_report() {
    local report_file="$REPORTS_DIR/learning-effectiveness-$(date +%Y%m%d).md"

    if [[ ! -f "$EFFECTIVENESS_FILE" ]]; then
        echo "Error: No effectiveness data available."
        exit 1
    fi

    cat > "$report_file" <<EOF
# Learning Effectiveness Report
**Date**: $(date +"%Y-%m-%d")
**Generated**: $(date +"%Y-%m-%d %H:%M:%S")

---

## Baseline vs Current

EOF

    if [[ -f "$EFFECTIVENESS_FILE" ]]; then
        cat >> "$report_file" <<EOF
### Cache System
- **Baseline Hit Rate**: $(jq -r '(.baseline_metrics.cache_hit_rate * 100 | floor)' "$EFFECTIVENESS_FILE")%
- **Current Hit Rate**: $(jq -r '(.cache_metrics.current.combined.hit_rate * 100 | floor)' "$METRICS_FILE" 2>/dev/null || echo "N/A")
- **Improvement**: $(jq -r 'if .baseline_metrics.cache_hit_rate > 0 then (((.cache_metrics.current.combined.hit_rate // 0) - .baseline_metrics.cache_hit_rate) * 100 | floor) else 0 end' "$EFFECTIVENESS_FILE" 2>/dev/null || echo "0")%

### Parallel Execution
- **Baseline Success Rate**: $(jq -r '.baseline_metrics.parallel_success_rate' "$EFFECTIVENESS_FILE")%
- **Current Success Rate**: $(jq -r '.parallel_metrics.current.success_rate_pct' "$METRICS_FILE" 2>/dev/null || echo "N/A")%

### Latency
- **Baseline Avg Latency**: $(jq -r '.baseline_metrics.avg_latency_ms' "$EFFECTIVENESS_FILE") ms
- **Current Avg Latency**: $(jq -r '.cache_metrics.current.performance.avg_latency_ms' "$METRICS_FILE" 2>/dev/null || echo "N/A") ms

EOF
    fi

    cat >> "$report_file" <<EOF
---

## ROI Summary

EOF

    cat >> "$report_file" <<EOF
- **Total Adaptations**: $(jq -r '.roi_metrics.total_adaptations' "$EFFECTIVENESS_FILE")
- **Successful**: $(jq -r '.roi_metrics.successful_adaptations' "$EFFECTIVENESS_FILE")
- **Failed**: $(jq -r '.roi_metrics.failed_adaptations' "$EFFECTIVENESS_FILE")
- **Success Rate**: $(jq -r 'if .roi_metrics.total_adaptations > 0 then (.roi_metrics.successful_adaptations / .roi_metrics.total_adaptations * 100 | floor) else 0 end' "$EFFECTIVENESS_FILE")%
- **Avg Improvement**: $(jq -r '.roi_metrics.avg_improvement_pct' "$EFFECTIVENESS_FILE")%

### Financial Impact
- **Total Cost Saved**: \$$(jq -r '.roi_metrics.total_cost_savings_usd' "$EFFECTIVENESS_FILE")
- **Total Time Saved**: $(jq -r '.roi_metrics.total_time_savings_ms' "$EFFECTIVENESS_FILE") ms

EOF

    cat >> "$report_file" <<EOF
---

## Recent Adaptations

### Cache Adaptations
EOF

    local cache_adaptations=$(jq -r '.adaptation_effectiveness.cache_adaptations | length' "$EFFECTIVENESS_FILE")
    if [[ $cache_adaptations -gt 0 ]]; then
        jq -r '
            .adaptation_effectiveness.cache_adaptations[-5:] | reverse | .[] |
            "- **[\(.timestamp | split("T")[0])]** \(.type): \(.old_value) → \(.new_value)\n" +
            "  - Hit rate: \(.before_hit_rate * 100 | floor)% → \(.after_hit_rate * 100 | floor)%\n" +
            "  - Result: \(if .success then "✅ Success" else "❌ Failed" end) (\(.improvement_pct | floor)% change)\n"
            ' "$EFFECTIVENESS_FILE" >> "$report_file"
    else
        echo "No cache adaptations recorded yet." >> "$report_file"
    fi

    cat >> "$report_file" <<EOF

### Parallel Adaptations
EOF

    local parallel_adaptations=$(jq -r '.adaptation_effectiveness.parallel_adaptations | length' "$EFFECTIVENESS_FILE")
    if [[ $parallel_adaptations -gt 0 ]]; then
        jq -r '
            .adaptation_effectiveness.parallel_adaptations[-5:] | reverse | .[] |
            "- **[\(.timestamp | split("T")[0])]** \(.type): \(.old_value) → \(.new_value)\n" +
            "  - Success rate: \(.before_success_rate)% → \(.after_success_rate)%\n" +
            "  - Speedup: \(.before_speedup)x → \(.after_speedup)x\n" +
            "  - Result: \(if .success then "✅ Success" else "❌ Failed" end)\n"
            ' "$EFFECTIVENESS_FILE" >> "$report_file"
    else
        echo "No parallel adaptations recorded yet." >> "$report_file"
    fi

    cat >> "$report_file" <<EOF

---

## Data Quality Assessment

**Metrics Classification**:

### Real Metrics (Measured)
- ✅ Cache hit rates (from actual API calls)
- ✅ Latency measurements (from performance monitoring)
- ✅ Cost savings (calculated from actual usage)
- ✅ Parallel execution times (from actual task runs)
- ✅ Adaptation counts (from learning system logs)

### Limited Metrics (Needs More Data)
- ⚠️ Session quality (requires more user feedback signals)
- ⚠️ User satisfaction (requires explicit feedback mechanism)
- ⚠️ Response quality trends (needs standardized scoring)

### Recommendations
1. Continue collecting real metrics from cache and parallel systems
2. Implement explicit user feedback collection for session quality
3. Add response quality scoring mechanism
4. Increase sample size for statistical significance

---

*Report generated by Claude Adaptive Intelligence System*
EOF

    echo "✓ Learning effectiveness report generated: $report_file"
}

# Generate system health report
generate_health_report() {
    local report_file="$REPORTS_DIR/system-health-$(date +%Y%m%d).md"

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "Error: No metrics data available."
        exit 1
    fi

    cat > "$report_file" <<EOF
# System Health Report
**Date**: $(date +"%Y-%m-%d")
**Generated**: $(date +"%Y-%m-%d %H:%M:%S")

---

## Overall Status

**Health**: $(jq -r '.system_health.overall_status' "$METRICS_FILE" | tr '[:lower:]' '[:upper:]')

| Component | Status | Details |
|-----------|--------|---------|
EOF

    # Cache system
    local cache_status=$(jq -r '.system_health.components.cache_system' "$METRICS_FILE")
    local cache_details=""
    if [[ "$cache_status" == "healthy" ]]; then
        cache_details="$(jq -r '(.cache_metrics.current.combined.hit_rate * 100 | floor)' "$METRICS_FILE")% hit rate"
    fi
    echo "| Cache System | $cache_status | $cache_details |" >> "$report_file"

    # Parallel system
    local parallel_status=$(jq -r '.system_health.components.parallel_execution' "$METRICS_FILE")
    local parallel_details=""
    if [[ "$parallel_status" == "healthy" ]]; then
        parallel_details="$(jq -r '.parallel_metrics.current.success_rate_pct' "$METRICS_FILE")% success rate"
    fi
    echo "| Parallel Execution | $parallel_status | $parallel_details |" >> "$report_file"

    # Learning system
    local learning_status=$(jq -r '.system_health.components.learning_system' "$METRICS_FILE")
    local learning_details=""
    if [[ "$learning_status" == "healthy" ]]; then
        learning_details="$(jq -r '.learning_metrics.current.samples.cache_outcomes' "$METRICS_FILE") samples"
    fi
    echo "| Learning System | $learning_status | $learning_details |" >> "$report_file"

    # Session management
    local session_status=$(jq -r '.system_health.components.session_management' "$METRICS_FILE")
    local session_details=""
    if [[ "$session_status" == "healthy" ]]; then
        session_details="$(jq -r '.session_metrics.current.interactions.total_count' "$METRICS_FILE") interactions"
    fi
    echo "| Session Management | $session_status | $session_details |" >> "$report_file"

    cat >> "$report_file" <<EOF

---

## Component Details

### Cache System
- **Status**: $cache_status
- **Data Source**: \`$DATA_DIR/cache-metrics.json\`
- **Last Updated**: $(jq -r '.cache_metrics.current.timestamp // "N/A"' "$METRICS_FILE")

### Parallel Execution
- **Status**: $parallel_status
- **Data Source**: \`$DATA_DIR/parallel-metrics.json\`
- **Last Updated**: $(jq -r '.parallel_metrics.current.timestamp // "N/A"' "$METRICS_FILE")

### Learning System
- **Status**: $learning_status
- **Data Source**: \`$DATA_DIR/learning-data.json\`
- **Last Updated**: $(jq -r '.learning_metrics.current.timestamp // "N/A"' "$METRICS_FILE")

### Session Management
- **Status**: $session_status
- **Data Source**: \`$DATA_DIR/user-profile.json\`
- **Last Updated**: $(jq -r '.session_metrics.current.timestamp // "N/A"' "$METRICS_FILE")

---

## Data Collection Status

- **Total Collections**: $(jq -r '.collection_count' "$METRICS_FILE")
- **Last Collection**: $(jq -r '.last_collection' "$METRICS_FILE")
- **Collection Frequency**: On-demand

---

## Alerts

EOF

    # Generate alerts based on component status
    local has_alerts=false

    if [[ "$cache_status" != "healthy" ]]; then
        echo "- ⚠️ **Cache System**: $cache_status" >> "$report_file"
        has_alerts=true
    fi

    if [[ "$parallel_status" != "healthy" ]]; then
        echo "- ⚠️ **Parallel Execution**: $parallel_status" >> "$report_file"
        has_alerts=true
    fi

    if [[ "$learning_status" != "healthy" ]]; then
        echo "- ⚠️ **Learning System**: $learning_status" >> "$report_file"
        has_alerts=true
    fi

    if [[ "$session_status" != "healthy" ]]; then
        echo "- ⚠️ **Session Management**: $session_status" >> "$report_file"
        has_alerts=true
    fi

    # Check for low confidence
    local learning_confidence=$(jq -r '.learning_metrics.current.learned_patterns.confidence // 0' "$METRICS_FILE")
    if [[ $(echo "$learning_confidence > 0 && $learning_confidence < 0.7" | bc) -eq 1 ]]; then
        echo "- 📊 **Learning Confidence Low**: $(echo "$learning_confidence * 100" | bc | cut -d. -f1)% (target: 70%+)" >> "$report_file"
        has_alerts=true
    fi

    if [[ "$has_alerts" == "false" ]]; then
        echo "✅ No alerts. All systems operating normally." >> "$report_file"
    fi

    cat >> "$report_file" <<EOF

---

*Report generated by Claude Adaptive Intelligence System*
EOF

    echo "✓ System health report generated: $report_file"
}

# List all reports
list_reports() {
    echo "=== Available Reports ==="
    echo ""

    if [[ -d "$REPORTS_DIR" ]] && [[ -n "$(ls -A "$REPORTS_DIR" 2>/dev/null)" ]]; then
        ls -lht "$REPORTS_DIR"/*.md 2>/dev/null | while read -r line; do
            local file=$(echo "$line" | awk '{print $NF}')
            local size=$(echo "$line" | awk '{print $5}')
            local date=$(echo "$line" | awk '{print $6, $7, $8}')
            echo "  $(basename "$file") - $size - $date"
        done
    else
        echo "  No reports generated yet."
    fi
}

# Main command handler
main() {
    local command="${1:-}"

    case "$command" in
        daily)
            generate_daily_report
            ;;
        weekly)
            generate_weekly_report
            ;;
        learning)
            generate_learning_report
            ;;
        health)
            generate_health_report
            ;;
        all)
            echo "Generating all reports..."
            generate_daily_report
            generate_weekly_report
            generate_learning_report
            generate_health_report
            echo "✓ All reports generated"
            ;;
        list)
            list_reports
            ;;
        view)
            local report_name="${2:-}"
            if [[ -z "$report_name" ]]; then
                echo "Error: Provide report name to view"
                exit 1
            fi
            local report_path="$REPORTS_DIR/$report_name"
            if [[ -f "$report_path" ]]; then
                cat "$report_path"
            else
                echo "Error: Report not found: $report_name"
                exit 1
            fi
            ;;
        *)
            cat <<EOF
Report Generator - Generate comprehensive system reports

Usage: $(basename "$0") <command> [options]

Commands:
  daily               Generate daily summary report
  weekly              Generate weekly trend report (7-day analysis)
  learning            Generate learning effectiveness report
  health              Generate system health report
  all                 Generate all report types
  list                List all generated reports
  view <name>         View a specific report

Report Types:
  - Daily: Current day's metrics and system status
  - Weekly: 7-day trends and analysis
  - Learning: Adaptation effectiveness and ROI
  - Health: System component health status

Examples:
  $(basename "$0") daily                # Generate today's report
  $(basename "$0") all                  # Generate all reports
  $(basename "$0") list                 # List all reports
  $(basename "$0") view daily-*.md      # View daily report

Reports are saved to: $REPORTS_DIR/
EOF
            exit 1
            ;;
    esac
}

main "$@"
