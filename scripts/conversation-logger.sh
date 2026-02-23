#!/usr/bin/env bash
# conversation-logger.sh - Log conversation exchanges to JSONL
# Part of Per-Session Context System (Phase A)

set -euo pipefail

# Configuration
SESSIONS_BASE_DIR="${SESSIONS_BASE_DIR:-$HOME/Desktop/multi-claude-sessions/sessions}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*" >&2
    fi
}

# Estimate token count (rough approximation: 1 token ~= 4 characters)
estimate_tokens() {
    local text="$1"
    local char_count=${#text}
    echo $((char_count / 4))
}

# Log a message to the conversation log
log_message() {
    local session_dir="$1"
    local role="$2"           # user or assistant
    local content="$3"
    local input_tokens="${4:-0}"
    local output_tokens="${5:-0}"

    # Validate inputs
    if [[ ! -d "$session_dir" ]]; then
        log_error "Session directory not found: $session_dir"
        return 1
    fi

    if [[ "$role" != "user" ]] && [[ "$role" != "assistant" ]]; then
        log_error "Invalid role: $role (must be 'user' or 'assistant')"
        return 1
    fi

    # Estimate tokens if not provided
    if [[ $input_tokens -eq 0 ]] && [[ "$role" == "user" ]]; then
        input_tokens=$(estimate_tokens "$content")
    fi

    if [[ $output_tokens -eq 0 ]] && [[ "$role" == "assistant" ]]; then
        output_tokens=$(estimate_tokens "$content")
    fi

    local log_file="$session_dir/conversation-log.jsonl"
    local token_file="$session_dir/token-usage.json"
    local metadata_file="$session_dir/.session-metadata.json"

    # Create log entry
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local content_preview=$(echo "$content" | head -c 100 | tr '\n' ' ')
    local content_length=${#content}

    # Create log entry using jq for proper JSON formatting (compact, single-line)
    jq -nc \
        --arg timestamp "$timestamp" \
        --arg role "$role" \
        --arg content "$content" \
        --argjson content_length "$content_length" \
        --argjson input_tokens "$input_tokens" \
        --argjson output_tokens "$output_tokens" \
        --arg working_directory "$(pwd)" \
        --arg shell "${SHELL##*/}" \
        '{
            timestamp: $timestamp,
            role: $role,
            content: $content,
            content_length: $content_length,
            tokens: {
                input: $input_tokens,
                output: $output_tokens,
                total: ($input_tokens + $output_tokens)
            },
            metadata: {
                working_directory: $working_directory,
                shell: $shell
            }
        }' >> "$log_file"
    log_debug "Logged $role message ($content_length chars, $((input_tokens + output_tokens)) tokens)"

    # Update token usage tracking
    update_token_usage "$session_dir" "$input_tokens" "$output_tokens"

    # Update session metadata last_activity
    if [[ -f "$metadata_file" ]]; then
        local tmp_file=$(mktemp)
        jq --arg timestamp "$timestamp" \
           '.last_activity = $timestamp' \
           "$metadata_file" > "$tmp_file" && mv "$tmp_file" "$metadata_file"
    fi
}

# Update token usage statistics
update_token_usage() {
    local session_dir="$1"
    local input_tokens="$2"
    local output_tokens="$3"

    local token_file="$session_dir/token-usage.json"

    if [[ ! -f "$token_file" ]]; then
        log_error "Token usage file not found: $token_file"
        return 1
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local tmp_file=$(mktemp)

    jq --arg timestamp "$timestamp" \
       --argjson input "$input_tokens" \
       --argjson output "$output_tokens" \
       '
       .last_update = $timestamp |
       .total_tokens.input += $input |
       .total_tokens.output += $output |
       .total_tokens.total += ($input + $output) |
       .message_count += 1 |
       .interactions += [{
         "timestamp": $timestamp,
         "input_tokens": $input,
         "output_tokens": $output,
         "total_tokens": ($input + $output)
       }] |
       .interactions = (.interactions | if length > 100 then .[-100:] else . end)
       ' \
       "$token_file" > "$tmp_file" && mv "$tmp_file" "$token_file"

    log_debug "Updated token usage: +$input_tokens input, +$output_tokens output"
}

# Log user message
log_user_message() {
    local session_dir="${1:-}"
    local content="${2:-}"

    if [[ -z "$session_dir" ]] || [[ -z "$content" ]]; then
        log_error "Usage: log_user_message <session_dir> <content>"
        return 1
    fi

    log_message "$session_dir" "user" "$content"
}

# Log assistant message
log_assistant_message() {
    local session_dir="${1:-}"
    local content="${2:-}"
    local input_tokens="${3:-0}"
    local output_tokens="${4:-0}"

    if [[ -z "$session_dir" ]] || [[ -z "$content" ]]; then
        log_error "Usage: log_assistant_message <session_dir> <content> [input_tokens] [output_tokens]"
        return 1
    fi

    log_message "$session_dir" "assistant" "$content" "$input_tokens" "$output_tokens"
}

# Get conversation summary
get_conversation_summary() {
    local session_dir="$1"
    local log_file="$session_dir/conversation-log.jsonl"

    if [[ ! -f "$log_file" ]]; then
        log_error "Conversation log not found: $log_file"
        return 1
    fi

    local total_messages=$(jq -s 'length' "$log_file")
    local user_messages=$(jq -s '[.[] | select(.role == "user")] | length' "$log_file")
    local assistant_messages=$(jq -s '[.[] | select(.role == "assistant")] | length' "$log_file")

    echo ""
    echo "Conversation Summary"
    echo "===================="
    echo ""
    echo "Total Messages: $total_messages"
    echo "User Messages: $user_messages"
    echo "Assistant Messages: $assistant_messages"
    echo ""

    if [[ -f "$session_dir/token-usage.json" ]]; then
        echo "Token Usage:"
        jq -r '
          "  Input Tokens: \(.total_tokens.input)",
          "  Output Tokens: \(.total_tokens.output)",
          "  Total Tokens: \(.total_tokens.total)"
        ' "$session_dir/token-usage.json"
        echo ""
    fi
}

# Get recent messages
get_recent_messages() {
    local session_dir="$1"
    local count="${2:-10}"
    local log_file="$session_dir/conversation-log.jsonl"

    if [[ ! -f "$log_file" ]]; then
        log_error "Conversation log not found: $log_file"
        return 1
    fi

    echo ""
    echo "Recent Messages (last $count):"
    echo "=============================="
    echo ""

    # Read JSONL using jq slurp, then iterate over last N entries
    jq -s ".[-${count}:][] | {role, timestamp, content, tokens}" "$log_file" | \
    jq -c '.' | while IFS= read -r line; do
        local role=$(echo "$line" | jq -r '.role')
        local timestamp=$(echo "$line" | jq -r '.timestamp')
        local preview=$(echo "$line" | jq -r '.content' | head -c 80 | tr '\n' ' ')
        local token_count=$(echo "$line" | jq -r '.tokens.total')

        local role_color="${GREEN}"
        [[ "$role" == "assistant" ]] && role_color="${BLUE}"

        echo -e "${role_color}[$role]${NC} $timestamp"
        echo "  $preview... ($token_count tokens)"
        echo ""
    done
}

# Export conversation to markdown
export_to_markdown() {
    local session_dir="$1"
    local output_file="${2:-$session_dir/conversation-export.md}"
    local log_file="$session_dir/conversation-log.jsonl"

    if [[ ! -f "$log_file" ]]; then
        log_error "Conversation log not found: $log_file"
        return 1
    fi

    log_info "Exporting conversation to: $output_file"

    # Create markdown header
    cat > "$output_file" <<EOF
# Conversation Export

**Session:** $(basename "$session_dir")
**Exported:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

---

EOF

    # Process each message using jq and count them
    local temp_count_file=$(mktemp)
    echo "0" > "$temp_count_file"

    jq -s '.[]' "$log_file" | jq -c '.' | while IFS= read -r line; do
        local message_num=$(cat "$temp_count_file")
        message_num=$((message_num + 1))
        echo "$message_num" > "$temp_count_file"

        local role=$(echo "$line" | jq -r '.role')
        local timestamp=$(echo "$line" | jq -r '.timestamp')
        local content=$(echo "$line" | jq -r '.content')
        local tokens=$(echo "$line" | jq -r '.tokens.total')

        local role_emoji="👤"
        [[ "$role" == "assistant" ]] && role_emoji="🤖"

        cat >> "$output_file" <<EOF
## Message $message_num: $role_emoji $role

**Time:** $timestamp
**Tokens:** $tokens

$content

---

EOF
    done

    local total_exported=$(cat "$temp_count_file")
    rm -f "$temp_count_file"

    log_info "Exported $total_exported messages to $output_file"
}

# Search conversation for keywords
search_conversation() {
    local session_dir="$1"
    local keyword="$2"
    local log_file="$session_dir/conversation-log.jsonl"

    if [[ ! -f "$log_file" ]]; then
        log_error "Conversation log not found: $log_file"
        return 1
    fi

    if [[ -z "$keyword" ]]; then
        log_error "Usage: search_conversation <session_dir> <keyword>"
        return 1
    fi

    echo ""
    echo "Searching for: '$keyword'"
    echo "========================="
    echo ""

    local found=0
    jq -s '.[]' "$log_file" | jq -c '.' | while IFS= read -r line; do
        if echo "$line" | jq -r '.content' | grep -qi "$keyword"; then
            local role=$(echo "$line" | jq -r '.role')
            local timestamp=$(echo "$line" | jq -r '.timestamp')
            local content=$(echo "$line" | jq -r '.content')

            echo "[$role] $timestamp"
            echo "$content" | grep -i --color=auto "$keyword"
            echo ""
            found=$((found + 1))
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "No matches found."
    else
        echo "Found $found matches."
    fi
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        log-user)
            log_user_message "$@"
            ;;

        log-assistant)
            log_assistant_message "$@"
            ;;

        log)
            # Generic log command
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 log <session_dir> <role> <content> [input_tokens] [output_tokens]"
                exit 1
            fi
            log_message "$@"
            ;;

        summary)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 summary <session_dir>"
                exit 1
            fi
            get_conversation_summary "$1"
            ;;

        recent)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 recent <session_dir> [count]"
                exit 1
            fi
            get_recent_messages "$@"
            ;;

        export)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 export <session_dir> [output_file]"
                exit 1
            fi
            export_to_markdown "$@"
            ;;

        search)
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 search <session_dir> <keyword>"
                exit 1
            fi
            search_conversation "$@"
            ;;

        help|--help|-h)
            cat <<EOF
Conversation Logger - Log and manage conversation messages

USAGE:
    $0 <command> [options]

COMMANDS:
    log-user <session_dir> <content>
        Log a user message

    log-assistant <session_dir> <content> [input_tokens] [output_tokens]
        Log an assistant message with optional token counts

    log <session_dir> <role> <content> [input_tokens] [output_tokens]
        Generic log command (role: user or assistant)

    summary <session_dir>
        Show conversation summary with statistics

    recent <session_dir> [count]
        Show recent messages (default: 10)

    export <session_dir> [output_file]
        Export conversation to markdown

    search <session_dir> <keyword>
        Search conversation for keyword

    help
        Show this help message

EXAMPLES:
    # Log user message
    $0 log-user ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1 "Hello Claude"

    # Log assistant message
    $0 log-assistant ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1 "Hello! How can I help?"

    # Show summary
    $0 summary ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1

    # Export to markdown
    $0 export ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1

    # Search for keyword
    $0 search ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1 "error"

ENVIRONMENT:
    SESSIONS_BASE_DIR    Base directory for sessions (default: ~/Desktop/multi-claude-sessions/sessions)
    DEBUG                Enable debug output (set to 1)

EOF
            ;;

        *)
            log_error "Unknown command: $command"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
