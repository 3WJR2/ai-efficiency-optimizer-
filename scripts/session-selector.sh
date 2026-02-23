#!/usr/bin/env bash
# session-selector.sh - Select which sessions to load in each tier
# Part of 3-Tier Smart Context Management System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"

# Tier settings
TIER1_MAX_SESSIONS=2      # Recent full sessions
TIER2_MAX_SESSIONS=10     # Related summaries
TIER1_MAX_AGE_DAYS=7      # Don't load full sessions older than this

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Session Listing & Filtering
# ============================================================================

# Get all sessions sorted by date (newest first)
list_all_sessions() {
    if [[ ! -d "$SESSIONS_DIR" ]]; then
        echo "[]"
        return 1
    fi

    ls -1 "$SESSIONS_DIR" 2>/dev/null | sort -r | jq -R . | jq -s .
}

# Get sessions from last N days
list_recent_sessions() {
    local days="${1:-7}"
    local cutoff_date=$(date -v-${days}d +%Y-%m-%d 2>/dev/null || date -d "${days} days ago" +%Y-%m-%d 2>/dev/null)

    if [[ ! -d "$SESSIONS_DIR" ]]; then
        echo "[]"
        return 1
    fi

    ls -1 "$SESSIONS_DIR" 2>/dev/null | while read -r session_id; do
        local session_date=$(echo "$session_id" | cut -d'-' -f1-3)
        if [[ "$session_date" > "$cutoff_date" ]] || [[ "$session_date" == "$cutoff_date" ]]; then
            echo "$session_id"
        fi
    done | jq -R . | jq -s .
}

# Get last N sessions
get_last_n_sessions() {
    local n="${1:-2}"

    if [[ ! -d "$SESSIONS_DIR" ]]; then
        echo "[]"
        return 1
    fi

    ls -1 "$SESSIONS_DIR" 2>/dev/null | sort -r | head -n "$n" | jq -R . | jq -s .
}

# ============================================================================
# Tier 1 Selection (Full Recent Sessions)
# ============================================================================

# Select sessions for Tier 1 (full content)
select_tier1_sessions() {
    local current_session="${1:-}"

    local sessions=()

    # 1. Most recent session (always)
    local recent_sessions=$(get_last_n_sessions "$TIER1_MAX_SESSIONS")
    local recent_count=$(echo "$recent_sessions" | jq 'length')

    # Filter by age
    local cutoff_date=$(date -v-${TIER1_MAX_AGE_DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${TIER1_MAX_AGE_DAYS} days ago" +%Y-%m-%d 2>/dev/null)

    echo "$recent_sessions" | jq -r '.[]' | while read -r session_id; do
        # Skip current session
        if [[ "$session_id" == "$current_session" ]]; then
            continue
        fi

        # Check age
        local session_date=$(echo "$session_id" | cut -d'-' -f1-3)
        if [[ "$session_date" > "$cutoff_date" ]] || [[ "$session_date" == "$cutoff_date" ]]; then
            cat <<EOF
{
  "session_id": "$session_id",
  "tier": 1,
  "load_type": "full",
  "reason": "recent"
}
EOF
        fi
    done | jq -s .
}

# ============================================================================
# Tier 2 Selection (Related Summaries)
# ============================================================================

# Select sessions for Tier 2 (summaries)
select_tier2_sessions() {
    local current_task="$1"
    local current_context="${2:-{}}"
    local exclude_sessions="${3:-[]}"  # JSON array of session IDs to exclude

    # Use relevance scorer to find related sessions
    if [[ ! -x "$SCRIPT_DIR/relevance-scorer.sh" ]]; then
        echo "[]"
        return 1
    fi

    local related=$("$SCRIPT_DIR/relevance-scorer.sh" find "$current_task" "$TIER2_MAX_SESSIONS" "$current_context")

    # Filter out excluded sessions and format
    echo "$related" | jq -c '.[]' | while read -r entry; do
        local session_id=$(echo "$entry" | jq -r '.session_id')
        local score=$(echo "$entry" | jq -r '.relevance_score')

        # Check if excluded
        local is_excluded=$(echo "$exclude_sessions" | jq --arg sid "$session_id" 'any(. == $sid)')

        if [[ "$is_excluded" == "false" ]]; then
            cat <<EOF
{
  "session_id": "$session_id",
  "tier": 2,
  "load_type": "summary",
  "relevance_score": $score,
  "reason": "relevant"
}
EOF
        fi
    done | jq -s .
}

# ============================================================================
# Combined Selection
# ============================================================================

# Select sessions for all tiers
select_all_tiers() {
    local current_task="$1"
    local current_session="${2:-}"
    local current_context="${3:-{}}"

    # Tier 1: Recent full sessions
    local tier1=$(select_tier1_sessions "$current_session")

    # Get list of Tier 1 session IDs to exclude from Tier 2
    local tier1_ids=$(echo "$tier1" | jq -c '[.[].session_id]')

    # Tier 2: Related summaries (excluding Tier 1)
    local tier2=$(select_tier2_sessions "$current_task" "$current_context" "$tier1_ids")

    # Combine results
    cat <<EOF
{
  "tier1": $tier1,
  "tier2": $tier2,
  "summary": {
    "tier1_count": $(echo "$tier1" | jq 'length'),
    "tier2_count": $(echo "$tier2" | jq 'length'),
    "total_count": $(($(echo "$tier1" | jq 'length') + $(echo "$tier2" | jq 'length')))
  }
}
EOF
}

# ============================================================================
# Session Grouping & Categorization
# ============================================================================

# Group sessions by topic/theme
group_sessions_by_topic() {
    local session_ids="$1"  # JSON array

    local grouped=$(mktemp)
    echo "{}" > "$grouped"

    echo "$session_ids" | jq -r '.[]' | while read -r session_id; do
        # Get session themes
        local themes=$("$SCRIPT_DIR/relevance-scorer.sh" themes "$session_id" 2>/dev/null || echo "[]")

        # Group by first theme (or "general" if none)
        local primary_theme=$(echo "$themes" | jq -r '.[0] // "general"')

        # Add to group
        jq --arg theme "$primary_theme" --arg sid "$session_id" \
           '.[$theme] += [$sid]' "$grouped" > "${grouped}.tmp" && mv "${grouped}.tmp" "$grouped"
    done

    cat "$grouped"
    rm -f "$grouped"
}

# Group sessions by date range
group_sessions_by_date() {
    local session_ids="$1"  # JSON array

    local grouped='{
  "today": [],
  "this_week": [],
  "this_month": [],
  "older": []
}'

    local today=$(date +%Y-%m-%d)
    local week_ago=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null)
    local month_ago=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "30 days ago" +%Y-%m-%d 2>/dev/null)

    echo "$session_ids" | jq -r '.[]' | while read -r session_id; do
        local session_date=$(echo "$session_id" | cut -d'-' -f1-3)

        if [[ "$session_date" == "$today" ]]; then
            grouped=$(echo "$grouped" | jq --arg sid "$session_id" '.today += [$sid]')
        elif [[ "$session_date" > "$week_ago" ]] || [[ "$session_date" == "$week_ago" ]]; then
            grouped=$(echo "$grouped" | jq --arg sid "$session_id" '.this_week += [$sid]')
        elif [[ "$session_date" > "$month_ago" ]] || [[ "$session_date" == "$month_ago" ]]; then
            grouped=$(echo "$grouped" | jq --arg sid "$session_id" '.this_month += [$sid]')
        else
            grouped=$(echo "$grouped" | jq --arg sid "$session_id" '.older += [$sid]')
        fi
    done

    echo "$grouped"
}

# ============================================================================
# Session Validation
# ============================================================================

# Check if session has usable content
validate_session() {
    local session_id="$1"
    local session_dir="$SESSIONS_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        echo "false"
        return 1
    fi

    # Check for conversation log or context file
    if [[ -f "$session_dir/conversation-log.jsonl" ]] || [[ -f "$session_dir/.session-context.md" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Filter sessions to only those with content
filter_valid_sessions() {
    local session_ids="$1"  # JSON array

    echo "$session_ids" | jq -r '.[]' | while read -r session_id; do
        local is_valid=$(validate_session "$session_id")
        if [[ "$is_valid" == "true" ]]; then
            echo "$session_id"
        fi
    done | jq -R . | jq -s .
}

# ============================================================================
# Statistics
# ============================================================================

# Get session selection statistics
get_selection_stats() {
    local all_sessions=$(list_all_sessions)
    local recent_sessions=$(list_recent_sessions 7)
    local valid_sessions=$(filter_valid_sessions "$all_sessions")

    cat <<EOF
{
  "total_sessions": $(echo "$all_sessions" | jq 'length'),
  "recent_sessions": $(echo "$recent_sessions" | jq 'length'),
  "valid_sessions": $(echo "$valid_sessions" | jq 'length'),
  "tier1_max": $TIER1_MAX_SESSIONS,
  "tier2_max": $TIER2_MAX_SESSIONS,
  "tier1_age_limit_days": $TIER1_MAX_AGE_DAYS
}
EOF
}

# ============================================================================
# Main CLI
# ============================================================================

show_usage() {
    cat <<EOF
Session Selector - Select sessions for context tiers

Usage:
  $(basename "$0") tier1 [current_session]                Select Tier 1 sessions
  $(basename "$0") tier2 <task> [context] [exclude]       Select Tier 2 sessions
  $(basename "$0") all <task> [current_session] [context] Select all tiers
  $(basename "$0") list [days]                            List recent sessions
  $(basename "$0") validate <session_id>                  Validate session
  $(basename "$0") stats                                  Show statistics
  $(basename "$0") group-by-topic <sessions_json>         Group by topic
  $(basename "$0") group-by-date <sessions_json>          Group by date

Examples:
  # Select Tier 1 sessions
  $(basename "$0") tier1

  # Select Tier 2 sessions
  $(basename "$0") tier2 "implement authentication"

  # Select all tiers
  $(basename "$0") all "build TUI interface"

  # List recent sessions
  $(basename "$0") list 7

  # Get statistics
  $(basename "$0") stats
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        tier1)
            select_tier1_sessions "${2:-}" | jq .
            ;;
        tier2)
            select_tier2_sessions "${2:-}" "${3:-{}}" "${4:-[]}" | jq .
            ;;
        all)
            select_all_tiers "${2:-general}" "${3:-}" "${4:-{}}" | jq .
            ;;
        list)
            list_recent_sessions "${2:-7}" | jq .
            ;;
        validate)
            validate_session "${2:-}"
            ;;
        stats)
            get_selection_stats | jq .
            ;;
        group-by-topic)
            group_sessions_by_topic "${2:-[]}" | jq .
            ;;
        group-by-date)
            group_sessions_by_date "${2:-[]}" | jq .
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}" >&2
            show_usage
            exit 1
            ;;
    esac
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
