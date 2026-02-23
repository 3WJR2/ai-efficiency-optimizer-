#!/usr/bin/env bash

# Context Injector
# Injects loaded context into current conversation seamlessly
# Version: 1.0.0

set -euo pipefail

# Directories
CLAUDE_DIR="${HOME}/.claude"
DATA_DIR="${CLAUDE_DIR}/data"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"

# Source common utilities
source "${SCRIPTS_DIR}/common-utils.sh" 2>/dev/null || true

# Files
CONTEXT_FILE="${CLAUDE_DIR}/project-context.md"
INJECTION_LOG="${DATA_DIR}/context-injection-log.json"

# Initialize
initialize_injector() {
    mkdir -p "${DATA_DIR}"

    if [ ! -f "${INJECTION_LOG}" ]; then
        cat > "${INJECTION_LOG}" <<EOF
{
  "version": "1.0.0",
  "injections": [],
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi
}

# Inject full conversation
inject_full_conversation() {
    local session_id="$1"
    local conversation="$2"

    inject_context "$session_id" "$conversation" ""
}

# Inject focused section
inject_focused_section() {
    local session_id="$1"
    local conversation="$2"
    local focus="$3"

    inject_context "$session_id" "$conversation" "$focus"
}

# Main injection function
inject_context() {
    local session_id="$1"
    local conversation="$2"
    local focus="${3:-}"

    # Get session metadata
    local session_info=$(get_session_metadata "$session_id")
    local summary=$(echo "$session_info" | jq -r '.summary // "No summary available"')
    local message_count=$(echo "$session_info" | jq -r '.messageCount // 0')
    local created=$(echo "$session_info" | jq -r '.created // "Unknown"')
    local modified=$(echo "$session_info" | jq -r '.modified // "Unknown"')

    # Estimate tokens
    local tokens=$(estimate_tokens "$conversation")

    # Format the injection
    local formatted_content=$(format_injection "$session_id" "$summary" "$conversation" "$focus" "$message_count" "$created" "$modified" "$tokens")

    # Write to context file
    update_context_file "$formatted_content"

    # Log the injection
    log_injection "$session_id" "$focus" "$tokens"

    echo "   ✓ Context injected to: $CONTEXT_FILE"
}

# Get session metadata
get_session_metadata() {
    local session_id="$1"

    # Search in all sessions-index.json files
    for index_file in "${CLAUDE_DIR}/projects"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            local match=$(jq --arg id "$session_id" '
                .entries[] | select(.sessionId == $id)
            ' "$index_file")

            if [ -n "$match" ] && [ "$match" != "null" ]; then
                echo "$match"
                return 0
            fi
        fi
    done

    # Return empty metadata if not found
    echo '{}'
}

# Format injection for display
format_injection() {
    local session_id="$1"
    local summary="$2"
    local conversation="$3"
    local focus="$4"
    local message_count="$5"
    local created="$6"
    local modified="$7"
    local tokens="$8"

    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
    local created_date=$(echo "$created" | cut -d'T' -f1)
    local modified_date=$(echo "$modified" | cut -d'T' -f1)

    # Calculate duration if possible
    local duration=""
    if [ "$created" != "Unknown" ] && [ "$modified" != "Unknown" ]; then
        local created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created%.*}" "+%s" 2>/dev/null || echo "0")
        local modified_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${modified%.*}" "+%s" 2>/dev/null || echo "0")
        if [ "$created_epoch" != "0" ] && [ "$modified_epoch" != "0" ]; then
            local duration_seconds=$((modified_epoch - created_epoch))
            local hours=$((duration_seconds / 3600))
            local minutes=$(((duration_seconds % 3600) / 60))
            if [ $hours -gt 0 ]; then
                duration="${hours}h ${minutes}m"
            else
                duration="${minutes}m"
            fi
        fi
    fi

    local focus_note=""
    if [ -n "$focus" ]; then
        focus_note="
**Focus:** $focus (filtered content)"
    fi

    # Format the header
    cat <<EOF

---
📥 **On-Demand Context Loaded**
**Source:** Session ${session_id}
**Topic:** ${summary}
**Tokens:** ~${tokens}
**Loaded:** ${timestamp}${focus_note}
---

# Loaded Conversation: ${summary}

## Session Metadata
- **Session ID:** \`${session_id}\`
- **Created:** ${created_date}
- **Modified:** ${modified_date}$([ -n "$duration" ] && echo "
- **Duration:** ${duration}")
- **Messages:** ${message_count}
- **Estimated Tokens:** ~${tokens}

## Full Conversation

EOF

    # Format conversation messages
    echo "$conversation" | jq -r '
        if type == "array" then
            .[]
        else
            .
        end |
        if type == "object" then
            if has("type") and .type == "file-history-snapshot" then
                empty
            else
                "### " + (if .role == "user" then "👤 User" elif .role == "assistant" then "🤖 Assistant" else "📝 " + (.role // "Unknown") end) + "\n\n" + (.content // .text // "")
            end
        else
            empty
        end
    ' | sed 's/^$/\n/g'

    # Format the footer
    cat <<EOF


---
📥 **End of Loaded Context** (Session: ${session_id})
---

EOF
}

# Estimate tokens
estimate_tokens() {
    local content="$1"

    # Rough estimation: ~4 characters per token
    local char_count=$(echo "$content" | wc -c | tr -d ' ')
    local estimated_tokens=$((char_count / 4))

    echo "$estimated_tokens"
}

# Update context file
update_context_file() {
    local content="$1"

    # Create context file if it doesn't exist
    if [ ! -f "$CONTEXT_FILE" ]; then
        cat > "$CONTEXT_FILE" <<EOF
# Project Context

This file contains dynamically loaded context for the current session.

EOF
    fi

    # Append the new content
    echo "$content" >> "$CONTEXT_FILE"
}

# Log injection
log_injection() {
    local session_id="$1"
    local focus="$2"
    local tokens="$3"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local injection=$(jq -n \
        --arg session_id "$session_id" \
        --arg focus "$focus" \
        --arg tokens "$tokens" \
        --arg timestamp "$timestamp" \
        '{
            session_id: $session_id,
            focus: $focus,
            tokens: ($tokens | tonumber),
            timestamp: $timestamp
        }')

    local tmpfile="${INJECTION_LOG}.tmp.$$"
    jq --argjson injection "$injection" \
        '.injections += [$injection] |
         .last_updated = $injection.timestamp' \
        "${INJECTION_LOG}" > "$tmpfile" && mv "$tmpfile" "${INJECTION_LOG}"
}

# Get injection history
get_injection_history() {
    if [ ! -f "${INJECTION_LOG}" ]; then
        echo "No injection history available."
        return 0
    fi

    echo "📥 Context Injection History:"
    echo ""

    jq -r '.injections[] |
        "• \(.timestamp): Session \(.session_id)\n  Focus: \(.focus // "full conversation")\n  Tokens: \(.tokens)\n"' \
        "${INJECTION_LOG}"
}

# Clear context file
clear_context_file() {
    if [ -f "$CONTEXT_FILE" ]; then
        cat > "$CONTEXT_FILE" <<EOF
# Project Context

This file contains dynamically loaded context for the current session.

EOF
        echo "✅ Context file cleared."
    else
        echo "Context file doesn't exist."
    fi
}

# Format injection with syntax highlighting
format_with_highlighting() {
    local conversation="$1"

    echo "$conversation" | jq -r '
        if type == "array" then .[] else . end |
        if type == "object" then
            if has("type") and .type == "file-history-snapshot" then
                empty
            else
                "**" + (.role // "user") + ":**\n\n" + (.content // .text // "") + "\n\n---\n"
            end
        else
            empty
        end
    '
}

# Inject with custom format
inject_custom_format() {
    local session_id="$1"
    local conversation="$2"
    local format="${3:-markdown}"

    case "$format" in
        "markdown")
            inject_context "$session_id" "$conversation" ""
            ;;
        "json")
            # Output as JSON structure
            local formatted=$(jq -n \
                --arg session_id "$session_id" \
                --argjson conversation "$conversation" \
                '{
                    session_id: $session_id,
                    conversation: $conversation,
                    loaded_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
                }')
            echo "$formatted" >> "${CONTEXT_FILE}.json"
            ;;
        "plain")
            # Plain text format
            echo "$conversation" | jq -r '
                if type == "array" then .[] else . end |
                if type == "object" then
                    (.role // "user") + ": " + (.content // .text // "")
                else
                    .
                end
            ' >> "$CONTEXT_FILE"
            ;;
        *)
            echo "Unknown format: $format"
            return 1
            ;;
    esac
}

# Get context statistics
get_context_statistics() {
    if [ ! -f "$CONTEXT_FILE" ]; then
        echo "No context file found."
        return 0
    fi

    local file_size=$(wc -c < "$CONTEXT_FILE" | tr -d ' ')
    local line_count=$(wc -l < "$CONTEXT_FILE" | tr -d ' ')
    local injection_count=$(grep -c "On-Demand Context Loaded" "$CONTEXT_FILE" 2>/dev/null || echo "0")

    echo "📊 Context File Statistics:"
    echo ""
    echo "File size: $file_size bytes"
    echo "Lines: $line_count"
    echo "Injections: $injection_count"
    echo ""
    echo "File location: $CONTEXT_FILE"
}

# CLI Interface
main() {
    initialize_injector

    local command="${1:-}"
    shift || true

    case "$command" in
        "inject")
            if [ $# -lt 2 ]; then
                echo "Usage: context-injector.sh inject <session-id> <conversation-json>"
                exit 1
            fi
            inject_context "$1" "$2" "${3:-}"
            ;;
        "inject-file")
            if [ $# -lt 2 ]; then
                echo "Usage: context-injector.sh inject-file <session-id> <conversation-file>"
                exit 1
            fi
            local conversation=$(cat "$2")
            inject_context "$1" "$conversation" "${3:-}"
            ;;
        "history")
            get_injection_history
            ;;
        "clear")
            clear_context_file
            ;;
        "stats")
            get_context_statistics
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
Context Injector - Inject loaded context into current session

USAGE:
    context-injector.sh <command> [options]

COMMANDS:
    inject <session-id> <json>          Inject context from JSON string
    inject-file <session-id> <file>     Inject context from file
    history                             Show injection history
    clear                               Clear context file
    stats                               Show context statistics
    help                                Show this help message

EXAMPLES:
    # Inject from JSON string
    context-injector.sh inject "session-123" '{"role":"user","content":"hello"}'

    # Inject from file
    context-injector.sh inject-file "session-123" conversation.jsonl

    # View history
    context-injector.sh history

    # Clear context
    context-injector.sh clear

EOF
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'context-injector.sh help' for usage information."
            exit 1
            ;;
    esac
}

# Export functions for sourcing
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
