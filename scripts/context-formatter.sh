#!/usr/bin/env bash
# context-formatter.sh - Format context for Claude consumption
# Part of 3-Tier Smart Context Management System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Session Content Loading
# ============================================================================

# Load full conversation from session
load_full_conversation() {
    local session_id="$1"
    local session_dir="$SESSIONS_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        echo "Session not found: $session_id"
        return 1
    fi

    # Try conversation log first
    if [[ -f "$session_dir/conversation-log.jsonl" ]]; then
        # Format JSONL conversation
        cat "$session_dir/conversation-log.jsonl" | while IFS= read -r line; do
            local role=$(echo "$line" | jq -r '.role // "unknown"')
            local content=$(echo "$line" | jq -r '.content // ""')
            local timestamp=$(echo "$line" | jq -r '.timestamp // ""')

            echo "${role}: ${content}"
            echo ""
        done
    elif [[ -f "$session_dir/.session-context.md" ]]; then
        # Use context file
        cat "$session_dir/.session-context.md"
    else
        echo "No conversation content available"
    fi
}

# Load session summary
load_session_summary() {
    local session_id="$1"
    local session_dir="$SESSIONS_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        echo "Session not found"
        return 1
    fi

    # Check for existing summary
    if [[ -f "$session_dir/summary.md" ]]; then
        cat "$session_dir/summary.md"
        return 0
    fi

    # Generate basic summary from available data
    local session_date=$(echo "$session_id" | cut -d'-' -f1-3)
    local themes=$("$SCRIPT_DIR/relevance-scorer.sh" themes "$session_id" 2>/dev/null || echo "[]")
    local themes_text=$(echo "$themes" | jq -r '.[]' | tr '\n' ', ' | sed 's/, $//')

    # Get conversation preview
    local preview=""
    if [[ -f "$session_dir/.session-context.md" ]]; then
        preview=$(head -20 "$session_dir/.session-context.md")
    fi

    cat <<EOF
**Date:** $session_date
**Topics:** ${themes_text:-general}

$preview

[Summary not yet generated - run knowledge pipeline to create detailed summaries]
EOF
}

# ============================================================================
# Tier 1 Formatting (Full Conversations)
# ============================================================================

format_tier1() {
    local sessions="$1"  # JSON array of session objects

    cat <<EOF
# 💬 Recent Conversations (Full Detail)

EOF

    local count=$(echo "$sessions" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No recent sessions to load."
        return 0
    fi

    echo "$sessions" | jq -c '.[]' | while read -r session_entry; do
        local session_id=$(echo "$session_entry" | jq -r '.session_id')
        local session_date=$(echo "$session_id" | cut -d'-' -f1-3)
        local reason=$(echo "$session_entry" | jq -r '.reason // "recent"')

        # Format date nicely
        local date_display=$(date -j -f "%Y-%m-%d" "$session_date" "+%B %d, %Y" 2>/dev/null || echo "$session_date")

        # Get session metadata
        local metadata=$("$SCRIPT_DIR/relevance-scorer.sh" metadata "$session_id" 2>/dev/null || echo "{}")
        local themes=$(echo "$metadata" | jq -r '.themes[]?' | head -3 | tr '\n' ', ' | sed 's/, $//')

        cat <<EOF
## Session: $session_id
**Date:** $date_display
**Topics:** ${themes:-general}

<conversation>
$(load_full_conversation "$session_id")
</conversation>

---

EOF
    done
}

# ============================================================================
# Tier 2 Formatting (Summaries)
# ============================================================================

format_tier2() {
    local sessions="$1"  # JSON array of session objects

    cat <<EOF
# 📚 Related Work (Summaries)

These sessions are relevant to your current task based on topic similarity, shared files, and context overlap.

EOF

    local count=$(echo "$sessions" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No related sessions found."
        return 0
    fi

    # Group sessions by topic for better organization
    local all_session_ids=$(echo "$sessions" | jq -c '[.[].session_id]')
    local grouped=$("$SCRIPT_DIR/session-selector.sh" group-by-topic "$all_session_ids" 2>/dev/null || echo "{}")

    # Format by topic groups
    echo "$grouped" | jq -r 'to_entries | .[]' | while read -r group_entry; do
        local topic=$(echo "$group_entry" | jq -r '.key')
        local group_sessions=$(echo "$group_entry" | jq -c '.value')

        cat <<EOF
## Topic: ${topic}

EOF

        echo "$group_sessions" | jq -r '.[]' | while read -r session_id; do
            local session_date=$(echo "$session_id" | cut -d'-' -f1-3)
            local date_display=$(date -j -f "%Y-%m-%d" "$session_date" "+%b %d" 2>/dev/null || echo "$session_date")

            # Get relevance score if available
            local score=$(echo "$sessions" | jq -r --arg sid "$session_id" '.[] | select(.session_id == $sid) | .relevance_score // 0')
            local score_display=$(echo "scale=2; $score * 100" | bc)

            cat <<EOF
### $session_id ($date_display) - Relevance: ${score_display}%

$(load_session_summary "$session_id")

EOF
        done

        echo ""
    done
}

# ============================================================================
# Tier 3 Formatting (Index)
# ============================================================================

format_tier3() {
    local all_sessions="$1"  # JSON array of all session IDs

    cat <<EOF
# 🔍 Full History Available (On-Demand)

You can request full details from any past session. Say "load session X" or "show me the conversation about Y" to access complete context.

EOF

    local total=$(echo "$all_sessions" | jq 'length')

    # Group by date
    local grouped=$("$SCRIPT_DIR/session-selector.sh" group-by-date "$all_sessions" 2>/dev/null || echo '{}')

    # Today
    local today_sessions=$(echo "$grouped" | jq -c '.today')
    local today_count=$(echo "$today_sessions" | jq 'length')
    if [[ $today_count -gt 0 ]]; then
        cat <<EOF
## Today ($today_count sessions)

EOF
        echo "$today_sessions" | jq -r '.[]' | while read -r session_id; do
            local metadata=$("$SCRIPT_DIR/relevance-scorer.sh" metadata "$session_id" 2>/dev/null || echo "{}")
            local themes=$(echo "$metadata" | jq -r '.themes[0:2][]?' | tr '\n' ', ' | sed 's/, $//')
            echo "  - **$session_id**: ${themes:-general}"
        done
        echo ""
    fi

    # This week
    local week_sessions=$(echo "$grouped" | jq -c '.this_week')
    local week_count=$(echo "$week_sessions" | jq 'length')
    if [[ $week_count -gt 0 ]]; then
        cat <<EOF
## This Week ($week_count sessions)

EOF
        echo "$week_sessions" | jq -r '.[]' | while read -r session_id; do
            local session_date=$(echo "$session_id" | cut -d'-' -f1-3)
            local metadata=$("$SCRIPT_DIR/relevance-scorer.sh" metadata "$session_id" 2>/dev/null || echo "{}")
            local themes=$(echo "$metadata" | jq -r '.themes[0:2][]?' | tr '\n' ', ' | sed 's/, $//')
            echo "  - **$session_id** ($session_date): ${themes:-general}"
        done
        echo ""
    fi

    # This month
    local month_sessions=$(echo "$grouped" | jq -c '.this_month')
    local month_count=$(echo "$month_sessions" | jq 'length')
    if [[ $month_count -gt 0 ]]; then
        cat <<EOF
## This Month ($month_count sessions)

EOF
        echo "$month_sessions" | jq -r '.[]' | head -10 | while read -r session_id; do
            local session_date=$(echo "$session_id" | cut -d'-' -f1-3)
            local metadata=$("$SCRIPT_DIR/relevance-scorer.sh" metadata "$session_id" 2>/dev/null || echo "{}")
            local themes=$(echo "$metadata" | jq -r '.themes[0:1][]?' | tr '\n' ', ' | sed 's/, $//')
            echo "  - **$session_id** ($session_date): ${themes:-general}"
        done
        if [[ $month_count -gt 10 ]]; then
            echo "  - ... and $((month_count - 10)) more"
        fi
        echo ""
    fi

    # Older
    local older_sessions=$(echo "$grouped" | jq -c '.older')
    local older_count=$(echo "$older_sessions" | jq 'length')
    if [[ $older_count -gt 0 ]]; then
        cat <<EOF
## Older Sessions ($older_count sessions)

Available on request. Topics include: authentication, TUI development, testing, performance optimization, and more.

EOF
    fi

    # Search hint
    cat <<EOF

---

💡 **Load full conversations by saying:**
  - "Show me the session from Feb 15"
  - "Load the authentication conversation"
  - "What did we discuss about TUI?"

EOF
}

# ============================================================================
# Current Project Context
# ============================================================================

format_current_project() {
    local working_dir="${1:-.}"

    cat <<EOF
# 📍 Current Project Context

**Working Directory:** $working_dir
**Project:** $(basename "$working_dir")

EOF

    # Get git info if available
    if [[ -d "$working_dir/.git" ]]; then
        local branch=$(git -C "$working_dir" branch --show-current 2>/dev/null || echo "unknown")
        local last_commit=$(git -C "$working_dir" log -1 --oneline 2>/dev/null || echo "none")

        cat <<EOF
**Git Branch:** $branch
**Last Commit:** $last_commit

EOF
    fi

    # Check for project context file
    if [[ -f "$working_dir/.claude/project-context.md" ]]; then
        echo "**Project Context:**"
        echo ""
        head -30 "$working_dir/.claude/project-context.md"
        echo ""
    fi
}

# ============================================================================
# Complete Context Assembly
# ============================================================================

format_complete_context() {
    local tier1_sessions="$1"
    local tier2_sessions="$2"
    local all_sessions="$3"
    local working_dir="${4:-.}"
    local current_task="${5:-general}"

    # Calculate token usage
    local tier1_content=$(format_tier1 "$tier1_sessions")
    local tier2_content=$(format_tier2 "$tier2_sessions")
    local tier3_content=$(format_tier3 "$all_sessions")
    local project_content=$(format_current_project "$working_dir")

    local tier1_tokens=$("$SCRIPT_DIR/token-budget-manager.sh" estimate "$tier1_content")
    local tier2_tokens=$("$SCRIPT_DIR/token-budget-manager.sh" estimate "$tier2_content")
    local tier3_tokens=$("$SCRIPT_DIR/token-budget-manager.sh" estimate "$tier3_content")
    local total_tokens=$((tier1_tokens + tier2_tokens + tier3_tokens))
    local estimated_cost=$("$SCRIPT_DIR/token-budget-manager.sh" calculate-cost "$total_tokens")

    # Header
    cat <<EOF
# 🧠 Your Complete Context

**Generated:** $(date "+%Y-%m-%d %H:%M:%S")
**Current Task:** $current_task
**Total Context:** ~${total_tokens} tokens (~\$${estimated_cost})

**Context Breakdown:**
- Tier 1 (Full): ~${tier1_tokens} tokens
- Tier 2 (Summaries): ~${tier2_tokens} tokens
- Tier 3 (Index): ~${tier3_tokens} tokens

---

EOF

    # Current project
    echo "$project_content"
    echo ""
    echo "---"
    echo ""

    # Tier 1
    echo "$tier1_content"
    echo "---"
    echo ""

    # Tier 2
    echo "$tier2_content"
    echo "---"
    echo ""

    # Tier 3
    echo "$tier3_content"
}

# ============================================================================
# Navigation Hints
# ============================================================================

add_navigation_hints() {
    cat <<EOF

---

# 🧭 Context Navigation

**You have access to:**
1. **Recent sessions (full detail)** - Complete conversation history from your last 1-2 sessions
2. **Related sessions (summaries)** - Condensed summaries of 10 relevant past sessions
3. **Full history (on-demand)** - All $total_sessions sessions searchable and loadable

**How to navigate:**
- Ask "Show me the session about X" to load full conversation
- Ask "What did we discuss about Y?" to search across all sessions
- Say "Load session Z" to get complete details from a specific session

**Context is automatically optimized:**
- Most relevant content loaded first
- Token budget managed (~60K tokens)
- Cost optimized (~\$0.15-0.30 per session)

EOF
}

# ============================================================================
# Main CLI
# ============================================================================

show_usage() {
    cat <<EOF
Context Formatter - Format context for Claude

Usage:
  $(basename "$0") tier1 <sessions_json>                  Format Tier 1 (full)
  $(basename "$0") tier2 <sessions_json>                  Format Tier 2 (summaries)
  $(basename "$0") tier3 <sessions_json>                  Format Tier 3 (index)
  $(basename "$0") complete <t1> <t2> <all> [wd] [task]   Format complete context
  $(basename "$0") conversation <session_id>              Load full conversation
  $(basename "$0") summary <session_id>                   Load summary
  $(basename "$0") project [working_dir]                  Format project context

Examples:
  # Format Tier 1
  $(basename "$0") tier1 '[{"session_id":"2026-02-18-session-1-abc"}]'

  # Format complete context
  $(basename "$0") complete "\$tier1" "\$tier2" "\$all" "." "implement auth"

  # Load conversation
  $(basename "$0") conversation 2026-02-18-session-1-abc
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        tier1)
            format_tier1 "${2:-[]}"
            ;;
        tier2)
            format_tier2 "${2:-[]}"
            ;;
        tier3)
            format_tier3 "${2:-[]}"
            ;;
        complete)
            format_complete_context "${2:-[]}" "${3:-[]}" "${4:-[]}" "${5:-.}" "${6:-general}"
            ;;
        conversation)
            load_full_conversation "${2:-}"
            ;;
        summary)
            load_session_summary "${2:-}"
            ;;
        project)
            format_current_project "${2:-.}"
            ;;
        navigation)
            add_navigation_hints
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
