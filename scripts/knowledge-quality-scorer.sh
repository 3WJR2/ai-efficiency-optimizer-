#!/usr/bin/env bash

# knowledge-quality-scorer.sh
# Score knowledge quality and update confidence ratings
# Part of Cross-Session Knowledge Extraction System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-${HOME}/.claude/knowledge}"

# Scoring weights
WEIGHT_SUCCESS=0.40
WEIGHT_COMPLETENESS=0.20
WEIGHT_REUSABILITY=0.20
WEIGHT_RECENCY=0.10
WEIGHT_VALIDATION=0.10

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# ============================================================================
# Scoring Components
# ============================================================================

# Score success indicators (40%)
score_success_indicators() {
    local indicators="$1"

    local count=$(echo "$indicators" | jq 'length')
    local max_score=1.0

    # Points per indicator
    local has_user_confirmed=$(echo "$indicators" | jq 'contains(["user_confirmed"]) | if . then 0.30 else 0 end')
    local has_no_errors=$(echo "$indicators" | jq 'contains(["no_errors_after"]) | if . then 0.25 else 0 end')
    local has_tests_passed=$(echo "$indicators" | jq 'contains(["tests_passed"]) | if . then 0.25 else 0 end')
    local has_positive=$(echo "$indicators" | jq 'contains(["positive_feedback"]) | if . then 0.20 else 0 end')

    # Calculate total
    echo "scale=4; $has_user_confirmed + $has_no_errors + $has_tests_passed + $has_positive" | bc
}

# Score completeness (20%)
score_completeness() {
    local entry="$1"

    local has_problem=$(echo "$entry" | jq 'if .problem != "" then 0.25 else 0 end')
    local has_solution=$(echo "$entry" | jq 'if .solution != "" then 0.30 else 0 end')
    local has_code=$(echo "$entry" | jq 'if .code_snippet != "" then 0.25 else 0 end')
    local has_context=$(echo "$entry" | jq 'if .context != "" then 0.20 else 0 end')

    echo "scale=4; $has_problem + $has_solution + $has_code + $has_context" | bc
}

# Score reusability (20%)
score_reusability() {
    local reusability="$1"
    local knowledge_type="$2"

    case "$reusability" in
        generalizable)
            echo "1.0"
            ;;
        pattern)
            echo "0.9"
            ;;
        specific)
            # Specific solutions still valuable
            if [[ "$knowledge_type" == "solution" ]]; then
                echo "0.6"
            else
                echo "0.5"
            fi
            ;;
        *)
            echo "0.5"
            ;;
    esac
}

# Score recency (10%)
score_recency() {
    local timestamp="$1"

    # Calculate days ago
    local entry_date=$(echo "$timestamp" | cut -d'T' -f1)
    local current_date=$(date +%Y-%m-%d)

    local entry_seconds=$(date -j -f "%Y-%m-%d" "$entry_date" +%s 2>/dev/null || date -d "$entry_date" +%s 2>/dev/null)
    local current_seconds=$(date +%s)

    local days_ago=$(( (current_seconds - entry_seconds) / 86400 ))

    # Decay: 1.0 for 0-7 days, 0.8 for 8-30 days, 0.6 for 31-90 days, 0.4 for 91+ days
    if [[ $days_ago -le 7 ]]; then
        echo "1.0"
    elif [[ $days_ago -le 30 ]]; then
        echo "0.8"
    elif [[ $days_ago -le 90 ]]; then
        echo "0.6"
    else
        echo "0.4"
    fi
}

# Score validation (10%)
score_validation() {
    local entry="$1"

    # Check if entry has been validated through application
    local applied_count=$(echo "$entry" | jq '.metadata.applied_count // 0')
    local no_failures=$(echo "$entry" | jq '.metadata.failure_count // 0 | if . == 0 then true else false end')

    if [[ "$applied_count" -gt 0 ]] && [[ "$no_failures" == "true" ]]; then
        echo "1.0"
    elif [[ "$applied_count" -gt 0 ]]; then
        echo "0.6"
    else
        echo "0.3"  # Unvalidated but extracted
    fi
}

# ============================================================================
# Main Scoring Function
# ============================================================================

# Calculate comprehensive quality score
calculate_quality_score() {
    local entry="$1"

    # Extract fields
    local indicators=$(echo "$entry" | jq -c '.success_indicators // []')
    local reusability=$(echo "$entry" | jq -r '.reusability // "specific"')
    local knowledge_type=$(echo "$entry" | jq -r '.type')
    local timestamp=$(echo "$entry" | jq -r '.timestamp')

    # Calculate component scores
    local success_score=$(score_success_indicators "$indicators")
    local completeness_score=$(score_completeness "$entry")
    local reusability_score=$(score_reusability "$reusability" "$knowledge_type")
    local recency_score=$(score_recency "$timestamp")
    local validation_score=$(score_validation "$entry")

    # Weighted total
    local total=$(echo "scale=4; \
        ($success_score * $WEIGHT_SUCCESS) + \
        ($completeness_score * $WEIGHT_COMPLETENESS) + \
        ($reusability_score * $WEIGHT_REUSABILITY) + \
        ($recency_score * $WEIGHT_RECENCY) + \
        ($validation_score * $WEIGHT_VALIDATION)" | bc)

    # Create score breakdown
    jq -n \
        --argjson success "$success_score" \
        --argjson completeness "$completeness_score" \
        --argjson reusability "$reusability_score" \
        --argjson recency "$recency_score" \
        --argjson validation "$validation_score" \
        --argjson total "$total" \
        '{
            success_indicators: $success,
            completeness: $completeness,
            reusability: $reusability,
            recency: $recency,
            validation: $validation,
            total: $total
        }'
}

# Score single entry
score_entry() {
    local entry="$1"

    local entry_id=$(echo "$entry" | jq -r '.id')
    log "Scoring entry: $entry_id"

    # Calculate quality score
    local quality_score=$(calculate_quality_score "$entry")
    local total_score=$(echo "$quality_score" | jq -r '.total')

    # Update entry with quality score (compact JSON)
    echo "$entry" | jq -c \
        --argjson quality "$quality_score" \
        '. + {quality_score: $quality, confidence: ($quality.total)}'
}

# ============================================================================
# Batch Scoring
# ============================================================================

# Score all entries in file
score_file() {
    local input_file="$1"
    local output_file="${2:-${input_file%.jsonl}-scored.jsonl}"

    [[ ! -f "$input_file" ]] && error "Input file not found: $input_file"

    log "Scoring knowledge from: $input_file"
    log "Output file: $output_file"

    # Clear output file
    > "$output_file"

    local count=0
    while IFS= read -r entry; do
        score_entry "$entry" >> "$output_file"
        ((count++))
        [[ $((count % 10)) -eq 0 ]] && log "Scored $count entries"
    done < "$input_file"

    log "Scoring complete: $count entries"
}

# Rescore all knowledge (recalculate with latest metrics)
rescore_all() {
    local knowledge_file="${1:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    log "Rescoring all knowledge"
    score_file "$knowledge_file"
}

# ============================================================================
# Feedback Integration
# ============================================================================

# Update score based on application feedback
update_with_feedback() {
    local knowledge_id="$1"
    local outcome="$2"  # success or failure
    local knowledge_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$knowledge_file" ]] && error "Knowledge file not found: $knowledge_file"

    log "Updating $knowledge_id with outcome: $outcome"

    # Read all entries
    local entries=$(jq -s '.' "$knowledge_file")

    # Update the entry
    local updated_entries=$(echo "$entries" | jq \
        --arg id "$knowledge_id" \
        --arg outcome "$outcome" \
        'map(
            if .id == $id then
                . + {
                    metadata: (.metadata // {}) + {
                        applied_count: ((.metadata.applied_count // 0) + 1),
                        failure_count: (if $outcome == "failure" then ((.metadata.failure_count // 0) + 1) else (.metadata.failure_count // 0) end),
                        success_count: (if $outcome == "success" then ((.metadata.success_count // 0) + 1) else (.metadata.success_count // 0) end),
                        last_applied: (now | todate)
                    }
                }
            else
                .
            end
        )')

    # Write back
    echo "$updated_entries" | jq -c '.[]' > "$knowledge_file"

    # Rescore the updated entry
    local updated_entry=$(echo "$updated_entries" | jq --arg id "$knowledge_id" '.[] | select(.id == $id)')
    local rescored=$(score_entry "$updated_entry")

    log "Rescored entry:"
    echo "$rescored" | jq '{id, confidence, quality_score}'
}

# ============================================================================
# Quality Analytics
# ============================================================================

# Show quality distribution
show_quality_distribution() {
    local file="${1:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$file" ]] && error "File not found: $file"

    cat <<EOF
Quality Score Distribution
==========================
File: $file

By confidence level:
Very High (0.9-1.0): $(jq 'select(.confidence >= 0.9)' "$file" | wc -l)
High (0.7-0.9):      $(jq 'select(.confidence >= 0.7 and .confidence < 0.9)' "$file" | wc -l)
Medium (0.5-0.7):    $(jq 'select(.confidence >= 0.5 and .confidence < 0.7)' "$file" | wc -l)
Low (0.3-0.5):       $(jq 'select(.confidence >= 0.3 and .confidence < 0.5)' "$file" | wc -l)
Very Low (0.0-0.3):  $(jq 'select(.confidence < 0.3)' "$file" | wc -l)

Average quality score: $(jq -s 'map(.confidence // 0) | add / length' "$file")

Top quality entries:
$(jq 'select(.confidence >= 0.8)' "$file" | jq -r '"\(.confidence | tostring | .[0:4]) - \(.type) - \(.problem | .[0:60])..."' | head -10)

Low quality entries (needs review):
$(jq 'select(.confidence < 0.4)' "$file" | jq -r '"\(.confidence | tostring | .[0:4]) - \(.type) - \(.problem | .[0:60])..."' | head -10)
EOF
}

# Identify entries needing validation
identify_needs_validation() {
    local file="${1:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$file" ]] && error "File not found: $file"

    log "Identifying entries needing validation"

    jq 'select((.metadata.applied_count // 0) == 0 and .confidence >= 0.5)' "$file" | \
        jq -r '"\(.id) - \(.type) - \(.problem | .[0:60])..."'
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Quality Scorer - Score and rate knowledge quality

Usage: $(basename "$0") <command> [options]

Commands:
  score <file> [output]              Score all entries in file
  rescore [file]                     Recalculate all scores
  feedback <id> <outcome> [file]     Update with application feedback
  distribution [file]                Show quality distribution
  needs-validation [file]            List entries needing validation
  help                               Show this help message

Feedback outcomes: success, failure

Examples:
  $(basename "$0") score ~/.claude/knowledge/knowledge-base-categorized.jsonl
  $(basename "$0") rescore ~/.claude/knowledge/knowledge-embeddings.jsonl
  $(basename "$0") feedback "k_session1_msg45_20260218" success
  $(basename "$0") distribution
  $(basename "$0") needs-validation
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"

    case "$command" in
        score)
            [[ $# -lt 2 ]] && error "Usage: $0 score <file> [output]"
            score_file "${@:2}"
            ;;
        rescore)
            rescore_all "${2:-}"
            ;;
        feedback)
            [[ $# -lt 3 ]] && error "Usage: $0 feedback <id> <outcome> [file]"
            update_with_feedback "${@:2}"
            ;;
        distribution)
            show_quality_distribution "${2:-}"
            ;;
        needs-validation)
            identify_needs_validation "${2:-}"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: $command\nRun '$0 help' for usage"
            ;;
    esac
}

main "$@"
