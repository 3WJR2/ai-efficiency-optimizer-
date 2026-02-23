#!/usr/bin/env bash

# Request Parser
# Parses natural language requests into structured queries
# Version: 1.0.0

set -euo pipefail

# Directories
CLAUDE_DIR="${HOME}/.claude"
DATA_DIR="${CLAUDE_DIR}/data"

# Pattern matching (note: these are for documentation/reference)
# Actual pattern matching is done via regex in match_patterns function

# Initialize
initialize_parser() {
    mkdir -p "${DATA_DIR}"
}

# Parse natural language request
parse_request() {
    local query="$1"
    local query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

    # Try pattern matching
    local parsed=$(match_patterns "$query_lower")

    if [ "$parsed" != "{}" ]; then
        echo "$parsed"
        return 0
    fi

    # Fallback: extract topic and timeframe
    local topic=$(extract_topic "$query")
    local timeframe=$(extract_timeframe "$query")
    local focus=$(extract_focus "$query")

    # Build JSON response
    jq -n \
        --arg topic "$topic" \
        --arg timeframe "$timeframe" \
        --arg focus "$focus" \
        '{
            action: "load",
            topic: (if $topic != "" then $topic else null end),
            timeframe: (if $timeframe != "" then $timeframe else null end),
            focus: (if $focus != "" then $focus else null end)
        }'
}

# Match against patterns
match_patterns() {
    local query="$1"

    # Load session by number
    if [[ "$query" =~ load[[:space:]]+session[[:space:]]+([0-9]+) ]]; then
        jq -n \
            --arg session_number "${BASH_REMATCH[1]}" \
            '{action: "load", session_number: $session_number, topic: null, timeframe: null, focus: null}'
        return 0
    fi

    # Show session by ID
    if [[ "$query" =~ show[[:space:]](me[[:space:]])?session[[:space:]]+([a-z0-9-]+) ]]; then
        jq -n \
            --arg session_id "${BASH_REMATCH[2]}" \
            '{action: "load", session_id: $session_id, topic: null, timeframe: null, focus: null}'
        return 0
    fi

    # Get conversation about
    if [[ "$query" =~ get[[:space:]]conversation[[:space:]](from|about)[[:space:]](.*) ]]; then
        jq -n \
            --arg topic "${BASH_REMATCH[2]}" \
            '{action: "load", topic: $topic, timeframe: null, focus: null}'
        return 0
    fi

    # What did we do/build/decide about
    if [[ "$query" =~ what[[:space:]]did[[:space:]]we[[:space:]](do|build|decide|discuss)[[:space:]](about|with|for|on)[[:space:]](.*) ]]; then
        local action="${BASH_REMATCH[1]}"
        local topic="${BASH_REMATCH[3]}"
        local focus=""

        case "$action" in
            "decide")
                focus="decisions"
                ;;
            "build")
                focus="code"
                ;;
        esac

        jq -n \
            --arg topic "$topic" \
            --arg focus "$focus" \
            '{action: "load", topic: $topic, timeframe: null, focus: (if $focus != "" then $focus else null end)}'
        return 0
    fi

    # Show me X work
    if [[ "$query" =~ show[[:space:]](me[[:space:]])?(.*)work ]]; then
        jq -n \
            --arg topic "${BASH_REMATCH[2]}" \
            '{action: "load", topic: ($topic | rtrimstr(" ")), timeframe: null, focus: null}'
        return 0
    fi

    # Last week/month/session
    if [[ "$query" =~ last[[:space:]](week|month|session) ]]; then
        local period="${BASH_REMATCH[1]}"
        local timeframe=""

        case "$period" in
            "week")
                timeframe="last_week"
                ;;
            "month")
                timeframe="last_month"
                ;;
            "session")
                timeframe="last_session"
                ;;
        esac

        jq -n \
            --arg timeframe "$timeframe" \
            '{action: "load", topic: null, timeframe: $timeframe, focus: null}'
        return 0
    fi

    # Sessions from month
    if [[ "$query" =~ sessions?[[:space:]]from[[:space:]]([0-9]{4}-[0-9]{2}) ]]; then
        jq -n \
            --arg timeframe "${BASH_REMATCH[1]}" \
            '{action: "load", topic: null, timeframe: $timeframe, focus: null}'
        return 0
    fi

    # Yesterday's conversation
    if [[ "$query" =~ yesterday ]]; then
        jq -n \
            '{action: "load", topic: null, timeframe: "yesterday", focus: null}'
        return 0
    fi

    # Decisions about
    if [[ "$query" =~ decisions?[[:space:]](about|on|for)[[:space:]](.*) ]]; then
        jq -n \
            --arg topic "${BASH_REMATCH[2]}" \
            '{action: "load", topic: $topic, timeframe: null, focus: "decisions"}'
        return 0
    fi

    # Code for
    if [[ "$query" =~ code[[:space:]](for|from)[[:space:]](.*) ]]; then
        jq -n \
            --arg topic "${BASH_REMATCH[2]}" \
            '{action: "load", topic: $topic, timeframe: null, focus: "code"}'
        return 0
    fi

    # Why chose
    if [[ "$query" =~ why[[:space:]](we[[:space:]]|did[[:space:]]we[[:space:]])?chose[[:space:]](.*) ]]; then
        jq -n \
            --arg topic "${BASH_REMATCH[2]}" \
            '{action: "load", topic: $topic, timeframe: null, focus: "decisions"}'
        return 0
    fi

    # Errors in
    if [[ "$query" =~ errors?[[:space:]](in|from|about)[[:space:]](.*) ]]; then
        jq -n \
            --arg topic "${BASH_REMATCH[2]}" \
            '{action: "load", topic: $topic, timeframe: null, focus: "errors"}'
        return 0
    fi

    # No pattern matched
    echo "{}"
}

# Extract topic from query
extract_topic() {
    local query="$1"

    # Remove common time-related words
    local topic=$(echo "$query" | sed -E '
        s/(last|yesterday|today|this) (week|month|year|session)//gi
        s/from [0-9]{4}-[0-9]{2}(-[0-9]{2})?//gi
        s/(show me|load|get|find)//gi
        s/(about|with|for|on)//gi
        s/(conversation|session|work)//gi
    ' | xargs)

    # If topic is too short, return empty
    if [ ${#topic} -lt 3 ]; then
        echo ""
    else
        echo "$topic"
    fi
}

# Extract timeframe from query
extract_timeframe() {
    local query="$1"

    # Check for specific patterns
    if [[ "$query" =~ last[[:space:]]week ]]; then
        echo "last_week"
        return 0
    fi

    if [[ "$query" =~ last[[:space:]]month ]]; then
        echo "last_month"
        return 0
    fi

    if [[ "$query" =~ yesterday ]]; then
        echo "yesterday"
        return 0
    fi

    if [[ "$query" =~ today ]]; then
        echo "today"
        return 0
    fi

    # Extract date patterns
    if [[ "$query" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "$query" =~ ([0-9]{4}-[0-9]{2}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # No timeframe found
    echo ""
}

# Extract focus from query
extract_focus() {
    local query="$1"

    if [[ "$query" =~ decision ]]; then
        echo "decisions"
        return 0
    fi

    if [[ "$query" =~ code ]]; then
        echo "code"
        return 0
    fi

    if [[ "$query" =~ error|bug|issue ]]; then
        echo "errors"
        return 0
    fi

    if [[ "$query" =~ debug ]]; then
        echo "debugging"
        return 0
    fi

    # No focus found
    echo ""
}

# Test parser with examples
test_parser() {
    echo "🧪 Testing Request Parser"
    echo ""

    local test_cases=(
        "show me the auth session from february"
        "what did we decide about caching?"
        "load the JWT implementation code"
        "last week's debugging session"
        "session 5 from january"
        "yesterday's conversation"
        "decisions about database"
        "code for authentication"
        "why we chose redis"
        "errors in the API"
    )

    for query in "${test_cases[@]}"; do
        echo "Query: $query"
        parse_request "$query" | jq '.'
        echo ""
    done
}

# Get parse statistics
get_parse_statistics() {
    echo "📊 Parser Statistics:"
    echo ""
    echo "Supported patterns: ${#PATTERNS[@]}"
    echo ""
    echo "Pattern categories:"
    echo "• Session loading: 3 patterns"
    echo "• Topic-based: 3 patterns"
    echo "• Time-based: 4 patterns"
    echo "• Focused loading: 4 patterns"
    echo "• Common questions: 3 patterns"
}

# CLI Interface
main() {
    initialize_parser

    local command="${1:-}"
    shift || true

    case "$command" in
        "parse")
            if [ $# -eq 0 ]; then
                echo "Usage: request-parser.sh parse <query>"
                exit 1
            fi
            parse_request "$*"
            ;;
        "test")
            test_parser
            ;;
        "stats")
            get_parse_statistics
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
Request Parser - Parse natural language queries

USAGE:
    request-parser.sh <command> [options]

COMMANDS:
    parse <query>      Parse a natural language query
    test               Run test cases
    stats              Show parser statistics
    help               Show this help message

SUPPORTED PATTERNS:
    Session Loading:
    • "load session 5"
    • "show me session abc-123"
    • "get conversation about authentication"

    Topic-based:
    • "what did we build for authentication"
    • "show me caching work"
    • "load JWT sessions"

    Time-based:
    • "last week"
    • "sessions from 2026-02"
    • "yesterday's conversation"

    Focused Loading:
    • "decisions about caching"
    • "code for JWT"
    • "why we chose Redis"
    • "errors in the API"

EXAMPLES:
    # Parse a query
    request-parser.sh parse "show me the auth session from february"

    # Test parser
    request-parser.sh test

EOF
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'request-parser.sh help' for usage information."
            exit 1
            ;;
    esac
}

# Export functions for sourcing
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
