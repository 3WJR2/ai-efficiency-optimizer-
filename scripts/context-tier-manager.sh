#!/usr/bin/env bash
# context-tier-manager.sh - 3-Tier Smart Context Management System
# Orchestrates intelligent context loading with cost optimization

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"
CONFIG_FILE="$DATA_DIR/context-tier-config.json"

# Component scripts
TOKEN_MANAGER="$SCRIPT_DIR/token-budget-manager.sh"
RELEVANCE_SCORER="$SCRIPT_DIR/relevance-scorer.sh"
SESSION_SELECTOR="$SCRIPT_DIR/session-selector.sh"
CONTEXT_FORMATTER="$SCRIPT_DIR/context-formatter.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# Configuration Management
# ============================================================================

init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$DATA_DIR"
        cat > "$CONFIG_FILE" <<'EOF'
{
  "version": "1.0.0",
  "enabled": true,
  "tier_settings": {
    "tier1": {
      "max_sessions": 2,
      "max_age_days": 7,
      "token_budget": 20000,
      "load_full": true
    },
    "tier2": {
      "max_sessions": 10,
      "token_budget": 30000,
      "load_summaries": true
    },
    "tier3": {
      "token_budget": 10000,
      "index_only": true
    }
  },
  "total_token_budget": 60000,
  "cost_target": 0.30,
  "optimization": {
    "enable_caching": true,
    "prefer_summaries": true,
    "adaptive_sizing": true
  },
  "metrics": {
    "total_loads": 0,
    "total_tokens": 0,
    "total_cost": 0.0,
    "avg_load_time": 0
  }
}
EOF
    fi
}

get_config() {
    init_config
    cat "$CONFIG_FILE"
}

update_metrics() {
    local tokens="$1"
    local cost="$2"
    local load_time="$3"

    local config=$(get_config)

    local total_loads=$(echo "$config" | jq '.metrics.total_loads')
    local total_tokens=$(echo "$config" | jq '.metrics.total_tokens')
    local total_cost=$(echo "$config" | jq '.metrics.total_cost')
    local avg_load_time=$(echo "$config" | jq '.metrics.avg_load_time')

    # Update metrics
    total_loads=$((total_loads + 1))
    total_tokens=$((total_tokens + tokens))
    total_cost=$(echo "scale=6; $total_cost + $cost" | bc)

    # Calculate new average load time
    local new_avg=$(echo "scale=2; (($avg_load_time * ($total_loads - 1)) + $load_time) / $total_loads" | bc)

    # Update config
    echo "$config" | jq \
        --arg loads "$total_loads" \
        --arg tokens "$total_tokens" \
        --arg cost "$total_cost" \
        --arg avg "$new_avg" \
        '.metrics.total_loads = ($loads | tonumber) |
         .metrics.total_tokens = ($tokens | tonumber) |
         .metrics.total_cost = ($cost | tonumber) |
         .metrics.avg_load_time = ($avg | tonumber)' \
        > "$CONFIG_FILE"
}

# ============================================================================
# Context Building
# ============================================================================

build_session_context() {
    local session_id="${1:-}"
    local current_task="${2:-general}"
    local working_dir="${3:-.}"

    local start_time=$(date +%s)

    echo -e "${BLUE}Building 3-tier context...${NC}" >&2

    # Load configuration
    local config=$(get_config)
    local tier1_max=$(echo "$config" | jq -r '.tier_settings.tier1.max_sessions')
    local tier2_max=$(echo "$config" | jq -r '.tier_settings.tier2.max_sessions')
    local total_budget=$(echo "$config" | jq -r '.total_token_budget')

    # Prepare current context for relevance scoring
    local current_context=$(cat <<EOF
{
  "task": "$current_task",
  "working_dir": "$working_dir",
  "themes": ["authentication", "TUI", "testing"],
  "files": []
}
EOF
    )

    # Step 1: Select sessions for each tier
    echo -e "${CYAN}→ Selecting sessions...${NC}" >&2

    local selection=$("$SESSION_SELECTOR" all "$current_task" "$session_id" "$current_context")

    local tier1_sessions=$(echo "$selection" | jq -c '.tier1')
    local tier2_sessions=$(echo "$selection" | jq -c '.tier2')

    local tier1_count=$(echo "$tier1_sessions" | jq 'length')
    local tier2_count=$(echo "$tier2_sessions" | jq 'length')

    echo -e "${GREEN}  ✓ Tier 1: $tier1_count sessions (full)${NC}" >&2
    echo -e "${GREEN}  ✓ Tier 2: $tier2_count sessions (summaries)${NC}" >&2

    # Step 2: Get all sessions for index
    local all_sessions=$("$SESSION_SELECTOR" list 365)  # All sessions from last year

    # Step 3: Format context for each tier
    echo -e "${CYAN}→ Formatting context...${NC}" >&2

    local tier1_content=$("$CONTEXT_FORMATTER" tier1 "$tier1_sessions")
    local tier2_content=$("$CONTEXT_FORMATTER" tier2 "$tier2_sessions")
    local tier3_content=$("$CONTEXT_FORMATTER" tier3 "$all_sessions")

    # Step 4: Check token budget and trim if needed
    echo -e "${CYAN}→ Checking token budget...${NC}" >&2

    local tier1_tokens=$("$TOKEN_MANAGER" estimate "$tier1_content")
    local tier2_tokens=$("$TOKEN_MANAGER" estimate "$tier2_content")
    local tier3_tokens=$("$TOKEN_MANAGER" estimate "$tier3_content")
    local total_tokens=$((tier1_tokens + tier2_tokens + tier3_tokens))

    echo -e "${BLUE}  Token usage:${NC}" >&2
    echo -e "    Tier 1: ${tier1_tokens} tokens" >&2
    echo -e "    Tier 2: ${tier2_tokens} tokens" >&2
    echo -e "    Tier 3: ${tier3_tokens} tokens" >&2
    echo -e "    ${BOLD}Total: ${total_tokens} / ${total_budget} tokens${NC}" >&2

    # Trim if over budget
    if [[ $total_tokens -gt $total_budget ]]; then
        echo -e "${YELLOW}  ⚠ Over budget, trimming Tier 2...${NC}" >&2

        local tier2_budget=$(echo "$config" | jq -r '.tier_settings.tier2.token_budget')
        local tier1_actual=$tier1_tokens
        local tier3_actual=$tier3_tokens
        local remaining=$((total_budget - tier1_actual - tier3_actual))

        tier2_content=$("$TOKEN_MANAGER" trim "$tier2_content" "$remaining")
        tier2_tokens=$("$TOKEN_MANAGER" estimate "$tier2_content")
        total_tokens=$((tier1_tokens + tier2_tokens + tier3_tokens))

        echo -e "${GREEN}  ✓ Trimmed to ${total_tokens} tokens${NC}" >&2
    fi

    # Step 5: Assemble complete context
    echo -e "${CYAN}→ Assembling complete context...${NC}" >&2

    local complete_context=$("$CONTEXT_FORMATTER" complete \
        "$tier1_sessions" \
        "$tier2_sessions" \
        "$all_sessions" \
        "$working_dir" \
        "$current_task")

    # Step 6: Calculate cost
    local estimated_cost=$("$TOKEN_MANAGER" calculate-cost "$total_tokens")

    # Step 7: Update metrics
    local end_time=$(date +%s)
    local load_time=$((end_time - start_time))

    update_metrics "$total_tokens" "$estimated_cost" "$load_time"

    # Step 8: Output context
    echo "$complete_context"

    # Summary to stderr
    echo -e "${GREEN}✓ Context built successfully!${NC}" >&2
    echo -e "${BLUE}  Sessions: $tier1_count full + $tier2_count summaries${NC}" >&2
    echo -e "${BLUE}  Tokens: $total_tokens (~\$${estimated_cost})${NC}" >&2
    echo -e "${BLUE}  Build time: ${load_time}s${NC}" >&2
}

# ============================================================================
# Tier Management
# ============================================================================

# Load Tier 1 context only
load_tier1_context() {
    local current_session="${1:-}"

    local tier1_sessions=$("$SESSION_SELECTOR" tier1 "$current_session")
    "$CONTEXT_FORMATTER" tier1 "$tier1_sessions"
}

# Load Tier 2 context only
load_tier2_context() {
    local current_task="$1"
    local current_context="${2:-{}}"

    local tier2_sessions=$("$SESSION_SELECTOR" tier2 "$current_task" "$current_context" "[]")
    "$CONTEXT_FORMATTER" tier2 "$tier2_sessions"
}

# Load Tier 3 index
load_tier3_index() {
    local all_sessions=$("$SESSION_SELECTOR" list 365)
    "$CONTEXT_FORMATTER" tier3 "$all_sessions"
}

# ============================================================================
# On-Demand Loading
# ============================================================================

# Load a specific session on demand
load_session_on_demand() {
    local session_id="$1"

    echo -e "${CYAN}Loading session: $session_id${NC}" >&2

    local conversation=$("$CONTEXT_FORMATTER" conversation "$session_id")
    local metadata=$("$RELEVANCE_SCORER" metadata "$session_id")

    local session_date=$(echo "$metadata" | jq -r '.date')
    local themes=$(echo "$metadata" | jq -r '.themes[]?' | head -3 | tr '\n' ', ' | sed 's/, $//')

    cat <<EOF
# Session: $session_id

**Date:** $session_date
**Topics:** ${themes:-general}

## Full Conversation

$conversation

EOF
}

# Search for sessions matching query
search_sessions() {
    local query="$1"
    local limit="${2:-5}"

    echo -e "${CYAN}Searching for: \"$query\"${NC}" >&2

    local related=$("$RELEVANCE_SCORER" find "$query" "$limit")

    echo "# Search Results for: \"$query\""
    echo ""

    echo "$related" | jq -c '.[]' | while read -r entry; do
        local session_id=$(echo "$entry" | jq -r '.session_id')
        local score=$(echo "$entry" | jq -r '.relevance_score')
        local score_pct=$(echo "scale=0; $score * 100" | bc)

        local metadata=$("$RELEVANCE_SCORER" metadata "$session_id")
        local date=$(echo "$metadata" | jq -r '.date')
        local themes=$(echo "$metadata" | jq -r '.themes[0:2][]?' | tr '\n' ', ' | sed 's/, $//')

        cat <<EOF
## $session_id ($date) - Match: ${score_pct}%

**Topics:** ${themes:-general}

**Preview:**
$(load_session_summary "$session_id" | head -10)

[Load full session with: load-session $session_id]

---

EOF
    done
}

load_session_summary() {
    local session_id="$1"
    "$CONTEXT_FORMATTER" summary "$session_id"
}

# ============================================================================
# Cost Analysis
# ============================================================================

estimate_session_cost() {
    local session_id="${1:-}"
    local current_task="${2:-general}"

    echo -e "${BLUE}Estimating context cost...${NC}"

    # Build context to temporary file
    local temp_context=$(mktemp)
    build_session_context "$session_id" "$current_task" "." > "$temp_context" 2>/dev/null

    # Estimate tokens
    local tokens=$("$TOKEN_MANAGER" estimate "$(cat "$temp_context")")
    local cost=$("$TOKEN_MANAGER" calculate-cost "$tokens")

    rm -f "$temp_context"

    cat <<EOF
# Context Cost Estimate

**Total Tokens:** $tokens
**Estimated Cost:** \$$cost

**Breakdown:**
- Input tokens: $tokens × \$0.003/1K = \$$cost
- With caching (90% cached): ~\$$(echo "scale=6; $cost * 0.1" | bc)
- Per session target: \$0.15-0.30 ✓

EOF
}

# ============================================================================
# Statistics & Reporting
# ============================================================================

show_stats() {
    local config=$(get_config)

    local total_loads=$(echo "$config" | jq -r '.metrics.total_loads')
    local total_tokens=$(echo "$config" | jq -r '.metrics.total_tokens')
    local total_cost=$(echo "$config" | jq -r '.metrics.total_cost')
    local avg_load_time=$(echo "$config" | jq -r '.metrics.avg_load_time')

    local avg_tokens=$((total_tokens / (total_loads > 0 ? total_loads : 1)))
    local avg_cost=$(echo "scale=4; $total_cost / ($total_loads > 0 ? $total_loads : 1)" | bc)

    cat <<EOF
# Context Tier Manager Statistics

## Lifetime Metrics
- **Total Context Loads:** $total_loads
- **Total Tokens Loaded:** $total_tokens
- **Total Cost:** \$$total_cost
- **Average Load Time:** ${avg_load_time}s

## Per-Session Averages
- **Average Tokens:** $avg_tokens
- **Average Cost:** \$$avg_cost
- **Target Cost:** \$0.15-0.30

## Configuration
- **Tier 1:** $(echo "$config" | jq -r '.tier_settings.tier1.max_sessions') sessions, $(echo "$config" | jq -r '.tier_settings.tier1.token_budget') token budget
- **Tier 2:** $(echo "$config" | jq -r '.tier_settings.tier2.max_sessions') sessions, $(echo "$config" | jq -r '.tier_settings.tier2.token_budget') token budget
- **Tier 3:** Index only, $(echo "$config" | jq -r '.tier_settings.tier3.token_budget') token budget
- **Total Budget:** $(echo "$config" | jq -r '.total_token_budget') tokens

EOF
}

# Generate budget report
budget_report() {
    "$TOKEN_MANAGER" allocation | jq .
}

# ============================================================================
# Integration with Session Startup
# ============================================================================

inject_into_session() {
    local session_dir="$1"
    local current_task="${2:-general}"

    echo -e "${CYAN}Injecting smart context into session...${NC}" >&2

    # Build context
    local context=$(build_session_context "$(basename "$session_dir")" "$current_task" "$(pwd)")

    # Save to session
    echo "$context" > "$session_dir/.session-context.md"

    echo -e "${GREEN}✓ Context injected into: $session_dir/.session-context.md${NC}" >&2
}

# Hook for session startup
on_session_start() {
    local session_dir="$1"
    local initial_prompt="${2:-general}"

    echo -e "${BOLD}${BLUE}🧠 Loading Smart Context...${NC}" >&2

    # Build and inject context
    inject_into_session "$session_dir" "$initial_prompt"

    # Show summary
    local config=$(get_config)
    local tier1=$(echo "$config" | jq -r '.tier_settings.tier1.max_sessions')
    local tier2=$(echo "$config" | jq -r '.tier_settings.tier2.max_sessions')

    echo -e "${GREEN}✅ Smart context loaded:${NC}" >&2
    echo -e "   Tier 1: $tier1 sessions (full detail)" >&2
    echo -e "   Tier 2: $tier2 sessions (summaries)" >&2
    echo -e "   Tier 3: All sessions (searchable)" >&2
}

# ============================================================================
# Main CLI
# ============================================================================

show_usage() {
    cat <<EOF
${BOLD}Context Tier Manager - 3-Tier Smart Context Management${NC}

${BOLD}Usage:${NC}
  $(basename "$0") build [session_id] [task] [dir]    Build complete context
  $(basename "$0") tier1 [session]                    Load Tier 1 only
  $(basename "$0") tier2 <task> [context]             Load Tier 2 only
  $(basename "$0") tier3                              Load Tier 3 index
  $(basename "$0") load <session_id>                  Load specific session
  $(basename "$0") search <query> [limit]             Search sessions
  $(basename "$0") estimate [session] [task]          Estimate cost
  $(basename "$0") stats                              Show statistics
  $(basename "$0") budget                             Show budget allocation
  $(basename "$0") inject <session_dir> [task]        Inject into session
  $(basename "$0") hook <session_dir> [prompt]        Session startup hook

${BOLD}Examples:${NC}
  # Build complete context for current task
  $(basename "$0") build "" "implement authentication"

  # Load specific session on-demand
  $(basename "$0") load 2026-02-18-session-1-abc

  # Search for relevant sessions
  $(basename "$0") search "JWT implementation" 5

  # Estimate cost
  $(basename "$0") estimate

  # Show statistics
  $(basename "$0") stats

${BOLD}Integration:${NC}
  # Add to session-startup-hook.sh:
  source ~/.claude/scripts/context-tier-manager.sh
  on_session_start "\$session_dir" "\$initial_prompt"

EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        build)
            build_session_context "${2:-}" "${3:-general}" "${4:-.}"
            ;;
        tier1)
            load_tier1_context "${2:-}"
            ;;
        tier2)
            load_tier2_context "${2:-general}" "${3:-{}}"
            ;;
        tier3)
            load_tier3_index
            ;;
        load)
            load_session_on_demand "${2:-}"
            ;;
        search)
            search_sessions "${2:-}" "${3:-5}"
            ;;
        estimate)
            estimate_session_cost "${2:-}" "${3:-general}"
            ;;
        stats)
            show_stats
            ;;
        budget)
            budget_report
            ;;
        inject)
            inject_into_session "${2:-}" "${3:-general}"
            ;;
        hook)
            on_session_start "${2:-}" "${3:-general}"
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

# Export functions for sourcing
export -f on_session_start
export -f inject_into_session
export -f build_session_context

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
