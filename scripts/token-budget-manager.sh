#!/usr/bin/env bash
# token-budget-manager.sh - Manage token budgets for context loading
# Part of 3-Tier Smart Context Management System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"

# Token budgets
TIER1_BUDGET=20000   # Recent sessions (full)
TIER2_BUDGET=30000   # Related summaries
TIER3_BUDGET=10000   # Index
TOTAL_BUDGET=60000   # ~$0.18 at Claude Sonnet rates

# API costs (per 1K tokens)
INPUT_COST=0.003      # $0.003 per 1K input tokens
OUTPUT_COST=0.015     # $0.015 per 1K output tokens
CACHED_COST=0.0003    # $0.0003 per 1K cached tokens (90% savings)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Token Estimation
# ============================================================================

# Estimate tokens from text (rough approximation: 1 token ≈ 4 characters)
estimate_tokens() {
    local text="$1"
    local char_count=${#text}
    local token_estimate=$((char_count / 4))
    echo "$token_estimate"
}

# Estimate tokens from file
estimate_tokens_file() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo "0"
        return 1
    fi

    local char_count=$(wc -m < "$file_path" | tr -d ' ')
    local token_estimate=$((char_count / 4))
    echo "$token_estimate"
}

# More accurate token estimation (words * 1.3)
estimate_tokens_accurate() {
    local text="$1"

    # Count words and multiply by 1.3 (average tokens per word)
    local word_count=$(echo "$text" | wc -w | tr -d ' ')
    local token_estimate=$(echo "$word_count * 1.3" | bc | cut -d'.' -f1)

    echo "$token_estimate"
}

# ============================================================================
# Cost Calculation
# ============================================================================

# Calculate cost from token count
calculate_cost() {
    local tokens="$1"
    local rate="${2:-$INPUT_COST}"  # Default to input cost

    # Convert tokens to thousands and multiply by rate
    local cost=$(echo "scale=6; $tokens / 1000 * $rate" | bc)
    echo "$cost"
}

# Calculate total session cost
calculate_session_cost() {
    local input_tokens="$1"
    local output_tokens="${2:-0}"
    local cached_tokens="${3:-0}"

    local input_cost=$(calculate_cost "$input_tokens" "$INPUT_COST")
    local output_cost=$(calculate_cost "$output_tokens" "$OUTPUT_COST")
    local cached_cost=$(calculate_cost "$cached_tokens" "$CACHED_COST")

    local total=$(echo "scale=6; $input_cost + $output_cost + $cached_cost" | bc)
    echo "$total"
}

# Calculate cost savings with caching
calculate_savings() {
    local total_input="$1"
    local cached_portion="$2"

    local uncached_tokens=$((total_input - cached_portion))

    # Cost without cache
    local cost_no_cache=$(calculate_cost "$total_input" "$INPUT_COST")

    # Cost with cache
    local uncached_cost=$(calculate_cost "$uncached_tokens" "$INPUT_COST")
    local cached_cost=$(calculate_cost "$cached_portion" "$CACHED_COST")
    local cost_with_cache=$(echo "scale=6; $uncached_cost + $cached_cost" | bc)

    # Savings
    local savings=$(echo "scale=6; $cost_no_cache - $cost_with_cache" | bc)
    local savings_pct=$(echo "scale=2; ($savings / $cost_no_cache) * 100" | bc)

    cat <<EOF
{
  "without_cache": "$cost_no_cache",
  "with_cache": "$cost_with_cache",
  "savings": "$savings",
  "savings_percent": "$savings_pct"
}
EOF
}

# ============================================================================
# Budget Management
# ============================================================================

# Check if content fits in budget
check_budget() {
    local tokens="$1"
    local budget="$2"

    if [[ $tokens -le $budget ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Calculate remaining budget
remaining_budget() {
    local used="$1"
    local total="$2"

    local remaining=$((total - used))
    echo "$remaining"
}

# Get budget allocation for all tiers
get_budget_allocation() {
    cat <<EOF
{
  "tier1": {
    "name": "Recent Sessions (Full)",
    "budget": $TIER1_BUDGET,
    "priority": 1
  },
  "tier2": {
    "name": "Related Summaries",
    "budget": $TIER2_BUDGET,
    "priority": 2
  },
  "tier3": {
    "name": "Session Index",
    "budget": $TIER3_BUDGET,
    "priority": 3
  },
  "total": {
    "budget": $TOTAL_BUDGET,
    "estimated_cost": "$(calculate_cost $TOTAL_BUDGET $INPUT_COST)"
  }
}
EOF
}

# ============================================================================
# Content Trimming
# ============================================================================

# Trim text to fit within token budget
trim_to_budget() {
    local text="$1"
    local max_tokens="$2"

    local current_tokens=$(estimate_tokens "$text")

    if [[ $current_tokens -le $max_tokens ]]; then
        echo "$text"
        return 0
    fi

    # Calculate what percentage to keep
    local keep_ratio=$(echo "scale=4; $max_tokens / $current_tokens" | bc)
    local keep_chars=$(echo "${#text} * $keep_ratio" | bc | cut -d'.' -f1)

    # Trim and add indicator
    local trimmed="${text:0:$keep_chars}"
    echo "${trimmed}

[... Content trimmed to fit token budget ...]"
}

# Trim file to fit within token budget
trim_file_to_budget() {
    local file_path="$1"
    local max_tokens="$2"
    local output_file="${3:-}"

    if [[ ! -f "$file_path" ]]; then
        return 1
    fi

    local content=$(cat "$file_path")
    local trimmed=$(trim_to_budget "$content" "$max_tokens")

    if [[ -n "$output_file" ]]; then
        echo "$trimmed" > "$output_file"
    else
        echo "$trimmed"
    fi
}

# Intelligently prioritize and trim sections
prioritize_content() {
    local -n sections=$1
    local max_tokens="$2"

    # Sort sections by priority (lower number = higher priority)
    local sorted_sections=()
    while IFS= read -r section; do
        sorted_sections+=("$section")
    done < <(printf '%s\n' "${sections[@]}" | sort -t: -k2 -n)

    local total_tokens=0
    local kept_sections=()

    for section in "${sorted_sections[@]}"; do
        local section_name="${section%%:*}"
        local section_priority="${section#*:}"
        local section_tokens=$(estimate_tokens "$section_name")

        if [[ $((total_tokens + section_tokens)) -le $max_tokens ]]; then
            kept_sections+=("$section_name")
            total_tokens=$((total_tokens + section_tokens))
        else
            # Check if we can fit a trimmed version
            local remaining=$((max_tokens - total_tokens))
            if [[ $remaining -gt 500 ]]; then
                local trimmed=$(trim_to_budget "$section_name" "$remaining")
                kept_sections+=("$trimmed")
                total_tokens=$max_tokens
            fi
            break
        fi
    done

    printf '%s\n' "${kept_sections[@]}"
}

# ============================================================================
# Statistics & Reporting
# ============================================================================

# Generate budget report
budget_report() {
    local tier1_used="${1:-0}"
    local tier2_used="${2:-0}"
    local tier3_used="${3:-0}"

    local total_used=$((tier1_used + tier2_used + tier3_used))
    local total_cost=$(calculate_cost "$total_used" "$INPUT_COST")

    local tier1_pct=$(echo "scale=2; ($tier1_used / $TIER1_BUDGET) * 100" | bc)
    local tier2_pct=$(echo "scale=2; ($tier2_used / $TIER2_BUDGET) * 100" | bc)
    local tier3_pct=$(echo "scale=2; ($tier3_used / $TIER3_BUDGET) * 100" | bc)
    local total_pct=$(echo "scale=2; ($total_used / $TOTAL_BUDGET) * 100" | bc)

    cat <<EOF
# Token Budget Report

## Tier 1: Recent Sessions (Full)
  Used: ${tier1_used} / ${TIER1_BUDGET} tokens (${tier1_pct}%)
  Status: $([ $tier1_used -le $TIER1_BUDGET ] && echo "✓ Within budget" || echo "⚠ Over budget")

## Tier 2: Related Summaries
  Used: ${tier2_used} / ${TIER2_BUDGET} tokens (${tier2_pct}%)
  Status: $([ $tier2_used -le $TIER2_BUDGET ] && echo "✓ Within budget" || echo "⚠ Over budget")

## Tier 3: Session Index
  Used: ${tier3_used} / ${TIER3_BUDGET} tokens (${tier3_pct}%)
  Status: $([ $tier3_used -le $TIER3_BUDGET ] && echo "✓ Within budget" || echo "⚠ Over budget")

## Total
  Used: ${total_used} / ${TOTAL_BUDGET} tokens (${total_pct}%)
  Estimated Cost: \$${total_cost}
  Status: $([ $total_used -le $TOTAL_BUDGET ] && echo "✓ Within budget" || echo "⚠ Over budget")
EOF
}

# Format cost for display
format_cost() {
    local cost="$1"
    printf "\$%.4f" "$cost"
}

# ============================================================================
# Main CLI
# ============================================================================

show_usage() {
    cat <<EOF
Token Budget Manager - Manage context token budgets

Usage:
  $(basename "$0") estimate <text|file>        Estimate tokens
  $(basename "$0") calculate-cost <tokens>     Calculate cost
  $(basename "$0") session-cost <in> [out] [cached]  Calculate session cost
  $(basename "$0") check-budget <tokens> <budget>    Check if fits in budget
  $(basename "$0") trim <text> <max_tokens>          Trim to budget
  $(basename "$0") allocation                        Show budget allocation
  $(basename "$0") report <t1> <t2> <t3>            Generate budget report
  $(basename "$0") savings <total> <cached>          Calculate cache savings

Examples:
  # Estimate tokens in text
  $(basename "$0") estimate "Hello world"

  # Estimate tokens in file
  $(basename "$0") estimate /path/to/file.txt

  # Calculate cost
  $(basename "$0") calculate-cost 50000

  # Session cost
  $(basename "$0") session-cost 45000 5000 20000

  # Check budget
  $(basename "$0") check-budget 25000 30000

  # Show allocation
  $(basename "$0") allocation

  # Generate report
  $(basename "$0") report 18500 28000 9500
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        estimate)
            if [[ -f "${2:-}" ]]; then
                estimate_tokens_file "$2"
            else
                estimate_tokens "${2:-}"
            fi
            ;;
        calculate-cost)
            calculate_cost "${2:-0}"
            ;;
        session-cost)
            calculate_session_cost "${2:-0}" "${3:-0}" "${4:-0}"
            ;;
        check-budget)
            check_budget "${2:-0}" "${3:-$TOTAL_BUDGET}"
            ;;
        trim)
            trim_to_budget "${2:-}" "${3:-$TOTAL_BUDGET}"
            ;;
        allocation)
            get_budget_allocation | jq .
            ;;
        report)
            budget_report "${2:-0}" "${3:-0}" "${4:-0}"
            ;;
        savings)
            calculate_savings "${2:-0}" "${3:-0}" | jq .
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
