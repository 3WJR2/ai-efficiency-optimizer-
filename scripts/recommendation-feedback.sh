#!/usr/bin/env bash
# recommendation-feedback.sh - Track recommendation usage and feedback
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
FEEDBACK_FILE="${KNOWLEDGE_DIR}/recommendation-feedback.json"
RECOMMENDATION_CACHE="${KNOWLEDGE_DIR}/recommendation-cache.json"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Initialize feedback storage
initialize_feedback() {
    if [[ ! -f "${FEEDBACK_FILE}" ]]; then
        cat > "${FEEDBACK_FILE}" <<'EOF'
{
  "version": "1.0.0",
  "feedback_entries": [],
  "usage_stats": {},
  "weights": {
    "semantic_similarity": 0.40,
    "tag_overlap": 0.20,
    "recency": 0.15,
    "confidence": 0.15,
    "success_rate": 0.10
  },
  "last_updated": ""
}
EOF
    fi

    # Initialize recommendation cache if not exists
    if [[ ! -f "${RECOMMENDATION_CACHE}" ]]; then
        cat > "${RECOMMENDATION_CACHE}" <<'EOF'
{
  "version": "1.0.0",
  "recommendations": {},
  "usage_stats": {}
}
EOF
    fi
}

# Track recommendation usage
track_recommendation_use() {
    local knowledge_id="$1"
    local outcome="${2:-used}"  # used|helpful|not_helpful|success|failure

    initialize_feedback

    log_info "Tracking: $knowledge_id -> $outcome"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Add feedback entry
    jq --arg id "$knowledge_id" \
       --arg outcome "$outcome" \
       --arg ts "$timestamp" \
       '.feedback_entries += [{
         knowledge_id: $id,
         outcome: $outcome,
         timestamp: $ts
       }] |
       .usage_stats[$id] = (.usage_stats[$id] // {
         total_uses: 0,
         helpful_count: 0,
         not_helpful_count: 0,
         success_count: 0,
         failure_count: 0
       }) |
       .usage_stats[$id].total_uses += 1 |
       .usage_stats[$id].last_used = $ts |
       if $outcome == "helpful" or $outcome == "success" then
         .usage_stats[$id].helpful_count += 1
       elif $outcome == "not_helpful" or $outcome == "failure" then
         .usage_stats[$id].not_helpful_count += 1
       else . end |
       if $outcome == "success" then
         .usage_stats[$id].success_count += 1
       elif $outcome == "failure" then
         .usage_stats[$id].failure_count += 1
       else . end |
       .last_updated = $ts' \
       "${FEEDBACK_FILE}" > "${FEEDBACK_FILE}.tmp"

    mv "${FEEDBACK_FILE}.tmp" "${FEEDBACK_FILE}"

    # Also update recommendation cache
    jq --arg id "$knowledge_id" \
       --arg outcome "$outcome" \
       '.usage_stats[$id] = (.usage_stats[$id] // {
         used_count: 0,
         success_count: 0,
         failure_count: 0
       }) |
       .usage_stats[$id].used_count += 1 |
       if $outcome == "success" or $outcome == "helpful" then
         .usage_stats[$id].success_count += 1
       elif $outcome == "failure" or $outcome == "not_helpful" then
         .usage_stats[$id].failure_count += 1
       else . end' \
       "${RECOMMENDATION_CACHE}" > "${RECOMMENDATION_CACHE}.tmp"

    mv "${RECOMMENDATION_CACHE}.tmp" "${RECOMMENDATION_CACHE}"

    log_success "Feedback recorded"
}

# Update recommendation weights based on feedback
update_recommendation_weights() {
    initialize_feedback

    log_info "Updating recommendation weights based on feedback..."

    # Analyze which factors correlate with successful recommendations
    local total_feedback=$(jq '.feedback_entries | length' "${FEEDBACK_FILE}")

    if [[ $total_feedback -lt 10 ]]; then
        log_warn "Not enough feedback data (need 10+, have $total_feedback)"
        return 0
    fi

    log_info "Analyzing $total_feedback feedback entries..."

    # Simple weight adjustment based on success/failure ratio
    # In production, would use more sophisticated ML techniques

    # Get current weights
    local current_weights=$(jq '.weights' "${FEEDBACK_FILE}")

    # Calculate success rate
    local helpful=$(jq '[.feedback_entries[] | select(.outcome == "helpful" or .outcome == "success")] | length' "${FEEDBACK_FILE}")
    local not_helpful=$(jq '[.feedback_entries[] | select(.outcome == "not_helpful" or .outcome == "failure")] | length' "${FEEDBACK_FILE}")

    local success_rate=$(echo "scale=3; $helpful / ($helpful + $not_helpful)" | bc)

    log_info "Overall success rate: $(echo "$success_rate * 100" | bc)%"

    # Adjust weights slightly based on success rate
    # If success rate is high (>0.80), current weights are good
    # If low (<0.50), adjust to favor confidence and success_rate more

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if (( $(echo "$success_rate < 0.50" | bc -l) )); then
        log_info "Low success rate, adjusting weights to favor proven solutions..."

        jq '.weights.semantic_similarity = 0.30 |
            .weights.tag_overlap = 0.15 |
            .weights.recency = 0.10 |
            .weights.confidence = 0.20 |
            .weights.success_rate = 0.25 |
            .last_weight_update = "'"$timestamp"'" |
            .last_updated = "'"$timestamp"'"' \
            "${FEEDBACK_FILE}" > "${FEEDBACK_FILE}.tmp"

        mv "${FEEDBACK_FILE}.tmp" "${FEEDBACK_FILE}"
        log_success "Weights adjusted to favor proven solutions"

    elif (( $(echo "$success_rate > 0.80" | bc -l) )); then
        log_success "High success rate, keeping current weights"

        jq '.last_weight_update = "'"$timestamp"'" |
            .last_updated = "'"$timestamp"'"' \
            "${FEEDBACK_FILE}" > "${FEEDBACK_FILE}.tmp"

        mv "${FEEDBACK_FILE}.tmp" "${FEEDBACK_FILE}"
    else
        log_info "Moderate success rate, making minor adjustments..."

        jq '.weights.semantic_similarity = 0.35 |
            .weights.tag_overlap = 0.20 |
            .weights.recency = 0.15 |
            .weights.confidence = 0.18 |
            .weights.success_rate = 0.12 |
            .last_weight_update = "'"$timestamp"'" |
            .last_updated = "'"$timestamp"'"' \
            "${FEEDBACK_FILE}" > "${FEEDBACK_FILE}.tmp"

        mv "${FEEDBACK_FILE}.tmp" "${FEEDBACK_FILE}"
        log_success "Weights balanced"
    fi
}

# Get recommendation statistics
get_recommendation_stats() {
    initialize_feedback

    log_info "Recommendation Statistics:"
    echo ""

    # Overall stats
    local total=$(jq '.feedback_entries | length' "${FEEDBACK_FILE}")
    local helpful=$(jq '[.feedback_entries[] | select(.outcome == "helpful" or .outcome == "success")] | length' "${FEEDBACK_FILE}")
    local not_helpful=$(jq '[.feedback_entries[] | select(.outcome == "not_helpful" or .outcome == "failure")] | length' "${FEEDBACK_FILE}")

    echo "Total Feedback Entries: $total"
    if [[ $total -gt 0 ]]; then
        local success_rate=$(echo "scale=1; ($helpful * 100) / $total" | bc)
        echo "Success Rate: ${success_rate}% ($helpful helpful, $not_helpful not helpful)"
    fi
    echo ""

    # Per-knowledge stats
    echo "Top Recommended Knowledge:"
    jq -r '.usage_stats | to_entries |
        map({
          id: .key,
          uses: .value.total_uses,
          helpful: .value.helpful_count,
          not_helpful: .value.not_helpful_count,
          rate: (if .value.total_uses > 0 then
                  (.value.helpful_count * 100 / .value.total_uses | floor)
                 else 0 end)
        }) |
        sort_by(-.uses) |
        .[:10] |
        map("  " + .id + ": " + (.uses | tostring) + " uses, " +
            (.rate | tostring) + "% helpful (\(.helpful)/\(.not_helpful))") |
        join("\n")' "${FEEDBACK_FILE}"

    echo ""

    # Current weights
    echo "Current Ranking Weights:"
    jq -r '.weights | to_entries |
        map("  " + .key + ": " + ((.value * 100) | floor | tostring) + "%") |
        join("\n")' "${FEEDBACK_FILE}"

    echo ""
    echo "Last Updated: $(jq -r '.last_updated' "${FEEDBACK_FILE}")"
}

# Detect if knowledge was used (check for ID in recent queries)
detect_knowledge_usage() {
    local knowledge_id="$1"
    local query_text="$2"

    # Simple detection: check if knowledge ID or key terms appear in query
    if echo "$query_text" | grep -q "$knowledge_id"; then
        echo "explicit_reference"
        return 0
    fi

    # Could also check for code snippets, problem descriptions, etc.
    # For now, return unknown
    echo "unknown"
}

# Interactive feedback collection
interactive_feedback() {
    initialize_feedback

    echo ""
    echo "=== Recommendation Feedback ==="
    echo ""

    read -p "Knowledge ID: " knowledge_id

    if [[ -z "$knowledge_id" ]]; then
        log_error "No knowledge ID provided"
        return 1
    fi

    echo ""
    echo "How was this recommendation?"
    echo "1) Very helpful (solved my problem)"
    echo "2) Helpful (pointed me in right direction)"
    echo "3) Not helpful (not relevant)"
    echo "4) Harmful (led me astray)"
    echo ""

    read -p "Choice [1-4]: " choice

    case "$choice" in
        1)
            track_recommendation_use "$knowledge_id" "success"
            ;;
        2)
            track_recommendation_use "$knowledge_id" "helpful"
            ;;
        3)
            track_recommendation_use "$knowledge_id" "not_helpful"
            ;;
        4)
            track_recommendation_use "$knowledge_id" "failure"
            ;;
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac

    echo ""
    log_success "Thank you for your feedback!"
}

# Export feedback data
export_feedback() {
    local output_file="${1:-${KNOWLEDGE_DIR}/feedback-export.json}"

    initialize_feedback

    cp "${FEEDBACK_FILE}" "$output_file"

    log_success "Feedback data exported to: $output_file"
}

# Reset feedback (with confirmation)
reset_feedback() {
    echo ""
    echo "WARNING: This will delete all feedback data!"
    read -p "Are you sure? [y/N]: " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Reset cancelled"
        return 0
    fi

    # Backup first
    if [[ -f "${FEEDBACK_FILE}" ]]; then
        local backup="${FEEDBACK_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${FEEDBACK_FILE}" "$backup"
        log_info "Backup saved to: $backup"
    fi

    # Reset
    rm -f "${FEEDBACK_FILE}"
    initialize_feedback

    log_success "Feedback data reset"
}

# Main command dispatcher
main() {
    case "${1:-help}" in
        track)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 track <knowledge_id> [outcome]"
                exit 1
            fi
            track_recommendation_use "$2" "${3:-used}"
            ;;
        update-weights)
            update_recommendation_weights
            ;;
        stats)
            get_recommendation_stats
            ;;
        detect)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                log_error "Usage: $0 detect <knowledge_id> <query_text>"
                exit 1
            fi
            detect_knowledge_usage "$2" "$3"
            ;;
        interactive)
            interactive_feedback
            ;;
        export)
            export_feedback "${2:-}"
            ;;
        reset)
            reset_feedback
            ;;
        *)
            cat <<EOF
Usage: $0 {track|update-weights|stats|detect|interactive|export|reset}

Commands:
  track <knowledge_id> <outcome>
      Track recommendation usage
      Outcomes: used|helpful|not_helpful|success|failure

  update-weights
      Update recommendation weights based on feedback

  stats
      Show recommendation statistics

  detect <knowledge_id> <query>
      Detect if knowledge was used in query

  interactive
      Interactive feedback collection

  export [output_file]
      Export feedback data

  reset
      Reset all feedback data (with confirmation)

Examples:
  $0 track "k_auth_oauth_20260201" success
  $0 update-weights
  $0 stats
  $0 interactive
EOF
            exit 1
            ;;
    esac
}

# Run main
main "$@"
