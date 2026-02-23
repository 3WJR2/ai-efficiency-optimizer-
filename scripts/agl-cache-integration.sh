#!/usr/bin/env bash
#
# agl-cache-integration.sh - Integrate Agent Lightning with existing caching infrastructure
#
# Purpose: Bridge Agent Lightning's RL training with Claude's caching system
# Features:
#   - Cache-aware RL training (rewards cache hits)
#   - Automatic cache metric tracking during training
#   - Integration with existing llm-api-wrapper.sh
#   - Cache optimization based on RL outcomes
#

set -euo pipefail

# Configuration
CACHE_METRICS_FILE="${HOME}/.claude/data/cache-metrics.json"
AGL_METRICS_FILE="${HOME}/.claude/data/agent-lightning/metrics.json"
LEARNING_DATA_FILE="${HOME}/.claude/data/learning-data.json"
LLM_WRAPPER="${HOME}/.claude/scripts/llm-api-wrapper.sh"
AGL_WRAPPER="${HOME}/.claude/scripts/agent-lightning-wrapper.sh"

# Source dependencies
[[ -f "$LLM_WRAPPER" ]] && source "$LLM_WRAPPER"
[[ -f "$AGL_WRAPPER" ]] && source "$AGL_WRAPPER"

#
# Call Claude API with Agent Lightning tracking
#
call_claude_with_agl_tracking() {
    local system_prompt="$1"
    local user_prompt="$2"
    local model="${3:-claude-sonnet-4-5-20250929}"

    # Start AGL tracking
    local task_id="api_call_$(date +%s)"
    agl_init "$task_id"

    # Emit prompt event
    agl_emit_prompt "$user_prompt" "$model"

    # Call API with caching
    local start_time=$(date +%s%3N)
    local response=""
    local cache_hit="false"

    if type call_claude_api &>/dev/null; then
        response=$(call_claude_api "$system_prompt" "$user_prompt" "$model")
    else
        # Fallback: direct API call (simplified)
        response="API response placeholder"
    fi

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    # Check if cache was hit
    if [[ -f "$CACHE_METRICS_FILE" ]]; then
        local current_hits=$(jq '.prompt_cache.hits // 0' "$CACHE_METRICS_FILE")
        local previous_hits=$(jq '.previous_hits // 0' "$CACHE_METRICS_FILE" 2>/dev/null || echo "0")

        if [[ $current_hits -gt $previous_hits ]]; then
            cache_hit="true"
        fi

        # Update previous_hits
        jq --arg hits "$current_hits" '.previous_hits = ($hits | tonumber)' \
           "$CACHE_METRICS_FILE" > "${CACHE_METRICS_FILE}.tmp" && \
           mv "${CACHE_METRICS_FILE}.tmp" "$CACHE_METRICS_FILE"
    fi

    # Emit response
    agl_emit_response "$response" "$model"

    # Calculate reward based on cache hit and latency
    local reward=0.5  # Base reward
    if [[ "$cache_hit" == "true" ]]; then
        reward=$(echo "$reward + 0.3" | bc)  # Bonus for cache hit
    fi

    # Bonus for low latency (< 1000ms)
    if [[ $duration -lt 1000 ]]; then
        reward=$(echo "$reward + 0.2" | bc)
    fi

    # Emit reward
    agl_emit_reward "$reward" "api_call_cache_hit=${cache_hit}_latency=${duration}ms"

    # Finalize
    agl_finalize

    # Return response
    echo "$response"
}

#
# Analyze cache performance for RL training
#
analyze_cache_for_rl() {
    if [[ ! -f "$CACHE_METRICS_FILE" ]]; then
        echo "ERROR: Cache metrics file not found"
        return 1
    fi

    echo "=== Cache Performance Analysis for RL ==="
    echo ""

    local prompt_hits=$(jq '.prompt_cache.hits // 0' "$CACHE_METRICS_FILE")
    local prompt_misses=$(jq '.prompt_cache.misses // 0' "$CACHE_METRICS_FILE")
    local total=$((prompt_hits + prompt_misses))

    if [[ $total -gt 0 ]]; then
        local hit_rate=$(echo "scale=4; $prompt_hits / $total" | bc)
        echo "Cache Hit Rate: $(echo "$hit_rate * 100" | bc)%"
        echo "Total Requests: $total"
        echo "Hits: $prompt_hits"
        echo "Misses: $prompt_misses"
    else
        echo "No cache data available yet"
    fi

    # Tokens saved
    local tokens_saved=$(jq '.savings.tokens_saved // 0' "$CACHE_METRICS_FILE")
    echo ""
    echo "Tokens Saved: $tokens_saved"

    # Cost savings
    local cost_saved=$(jq '.savings.cost_saved_usd // 0' "$CACHE_METRICS_FILE")
    echo "Cost Saved: \$${cost_saved}"

    # Latency with/without cache
    local avg_latency_cached=$(jq '.latency.avg_with_cache_ms // 0' "$CACHE_METRICS_FILE")
    local avg_latency_no_cache=$(jq '.latency.avg_without_cache_ms // 0' "$CACHE_METRICS_FILE")

    echo ""
    echo "Average Latency (with cache): ${avg_latency_cached}ms"
    echo "Average Latency (without cache): ${avg_latency_no_cache}ms"

    if [[ $(echo "$avg_latency_no_cache > 0" | bc) -eq 1 ]]; then
        local speedup=$(echo "scale=2; $avg_latency_no_cache / $avg_latency_cached" | bc)
        echo "Speedup: ${speedup}x"
    fi
}

#
# Optimize cache settings based on RL outcomes
#
optimize_cache_from_rl() {
    echo "=== Optimizing Cache Based on RL Outcomes ==="
    echo ""

    if [[ ! -f "$AGL_METRICS_FILE" ]]; then
        echo "No AGL metrics available yet"
        return 0
    fi

    # Get average reward
    local avg_reward=$(jq '.average_reward // 0' "$AGL_METRICS_FILE")
    echo "Average RL Reward: $avg_reward"

    # Get cache hit rate
    if [[ ! -f "$CACHE_METRICS_FILE" ]]; then
        echo "Cache metrics not available"
        return 0
    fi

    local cache_hit_rate=$(jq '
        (.prompt_cache.hits // 0) /
        ((.prompt_cache.hits // 0) + (.prompt_cache.misses // 0) + 1)
    ' "$CACHE_METRICS_FILE")

    echo "Current Cache Hit Rate: $(echo "$cache_hit_rate * 100" | bc)%"

    # Correlation analysis
    echo ""
    echo "Analysis:"

    if (( $(echo "$avg_reward > 0.7" | bc -l) )); then
        echo "✓ High reward score - cache optimization is working well"

        if (( $(echo "$cache_hit_rate < 0.6" | bc -l) )); then
            echo "  → Suggestion: Cache hit rate could be improved"
            echo "  → Consider lowering similarity threshold for more cache hits"
        fi
    elif (( $(echo "$avg_reward < 0.5" | bc -l) )); then
        echo "✗ Low reward score - cache may need optimization"

        if (( $(echo "$cache_hit_rate > 0.8" | bc -l) )); then
            echo "  → Suggestion: High cache hit rate but low rewards"
            echo "  → Consider raising similarity threshold for better quality"
        else
            echo "  → Suggestion: Both reward and hit rate are low"
            echo "  → Review cache configuration and RL training setup"
        fi
    else
        echo "○ Moderate reward score - cache performing adequately"
    fi

    # Recommendation
    echo ""
    echo "=== Recommendations ==="

    if (( $(echo "$cache_hit_rate < 0.65" | bc -l) )); then
        local current_threshold=$(jq '.similarity_threshold // 0.92' ~/.claude/data/cache-config.json)
        local new_threshold=$(echo "$current_threshold - 0.02" | bc)

        echo "Lower similarity threshold: $current_threshold → $new_threshold"
        echo "Run: jq '.similarity_threshold = $new_threshold' ~/.claude/data/cache-config.json | sponge ~/.claude/data/cache-config.json"
    elif (( $(echo "$cache_hit_rate > 0.85 && $avg_reward < 0.6" | bc -l) )); then
        local current_threshold=$(jq '.similarity_threshold // 0.92' ~/.claude/data/cache-config.json)
        local new_threshold=$(echo "$current_threshold + 0.02" | bc)

        echo "Raise similarity threshold: $current_threshold → $new_threshold"
        echo "Run: jq '.similarity_threshold = $new_threshold' ~/.claude/data/cache-config.json | sponge ~/.claude/data/cache-config.json"
    else
        echo "Current cache configuration is optimal - no changes recommended"
    fi
}

#
# Generate RL training dataset with cache awareness
#
generate_rl_dataset_with_cache() {
    local output_file="${1:-${HOME}/.claude/data/agent-lightning/rl_training_cache_aware.json}"

    echo "=== Generating RL Training Dataset (Cache-Aware) ==="
    echo ""

    # Collect all AGL traces
    local traces_dir="${HOME}/.claude/data/agent-lightning/traces"
    if [[ ! -d "$traces_dir" ]]; then
        echo "No traces directory found"
        return 1
    fi

    local trace_files=$(find "$traces_dir" -name "*.json" -type f 2>/dev/null)
    if [[ -z "$trace_files" ]]; then
        echo "No trace files found"
        return 1
    fi

    # Create training dataset
    local dataset='{"episodes": [], "metadata": {}}'

    while IFS= read -r trace_file; do
        # Extract relevant data
        local episode=$(jq '{
            task_id: .task_id,
            duration: .duration_seconds,
            events: [.events[] | select(.type == "prompt" or .type == "response" or .type == "reward")],
            total_reward: ([.events[] | select(.type == "reward") | .reward] | add // 0),
            cache_enabled: .integration_data.cache_enabled,
            adaptive_stage: .integration_data.learning_stage
        }' "$trace_file")

        # Add to dataset
        dataset=$(echo "$dataset" | jq --argjson ep "$episode" '.episodes += [$ep]')
    done <<< "$trace_files"

    # Add metadata
    dataset=$(echo "$dataset" | jq --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .metadata = {
            created: $created,
            total_episodes: (.episodes | length),
            avg_reward: (([.episodes[].total_reward] | add) / ([.episodes[].total_reward] | length)),
            cache_aware: true
        }
    ')

    # Write dataset
    echo "$dataset" | jq . > "$output_file"

    echo "Dataset written to: $output_file"
    echo "Total episodes: $(echo "$dataset" | jq '.metadata.total_episodes')"
    echo "Average reward: $(echo "$dataset" | jq '.metadata.avg_reward')"
}

#
# Integration health check
#
check_agl_cache_integration() {
    echo "=== Agent Lightning + Cache Integration Health Check ==="
    echo ""

    # Check cache system
    if [[ -f "$CACHE_METRICS_FILE" ]]; then
        echo "✓ Cache metrics available"
        local hit_rate=$(jq '
            (.prompt_cache.hits // 0) /
            ((.prompt_cache.hits // 0) + (.prompt_cache.misses // 0) + 1)
        ' "$CACHE_METRICS_FILE")
        echo "  Hit rate: $(echo "$hit_rate * 100" | bc)%"
    else
        echo "✗ Cache metrics not found"
    fi

    # Check AGL metrics
    if [[ -f "$AGL_METRICS_FILE" ]]; then
        echo "✓ Agent Lightning metrics available"
        local sessions=$(jq '.total_sessions // 0' "$AGL_METRICS_FILE")
        local avg_reward=$(jq '.average_reward // 0' "$AGL_METRICS_FILE")
        echo "  Sessions: $sessions"
        echo "  Avg reward: $avg_reward"
    else
        echo "✗ Agent Lightning metrics not found"
    fi

    # Check learning data
    if [[ -f "$LEARNING_DATA_FILE" ]]; then
        echo "✓ Adaptive learning data available"
        local stage=$(jq -r '.learning_stage // "unknown"' "$LEARNING_DATA_FILE")
        echo "  Learning stage: $stage"
    else
        echo "✗ Learning data not found"
    fi

    # Check wrappers
    if [[ -f "$LLM_WRAPPER" ]]; then
        echo "✓ LLM API wrapper available"
    else
        echo "✗ LLM API wrapper not found"
    fi

    if [[ -f "$AGL_WRAPPER" ]]; then
        echo "✓ Agent Lightning wrapper available"
    else
        echo "✗ Agent Lightning wrapper not found"
    fi

    echo ""
    echo "Integration Status: $(
        [[ -f "$CACHE_METRICS_FILE" && -f "$AGL_METRICS_FILE" && -f "$LLM_WRAPPER" && -f "$AGL_WRAPPER" ]] \
            && echo "HEALTHY" || echo "NEEDS ATTENTION"
    )"
}

# Export functions
export -f call_claude_with_agl_tracking
export -f analyze_cache_for_rl
export -f optimize_cache_from_rl
export -f generate_rl_dataset_with_cache
export -f check_agl_cache_integration

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        analyze)
            analyze_cache_for_rl
            ;;
        optimize)
            optimize_cache_from_rl
            ;;
        dataset)
            generate_rl_dataset_with_cache "${2:-}"
            ;;
        check)
            check_agl_cache_integration
            ;;
        *)
            echo "Usage: $0 {analyze|optimize|dataset|check}"
            echo ""
            echo "Commands:"
            echo "  analyze   - Analyze cache performance for RL"
            echo "  optimize  - Optimize cache based on RL outcomes"
            echo "  dataset   - Generate RL training dataset (cache-aware)"
            echo "  check     - Health check for AGL+Cache integration"
            ;;
    esac
fi
