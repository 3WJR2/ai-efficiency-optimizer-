#!/usr/bin/env bash
# context-generator.sh - Generate session context from conversation logs
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

# Extract topics from conversation (simple keyword extraction)
extract_topics() {
    local log_file="$1"

    # Common technical keywords to look for
    local keywords="API|database|function|class|error|bug|fix|test|deploy|build|config|security|performance|refactor|feature|documentation|debug|install|server|client|authentication|authorization|cache|git|commit|branch|merge|request|review|docker|kubernetes|CI/CD|pipeline|script|bash|python|javascript|typescript|go|rust|java|react|vue|angular|node|express|django|flask"

    # Extract all content and search for keywords
    jq -s '[.[] | .content] | join(" ")' "$log_file" | \
    grep -oi "\b\($keywords\)\b" | \
    tr '[:upper:]' '[:lower:]' | \
    sort | uniq -c | sort -rn | head -10 | awk '{print $2}'
}

# Extract commands from conversation
extract_commands() {
    local log_file="$1"

    # Look for shell commands, file operations, etc.
    grep -o '`[^`]*`' "$log_file" 2>/dev/null | \
        sed 's/`//g' | \
        grep -E '^[a-z]' | \
        head -20 || echo ""
}

# Extract error patterns
extract_errors() {
    local log_file="$1"

    jq -s '.[]' "$log_file" | jq -c '.' | while IFS= read -r line; do
        local content=$(echo "$line" | jq -r '.content')

        # Look for error-related content
        if echo "$content" | grep -qi 'error\|exception\|failed\|warning'; then
            echo "$content" | grep -i 'error\|exception\|failed\|warning' | head -3
        fi
    done | head -10
}

# Extract solutions (assistant responses after errors)
extract_solutions() {
    local log_file="$1"
    local prev_role=""
    local solutions=()

    jq -s '.[]' "$log_file" | jq -c '.' | while IFS= read -r line; do
        local role=$(echo "$line" | jq -r '.role')
        local content=$(echo "$line" | jq -r '.content')

        # If previous was user with error/problem, and current is assistant
        if [[ "$prev_role" == "user" ]] && [[ "$role" == "assistant" ]]; then
            # Extract first sentence/paragraph as solution summary
            local solution=$(echo "$content" | head -c 200 | tr '\n' ' ')
            echo "$solution"
        fi

        prev_role="$role"
    done | head -5
}

# Identify user preferences
identify_preferences() {
    local log_file="$1"
    local preferences=()

    # Analyze user message patterns
    local total_user_messages=$(jq -s '[.[] | select(.role == "user")] | length' "$log_file")
    local avg_user_message_length=0

    if [[ $total_user_messages -gt 0 ]]; then
        local total_length=$(jq -s '[.[] | select(.role == "user") | .content_length] | add' "$log_file")
        avg_user_message_length=$((total_length / total_user_messages))
    fi

    # Determine communication style
    if [[ $avg_user_message_length -lt 100 ]]; then
        preferences+=("Prefers concise communication")
    elif [[ $avg_user_message_length -gt 500 ]]; then
        preferences+=("Provides detailed context")
    fi

    # Check for code-heavy conversations
    local code_mentions=$(jq -s '[.[] | .content | select(contains("```"))] | length' "$log_file")
    if [[ $code_mentions -gt 5 ]]; then
        preferences+=("Code-focused interactions")
    fi

    # Check for question patterns
    local question_mentions=$(jq -s '[.[] | .content | select(contains("?"))] | length' "$log_file")
    if [[ $question_mentions -gt 10 ]]; then
        preferences+=("Exploratory learning style")
    fi

    printf '%s\n' "${preferences[@]}"
}

# Generate session context
generate_context() {
    local session_dir="$1"
    local log_file="$session_dir/conversation-log.jsonl"
    local context_file="$session_dir/.session-context.md"
    local token_file="$session_dir/token-usage.json"
    local metadata_file="$session_dir/.session-metadata.json"

    if [[ ! -f "$log_file" ]]; then
        log_error "Conversation log not found: $log_file"
        return 1
    fi

    # Check if we have enough data
    local message_count=$(wc -l < "$log_file")
    if [[ $message_count -lt 2 ]]; then
        log_warn "Insufficient data for context generation (need at least 2 messages)"
        return 0
    fi

    log_info "Generating context for session: $(basename "$session_dir")"

    # Extract session information
    local session_id=$(basename "$session_dir")
    local created_at="Unknown"
    local status="Active"

    if [[ -f "$metadata_file" ]]; then
        created_at=$(jq -r '.created_at' "$metadata_file")
        status=$(jq -r '.status' "$metadata_file")
    fi

    # Extract patterns
    log_debug "Extracting topics..."
    local topics=$(extract_topics "$log_file")

    log_debug "Extracting commands..."
    local commands=$(extract_commands "$log_file")

    log_debug "Extracting errors..."
    local errors=$(extract_errors "$log_file")

    log_debug "Extracting solutions..."
    local solutions=$(extract_solutions "$log_file")

    log_debug "Identifying preferences..."
    local preferences=$(identify_preferences "$log_file")

    # Get token statistics
    local total_messages=0
    local total_tokens=0
    local input_tokens=0
    local output_tokens=0

    if [[ -f "$token_file" ]]; then
        total_messages=$(jq -r '.message_count' "$token_file")
        total_tokens=$(jq -r '.total_tokens.total' "$token_file")
        input_tokens=$(jq -r '.total_tokens.input' "$token_file")
        output_tokens=$(jq -r '.total_tokens.output' "$token_file")
    fi

    # Generate context file
    cat > "$context_file" <<EOF
# Session Context: $session_id

**Created:** $created_at
**Status:** $status
**Last Updated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Session Statistics

- **Total Messages:** $total_messages
- **Total Tokens:** $total_tokens (Input: $input_tokens, Output: $output_tokens)
- **Conversation Depth:** $(printf "%.1f" $(echo "scale=1; $total_messages / 2" | bc)) exchanges

## Session Summary

This session has been active with $total_messages messages exchanged.
$(if [[ $message_count -ge 10 ]]; then echo "The conversation has substantial depth."; else echo "The conversation is still developing."; fi)

## Active Topics

EOF

    if [[ -n "$topics" ]]; then
        echo "$topics" | while IFS= read -r topic; do
            echo "- $topic" >> "$context_file"
        done
    else
        echo "- (No specific topics identified yet)" >> "$context_file"
    fi

    cat >> "$context_file" <<EOF

## Recent Commands

EOF

    if [[ -n "$commands" ]]; then
        echo "$commands" | head -10 | while IFS= read -r cmd; do
            echo "- \`$cmd\`" >> "$context_file"
        done
    else
        echo "- (No commands logged yet)" >> "$context_file"
    fi

    cat >> "$context_file" <<EOF

## Known Issues and Solutions

EOF

    if [[ -n "$errors" ]]; then
        echo "### Recent Issues" >> "$context_file"
        echo "" >> "$context_file"
        echo "$errors" | while IFS= read -r error; do
            echo "- $error" >> "$context_file"
        done
        echo "" >> "$context_file"

        if [[ -n "$solutions" ]]; then
            echo "### Solutions Applied" >> "$context_file"
            echo "" >> "$context_file"
            echo "$solutions" | while IFS= read -r solution; do
                echo "- $solution" >> "$context_file"
            done
            echo "" >> "$context_file"
        fi
    else
        echo "- (No issues reported yet)" >> "$context_file"
    fi

    cat >> "$context_file" <<EOF

## User Preferences Observed

EOF

    if [[ -n "$preferences" ]]; then
        echo "$preferences" | while IFS= read -r pref; do
            echo "- $pref" >> "$context_file"
        done
    else
        echo "- (Learning in progress)" >> "$context_file"
    fi

    cat >> "$context_file" <<EOF

## Context for Next Interaction

Based on this session, Claude should:

1. **Remember:** The main focus areas are ${topics:-general conversation}
2. **Consider:** User's communication style and preferences
3. **Be aware of:** Any unresolved issues or ongoing work
4. **Maintain:** Continuity with previous discussions

---

*This file is automatically updated by the session context system.*
*Last updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")*
*Messages analyzed: $message_count*
EOF

    log_info "Context generated successfully: $context_file"
}

# Auto-generate context (if enough new messages)
auto_generate() {
    local session_dir="$1"
    local log_file="$session_dir/conversation-log.jsonl"
    local context_file="$session_dir/.session-context.md"

    if [[ ! -f "$log_file" ]]; then
        log_error "Conversation log not found: $log_file"
        return 1
    fi

    # Get current message count
    local current_messages=$(wc -l < "$log_file")

    # Get last update message count (stored in context file)
    local last_update_messages=0
    if [[ -f "$context_file" ]]; then
        last_update_messages=$(grep "Messages analyzed:" "$context_file" | grep -o '[0-9]*' || echo "0")
    fi

    # Regenerate if 5+ new messages
    local new_messages=$((current_messages - last_update_messages))

    if [[ $new_messages -ge 5 ]]; then
        log_info "Auto-generating context ($new_messages new messages)"
        generate_context "$session_dir"
    else
        log_debug "Not enough new messages for auto-generation ($new_messages < 5)"
    fi
}

# Show context
show_context() {
    local session_dir="$1"
    local context_file="$session_dir/.session-context.md"

    if [[ ! -f "$context_file" ]]; then
        log_error "Context file not found: $context_file"
        return 1
    fi

    cat "$context_file"
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        generate|gen)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 generate <session_dir>"
                exit 1
            fi
            generate_context "$1"
            ;;

        auto)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 auto <session_dir>"
                exit 1
            fi
            auto_generate "$1"
            ;;

        show|cat)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 show <session_dir>"
                exit 1
            fi
            show_context "$1"
            ;;

        help|--help|-h)
            cat <<EOF
Context Generator - Generate session context from conversation logs

USAGE:
    $0 <command> [options]

COMMANDS:
    generate|gen <session_dir>
        Generate context file from conversation log

    auto <session_dir>
        Auto-generate context if enough new messages (5+)

    show|cat <session_dir>
        Display current context file

    help
        Show this help message

EXAMPLES:
    # Generate context
    $0 generate ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1

    # Auto-generate (only if needed)
    $0 auto ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1

    # Show current context
    $0 show ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1

ENVIRONMENT:
    SESSIONS_BASE_DIR    Base directory for sessions (default: ~/Desktop/multi-claude-sessions/sessions)
    DEBUG                Enable debug output (set to 1)

NOTES:
    - Minimum 2 messages required for context generation
    - Auto-generation triggered after 5+ new messages
    - Context includes topics, commands, errors, solutions, and preferences

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
