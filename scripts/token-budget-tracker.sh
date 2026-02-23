#!/usr/bin/env bash

# Token Budget Tracker
# Tracks and manages context window usage
# Version: 1.0.0

set -euo pipefail

# Directories
CLAUDE_DIR="${HOME}/.claude"
DATA_DIR="${CLAUDE_DIR}/data"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"

# Source common utilities
source "${SCRIPTS_DIR}/common-utils.sh" 2>/dev/null || true

# Files
BUDGET_FILE="${DATA_DIR}/token-budget.json"

# Context window limits
CONTEXT_WINDOW=200000     # Claude's context limit
SAFE_THRESHOLD=150000     # Warn at 75%
CRITICAL_THRESHOLD=180000 # Block at 90%

# Initialize
initialize_tracker() {
    mkdir -p "${DATA_DIR}"

    if [ ! -f "${BUDGET_FILE}" ]; then
        cat > "${BUDGET_FILE}" <<EOF
{
  "version": "1.0.0",
  "context_window": ${CONTEXT_WINDOW},
  "safe_threshold": ${SAFE_THRESHOLD},
  "critical_threshold": ${CRITICAL_THRESHOLD},
  "current_session": {
    "base_context_tokens": 0,
    "loaded_context_tokens": 0,
    "conversation_tokens": 0,
    "total_tokens": 0,
    "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  },
  "history": []
}
EOF
    fi
}

# Get current token count
get_current_token_count() {
    if [ ! -f "${BUDGET_FILE}" ]; then
        echo "0"
        return 0
    fi

    jq -r '.current_session.total_tokens' "${BUDGET_FILE}"
}

# Estimate tokens from text
estimate_tokens() {
    local text="$1"

    # Rough estimation: ~4 characters per token
    local char_count=$(echo "$text" | wc -c | tr -d ' ')
    local estimated_tokens=$((char_count / 4))

    echo "$estimated_tokens"
}

# Estimate tokens from file
estimate_tokens_from_file() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        echo "0"
        return 0
    fi

    local content=$(cat "$file_path")
    estimate_tokens "$content"
}

# Check budget before loading
check_budget_before_load() {
    local tokens_to_add="$1"
    local current_tokens=$(get_current_token_count)
    local new_total=$((current_tokens + tokens_to_add))

    if [ $new_total -gt $CRITICAL_THRESHOLD ]; then
        echo "❌ Cannot load: Would exceed context limit"
        echo ""
        echo "Current tokens: $current_tokens"
        echo "Tokens to add: $tokens_to_add"
        echo "New total: $new_total"
        echo "Critical threshold: $CRITICAL_THRESHOLD"
        echo "Context limit: $CONTEXT_WINDOW"
        echo ""
        echo "💡 Suggestions:"
        suggest_context_cleanup
        return 1
    elif [ $new_total -gt $SAFE_THRESHOLD ]; then
        echo "⚠️  Warning: Approaching context limit"
        echo ""
        echo "Current tokens: $current_tokens"
        echo "Tokens to add: $tokens_to_add"
        echo "New total: $new_total ($((new_total * 100 / CONTEXT_WINDOW))% of limit)"
        echo "Safe threshold: $SAFE_THRESHOLD"
        echo ""
        read -p "Continue anyway? [y/n] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    return 0
}

# Warn if approaching limit
warn_if_approaching_limit() {
    local current_tokens=$(get_current_token_count)
    local percentage=$((current_tokens * 100 / CONTEXT_WINDOW))

    if [ $current_tokens -gt $CRITICAL_THRESHOLD ]; then
        echo "🚨 CRITICAL: Context window at ${percentage}% capacity!"
        echo "   Current: $current_tokens / $CONTEXT_WINDOW tokens"
        echo "   Consider starting a new session or clearing context."
        return 0
    elif [ $current_tokens -gt $SAFE_THRESHOLD ]; then
        echo "⚠️  Warning: Context window at ${percentage}% capacity"
        echo "   Current: $current_tokens / $CONTEXT_WINDOW tokens"
        return 0
    fi

    return 1
}

# Suggest context cleanup
suggest_context_cleanup() {
    echo "To free up context space, you can:"
    echo ""
    echo "1. Start a new session (preserves conversation history)"
    echo "   • Saves current context to history"
    echo "   • Resets token counter"
    echo ""
    echo "2. Clear loaded contexts"
    echo "   • Run: ondemand-loader.sh clear"
    echo "   • Keeps base conversation"
    echo ""
    echo "3. Summarize and compress"
    echo "   • Extract key decisions and code"
    echo "   • Remove verbose explanations"
    echo ""

    # Show largest context items
    local context_file="${CLAUDE_DIR}/project-context.md"
    if [ -f "$context_file" ]; then
        local context_size=$(wc -c < "$context_file" | tr -d ' ')
        local context_tokens=$((context_size / 4))

        echo "Current context file:"
        echo "   Size: $context_size bytes (~$context_tokens tokens)"
        echo "   Location: $context_file"
    fi
}

# Update token count
update_token_count() {
    local category="$1"  # base_context, loaded_context, conversation
    local tokens="$2"

    # Append _tokens if not already present
    local key="${category}"
    if [[ ! "$key" =~ _tokens$ ]]; then
        key="${key}_tokens"
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmpfile="${BUDGET_FILE}.tmp.$$"
    jq --arg key "$key" \
       --arg tokens "$tokens" \
       --arg timestamp "$timestamp" \
       '.current_session[$key] = ($tokens | tonumber) |
        .current_session.total_tokens = (
            .current_session.base_context_tokens +
            .current_session.loaded_context_tokens +
            .current_session.conversation_tokens
        ) |
        .current_session.last_updated = $timestamp' \
        "${BUDGET_FILE}" > "$tmpfile" && mv "$tmpfile" "${BUDGET_FILE}"
}

# Add tokens to category
add_tokens() {
    local category="$1"
    local tokens="$2"

    # Append _tokens if not already present
    local key="${category}"
    if [[ ! "$key" =~ _tokens$ ]]; then
        key="${key}_tokens"
    fi

    local current=$(jq -r ".current_session.${key} // 0" "${BUDGET_FILE}")
    local new_total=$((current + tokens))

    update_token_count "$category" "$new_total"
}

# Reset session (save to history)
reset_session() {
    local reason="${1:-manual_reset}"

    # Save current session to history
    local current_session=$(jq '.current_session' "${BUDGET_FILE}")

    local tmpfile="${BUDGET_FILE}.tmp.$$"
    jq --argjson session "$current_session" \
       --arg reason "$reason" \
       '.history += [$session + {reset_reason: $reason}] |
        .current_session = {
            base_context_tokens: 0,
            loaded_context_tokens: 0,
            conversation_tokens: 0,
            total_tokens: 0,
            last_updated: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }' \
        "${BUDGET_FILE}" > "$tmpfile" && mv "$tmpfile" "${BUDGET_FILE}"

    echo "✅ Session reset. Previous session saved to history."
}

# Get budget status
get_budget_status() {
    if [ ! -f "${BUDGET_FILE}" ]; then
        echo "No budget data available."
        return 0
    fi

    local current_tokens=$(get_current_token_count)
    local percentage=$((current_tokens * 100 / CONTEXT_WINDOW))
    local remaining=$((CONTEXT_WINDOW - current_tokens))

    echo "📊 Token Budget Status:"
    echo ""
    echo "Context Window: $CONTEXT_WINDOW tokens"
    echo "Current Usage: $current_tokens tokens (${percentage}%)"
    echo "Remaining: $remaining tokens"
    echo ""

    # Status indicator
    if [ $current_tokens -gt $CRITICAL_THRESHOLD ]; then
        echo "Status: 🚨 CRITICAL (>${CRITICAL_THRESHOLD})"
    elif [ $current_tokens -gt $SAFE_THRESHOLD ]; then
        echo "Status: ⚠️  WARNING (>${SAFE_THRESHOLD})"
    else
        echo "Status: ✅ HEALTHY (<${SAFE_THRESHOLD})"
    fi

    echo ""
    echo "Breakdown:"
    jq -r '.current_session |
        "• Base context: \(.base_context_tokens) tokens",
        "• Loaded context: \(.loaded_context_tokens) tokens",
        "• Conversation: \(.conversation_tokens) tokens"' \
        "${BUDGET_FILE}"

    echo ""
    echo "Visual:"
    draw_progress_bar "$current_tokens" "$CONTEXT_WINDOW"
}

# Draw progress bar
draw_progress_bar() {
    local current="$1"
    local total="$2"
    local width=50

    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %d%%\n" $((current * 100 / total))
}

# Get budget history
get_budget_history() {
    if [ ! -f "${BUDGET_FILE}" ]; then
        echo "No budget history available."
        return 0
    fi

    echo "📜 Budget History:"
    echo ""

    jq -r '.history[] |
        "Session ended: \(.last_updated)",
        "Reason: \(.reset_reason // "unknown")",
        "Total tokens: \(.total_tokens)",
        "  Base: \(.base_context_tokens)",
        "  Loaded: \(.loaded_context_tokens)",
        "  Conversation: \(.conversation_tokens)",
        ""' \
        "${BUDGET_FILE}"
}

# Calculate optimal load size
calculate_optimal_load_size() {
    local current_tokens=$(get_current_token_count)
    local available=$((SAFE_THRESHOLD - current_tokens))

    if [ $available -lt 0 ]; then
        echo "0"
        return 0
    fi

    echo "$available"
}

# Estimate context size
estimate_context_size() {
    local context_file="${CLAUDE_DIR}/project-context.md"

    if [ ! -f "$context_file" ]; then
        echo "0"
        return 0
    fi

    estimate_tokens_from_file "$context_file"
}

# Monitor budget continuously
monitor_budget() {
    local interval="${1:-5}"  # seconds

    echo "🔍 Monitoring token budget (press Ctrl+C to stop)"
    echo ""

    while true; do
        clear
        get_budget_status
        warn_if_approaching_limit || true
        echo ""
        echo "Updated: $(date)"
        sleep "$interval"
    done
}

# Export budget report
export_budget_report() {
    local output_file="${1:-${DATA_DIR}/budget-report.json}"

    if [ ! -f "${BUDGET_FILE}" ]; then
        echo "No budget data available."
        return 1
    fi

    jq '{
        timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        current_session: .current_session,
        statistics: {
            total_sessions: (.history | length),
            average_tokens_per_session: (
                [.history[].total_tokens] | add / length
            ),
            highest_usage: (
                [.history[].total_tokens] | max
            )
        },
        history: .history
    }' "${BUDGET_FILE}" > "$output_file"

    echo "✅ Budget report exported to: $output_file"
}

# CLI Interface
main() {
    initialize_tracker

    local command="${1:-}"
    shift || true

    case "$command" in
        "status")
            get_budget_status
            ;;
        "check")
            if [ $# -eq 0 ]; then
                echo "Usage: token-budget-tracker.sh check <tokens>"
                exit 1
            fi
            check_budget_before_load "$1"
            ;;
        "warn")
            warn_if_approaching_limit
            ;;
        "suggest")
            suggest_context_cleanup
            ;;
        "update")
            if [ $# -lt 2 ]; then
                echo "Usage: token-budget-tracker.sh update <category> <tokens>"
                exit 1
            fi
            update_token_count "$1" "$2"
            ;;
        "add")
            if [ $# -lt 2 ]; then
                echo "Usage: token-budget-tracker.sh add <category> <tokens>"
                exit 1
            fi
            add_tokens "$1" "$2"
            ;;
        "reset")
            reset_session "${1:-manual_reset}"
            ;;
        "history")
            get_budget_history
            ;;
        "optimal")
            optimal=$(calculate_optimal_load_size)
            echo "Optimal load size: $optimal tokens"
            ;;
        "estimate")
            if [ $# -eq 0 ]; then
                size=$(estimate_context_size)
                echo "Current context size: $size tokens"
            else
                size=$(estimate_tokens_from_file "$1")
                echo "File size: $size tokens"
            fi
            ;;
        "monitor")
            monitor_budget "${1:-5}"
            ;;
        "export")
            export_budget_report "$1"
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
Token Budget Tracker - Manage context window usage

USAGE:
    token-budget-tracker.sh <command> [options]

COMMANDS:
    status                          Show current budget status
    check <tokens>                  Check if tokens can be loaded
    warn                            Check and warn if approaching limit
    suggest                         Suggest cleanup actions
    update <category> <tokens>      Update token count for category
    add <category> <tokens>         Add tokens to category
    reset [reason]                  Reset session (save to history)
    history                         Show budget history
    optimal                         Calculate optimal load size
    estimate [file]                 Estimate context/file size
    monitor [interval]              Monitor budget continuously
    export [file]                   Export budget report
    help                            Show this help message

CATEGORIES:
    base_context                    Base conversation context
    loaded_context                  On-demand loaded context
    conversation                    Current conversation tokens

EXAMPLES:
    # Check status
    token-budget-tracker.sh status

    # Check if can load 10000 tokens
    token-budget-tracker.sh check 10000

    # Add tokens to loaded context
    token-budget-tracker.sh add loaded_context 5000

    # Reset session
    token-budget-tracker.sh reset "starting new task"

    # Monitor continuously
    token-budget-tracker.sh monitor 5

EOF
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'token-budget-tracker.sh help' for usage information."
            exit 1
            ;;
    esac
}

# Export functions for sourcing
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
