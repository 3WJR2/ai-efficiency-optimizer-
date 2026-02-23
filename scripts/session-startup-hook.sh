#!/usr/bin/env bash

# session-startup-hook.sh
# Hook that runs at session startup to inject relevant knowledge
# Part of Cross-Session Knowledge Synthesis Integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
LOG_DIR="${HOME}/.claude/logs"
INJECTION_LOG="${LOG_DIR}/knowledge-injection.log"

mkdir -p "$LOG_DIR"

# ============================================================================
# Logging
# ============================================================================

log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$INJECTION_LOG"
}

# ============================================================================
# Context Detection
# ============================================================================

# Analyze startup context to determine what knowledge is relevant
analyze_startup_context() {
    local session_dir="$1"
    local initial_prompt="$2"

    local context="{}"

    # Detect working directory
    local working_dir=$(jq -r '.working_directory // ""' "${session_dir}/.session-metadata.json" 2>/dev/null || echo "")
    context=$(echo "$context" | jq --arg wd "$working_dir" '. + {"working_directory": $wd}')

    # Detect technologies from prompt
    local technologies=()

    if echo "$initial_prompt" | grep -qiE "(python|django|flask)"; then
        technologies+=("python")
    fi
    if echo "$initial_prompt" | grep -qiE "(javascript|typescript|node|react|vue)"; then
        technologies+=("javascript")
    fi
    if echo "$initial_prompt" | grep -qiE "(rust|cargo)"; then
        technologies+=("rust")
    fi
    if echo "$initial_prompt" | grep -qiE "(docker|kubernetes|container)"; then
        technologies+=("docker")
    fi
    if echo "$initial_prompt" | grep -qiE "(database|postgres|mysql|mongodb|redis)"; then
        technologies+=("database")
    fi

    local tech_json=$(printf '%s\n' "${technologies[@]}" | jq -R . | jq -s .)
    context=$(echo "$context" | jq --argjson tech "$tech_json" '. + {"technologies": $tech}')

    # Detect task type
    local task_type="general"
    if echo "$initial_prompt" | grep -qiE "(bug|error|fix|issue)"; then
        task_type="debugging"
    elif echo "$initial_prompt" | grep -qiE "(implement|add|create|build)"; then
        task_type="implementation"
    elif echo "$initial_prompt" | grep -qiE "(refactor|optimize|improve)"; then
        task_type="optimization"
    elif echo "$initial_prompt" | grep -qiE "(design|architecture)"; then
        task_type="design"
    fi

    context=$(echo "$context" | jq --arg tt "$task_type" '. + {"task_type": $tt}')

    # Extract key terms from prompt
    local key_terms=$(echo "$initial_prompt" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,15}\b' | sort -u | head -20 | jq -R . | jq -s .)
    context=$(echo "$context" | jq --argjson terms "$key_terms" '. + {"key_terms": $terms}')

    echo "$context"
}

# ============================================================================
# Knowledge Search & Ranking
# ============================================================================

# Search knowledge base for relevant entries
fetch_relevant_knowledge() {
    local context="$1"
    local initial_prompt="$2"
    local limit="${3:-5}"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        log "No knowledge base found"
        echo "[]"
        return 0
    fi

    # Extract context fields
    local technologies=$(echo "$context" | jq -r '.technologies[]' 2>/dev/null || echo "")
    local task_type=$(echo "$context" | jq -r '.task_type' 2>/dev/null || echo "general")
    local key_terms=$(echo "$context" | jq -r '.key_terms[]' 2>/dev/null || echo "")

    # Build search pattern
    local search_terms="$initial_prompt $technologies $key_terms"
    search_terms=$(echo "$search_terms" | tr '[:upper:]' '[:lower:]' | tr -s ' ')

    # Search and rank knowledge entries
    local results=()
    local result_scores=()

    while IFS= read -r entry; do
        local score=0

        # Calculate relevance score
        local entry_text=$(echo "$entry" | jq -r '.problem + " " + .solution + " " + (.tags | join(" "))' | tr '[:upper:]' '[:lower:]')

        # Technology match (+20 points)
        for tech in $technologies; do
            if echo "$entry_text" | grep -q "$tech"; then
                score=$((score + 20))
            fi
        done

        # Key term match (+10 points each)
        for term in $key_terms; do
            if echo "$entry_text" | grep -q "$term"; then
                score=$((score + 10))
            fi
        done

        # Task type match (+15 points)
        local entry_type=$(echo "$entry" | jq -r '.type')
        if [[ "$task_type" == "debugging" ]] && [[ "$entry_type" == "error" || "$entry_type" == "solution" ]]; then
            score=$((score + 15))
        elif [[ "$task_type" == "implementation" ]] && [[ "$entry_type" == "solution" || "$entry_type" == "pattern" ]]; then
            score=$((score + 15))
        fi

        # Confidence bonus (up to +10 points)
        local confidence=$(echo "$entry" | jq -r '.confidence')
        local confidence_bonus=$(echo "$confidence * 10" | bc | cut -d. -f1)
        score=$((score + confidence_bonus))

        # Recency bonus (within last 7 days: +5 points)
        local timestamp=$(echo "$entry" | jq -r '.timestamp')
        local entry_date=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || echo "0")
        local now=$(date +%s)
        local days_ago=$(( (now - entry_date) / 86400 ))

        if [[ $days_ago -le 7 ]]; then
            score=$((score + 5))
        fi

        # Only include entries with score > 0
        if [[ $score -gt 0 ]]; then
            results+=("$entry")
            result_scores+=("$score")
        fi

    done < "$knowledge_base"

    # Sort by score (descending) and take top N
    local sorted_results=()

    # Simple bubble sort by score
    for ((i = 0; i < ${#results[@]}; i++)); do
        for ((j = i + 1; j < ${#results[@]}; j++)); do
            if [[ ${result_scores[i]} -lt ${result_scores[j]} ]]; then
                # Swap
                local tmp_result="${results[i]}"
                local tmp_score="${result_scores[i]}"
                results[i]="${results[j]}"
                result_scores[i]="${result_scores[j]}"
                results[j]="$tmp_result"
                result_scores[j]="$tmp_score"
            fi
        done
    done

    # Take top N
    local top_results=()
    for ((i = 0; i < ${#results[@]} && i < limit; i++)); do
        local entry="${results[i]}"
        local score="${result_scores[i]}"
        # Add relevance score to entry
        entry=$(echo "$entry" | jq --argjson score "$score" '. + {"relevance_score": $score}')
        top_results+=("$entry")
    done

    # Convert to JSON array
    printf '%s\n' "${top_results[@]}" | jq -s .
}

# ============================================================================
# Knowledge Formatting
# ============================================================================

# Format knowledge for injection into session context
format_knowledge_injection() {
    local recommendations="$1"
    local session_id="$2"

    local count=$(echo "$recommendations" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo ""
        return 0
    fi

    cat <<EOF
<!-- Auto-generated by Knowledge Synthesis System -->
<!-- Session: $session_id -->
<!-- Injection time: $(date -u +"%Y-%m-%dT%H:%M:%SZ") -->

# 💡 Relevant Past Solutions

You've encountered similar tasks before. Here's what you learned:

EOF

    # Format each recommendation
    local index=1
    echo "$recommendations" | jq -c '.[]' | while IFS= read -r entry; do
        local id=$(echo "$entry" | jq -r '.id')
        local type=$(echo "$entry" | jq -r '.type')
        local problem=$(echo "$entry" | jq -r '.problem' | head -c 200)
        local solution=$(echo "$entry" | jq -r '.solution' | head -c 500)
        local confidence=$(echo "$entry" | jq -r '.confidence')
        local timestamp=$(echo "$entry" | jq -r '.timestamp')
        local tags=$(echo "$entry" | jq -r '.tags | join(", ")')
        local code_snippet=$(echo "$entry" | jq -r '.code_snippet')
        local relevance=$(echo "$entry" | jq -r '.relevance_score')

        # Calculate days ago
        local entry_date=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || echo "0")
        local now=$(date +%s)
        local days_ago=$(( (now - entry_date) / 86400 ))

        local time_ago="$days_ago days ago"
        if [[ $days_ago -eq 0 ]]; then
            time_ago="today"
        elif [[ $days_ago -eq 1 ]]; then
            time_ago="yesterday"
        fi

        # Confidence indicator
        local conf_indicator="⭐ High Confidence"
        if (( $(echo "$confidence < 0.7" | bc -l) )); then
            conf_indicator="⚠️ Medium Confidence"
        fi
        if (( $(echo "$confidence >= 0.85" | bc -l) )); then
            conf_indicator="⭐⭐ Very High Confidence"
        fi

        cat <<ENTRY

## $index. ${problem:0:60}... $conf_indicator
**When:** $time_ago
**Problem:** $problem
**Solution:** $solution
ENTRY

        # Add code snippet if available
        if [[ -n "$code_snippet" ]] && [[ "$code_snippet" != "null" ]] && [[ ${#code_snippet} -gt 10 ]]; then
            echo "$code_snippet"
        fi

        cat <<ENTRY
**Confidence:** $confidence | **Relevance:** $relevance/100
**Tags:** $tags
**[View full solution]($KNOWLEDGE_DIR/$id.md)**
ENTRY

        ((index++))
    done

    cat <<EOF

---

**Knowledge Stats:** $count solutions | Avg confidence: $(echo "$recommendations" | jq '[.[] | .confidence] | add / length')
**View your complete knowledge graph:** \`knowledge-assistant graph\`
EOF
}

# ============================================================================
# Knowledge Injection
# ============================================================================

# Inject knowledge into session context
inject_knowledge() {
    local session_dir="$1"
    local knowledge_md="$2"

    if [[ -z "$knowledge_md" ]]; then
        return 0
    fi

    local context_file="${session_dir}/.session-context.md"

    # Append knowledge to context file
    echo "" >> "$context_file"
    echo "$knowledge_md" >> "$context_file"

    log "Injected knowledge into session context: $session_dir"
}

# Log injection for feedback tracking
log_injection() {
    local session_id="$1"
    local knowledge_ids="$2"

    local injection_log_data="${DATA_DIR}/knowledge-injection-log.json"

    if [[ ! -f "$injection_log_data" ]]; then
        echo '{"injections": []}' > "$injection_log_data"
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp_file=$(mktemp)
    jq --arg session "$session_id" \
       --arg timestamp "$timestamp" \
       --argjson ids "$knowledge_ids" \
       '.injections += [{
          "session_id": $session,
          "timestamp": $timestamp,
          "knowledge_ids": $ids,
          "was_helpful": null
        }]' \
       "$injection_log_data" > "$tmp_file" && mv "$tmp_file" "$injection_log_data"

    log "Logged injection for session: $session_id"
}

# ============================================================================
# Main Hook Function
# ============================================================================

# Main hook called at session start
on_session_start() {
    local session_dir="$1"
    local initial_prompt="${2:-}"

    log "Session startup hook triggered: $(basename "$session_dir")"

    # Skip if no initial prompt
    if [[ -z "$initial_prompt" ]]; then
        log "No initial prompt - skipping knowledge injection"
        return 0
    fi

    # Analyze context
    log "Analyzing startup context..."
    local context=$(analyze_startup_context "$session_dir" "$initial_prompt")

    # Fetch relevant knowledge
    log "Searching for relevant knowledge..."
    local recommendations=$(fetch_relevant_knowledge "$context" "$initial_prompt" 5)

    local rec_count=$(echo "$recommendations" | jq 'length')
    log "Found $rec_count relevant knowledge entries"

    if [[ $rec_count -eq 0 ]]; then
        log "No relevant knowledge found"
        return 0
    fi

    # Format knowledge
    local session_id=$(basename "$session_dir")
    local knowledge_md=$(format_knowledge_injection "$recommendations" "$session_id")

    # Inject into session
    inject_knowledge "$session_dir" "$knowledge_md"

    # Log injection
    local knowledge_ids=$(echo "$recommendations" | jq '[.[] | .id]')
    log_injection "$session_id" "$knowledge_ids"

    log "Knowledge injection complete"
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Session Startup Hook - Inject relevant knowledge at session start

Usage: $(basename "$0") <command> [options]

Commands:
  hook <session_dir> <prompt>    Run startup hook
  test <prompt>                  Test knowledge search
  help                           Show this help

Examples:
  $(basename "$0") hook ~/sessions/2026-02-18-session-1 "implement auth"
  $(basename "$0") test "fix authentication bug"

Note: This script is typically called automatically by session-manager.sh
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        hook)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 hook <session_dir> <prompt>"
                exit 1
            fi
            on_session_start "$2" "$3"
            ;;

        test)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 test <prompt>"
                exit 1
            fi
            local context='{"technologies": [], "task_type": "general", "key_terms": []}'
            local recommendations=$(fetch_relevant_knowledge "$context" "$2" 5)
            echo "$recommendations" | jq .
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Export function for sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced - export function
    export -f on_session_start
else
    # Being executed - run main
    main "$@"
fi
