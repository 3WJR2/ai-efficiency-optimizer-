#!/usr/bin/env bash

# Session Search Engine
# Advanced search capabilities for finding past conversations
# Version: 1.0.0

set -euo pipefail

# Directories
CLAUDE_DIR="${HOME}/.claude"
DATA_DIR="${CLAUDE_DIR}/data"
PROJECTS_DIR="${CLAUDE_DIR}/projects"

# Data files
SEARCH_CACHE_FILE="${DATA_DIR}/session-search-cache.json"
EMBEDDINGS_DIR="${CLAUDE_DIR}/cache/embeddings"

# Initialize
initialize_search() {
    mkdir -p "${DATA_DIR}"
    mkdir -p "${EMBEDDINGS_DIR}"

    if [ ! -f "${SEARCH_CACHE_FILE}" ]; then
        cat > "${SEARCH_CACHE_FILE}" <<EOF
{
  "version": "1.0.0",
  "cached_searches": {},
  "last_indexed": null
}
EOF
    fi
}

# Search by topic (semantic search)
search_by_topic() {
    local topic="$1"

    # Check if knowledge embeddings exist
    local embeddings_file="${DATA_DIR}/knowledge-embeddings.json"

    if [ -f "$embeddings_file" ]; then
        # Use semantic search via embeddings
        semantic_search "$topic"
    else
        # Fallback to keyword search
        keyword_search "$topic"
    fi
}

# Semantic search using embeddings
semantic_search() {
    local query="$1"

    # Try to use knowledge search if available
    if [ -f "${CLAUDE_DIR}/scripts/knowledge-search.sh" ]; then
        local results=$(bash "${CLAUDE_DIR}/scripts/knowledge-search.sh" search "$query" 2>/dev/null || echo "[]")

        # Extract unique session IDs
        echo "$results" | jq -r '
            if type == "object" and has("results") then
                [.results[] | .session_id // .sessionId // empty] | unique
            else
                []
            end
        '
    else
        keyword_search "$query"
    fi
}

# Keyword search in session metadata
keyword_search() {
    local keywords="$1"

    local results="[]"

    # Search all sessions-index.json files
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

    echo "$results"
}

# Search by timeframe
search_by_timeframe() {
    local timeframe="$1"

    local start_date=$(parse_timeframe_start "$timeframe")
    local end_date=$(parse_timeframe_end "$timeframe")

    local results="[]"

    for index_file in "${PROJECTS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            local matches=$(jq --arg start "$start_date" --arg end "$end_date" '
                .entries[] | select(
                    (.created >= $start and .created <= $end) or
                    (.modified >= $start and .modified <= $end)
                )
            ' "$index_file" | jq -s '.')

            if [ "$matches" != "[]" ]; then
                results=$(echo "$results" | jq --argjson new "$matches" '. + $new')
            fi
        fi
    done

    echo "$results"
}

# Parse timeframe to start date
parse_timeframe_start() {
    local timeframe="$1"

    case "$timeframe" in
        "today")
            date -u +"%Y-%m-%d" || date -u -I
            ;;
        "yesterday")
            date -u -v-1d +"%Y-%m-%d" 2>/dev/null || date -u -d "yesterday" +"%Y-%m-%d"
            ;;
        "last_week")
            date -u -v-7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%d"
            ;;
        "last_month")
            date -u -v-1m +"%Y-%m-%d" 2>/dev/null || date -u -d "1 month ago" +"%Y-%m-%d"
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9])
            # Month format: 2026-02
            echo "${timeframe}-01"
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            # Date format: 2026-02-15
            echo "$timeframe"
            ;;
        *)
            # Default to 30 days ago
            date -u -v-30d +"%Y-%m-%d" 2>/dev/null || date -u -d "30 days ago" +"%Y-%m-%d"
            ;;
    esac
}

# Parse timeframe to end date
parse_timeframe_end() {
    local timeframe="$1"

    case "$timeframe" in
        "today")
            date -u +"%Y-%m-%d" || date -u -I
            ;;
        "yesterday")
            date -u -v-1d +"%Y-%m-%d" 2>/dev/null || date -u -d "yesterday" +"%Y-%m-%d"
            ;;
        "last_week"|"last_month")
            date -u +"%Y-%m-%d" || date -u -I
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9])
            # Month format: get last day of month
            local year="${timeframe%-*}"
            local month="${timeframe#*-}"
            local next_month=$(printf "%02d" $((10#$month + 1)))
            if [ "$next_month" = "13" ]; then
                next_month="01"
                year=$((year + 1))
            fi
            date -u -v"${year}y" -v"${next_month}m" -v1d -v-1d +"%Y-%m-%d" 2>/dev/null || \
            date -u -d "${year}-${next_month}-01 -1 day" +"%Y-%m-%d"
            ;;
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
            echo "$timeframe"
            ;;
        *)
            date -u +"%Y-%m-%d" || date -u -I
            ;;
    esac
}

# Search by tags/keywords
search_by_keywords() {
    local keywords="$1"

    # Split keywords by comma or space
    IFS=',' read -ra keyword_array <<< "$keywords"

    local results="[]"

    for index_file in "${PROJECTS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            for keyword in "${keyword_array[@]}"; do
                keyword=$(echo "$keyword" | xargs) # trim whitespace

                local matches=$(jq --arg keyword "$keyword" '
                    .entries[] | select(
                        (.summary // "" | ascii_downcase | contains($keyword | ascii_downcase)) or
                        (.firstPrompt // "" | ascii_downcase | contains($keyword | ascii_downcase))
                    )
                ' "$index_file" | jq -s '.')

                if [ "$matches" != "[]" ]; then
                    results=$(echo "$results" | jq --argjson new "$matches" '. + $new')
                fi
            done
        fi
    done

    # Deduplicate by sessionId
    echo "$results" | jq 'unique_by(.sessionId)'
}

# Combined search with all filters
search_sessions() {
    local topic="${1:-}"
    local timeframe="${2:-}"
    local tags="${3:-}"

    local results="[]"

    # Start with all sessions if no filters
    if [ -z "$topic" ] && [ -z "$timeframe" ] && [ -z "$tags" ]; then
        results=$(get_all_sessions)
    fi

    # Apply topic filter
    if [ -n "$topic" ]; then
        results=$(search_by_topic "$topic")
    fi

    # Apply timeframe filter
    if [ -n "$timeframe" ]; then
        if [ "$results" = "[]" ]; then
            results=$(search_by_timeframe "$timeframe")
        else
            # Filter existing results by timeframe
            local start_date=$(parse_timeframe_start "$timeframe")
            local end_date=$(parse_timeframe_end "$timeframe")

            results=$(echo "$results" | jq --arg start "$start_date" --arg end "$end_date" '
                map(select(
                    (.created >= $start and .created <= $end) or
                    (.modified >= $start and .modified <= $end)
                ))
            ')
        fi
    fi

    # Apply tag filter
    if [ -n "$tags" ]; then
        if [ "$results" = "[]" ]; then
            results=$(search_by_keywords "$tags")
        else
            # Filter existing results by keywords
            IFS=',' read -ra tag_array <<< "$tags"
            for tag in "${tag_array[@]}"; do
                tag=$(echo "$tag" | xargs)
                results=$(echo "$results" | jq --arg tag "$tag" '
                    map(select(
                        (.summary // "" | ascii_downcase | contains($tag | ascii_downcase)) or
                        (.firstPrompt // "" | ascii_downcase | contains($tag | ascii_downcase))
                    ))
                ')
            done
        fi
    fi

    # Score and rank results
    score_and_rank_sessions "$results"
}

# Get all sessions
get_all_sessions() {
    local results="[]"

    for index_file in "${PROJECTS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            local entries=$(jq '.entries[]' "$index_file" | jq -s '.')
            results=$(echo "$results" | jq --argjson new "$entries" '. + $new')
        fi
    done

    echo "$results"
}

# Score and rank sessions by relevance
score_and_rank_sessions() {
    local sessions="$1"

    # Sort by modified date (most recent first) and messageCount (longer sessions ranked higher)
    echo "$sessions" | jq '
        map(. + {
            score: (
                (.messageCount // 0) * 0.3 +
                (if .modified then 1000 else 0 end) * 0.7
            )
        }) |
        sort_by(.modified) |
        reverse |
        sort_by(-.score)
    '
}

# Filter sessions by timeframe
filter_by_timeframe() {
    local sessions="$1"
    local timeframe="$2"

    local start_date=$(parse_timeframe_start "$timeframe")
    local end_date=$(parse_timeframe_end "$timeframe")

    echo "$sessions" | jq --arg start "$start_date" --arg end "$end_date" '
        map(select(
            (.created >= $start and .created <= $end) or
            (.modified >= $start and .modified <= $end)
        ))
    '
}

# Filter sessions by tags
filter_by_tags() {
    local sessions="$1"
    local tags="$2"

    IFS=',' read -ra tag_array <<< "$tags"

    for tag in "${tag_array[@]}"; do
        tag=$(echo "$tag" | xargs)
        sessions=$(echo "$sessions" | jq --arg tag "$tag" '
            map(select(
                (.summary // "" | ascii_downcase | contains($tag | ascii_downcase)) or
                (.firstPrompt // "" | ascii_downcase | contains($tag | ascii_downcase))
            ))
        ')
    done

    echo "$sessions"
}

# List recent topics
list_recent_topics() {
    echo "📋 Recent Session Topics:"
    echo ""

    local all_sessions=$(get_all_sessions)

    echo "$all_sessions" | jq -r '
        sort_by(.modified) |
        reverse |
        .[0:20] |
        .[] |
        "• \(.summary // "No summary") (\(.modified[0:10]))"
    '
}

# Search sessions by session ID
search_by_session_id() {
    local session_id="$1"

    for index_file in "${PROJECTS_DIR}"/*-wallonwalusayi/sessions-index.json; do
        if [ -f "$index_file" ]; then
            local match=$(jq --arg id "$session_id" '
                .entries[] | select(.sessionId == $id)
            ' "$index_file")

            if [ -n "$match" ] && [ "$match" != "null" ]; then
                echo "[$match]"
                return 0
            fi
        fi
    done

    echo "[]"
}

# Get session statistics
get_session_statistics() {
    echo "📊 Session Statistics:"
    echo ""

    local all_sessions=$(get_all_sessions)
    local total=$(echo "$all_sessions" | jq 'length')
    local total_messages=$(echo "$all_sessions" | jq '[.[].messageCount // 0] | add')

    echo "Total sessions: $total"
    echo "Total messages: $total_messages"
    echo ""
    echo "Most active topics:"

    # Extract common words from summaries
    echo "$all_sessions" | jq -r '.[] | .summary // ""' | \
        tr '[:upper:]' '[:lower:]' | \
        tr -cs '[:alnum:]' '\n' | \
        sort | uniq -c | sort -rn | head -10 | \
        awk '{print "  " $2 " (" $1 ")"}'
}

# CLI Interface
main() {
    initialize_search

    local command="${1:-}"
    shift || true

    case "$command" in
        "search")
            local topic="${1:-}"
            local timeframe="${2:-}"
            local tags="${3:-}"
            search_sessions "$topic" "$timeframe" "$tags"
            ;;
        "by-topic")
            if [ $# -eq 0 ]; then
                echo "Usage: session-search.sh by-topic <topic>"
                exit 1
            fi
            search_by_topic "$1"
            ;;
        "by-timeframe")
            if [ $# -eq 0 ]; then
                echo "Usage: session-search.sh by-timeframe <timeframe>"
                exit 1
            fi
            search_by_timeframe "$1"
            ;;
        "by-keywords")
            if [ $# -eq 0 ]; then
                echo "Usage: session-search.sh by-keywords <keywords>"
                exit 1
            fi
            search_by_keywords "$1"
            ;;
        "by-id")
            if [ $# -eq 0 ]; then
                echo "Usage: session-search.sh by-id <session-id>"
                exit 1
            fi
            search_by_session_id "$1"
            ;;
        "topics")
            list_recent_topics
            ;;
        "stats")
            get_session_statistics
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
Session Search Engine - Find past conversations

USAGE:
    session-search.sh <command> [options]

COMMANDS:
    search <topic> [timeframe] [tags]    Combined search with filters
    by-topic <topic>                     Search by topic/content
    by-timeframe <timeframe>             Search by time period
    by-keywords <keywords>               Search by keywords (comma-separated)
    by-id <session-id>                   Find session by ID
    topics                               List recent session topics
    stats                                Show session statistics
    help                                 Show this help message

TIMEFRAME FORMATS:
    today                   Today's sessions
    yesterday               Yesterday's sessions
    last_week               Last 7 days
    last_month              Last 30 days
    2026-02                 Specific month
    2026-02-15              Specific date

EXAMPLES:
    # Search by topic
    session-search.sh by-topic "authentication"

    # Search by timeframe
    session-search.sh by-timeframe "2026-02"

    # Combined search
    session-search.sh search "JWT" "last_week" "security"

    # Find by ID
    session-search.sh by-id "5ff7e99f-a818-43a7-8ca5-4cfde0b106e6"

EOF
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'session-search.sh help' for usage information."
            exit 1
            ;;
    esac
}

# Export functions for sourcing
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
