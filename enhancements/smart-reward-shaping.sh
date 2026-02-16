#!/usr/bin/env bash
#
# Enhanced Reward Shaping for Agent-Lightning
# Makes the system smarter by using more sophisticated reward calculations
#

set -euo pipefail

# Advanced reward calculation with multiple dimensions
calculate_smart_reward() {
    local component="${1}"      # cache, parallel, etc.
    local metric_value="${2}"   # 0.0-1.0
    local metadata="${3}"       # JSON metadata

    local reward=0.0

    case "${component}" in
        cache)
            # Multi-factor cache reward
            local hit_rate=$(echo "${metadata}" | jq -r '.hit_rate // 0')
            local latency=$(echo "${metadata}" | jq -r '.latency_ms // 0')
            local query_complexity=$(echo "${metadata}" | jq -r '.query_complexity // 1')
            local time_of_day=$(date +%H)

            # Base reward from hit rate
            local base_reward
            if (( $(echo "${hit_rate} >= 0.80" | bc -l) )); then
                base_reward=1.5
            elif (( $(echo "${hit_rate} >= 0.65" | bc -l) )); then
                base_reward=1.0
            elif (( $(echo "${hit_rate} >= 0.50" | bc -l) )); then
                base_reward=0.5
            else
                base_reward=-0.2
            fi

            # Latency bonus (exponential decay)
            # Fast is better, but diminishing returns
            local latency_multiplier
            if (( latency < 100 )); then
                latency_multiplier=1.5  # Ultra fast
            elif (( latency < 500 )); then
                latency_multiplier=1.2  # Fast
            elif (( latency < 1000 )); then
                latency_multiplier=1.0  # Normal
            elif (( latency < 3000 )); then
                latency_multiplier=0.8  # Slow
            else
                latency_multiplier=0.5  # Too slow
            fi

            # Query complexity bonus
            # Harder queries get more reward for cache hits
            local complexity_multiplier
            case "${query_complexity}" in
                1) complexity_multiplier=1.0 ;;  # Simple
                2) complexity_multiplier=1.3 ;;  # Medium
                3) complexity_multiplier=1.6 ;;  # Complex
                *) complexity_multiplier=1.0 ;;
            esac

            # Time-of-day adjustment
            # Peak hours (9-17) get higher weight
            local time_multiplier
            if (( time_of_day >= 9 && time_of_day <= 17 )); then
                time_multiplier=1.2  # Peak hours - more important
            else
                time_multiplier=1.0  # Off-peak
            fi

            # Calculate final reward
            reward=$(echo "${base_reward} * ${latency_multiplier} * ${complexity_multiplier} * ${time_multiplier}" | bc -l)
            ;;

        parallel)
            # Multi-factor parallel execution reward
            local success_rate=$(echo "${metadata}" | jq -r '.success_rate // 0')
            local task_count=$(echo "${metadata}" | jq -r '.task_count // 1')
            local resource_usage=$(echo "${metadata}" | jq -r '.resource_usage // 0.5')
            local speedup_factor=$(echo "${metadata}" | jq -r '.speedup_factor // 1')

            # Base reward from success rate
            local base_reward
            if (( $(echo "${success_rate} >= 0.95" | bc -l) )); then
                base_reward=1.5
            elif (( $(echo "${success_rate} >= 0.90" | bc -l) )); then
                base_reward=1.0
            elif (( $(echo "${success_rate} >= 0.80" | bc -l) )); then
                base_reward=0.5
            else
                base_reward=-0.3
            fi

            # Task count scaling bonus
            # More parallel tasks = more impressive
            local scale_multiplier
            if (( task_count >= 10 )); then
                scale_multiplier=1.5
            elif (( task_count >= 5 )); then
                scale_multiplier=1.3
            elif (( task_count >= 3 )); then
                scale_multiplier=1.0
            else
                scale_multiplier=0.8
            fi

            # Resource efficiency bonus
            # Lower resource usage = better
            local efficiency_multiplier
            if (( $(echo "${resource_usage} < 0.3" | bc -l) )); then
                efficiency_multiplier=1.4  # Very efficient
            elif (( $(echo "${resource_usage} < 0.6" | bc -l) )); then
                efficiency_multiplier=1.2  # Efficient
            elif (( $(echo "${resource_usage} < 0.8" | bc -l) )); then
                efficiency_multiplier=1.0  # Normal
            else
                efficiency_multiplier=0.7  # Resource heavy
            fi

            # Speedup factor bonus
            # Actual speedup matters
            local speedup_multiplier
            if (( $(echo "${speedup_factor} >= 3.0" | bc -l) )); then
                speedup_multiplier=1.5
            elif (( $(echo "${speedup_factor} >= 2.0" | bc -l) )); then
                speedup_multiplier=1.2
            else
                speedup_multiplier=1.0
            fi

            # Calculate final reward
            reward=$(echo "${base_reward} * ${scale_multiplier} * ${efficiency_multiplier} * ${speedup_multiplier}" | bc -l)
            ;;

        adaptive)
            # Reward for adaptive learning improvements
            local improvement_rate=$(echo "${metadata}" | jq -r '.improvement_rate // 0')
            local confidence=$(echo "${metadata}" | jq -r '.confidence // 0.5')
            local sample_size=$(echo "${metadata}" | jq -r '.sample_size // 10')

            # Base reward from improvement
            local base_reward
            if (( $(echo "${improvement_rate} >= 0.20" | bc -l) )); then
                base_reward=2.0  # Major improvement
            elif (( $(echo "${improvement_rate} >= 0.10" | bc -l) )); then
                base_reward=1.5  # Good improvement
            elif (( $(echo "${improvement_rate} >= 0.05" | bc -l) )); then
                base_reward=1.0  # Moderate improvement
            elif (( $(echo "${improvement_rate} >= 0.0" | bc -l) )); then
                base_reward=0.3  # Small improvement
            else
                base_reward=-0.5  # Regression
            fi

            # Confidence multiplier
            local confidence_multiplier=$(echo "${confidence} + 0.5" | bc -l)

            # Sample size bonus (statistical significance)
            local sample_multiplier
            if (( sample_size >= 100 )); then
                sample_multiplier=1.3  # High confidence
            elif (( sample_size >= 50 )); then
                sample_multiplier=1.1  # Good confidence
            else
                sample_multiplier=0.9  # Low confidence
            fi

            # Calculate final reward
            reward=$(echo "${base_reward} * ${confidence_multiplier} * ${sample_multiplier}" | bc -l)
            ;;

        *)
            reward=0.0
            ;;
    esac

    # Round to 2 decimal places
    printf "%.2f" "${reward}"
}

# Temporal reward shaping (rewards decay over time)
calculate_temporal_reward() {
    local base_reward="${1}"
    local timestamp="${2}"
    local current_time=$(date +%s)

    # Calculate age in hours
    local event_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${timestamp}" +%s 2>/dev/null || echo "${current_time}")
    local age_hours=$(( (current_time - event_time) / 3600 ))

    # Apply exponential decay: reward = base_reward * e^(-decay_rate * age)
    # decay_rate = 0.01 means 1% decay per hour
    local decay_rate=0.01
    local decay_factor=$(echo "e(-${decay_rate} * ${age_hours})" | bc -l)
    local temporal_reward=$(echo "${base_reward} * ${decay_factor}" | bc -l)

    printf "%.2f" "${temporal_reward}"
}

# Context-aware reward shaping
calculate_contextual_reward() {
    local base_reward="${1}"
    local context="${2}"  # JSON: {user_type, task_type, system_load, etc}

    local user_type=$(echo "${context}" | jq -r '.user_type // "standard"')
    local task_type=$(echo "${context}" | jq -r '.task_type // "general"')
    local system_load=$(echo "${context}" | jq -r '.system_load // 0.5')

    local context_multiplier=1.0

    # User type weighting
    case "${user_type}" in
        power_user)
            context_multiplier=$(echo "${context_multiplier} * 1.5" | bc -l)
            ;;
        developer)
            context_multiplier=$(echo "${context_multiplier} * 1.3" | bc -l)
            ;;
        standard)
            context_multiplier=$(echo "${context_multiplier} * 1.0" | bc -l)
            ;;
    esac

    # Task type weighting
    case "${task_type}" in
        critical)
            context_multiplier=$(echo "${context_multiplier} * 2.0" | bc -l)
            ;;
        important)
            context_multiplier=$(echo "${context_multiplier} * 1.5" | bc -l)
            ;;
        routine)
            context_multiplier=$(echo "${context_multiplier} * 1.0" | bc -l)
            ;;
    esac

    # System load adjustment
    # Higher rewards when system is under heavy load and still performs
    if (( $(echo "${system_load} > 0.8" | bc -l) )); then
        context_multiplier=$(echo "${context_multiplier} * 1.4" | bc -l)
    elif (( $(echo "${system_load} > 0.6" | bc -l) )); then
        context_multiplier=$(echo "${context_multiplier} * 1.2" | bc -l)
    fi

    local contextual_reward=$(echo "${base_reward} * ${context_multiplier}" | bc -l)
    printf "%.2f" "${contextual_reward}"
}

# Curiosity-driven exploration bonus
calculate_exploration_bonus() {
    local config_hash="${1}"  # Hash of current configuration
    local history_file="${2}"

    # Count how many times this config was tried
    local try_count=0
    if [[ -f "${history_file}" ]]; then
        try_count=$(grep -c "${config_hash}" "${history_file}" 2>/dev/null || echo "0")
    fi

    # Bonus for trying new configurations
    # Formula: bonus = 1.0 / sqrt(try_count + 1)
    local exploration_bonus
    if (( try_count == 0 )); then
        exploration_bonus=1.0  # New configuration!
    else
        exploration_bonus=$(echo "1.0 / sqrt(${try_count} + 1)" | bc -l)
    fi

    printf "%.2f" "${exploration_bonus}"
}

# Demo usage
demo_smart_rewards() {
    echo "=== Smart Reward Shaping Demo ==="
    echo ""

    # Cache example
    echo "Example 1: Cache Performance"
    local cache_metadata='{"hit_rate": 0.85, "latency_ms": 120, "query_complexity": 2}'
    local cache_reward=$(calculate_smart_reward "cache" 0.85 "${cache_metadata}")
    echo "  Metadata: ${cache_metadata}"
    echo "  Reward: ${cache_reward}"
    echo ""

    # Parallel example
    echo "Example 2: Parallel Execution"
    local parallel_metadata='{"success_rate": 0.92, "task_count": 8, "resource_usage": 0.45, "speedup_factor": 3.2}'
    local parallel_reward=$(calculate_smart_reward "parallel" 0.92 "${parallel_metadata}")
    echo "  Metadata: ${parallel_metadata}"
    echo "  Reward: ${parallel_reward}"
    echo ""

    # Temporal decay example
    echo "Example 3: Temporal Reward Decay"
    local old_timestamp="2026-02-15T10:00:00Z"
    local temporal_reward=$(calculate_temporal_reward 1.0 "${old_timestamp}")
    echo "  Base reward: 1.0"
    echo "  Timestamp: ${old_timestamp}"
    echo "  Decayed reward: ${temporal_reward}"
    echo ""

    # Contextual example
    echo "Example 4: Contextual Reward"
    local context='{"user_type": "power_user", "task_type": "critical", "system_load": 0.85}'
    local contextual_reward=$(calculate_contextual_reward 1.0 "${context}")
    echo "  Context: ${context}"
    echo "  Base reward: 1.0"
    echo "  Contextual reward: ${contextual_reward}"
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo_smart_rewards
fi
