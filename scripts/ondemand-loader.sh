#!/usr/bin/env bash

# On-Demand Context Loader
# Main interface for requesting and loading full conversations during a session
# Version: 1.0.0

set -euo pipefail

# Directories
CLAUDE_DIR="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"
DATA_DIR="${CLAUDE_DIR}/data"
PROJECTS_DIR="${CLAUDE_DIR}/projects"
SESSIONS_DIR="${PROJECTS_DIR}"

# Source common utilities
source "${SCRIPTS_DIR}/common-utils.sh" 2>/dev/null || true

# Data files
LOADED_CONTEXT_FILE="${DATA_DIR}/loaded-contexts.json"
LOAD_HISTORY_FILE="${DATA_DIR}/context-load-history.json"

# Source dependencies
source "${SCRIPTS_DIR}/session-search.sh" 2>/dev/null || true
source "${SCRIPTS_DIR}/context-injector.sh" 2>/dev/null || true
source "${SCRIPTS_DIR}/request-parser.sh" 2>/dev/null || true
source "${SCRIPTS_DIR}/token-budget-tracker.sh" 2>/dev/null || true
source "${SCRIPTS_DIR}/context-suggestions.sh" 2>/dev/null || true

# Initialize
initialize_loader() {
    mkdir -p "${DATA_DIR}"

    if [ ! -f "${LOADED_CONTEXT_FILE}" ]; then
        cat > "${LOADED_CONTEXT_FILE}" <<EOF
{
  "version": "1.0.0",
  "loaded_contexts": [],
  "current_session_contexts": [],
  "total_tokens_loaded": 0,
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi

    if [ ! -f "${LOAD_HISTORY_FILE}" ]; then
        cat > "${LOAD_HISTORY_FILE}" <<EOF
{
  "version": "1.0.0",
  "load_events": [],
  "statistics": {
    "total_loads": 0,
    "total_tokens_loaded": 0,
    "average_load_time_ms": 0,
    "most_loaded_topics": []
  },
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi
}

# Parse natural language load request
parse_load_request() {
    local query="$1"

    # Use request parser
    if command -v parse_request &> /dev/null; then
        parse_request "$query"
    else
        # Fallback simple parsing
        echo "{
            \"action\": \"load\",
            \"topic\": \"$query\",
            \"timeframe\": null,
            \"focus\": null
        }"
    fi
}

# Load conversation by query
load_conversation() {
    local query="$1"
    local force="${2:-false}"

    local start_time=$(date +%s%3N)

    echo "🔍 Searching for: $query"

    # Parse the request
    local parsed=$(parse_load_request "$query")
    local topic=$(echo "$parsed" | jq -r '.topic // empty')
    local timeframe=$(echo "$parsed" | jq -r '.timeframe // empty')
    local focus=$(echo "$parsed" | jq -r '.focus // empty')
    local action=$(echo "$parsed" | jq -r '.action // "load"')

    echo "📊 Parsed request:"
    echo "   Topic: ${topic:-any}"
    echo "   Timeframe: ${timeframe:-any}"
    echo "   Focus: ${focus:-full conversation}"

    # Search for matching sessions
    local sessions
    if command -v search_sessions &> /dev/null; then
        sessions=$(search_sessions "$topic" "$timeframe" "" | head -10)
    else
        # Fallback: search in sessions-index.json
        sessions=$(find_sessions_fallback "$topic" "$timeframe")
    fi

    if [ -z "$sessions" ] || [ "$sessions" = "[]" ]; then
        echo "❌ No matching sessions found for: $query"
        echo ""
        suggest_alternatives "$query"
        return 1
    fi

    # Get best match
    local session_info=$(echo "$sessions" | jq -r '.[0]')
    local session_id=$(echo "$session_info" | jq -r '.sessionId // .session_id')
    local session_path=$(echo "$session_info" | jq -r '.fullPath // .path')
    local summary=$(echo "$session_info" | jq -r '.summary // "No summary"')
    local message_count=$(echo "$session_info" | jq -r '.messageCount // .message_count // 0')

    echo ""
    echo "✅ Found matching session:"
    echo "   ID: $session_id"
    echo "   Summary: $summary"
    echo "   Messages: $message_count"

    # Load conversation file
    if [ ! -f "$session_path" ]; then
        echo "❌ Session file not found: $session_path"
        return 1
    fi

    local conversation=$(cat "$session_path")

    # Apply focus if requested
    if [ -n "$focus" ]; then
        conversation=$(extract_focused_content "$conversation" "$focus")
        echo "   Focus: $focus (filtered content)"
    fi

    # Estimate tokens
    local tokens=$(estimate_tokens "$conversation")
    echo "   Estimated tokens: $tokens"

    # Check budget
    if [ "$force" != "true" ]; then
        if ! check_budget_before_load "$tokens"; then
            return 1
        fi
    fi

    # Inject into context
    if command -v inject_context &> /dev/null; then
        inject_context "$session_id" "$conversation" "$focus"
    else
        inject_context_fallback "$session_id" "$conversation" "$summary" "$tokens"
    fi

    # Record load event
    local end_time=$(date +%s%3N)
    local load_time=$((end_time - start_time))
    record_load_event "$session_id" "$query" "$tokens" "$load_time"

    # Update current session contexts
    update_current_contexts "$session_id" "$tokens"

    echo ""
    echo "✅ Context loaded successfully! (~${load_time}ms)"
    echo "   Total tokens in current session: $(get_current_token_count)"

    return 0
}

# Find sessions (fallback when search script not available)
find_sessions_fallback() {
    local topic="$1"
    local timeframe="$2"

    # Find all sessions-index.json files
    local results="[]"

    for index_file in "${SESSIONS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            # Search for topic in summaries and firstPrompt
            local matches=$(jq --arg topic "$topic" '
                .entries[] | select(
                    (.summary // "" | ascii_downcase | contains($topic | ascii_downcase)) or
                    (.firstPrompt // "" | ascii_downcase | contains($topic | ascii_downcase))
                )
            ' "$index_file" | jq -s '.')

            if [ "$matches" != "[]" ]; then
                results=$(echo "$results" | jq --argjson new "$matches" '. + $new')
            fi
        fi
    done

    # Sort by modified date (most recent first)
    echo "$results" | jq 'sort_by(.modified) | reverse'
}

# Extract focused content from conversation
extract_focused_content() {
    local conversation="$1"
    local focus="$2"

    case "$focus" in
        "decisions"|"decision")
            # Extract messages with decision-related content
            echo "$conversation" | jq -c '
                select(
                    .content // .text // "" |
                    test("decide|decision|chose|selected|went with"; "i")
                )
            '
            ;;
        "code")
            # Extract messages with code blocks
            echo "$conversation" | jq -c '
                select(
                    .content // .text // "" |
                    test("```|function |class |def |const |let |var ")
                )
            '
            ;;
        "errors"|"debugging")
            # Extract error-related messages
            echo "$conversation" | jq -c '
                select(
                    .content // .text // "" |
                    test("error|exception|failed|bug|issue"; "i")
                )
            '
            ;;
        *)
            # Return full conversation
            echo "$conversation"
            ;;
    esac
}

# Estimate token count
estimate_tokens() {
    local content="$1"

    # Rough estimation: ~4 characters per token
    local char_count=$(echo "$content" | wc -c | tr -d ' ')
    local estimated_tokens=$((char_count / 4))

    echo "$estimated_tokens"
}

# Record load event
record_load_event() {
    local session_id="$1"
    local query="$2"
    local tokens="$3"
    local load_time="$4"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Add to history
    local event=$(jq -n \
        --arg session_id "$session_id" \
        --arg query "$query" \
        --arg tokens "$tokens" \
        --arg load_time "$load_time" \
        --arg timestamp "$timestamp" \
        '{
            session_id: $session_id,
            query: $query,
            tokens_loaded: ($tokens | tonumber),
            load_time_ms: ($load_time | tonumber),
            timestamp: $timestamp
        }')

    local tmpfile="${LOAD_HISTORY_FILE}.tmp.$$"
    jq --argjson event "$event" \
        '.load_events += [$event] |
         .statistics.total_loads += 1 |
         .statistics.total_tokens_loaded += ($event.tokens_loaded) |
         .last_updated = $event.timestamp' \
        "${LOAD_HISTORY_FILE}" > "$tmpfile" && mv "$tmpfile" "${LOAD_HISTORY_FILE}"
}

# Update current session contexts
update_current_contexts() {
    local session_id="$1"
    local tokens="$2"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmpfile="${LOADED_CONTEXT_FILE}.tmp.$$"
    jq --arg session_id "$session_id" \
       --arg tokens "$tokens" \
       --arg timestamp "$timestamp" \
       '.current_session_contexts += [{
           session_id: $session_id,
           tokens: ($tokens | tonumber),
           loaded_at: $timestamp
       }] |
       .total_tokens_loaded = ([.current_session_contexts[].tokens] | add) |
       .last_updated = $timestamp' \
       "${LOADED_CONTEXT_FILE}" > "$tmpfile" && mv "$tmpfile" "${LOADED_CONTEXT_FILE}"
}

# Inject context (fallback)
inject_context_fallback() {
    local session_id="$1"
    local conversation="$2"
    local summary="$3"
    local tokens="$4"

    local context_file="${CLAUDE_DIR}/project-context.md"
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")

    # Create markdown formatted context
    local formatted_context=$(cat <<EOF

---
📥 **On-Demand Context Loaded**
**Source:** Session ${session_id}
**Summary:** ${summary}
**Tokens:** ~${tokens}
**Loaded:** ${timestamp}
---

# Loaded Conversation

## Session Details
- **Session ID:** ${session_id}
- **Estimated Tokens:** ${tokens}
- **Load Time:** ${timestamp}

## Conversation Log

EOF
)

    # Parse and format conversation messages
    echo "$conversation" | jq -r '
        if type == "object" then
            "**" + (.role // "user") + ":** " + (.content // .text // "")
        else
            .
        end
    ' | while IFS= read -r line; do
        formatted_context="${formatted_context}
${line}
"
    done

    formatted_context="${formatted_context}

---
📥 **End of Loaded Context**
---
"

    # Append to context file
    echo "$formatted_context" >> "$context_file"

    echo "   ✓ Context injected to: $context_file"
}

# Suggest alternatives when no matches found
suggest_alternatives() {
    local query="$1"

    echo "💡 Suggestions:"
    echo "   • Try a broader search term"
    echo "   • Check available topics:"

    # List recent session topics
    if command -v list_recent_topics &> /dev/null; then
        list_recent_topics | head -10
    else
        echo "     (run 'list_sessions' to see available sessions)"
    fi
}

# List all loaded contexts in current session
list_loaded_contexts() {
    if [ ! -f "${LOADED_CONTEXT_FILE}" ]; then
        echo "No contexts loaded yet."
        return 0
    fi

    echo "📥 Loaded Contexts in Current Session:"
    echo ""

    local contexts=$(jq -r '.current_session_contexts[]' "${LOADED_CONTEXT_FILE}")

    if [ -z "$contexts" ]; then
        echo "No contexts loaded in this session."
        return 0
    fi

    jq -r '.current_session_contexts[] |
        "• \(.session_id)\n  Tokens: \(.tokens)\n  Loaded: \(.loaded_at)\n"' \
        "${LOADED_CONTEXT_FILE}"

    echo ""
    local total=$(jq -r '.total_tokens_loaded' "${LOADED_CONTEXT_FILE}")
    echo "Total tokens loaded: $total"
}

# Clear loaded contexts for new session
clear_session_contexts() {
    local tmpfile="${LOADED_CONTEXT_FILE}.tmp.$$"
    jq '.current_session_contexts = [] |
        .total_tokens_loaded = 0 |
        .last_updated = now | strftime("%Y-%m-%dT%H:%M:%SZ")' \
        "${LOADED_CONTEXT_FILE}" > "$tmpfile" && mv "$tmpfile" "${LOADED_CONTEXT_FILE}"

    echo "✅ Session contexts cleared."
}

# Get load statistics
get_load_statistics() {
    if [ ! -f "${LOAD_HISTORY_FILE}" ]; then
        echo "No load history available."
        return 0
    fi

    echo "📊 Load Statistics:"
    echo ""

    jq -r '
        "Total loads: \(.statistics.total_loads)",
        "Total tokens loaded: \(.statistics.total_tokens_loaded)",
        "",
        "Recent loads:",
        (.load_events[-10:] | reverse | .[] |
            "• \(.timestamp): \(.query) (\(.tokens_loaded) tokens, \(.load_time_ms)ms)")
    ' "${LOAD_HISTORY_FILE}"
}

# Interactive load prompt
interactive_load() {
    echo "🔍 On-Demand Context Loader"
    echo ""
    echo "What would you like to load?"
    echo "Examples:"
    echo "  • 'authentication session from February'"
    echo "  • 'last week's caching work'"
    echo "  • 'decisions about JWT'"
    echo "  • 'session 5 from last month'"
    echo ""
    read -p "Query: " query

    if [ -z "$query" ]; then
        echo "No query provided."
        return 1
    fi

    load_conversation "$query"
}

# CLI Interface
main() {
    initialize_loader

    local command="${1:-}"
    shift || true

    case "$command" in
        "load")
            if [ $# -eq 0 ]; then
                echo "Usage: ondemand-loader.sh load <query>"
                echo "Example: ondemand-loader.sh load 'authentication session'"
                exit 1
            fi
            load_conversation "$*"
            ;;
        "list")
            list_loaded_contexts
            ;;
        "clear")
            clear_session_contexts
            ;;
        "stats")
            get_load_statistics
            ;;
        "interactive"|"")
            interactive_load
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
On-Demand Context Loader - Load full conversations during a session

USAGE:
    ondemand-loader.sh <command> [options]

COMMANDS:
    load <query>       Load conversation matching natural language query
    list               List all contexts loaded in current session
    clear              Clear loaded contexts for new session
    stats              Show load statistics and history
    interactive        Interactive loading prompt
    help               Show this help message

EXAMPLES:
    # Load by topic
    ondemand-loader.sh load "authentication implementation"

    # Load by timeframe
    ondemand-loader.sh load "session from last week"

    # Load with focus
    ondemand-loader.sh load "decisions about caching"

    # Interactive mode
    ondemand-loader.sh interactive

NATURAL LANGUAGE QUERIES:
    • "Show me the auth session from February"
    • "What did we decide about caching?"
    • "Load the JWT implementation code"
    • "Last week's debugging session"
    • "Session 5 from January"

EOF
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'ondemand-loader.sh help' for usage information."
            exit 1
            ;;
    esac
}

# Export functions for sourcing
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
