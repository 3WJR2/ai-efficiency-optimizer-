#!/usr/bin/env bash

# Context Suggestions
# Proactively suggests relevant sessions to load
# Version: 1.0.0

set -euo pipefail

# Directories
CLAUDE_DIR="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"
DATA_DIR="${CLAUDE_DIR}/data"
PROJECTS_DIR="${CLAUDE_DIR}/projects"

# Source common utilities
source "${SCRIPTS_DIR}/common-utils.sh" 2>/dev/null || true

# Files
SUGGESTIONS_FILE="${DATA_DIR}/context-suggestions.json"

# Source dependencies
source "${SCRIPTS_DIR}/session-search.sh" 2>/dev/null || true

# Initialize
initialize_suggestions() {
    mkdir -p "${DATA_DIR}"

    if [ ! -f "${SUGGESTIONS_FILE}" ]; then
        cat > "${SUGGESTIONS_FILE}" <<EOF
{
  "version": "1.0.0",
  "suggestions": [],
  "suggestion_history": [],
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi
}

# Suggest relevant sessions based on current topic
suggest_relevant_sessions() {
    local current_topic="$1"
    local limit="${2:-5}"

    echo "💡 Relevant Sessions Available"
    echo ""
    echo "Based on what you're working on, these past sessions might help:"
    echo ""

    # Search for related sessions
    local sessions
    if command -v search_by_topic &> /dev/null; then
        sessions=$(search_by_topic "$current_topic")
    else
        sessions=$(search_sessions_fallback "$current_topic")
    fi

    if [ -z "$sessions" ] || [ "$sessions" = "[]" ]; then
        echo "No relevant sessions found for: $current_topic"
        return 0
    fi

    # Display top matches
    local count=0
    echo "$sessions" | jq -r --arg limit "$limit" '
        limit(($limit | tonumber); .[]) |
        {
            sessionId: .sessionId,
            summary: .summary,
            modified: .modified,
            messageCount: .messageCount
        }
    ' | while IFS= read -r session; do
        count=$((count + 1))
        local session_id=$(echo "$session" | jq -r '.sessionId')
        local summary=$(echo "$session" | jq -r '.summary')
        local modified=$(echo "$session" | jq -r '.modified' | cut -d'T' -f1)
        local message_count=$(echo "$session" | jq -r '.messageCount')

        # Estimate tokens
        local session_path=$(find_session_path "$session_id")
        local tokens=0
        if [ -n "$session_path" ] && [ -f "$session_path" ]; then
            local content=$(cat "$session_path")
            tokens=$(estimate_tokens "$content")
        fi

        # Get emoji based on topic
        local emoji=$(get_topic_emoji "$summary")

        echo "${count}. ${emoji} **${summary}** (${modified})"
        echo "   - ${message_count} messages"
        echo "   - ~${tokens} tokens"
        echo "   - Load: \`load session ${session_id}\`"
        echo ""
    done

    echo "Say \"load [session-id]\" to see full conversation, or ask \"what did we do about X?\""
}

# Suggest based on errors
suggest_based_on_errors() {
    local error_text="$1"

    echo "💡 Sessions Related to This Error:"
    echo ""

    # Extract error type/keywords
    local error_keywords=$(extract_error_keywords "$error_text")

    # Search for sessions with similar errors
    local sessions
    if command -v search_by_keywords &> /dev/null; then
        sessions=$(search_by_keywords "$error_keywords")
    else
        sessions=$(search_sessions_fallback "$error_keywords")
    fi

    if [ -z "$sessions" ] || [ "$sessions" = "[]" ]; then
        echo "No sessions found with similar errors."
        return 0
    fi

    # Display matches
    echo "$sessions" | jq -r 'limit(3; .[]) |
        {
            sessionId: .sessionId,
            summary: .summary,
            modified: .modified
        }
    ' | while IFS= read -r session; do
        local session_id=$(echo "$session" | jq -r '.sessionId')
        local summary=$(echo "$session" | jq -r '.summary')
        local modified=$(echo "$session" | jq -r '.modified' | cut -d'T' -f1)

        echo "• **${summary}** (${modified})"
        echo "  Load: \`load session ${session_id}\`"
        echo ""
    done
}

# Suggest based on files
suggest_based_on_files() {
    local files=("$@")

    echo "💡 Sessions Working on Similar Files:"
    echo ""

    # Extract file paths and search in session history
    local keywords=""
    for file in "${files[@]}"; do
        local basename=$(basename "$file")
        keywords="${keywords} ${basename}"
    done

    local sessions
    if command -v search_by_keywords &> /dev/null; then
        sessions=$(search_by_keywords "$keywords")
    else
        sessions=$(search_sessions_fallback "$keywords")
    fi

    if [ -z "$sessions" ] || [ "$sessions" = "[]" ]; then
        echo "No sessions found working on these files."
        return 0
    fi

    # Display matches
    echo "$sessions" | jq -r 'limit(3; .[]) |
        {
            sessionId: .sessionId,
            summary: .summary,
            modified: .modified
        }
    ' | while IFS= read -r session; do
        local session_id=$(echo "$session" | jq -r '.sessionId')
        local summary=$(echo "$session" | jq -r '.summary')
        local modified=$(echo "$session" | jq -r '.modified' | cut -d'T' -f1)

        echo "• **${summary}** (${modified})"
        echo "  Load: \`load session ${session_id}\`"
        echo ""
    done
}

# Extract error keywords
extract_error_keywords() {
    local error_text="$1"

    # Extract common error patterns
    local keywords=$(echo "$error_text" | grep -oE '(Error|Exception|Failed|ENOENT|ECONNREFUSED|TypeError|SyntaxError|ReferenceError)' | head -3 | tr '\n' ' ')

    # If no specific errors, use general keywords
    if [ -z "$keywords" ]; then
        keywords="error bug issue"
    fi

    echo "$keywords" | xargs
}

# Find session path
find_session_path() {
    local session_id="$1"

    for index_file in "${PROJECTS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            local path=$(jq -r --arg id "$session_id" '
                .entries[] | select(.sessionId == $id) | .fullPath
            ' "$index_file")

            if [ -n "$path" ] && [ "$path" != "null" ]; then
                echo "$path"
                return 0
            fi
        fi
    done

    echo ""
}

# Estimate tokens
estimate_tokens() {
    local content="$1"
    local char_count=$(echo "$content" | wc -c | tr -d ' ')
    local estimated_tokens=$((char_count / 4))
    echo "$estimated_tokens"
}

# Get topic emoji
get_topic_emoji() {
    local summary="$1"
    local summary_lower=$(echo "$summary" | tr '[:upper:]' '[:lower:]')

    if [[ "$summary_lower" =~ auth|login|jwt|oauth ]]; then
        echo "🔐"
    elif [[ "$summary_lower" =~ secur|encrypt|hash ]]; then
        echo "🛡️"
    elif [[ "$summary_lower" =~ cache|redis|memory ]]; then
        echo "⚡"
    elif [[ "$summary_lower" =~ api|endpoint|rest ]]; then
        echo "🔌"
    elif [[ "$summary_lower" =~ databas|sql|query ]]; then
        echo "🗄️"
    elif [[ "$summary_lower" =~ test|debug|fix ]]; then
        echo "🔧"
    elif [[ "$summary_lower" =~ deploy|build|ci ]]; then
        echo "🚀"
    elif [[ "$summary_lower" =~ ui|frontend|react ]]; then
        echo "🎨"
    else
        echo "📄"
    fi
}

# Search sessions fallback
search_sessions_fallback() {
    local keywords="$1"

    local results="[]"

    for index_file in "${PROJECTS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            local matches=$(jq --arg keywords "$keywords" '
                .entries[] | select(
                    (.summary // "" | ascii_downcase | contains($keywords | ascii_downcase)) or
                    (.firstPrompt // "" | ascii_downcase | contains($keywords | ascii_downcase))
                )
            ' "$index_file" | jq -s '.')

            if [ "$matches" != "[]" ]; then
                results=$(echo "$results" | jq --argjson new "$matches" '. + $new')
            fi
        fi
    done

    echo "$results" | jq 'sort_by(.modified) | reverse'
}

# Auto-suggest based on context
auto_suggest() {
    local context="${1:-}"

    if [ -z "$context" ]; then
        # Try to detect current context
        context=$(detect_current_context)
    fi

    if [ -n "$context" ]; then
        suggest_relevant_sessions "$context"
    else
        echo "💡 Unable to determine current context for suggestions."
        echo "   Try: context-suggestions.sh suggest <topic>"
    fi
}

# Detect current context
detect_current_context() {
    # Check if we're in a git repo
    if git rev-parse --git-dir > /dev/null 2>&1; then
        local repo_name=$(basename "$(git rev-parse --show-toplevel)")
        echo "$repo_name"
        return 0
    fi

    # Check recent commands in history
    local recent_commands=$(history | tail -10 | cut -c 8-)

    # Extract common keywords
    local keywords=$(echo "$recent_commands" | grep -oE '\b[a-z]{4,}\b' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

    if [ -n "$keywords" ]; then
        echo "$keywords"
        return 0
    fi

    echo ""
}

# Suggest complementary sessions
suggest_complementary() {
    local session_id="$1"

    echo "💡 Related Sessions:"
    echo ""

    # Get the session info
    local session_info=$(get_session_info "$session_id")
    local summary=$(echo "$session_info" | jq -r '.summary // ""')

    if [ -z "$summary" ] || [ "$summary" = "null" ]; then
        echo "Session not found: $session_id"
        return 1
    fi

    # Extract keywords from summary
    local keywords=$(echo "$summary" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | head -3 | tr '\n' ' ')

    # Search for related sessions
    suggest_relevant_sessions "$keywords" 3
}

# Get session info
get_session_info() {
    local session_id="$1"

    for index_file in "${PROJECTS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            local info=$(jq --arg id "$session_id" '
                .entries[] | select(.sessionId == $id)
            ' "$index_file")

            if [ -n "$info" ] && [ "$info" != "null" ]; then
                echo "$info"
                return 0
            fi
        fi
    done

    echo "{}"
}

# Record suggestion
record_suggestion() {
    local topic="$1"
    local session_ids="$2"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmpfile="${SUGGESTIONS_FILE}.tmp.$$"
    jq --arg topic "$topic" \
       --arg session_ids "$session_ids" \
       --arg timestamp "$timestamp" \
       '.suggestion_history += [{
           topic: $topic,
           suggested_sessions: ($session_ids | split(",")),
           timestamp: $timestamp
       }] |
       .last_updated = $timestamp' \
       "${SUGGESTIONS_FILE}" > "$tmpfile" && mv "$tmpfile" "${SUGGESTIONS_FILE}"
}

# Get suggestion statistics
get_suggestion_statistics() {
    if [ ! -f "${SUGGESTIONS_FILE}" ]; then
        echo "No suggestion data available."
        return 0
    fi

    echo "📊 Suggestion Statistics:"
    echo ""

    jq -r '
        "Total suggestions made: \(.suggestion_history | length)",
        "",
        "Recent suggestions:",
        (.suggestion_history[-10:] | reverse | .[] |
            "• \(.timestamp): \(.topic) (\(.suggested_sessions | length) sessions)")
    ' "${SUGGESTIONS_FILE}"
}

# CLI Interface
main() {
    initialize_suggestions

    local command="${1:-}"
    shift || true

    case "$command" in
        "suggest")
            if [ $# -eq 0 ]; then
                auto_suggest
            else
                suggest_relevant_sessions "$1" "${2:-5}"
            fi
            ;;
        "error")
            if [ $# -eq 0 ]; then
                echo "Usage: context-suggestions.sh error <error-text>"
                exit 1
            fi
            suggest_based_on_errors "$*"
            ;;
        "files")
            if [ $# -eq 0 ]; then
                echo "Usage: context-suggestions.sh files <file1> [file2] ..."
                exit 1
            fi
            suggest_based_on_files "$@"
            ;;
        "complementary")
            if [ $# -eq 0 ]; then
                echo "Usage: context-suggestions.sh complementary <session-id>"
                exit 1
            fi
            suggest_complementary "$1"
            ;;
        "auto")
            auto_suggest "$1"
            ;;
        "stats")
            get_suggestion_statistics
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
Context Suggestions - Proactively suggest relevant sessions

USAGE:
    context-suggestions.sh <command> [options]

COMMANDS:
    suggest [topic] [limit]             Suggest sessions by topic
    error <error-text>                  Suggest based on error
    files <file1> [file2] ...           Suggest based on files
    complementary <session-id>          Suggest related sessions
    auto [context]                      Auto-detect and suggest
    stats                               Show suggestion statistics
    help                                Show this help message

EXAMPLES:
    # Suggest by topic
    context-suggestions.sh suggest "authentication"

    # Suggest based on error
    context-suggestions.sh error "TypeError: Cannot read property"

    # Suggest based on files
    context-suggestions.sh files auth.js login.js

    # Auto-suggest
    context-suggestions.sh auto

    # Find complementary sessions
    context-suggestions.sh complementary "abc-123"

EOF
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'context-suggestions.sh help' for usage information."
            exit 1
            ;;
    esac
}

# Export functions for sourcing
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
