#!/usr/bin/env bash

# learning-reader.sh - Extract actionable insights from global learning data
# Version: 1.0.0
# Part of Phase B: Learning Integration Engine

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
LEARNING_DATA_FILE="${DATA_DIR}/learning-data.json"
USER_PROFILE_FILE="${DATA_DIR}/user-profile.json"
INTERACTION_LEARNING_FILE="${DATA_DIR}/interaction-learning.json"
CONFIDENCE_THRESHOLD="${CONFIDENCE_THRESHOLD:-0.70}"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Initialize if needed
init_learning_data() {
    if [[ ! -f "$LEARNING_DATA_FILE" ]]; then
        log "Learning data file not found, initializing..."
        cat > "$LEARNING_DATA_FILE" <<'EOF'
{
  "version": "1.0.0",
  "initialized_at": "",
  "total_learning_cycles": 0,
  "cache_outcomes": {
    "hit_rate_history": []
  },
  "parallel_outcomes": {
    "success_rate_history": []
  },
  "learned_patterns": {
    "optimal_cache_threshold": null,
    "optimal_concurrent_processes": null,
    "best_performing_strategies": []
  },
  "adaptation_log": [],
  "last_analysis": null
}
EOF
    fi

    if [[ ! -f "$USER_PROFILE_FILE" ]]; then
        log "User profile not found, creating minimal profile..."
        cat > "$USER_PROFILE_FILE" <<'EOF'
{
  "version": "1.0.0",
  "profile": {
    "learning_stage": "initialization",
    "interaction_count": 0,
    "preferences": {
      "communication_style": "adaptive",
      "detail_level": "comprehensive"
    }
  }
}
EOF
    fi
}

# Calculate confidence score based on sample size
calculate_confidence() {
    local samples=$1
    local min_samples=${2:-10}

    if [[ $samples -ge $min_samples ]]; then
        echo "0.85"
    elif [[ $samples -ge 5 ]]; then
        echo "0.70"
    elif [[ $samples -ge 3 ]]; then
        echo "0.50"
    else
        echo "0.30"
    fi
}

# Extract cache insights
get_cache_insights() {
    local confidence_threshold=$1

    if [[ ! -f "$LEARNING_DATA_FILE" ]]; then
        echo "null"
        return
    fi

    local hit_rate_count=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA_FILE" 2>/dev/null || echo "0")
    local optimal_threshold=$(jq -r '.learned_patterns.optimal_cache_threshold // "null"' "$LEARNING_DATA_FILE" 2>/dev/null || echo "null")

    if [[ $hit_rate_count -eq 0 ]]; then
        echo "null"
        return
    fi

    local confidence=$(calculate_confidence "$hit_rate_count" 10)

    # Only return if confidence meets threshold
    if (( $(echo "$confidence >= $confidence_threshold" | bc -l) )); then
        local avg_hit_rate=$(jq '[.cache_outcomes.hit_rate_history[].hit_rate] | add / length' "$LEARNING_DATA_FILE" 2>/dev/null || echo "0")

        cat <<EOF
{
  "type": "cache_optimization",
  "confidence": $confidence,
  "samples": $hit_rate_count,
  "insights": {
    "optimal_threshold": $optimal_threshold,
    "average_hit_rate": $avg_hit_rate,
    "recommendation": "Cache system is learning your patterns. Current hit rate: $(printf "%.1f%%" $(echo "$avg_hit_rate * 100" | bc -l))"
  }
}
EOF
    else
        echo "null"
    fi
}

# Extract parallel execution insights
get_parallel_insights() {
    local confidence_threshold=$1

    if [[ ! -f "$LEARNING_DATA_FILE" ]]; then
        echo "null"
        return
    fi

    local success_count=$(jq '.parallel_outcomes.success_rate_history | length' "$LEARNING_DATA_FILE" 2>/dev/null || echo "0")
    local optimal_processes=$(jq -r '.learned_patterns.optimal_concurrent_processes // "null"' "$LEARNING_DATA_FILE" 2>/dev/null || echo "null")

    if [[ $success_count -eq 0 ]]; then
        echo "null"
        return
    fi

    local confidence=$(calculate_confidence "$success_count" 10)

    if (( $(echo "$confidence >= $confidence_threshold" | bc -l) )); then
        local avg_success_rate=$(jq '[.parallel_outcomes.success_rate_history[].success_rate] | add / length' "$LEARNING_DATA_FILE" 2>/dev/null || echo "0")

        cat <<EOF
{
  "type": "parallel_optimization",
  "confidence": $confidence,
  "samples": $success_count,
  "insights": {
    "optimal_processes": $optimal_processes,
    "average_success_rate": $avg_success_rate,
    "recommendation": "Parallel execution performing well. Success rate: $(printf "%.1f%%" $(echo "$avg_success_rate * 100" | bc -l))"
  }
}
EOF
    else
        echo "null"
    fi
}

# Extract user preference insights
get_user_preferences() {
    local confidence_threshold=$1

    if [[ ! -f "$USER_PROFILE_FILE" ]]; then
        echo "null"
        return
    fi

    local interaction_count=$(jq '.profile.interaction_count // 0' "$USER_PROFILE_FILE" 2>/dev/null || echo "0")
    local learning_stage=$(jq -r '.profile.learning_stage // "initialization"' "$USER_PROFILE_FILE" 2>/dev/null || echo "initialization")

    if [[ $interaction_count -lt 5 ]]; then
        echo "null"
        return
    fi

    local confidence=$(calculate_confidence "$interaction_count" 20)

    if (( $(echo "$confidence >= $confidence_threshold" | bc -l) )); then
        local preferences=$(jq -c '.profile.preferences' "$USER_PROFILE_FILE" 2>/dev/null || echo "{}")

        cat <<EOF
{
  "type": "user_preferences",
  "confidence": $confidence,
  "samples": $interaction_count,
  "insights": {
    "learning_stage": "$learning_stage",
    "preferences": $preferences,
    "recommendation": "Learning your preferences. Stage: $learning_stage with $interaction_count interactions."
  }
}
EOF
    else
        echo "null"
    fi
}

# Extract technology preferences
get_tech_preferences() {
    local confidence_threshold=$1

    if [[ ! -f "$INTERACTION_LEARNING_FILE" ]]; then
        echo "null"
        return
    fi

    local tech_count=$(jq '.learned_preferences.technologies | length' "$INTERACTION_LEARNING_FILE" 2>/dev/null || echo "0")

    if [[ $tech_count -eq 0 ]]; then
        echo "null"
        return
    fi

    # Calculate total usage
    local total_usage=$(jq '[.learned_preferences.technologies[]] | add' "$INTERACTION_LEARNING_FILE" 2>/dev/null || echo "0")

    if [[ $total_usage -lt 10 ]]; then
        echo "null"
        return
    fi

    local confidence=$(calculate_confidence "$total_usage" 50)

    if (( $(echo "$confidence >= $confidence_threshold" | bc -l) )); then
        # Get top 3 technologies
        local top_techs=$(jq -c '[.learned_preferences.technologies | to_entries | sort_by(-.value) | limit(3; .[])]' "$INTERACTION_LEARNING_FILE" 2>/dev/null || echo "[]")

        cat <<EOF
{
  "type": "technology_preferences",
  "confidence": $confidence,
  "samples": $total_usage,
  "insights": {
    "top_technologies": $top_techs,
    "recommendation": "Primary technologies detected. Optimizing responses for your tech stack."
  }
}
EOF
    else
        echo "null"
    fi
}

# Extract successful strategies
get_successful_strategies() {
    local confidence_threshold=$1

    if [[ ! -f "$LEARNING_DATA_FILE" ]]; then
        echo "null"
        return
    fi

    local strategies=$(jq -c '.learned_patterns.best_performing_strategies // []' "$LEARNING_DATA_FILE" 2>/dev/null || echo "[]")
    local strategy_count=$(echo "$strategies" | jq 'length')

    if [[ $strategy_count -eq 0 ]]; then
        echo "null"
        return
    fi

    cat <<EOF
{
  "type": "successful_strategies",
  "confidence": 0.80,
  "samples": $strategy_count,
  "insights": {
    "strategies": $strategies,
    "recommendation": "Using proven strategies from past successes."
  }
}
EOF
}

# Extract common pitfalls
get_common_pitfalls() {
    local confidence_threshold=$1

    if [[ ! -f "$INTERACTION_LEARNING_FILE" ]]; then
        echo "null"
        return
    fi

    local pitfalls=$(jq -c '.behavioral_insights.common_pitfalls // []' "$INTERACTION_LEARNING_FILE" 2>/dev/null || echo "[]")
    local pitfall_count=$(echo "$pitfalls" | jq 'length')

    if [[ $pitfall_count -eq 0 ]]; then
        echo "null"
        return
    fi

    cat <<EOF
{
  "type": "common_pitfalls",
  "confidence": 0.75,
  "samples": $pitfall_count,
  "insights": {
    "pitfalls": $pitfalls,
    "recommendation": "Avoiding known issues from past interactions."
  }
}
EOF
}

# Main function to extract all insights
extract_insights() {
    local confidence_threshold=${1:-$CONFIDENCE_THRESHOLD}

    init_learning_data

    log "Extracting insights with confidence threshold: $confidence_threshold"

    # Collect all insights
    local insights=()

    # Cache insights
    local cache_insight=$(get_cache_insights "$confidence_threshold")
    if [[ "$cache_insight" != "null" ]]; then
        insights+=("$cache_insight")
    fi

    # Parallel insights
    local parallel_insight=$(get_parallel_insights "$confidence_threshold")
    if [[ "$parallel_insight" != "null" ]]; then
        insights+=("$parallel_insight")
    fi

    # User preferences
    local user_insight=$(get_user_preferences "$confidence_threshold")
    if [[ "$user_insight" != "null" ]]; then
        insights+=("$user_insight")
    fi

    # Tech preferences
    local tech_insight=$(get_tech_preferences "$confidence_threshold")
    if [[ "$tech_insight" != "null" ]]; then
        insights+=("$tech_insight")
    fi

    # Successful strategies
    local strategy_insight=$(get_successful_strategies "$confidence_threshold")
    if [[ "$strategy_insight" != "null" ]]; then
        insights+=("$strategy_insight")
    fi

    # Common pitfalls
    local pitfall_insight=$(get_common_pitfalls "$confidence_threshold")
    if [[ "$pitfall_insight" != "null" ]]; then
        insights+=("$pitfall_insight")
    fi

    # Build JSON output
    local json_insights="["
    local first=true
    for insight in "${insights[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json_insights+=","
        fi
        json_insights+="$insight"
    done
    json_insights+="]"

    # Output final JSON
    cat <<EOF
{
  "version": "1.0.0",
  "extracted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "confidence_threshold": $confidence_threshold,
  "total_insights": ${#insights[@]},
  "insights": $json_insights,
  "metadata": {
    "learning_data_exists": $([ -f "$LEARNING_DATA_FILE" ] && echo "true" || echo "false"),
    "user_profile_exists": $([ -f "$USER_PROFILE_FILE" ] && echo "true" || echo "false"),
    "interaction_learning_exists": $([ -f "$INTERACTION_LEARNING_FILE" ] && echo "true" || echo "false")
  }
}
EOF
}

# CLI Interface
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Extract actionable insights from global learning data.

OPTIONS:
  extract [threshold]     Extract insights (default threshold: $CONFIDENCE_THRESHOLD)
  cache                   Extract cache-specific insights
  parallel                Extract parallel-specific insights
  preferences             Extract user preference insights
  tech                    Extract technology preference insights
  all                     Extract all available insights (no threshold)
  -h, --help              Show this help message

EXAMPLES:
  $(basename "$0") extract
  $(basename "$0") extract 0.80
  $(basename "$0") cache
  $(basename "$0") all

OUTPUT:
  JSON object containing actionable insights with confidence scores

EOF
}

# Main CLI handling
main() {
    local command="${1:-extract}"

    case "$command" in
        extract)
            local threshold="${2:-$CONFIDENCE_THRESHOLD}"
            extract_insights "$threshold"
            ;;
        cache)
            get_cache_insights "$CONFIDENCE_THRESHOLD"
            ;;
        parallel)
            get_parallel_insights "$CONFIDENCE_THRESHOLD"
            ;;
        preferences)
            get_user_preferences "$CONFIDENCE_THRESHOLD"
            ;;
        tech)
            get_tech_preferences "$CONFIDENCE_THRESHOLD"
            ;;
        all)
            extract_insights 0.0
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown command: $command. Use -h for help."
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
