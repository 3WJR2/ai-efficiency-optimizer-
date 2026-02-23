#!/usr/bin/env bash
# insights-generator.sh - Generate insights from conversation patterns
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

# Analyze interaction patterns
analyze_patterns() {
    local log_file="$1"

    local total_messages=$(jq -s 'length' "$log_file")
    local user_messages=$(jq -s '[.[] | select(.role == "user")] | length' "$log_file")
    local assistant_messages=$(jq -s '[.[] | select(.role == "assistant")] | length' "$log_file")

    # Calculate average response time (simulated, would need actual timestamps)
    local exchanges=$((user_messages < assistant_messages ? user_messages : assistant_messages))

    # Analyze message lengths
    local total_user_length=$(jq -s '[.[] | select(.role == "user") | .content_length] | add // 0' "$log_file")
    local total_assistant_length=$(jq -s '[.[] | select(.role == "assistant") | .content_length] | add // 0' "$log_file")

    local avg_user_length=0
    local avg_assistant_length=0

    [[ $user_messages -gt 0 ]] && avg_user_length=$((total_user_length / user_messages))
    [[ $assistant_messages -gt 0 ]] && avg_assistant_length=$((total_assistant_length / assistant_messages))

    # Determine conversation style
    local style="balanced"
    if [[ $avg_user_length -lt 100 ]]; then
        style="concise"
    elif [[ $avg_user_length -gt 500 ]]; then
        style="detailed"
    fi

    # Determine interaction type
    local interaction_type="exploratory"
    local code_blocks=$(jq -s '[.[] | .content | select(contains("```"))] | length' "$log_file")
    local error_mentions=$(jq -s '[.[] | .content | select(test("error|exception|failed"; "i"))] | length' "$log_file")

    if [[ $code_blocks -gt 10 ]]; then
        interaction_type="code-focused"
    elif [[ $error_mentions -gt 5 ]]; then
        interaction_type="troubleshooting"
    fi

    # Output patterns as JSON
    cat <<EOF
{
  "total_messages": $total_messages,
  "exchanges": $exchanges,
  "user_messages": $user_messages,
  "assistant_messages": $assistant_messages,
  "avg_user_length": $avg_user_length,
  "avg_assistant_length": $avg_assistant_length,
  "conversation_style": "$style",
  "interaction_type": "$interaction_type",
  "code_blocks": $code_blocks,
  "error_mentions": $error_mentions
}
EOF
}

# Identify successful interactions
identify_successes() {
    local log_file="$1"
    local successes=()

    # Look for positive indicators
    local prev_content=""
    local prev_role=""

    jq -s '.[]' "$log_file" | jq -c '.' | while IFS= read -r line; do
        local role=$(echo "$line" | jq -r '.role')
        local content=$(echo "$line" | jq -r '.content')

        # If user says "thanks", "works", "perfect", etc., previous assistant message was successful
        if [[ "$role" == "user" ]] && [[ "$prev_role" == "assistant" ]]; then
            if echo "$content" | grep -qi 'thanks\|thank you\|works\|perfect\|great\|excellent\|solved'; then
                local summary=$(echo "$prev_content" | head -c 100 | tr '\n' ' ')
                echo "$summary..."
            fi
        fi

        prev_role="$role"
        prev_content="$content"
    done | head -5
}

# Identify failed interactions
identify_failures() {
    local log_file="$1"
    local failures=()

    # Look for negative indicators or error patterns
    local prev_content=""
    local prev_role=""

    jq -s '.[]' "$log_file" | jq -c '.' | while IFS= read -r line; do
        local role=$(echo "$line" | jq -r '.role')
        local content=$(echo "$line" | jq -r '.content')

        # If user reports error or says "doesn't work" after assistant message
        if [[ "$role" == "user" ]] && [[ "$prev_role" == "assistant" ]]; then
            if echo "$content" | grep -qi 'error\|doesn'\''t work\|didn'\''t work\|still failing\|not working'; then
                local summary=$(echo "$content" | head -c 100 | tr '\n' ' ')
                echo "$summary..."
            fi
        fi

        prev_role="$role"
        prev_content="$content"
    done | head -5
}

# Extract learnings
extract_learnings() {
    local log_file="$1"
    local learnings=()

    # Look for learning moments (questions followed by explanations)
    local in_learning_sequence=0
    local learning_topic=""

    jq -s '.[]' "$log_file" | jq -c '.' | while IFS= read -r line; do
        local role=$(echo "$line" | jq -r '.role')
        local content=$(echo "$line" | jq -r '.content')

        # User asks "how", "why", "what", "explain"
        if [[ "$role" == "user" ]]; then
            if echo "$content" | grep -qi 'how\|why\|what\|explain\|understand'; then
                in_learning_sequence=1
                learning_topic=$(echo "$content" | head -c 80 | tr '\n' ' ')
            fi
        fi

        # Assistant provides explanation
        if [[ "$role" == "assistant" ]] && [[ $in_learning_sequence -eq 1 ]]; then
            echo "Q: $learning_topic... A: $(echo "$content" | head -c 80 | tr '\n' ' ')..."
            in_learning_sequence=0
        fi
    done | head -5
}

# Generate recommendations
generate_recommendations() {
    local patterns="$1"
    local recommendations=()

    local style=$(echo "$patterns" | jq -r '.conversation_style')
    local interaction_type=$(echo "$patterns" | jq -r '.interaction_type')
    local exchanges=$(echo "$patterns" | jq -r '.exchanges')
    local code_blocks=$(echo "$patterns" | jq -r '.code_blocks')

    # Style-based recommendations
    if [[ "$style" == "concise" ]]; then
        recommendations+=("User prefers brief, to-the-point responses")
        recommendations+=("Minimize explanatory text, focus on actionable items")
    elif [[ "$style" == "detailed" ]]; then
        recommendations+=("User appreciates comprehensive explanations")
        recommendations+=("Provide context and rationale for suggestions")
    fi

    # Interaction type recommendations
    if [[ "$interaction_type" == "code-focused" ]]; then
        recommendations+=("Code examples are highly valued")
        recommendations+=("Include working code snippets in responses")
    elif [[ "$interaction_type" == "troubleshooting" ]]; then
        recommendations+=("Focus on debugging and error resolution")
        recommendations+=("Provide systematic troubleshooting steps")
    fi

    # Engagement recommendations
    if [[ $exchanges -lt 5 ]]; then
        recommendations+=("Session is brief - consider if more exploration needed")
    elif [[ $exchanges -gt 20 ]]; then
        recommendations+=("Deep conversation - maintain context continuity")
    fi

    # Code-specific recommendations
    if [[ $code_blocks -gt 10 ]]; then
        recommendations+=("High code interaction - ensure code quality and testing")
    fi

    printf '%s\n' "${recommendations[@]}"
}

# Calculate quality score
calculate_quality_score() {
    local patterns="$1"
    local successes_count="${2:-0}"
    local failures_count="${3:-0}"

    local exchanges=$(echo "$patterns" | jq -r '.exchanges')
    local total_messages=$(echo "$patterns" | jq -r '.total_messages')

    # Base score
    local score=50

    # Positive factors
    [[ $exchanges -gt 5 ]] && score=$((score + 10))
    [[ $exchanges -gt 10 ]] && score=$((score + 10))
    [[ $successes_count -gt 0 ]] && score=$((score + successes_count * 5))

    # Negative factors
    [[ $failures_count -gt 0 ]] && score=$((score - failures_count * 5))

    # Engagement bonus
    local engagement_ratio=$(echo "scale=2; $exchanges / ($total_messages / 2.0)" | bc)
    if (( $(echo "$engagement_ratio > 0.8" | bc -l) )); then
        score=$((score + 10))
    fi

    # Cap at 100
    [[ $score -gt 100 ]] && score=100
    [[ $score -lt 0 ]] && score=0

    echo $score
}

# Generate insights
generate_insights() {
    local session_dir="$1"
    local log_file="$session_dir/conversation-log.jsonl"
    local insights_file="$session_dir/insights.md"
    local metadata_file="$session_dir/.session-metadata.json"

    if [[ ! -f "$log_file" ]]; then
        log_error "Conversation log not found: $log_file"
        return 1
    fi

    # Check if we have enough data
    local message_count=$(wc -l < "$log_file")
    if [[ $message_count -lt 5 ]]; then
        log_warn "Insufficient data for insights generation (need at least 5 messages)"
        return 0
    fi

    log_info "Generating insights for session: $(basename "$session_dir")"

    # Extract session information
    local session_id=$(basename "$session_dir")
    local created_at="Unknown"

    if [[ -f "$metadata_file" ]]; then
        created_at=$(jq -r '.created_at' "$metadata_file")
    fi

    # Analyze patterns
    log_debug "Analyzing patterns..."
    local patterns=$(analyze_patterns "$log_file")

    log_debug "Identifying successes..."
    local successes=$(identify_successes "$log_file")
    local successes_count=$(echo "$successes" | grep -c '.' || echo "0")

    log_debug "Identifying failures..."
    local failures=$(identify_failures "$log_file")
    local failures_count=$(echo "$failures" | grep -c '.' || echo "0")

    log_debug "Extracting learnings..."
    local learnings=$(extract_learnings "$log_file")

    log_debug "Generating recommendations..."
    local recommendations=$(generate_recommendations "$patterns")

    log_debug "Calculating quality score..."
    local quality_score=$(calculate_quality_score "$patterns" "$successes_count" "$failures_count")

    # Extract pattern details
    local total_messages=$(echo "$patterns" | jq -r '.total_messages')
    local exchanges=$(echo "$patterns" | jq -r '.exchanges')
    local style=$(echo "$patterns" | jq -r '.conversation_style')
    local interaction_type=$(echo "$patterns" | jq -r '.interaction_type')
    local code_blocks=$(echo "$patterns" | jq -r '.code_blocks')
    local error_mentions=$(echo "$patterns" | jq -r '.error_mentions')

    # Generate insights file
    cat > "$insights_file" <<EOF
# Session Insights: $session_id

**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Session Created:** $created_at
**Messages Analyzed:** $message_count

## Overview

This session consists of **$exchanges exchanges** with a **$style** communication style.
The interaction type is primarily **$interaction_type**.

### Quality Score: $quality_score/100

$(if [[ $quality_score -ge 80 ]]; then
    echo "High-quality interaction with strong engagement and successful outcomes."
elif [[ $quality_score -ge 60 ]]; then
    echo "Good interaction with room for improvement in some areas."
else
    echo "Average interaction - consider reviewing patterns for optimization."
fi)

## Patterns Detected

- **Total Messages:** $total_messages
- **Exchanges:** $exchanges
- **Communication Style:** $style
- **Interaction Type:** $interaction_type
- **Code Blocks:** $code_blocks
- **Error Mentions:** $error_mentions

### Communication Characteristics

EOF

    if [[ "$style" == "concise" ]]; then
        cat >> "$insights_file" <<EOF
- User prefers brief, direct responses
- Average user message length: Short
- Recommendation: Keep responses focused and actionable
EOF
    elif [[ "$style" == "detailed" ]]; then
        cat >> "$insights_file" <<EOF
- User provides comprehensive context
- Average user message length: Long
- Recommendation: Match detail level in responses
EOF
    else
        cat >> "$insights_file" <<EOF
- User employs balanced communication
- Average user message length: Moderate
- Recommendation: Adapt response length to query complexity
EOF
    fi

    cat >> "$insights_file" <<EOF

### Interaction Focus

EOF

    if [[ "$interaction_type" == "code-focused" ]]; then
        cat >> "$insights_file" <<EOF
- Heavy emphasis on code and implementation
- $code_blocks code blocks shared
- Recommendation: Prioritize working code examples
EOF
    elif [[ "$interaction_type" == "troubleshooting" ]]; then
        cat >> "$insights_file" <<EOF
- Primary focus on problem-solving and debugging
- $error_mentions error-related mentions
- Recommendation: Provide systematic debugging approaches
EOF
    else
        cat >> "$insights_file" <<EOF
- Exploratory conversation with varied topics
- Balanced mix of questions and implementation
- Recommendation: Maintain flexibility in approach
EOF
    fi

    cat >> "$insights_file" <<EOF

## Successful Interactions

EOF

    if [[ $successes_count -gt 0 ]]; then
        echo "$successes" | while IFS= read -r success; do
            echo "- $success" >> "$insights_file"
        done
    else
        echo "- (No explicit success indicators detected)" >> "$insights_file"
    fi

    cat >> "$insights_file" <<EOF

## Failed Interactions

EOF

    if [[ $failures_count -gt 0 ]]; then
        echo "$failures" | while IFS= read -r failure; do
            echo "- $failure" >> "$insights_file"
        done
        echo "" >> "$insights_file"
        echo "**Note:** Review these interactions to improve future responses." >> "$insights_file"
    else
        echo "- (No explicit failure indicators detected)" >> "$insights_file"
    fi

    cat >> "$insights_file" <<EOF

## Learning Moments

EOF

    if [[ -n "$learnings" ]]; then
        echo "$learnings" | while IFS= read -r learning; do
            echo "- $learning" >> "$insights_file"
        done
    else
        echo "- (No explicit learning sequences identified)" >> "$insights_file"
    fi

    cat >> "$insights_file" <<EOF

## Recommendations

EOF

    echo "$recommendations" | while IFS= read -r rec; do
        echo "- $rec" >> "$insights_file"
    done

    cat >> "$insights_file" <<EOF

## Action Items for Next Session

1. **Context Continuity:** Review this session's context before starting
2. **Communication Style:** Adapt to user's $style preference
3. **Focus Area:** Maintain focus on $interaction_type patterns
4. **Quality:** Target improvement in areas with lower scores

---

*This file is automatically updated by the insights generator.*
*Last updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")*
*Analysis based on $message_count messages*
EOF

    log_info "Insights generated successfully: $insights_file"
    log_info "Quality Score: $quality_score/100"
}

# Show insights
show_insights() {
    local session_dir="$1"
    local insights_file="$session_dir/insights.md"

    if [[ ! -f "$insights_file" ]]; then
        log_error "Insights file not found: $insights_file"
        return 1
    fi

    cat "$insights_file"
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
            generate_insights "$1"
            ;;

        show|cat)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 show <session_dir>"
                exit 1
            fi
            show_insights "$1"
            ;;

        help|--help|-h)
            cat <<EOF
Insights Generator - Generate insights from conversation patterns

USAGE:
    $0 <command> [options]

COMMANDS:
    generate|gen <session_dir>
        Generate insights file from conversation log

    show|cat <session_dir>
        Display current insights file

    help
        Show this help message

EXAMPLES:
    # Generate insights
    $0 generate ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1

    # Show current insights
    $0 show ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1

ENVIRONMENT:
    SESSIONS_BASE_DIR    Base directory for sessions (default: ~/Desktop/multi-claude-sessions/sessions)
    DEBUG                Enable debug output (set to 1)

NOTES:
    - Minimum 5 messages required for insights generation
    - Analyzes conversation patterns, successful/failed interactions
    - Provides quality score and recommendations
    - Identifies learning moments and action items

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
