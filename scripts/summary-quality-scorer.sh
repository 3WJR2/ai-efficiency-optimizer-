#!/usr/bin/env bash
#
# summary-quality-scorer.sh - Ensure summaries meet quality standards
#
# Part of the Conversation Summarization System
# Scores summaries on completeness, accuracy, conciseness, and searchability
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Token estimation
estimate_tokens() {
    local text="$1"
    local chars=$(echo -n "$text" | wc -c | tr -d ' ')
    echo $((chars / 4))
}

# Check if key points from original are present in summary
check_key_points_present() {
    local original="$1"
    local summary="$2"

    # Extract key terms from original (words 5+ chars)
    local key_terms=$(echo "$original" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{5,}\b' | sort | uniq -c | sort -rn | head -20 | awk '{print $2}')

    # Count how many key terms are in summary
    local total=0
    local present=0

    while IFS= read -r term; do
        ((total++))
        if echo "$summary" | grep -qi "$term"; then
            ((present++))
        fi
    done <<< "$key_terms"

    # Calculate percentage
    if [ $total -eq 0 ]; then
        echo "0"
    else
        echo "scale=2; $present / $total" | bc
    fi
}

# Calculate semantic similarity (simplified)
semantic_similarity() {
    local original="$1"
    local summary="$2"

    # Extract word sets
    local orig_words=$(echo "$original" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | sort -u)
    local summ_words=$(echo "$summary" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | sort -u)

    # Count overlapping words
    local overlap=$(comm -12 <(echo "$orig_words") <(echo "$summ_words") | wc -l | tr -d ' ')
    local orig_count=$(echo "$orig_words" | wc -w | tr -d ' ')

    # Jaccard similarity
    if [ $orig_count -eq 0 ]; then
        echo "0"
    else
        echo "scale=2; $overlap / $orig_count" | bc
    fi
}

# Score compression ratio (ideal: 8:1 to 12:1)
score_compression() {
    local compression_ratio="$1"

    # Convert to float for comparison
    local ratio=$(echo "$compression_ratio" | bc)

    # Scoring curve:
    # < 5:1 = too little compression (0.5)
    # 5-8:1 = acceptable (0.7-0.9)
    # 8-12:1 = ideal (1.0)
    # 12-15:1 = acceptable (0.8-0.9)
    # > 15:1 = too much compression (0.6)

    if [ $(echo "$ratio < 5" | bc) -eq 1 ]; then
        echo "0.50"
    elif [ $(echo "$ratio >= 5 && $ratio < 8" | bc) -eq 1 ]; then
        # Linear scale from 0.7 to 0.9
        echo "scale=2; 0.7 + (($ratio - 5) / 3) * 0.2" | bc
    elif [ $(echo "$ratio >= 8 && $ratio <= 12" | bc) -eq 1 ]; then
        echo "1.00"
    elif [ $(echo "$ratio > 12 && $ratio <= 15" | bc) -eq 1 ]; then
        # Linear scale from 0.9 to 0.8
        echo "scale=2; 0.9 - (($ratio - 12) / 3) * 0.1" | bc
    else
        echo "0.60"
    fi
}

# Check tag coverage
tag_coverage_score() {
    local original="$1"
    local summary="$2"

    # Common technical tags to look for
    local tags=(
        "authentication" "jwt" "redis" "database" "api"
        "security" "testing" "deployment" "docker" "kubernetes"
        "frontend" "backend" "react" "node" "python" "java"
        "bug" "feature" "optimization" "refactor" "debug"
        "performance" "scalability" "architecture"
    )

    # Count tags in original and summary
    local tags_in_orig=0
    local tags_in_summ=0

    for tag in "${tags[@]}"; do
        if echo "$original" | grep -qi "$tag"; then
            ((tags_in_orig++))
            if echo "$summary" | grep -qi "$tag"; then
                ((tags_in_summ++))
            fi
        fi
    done

    # Calculate coverage
    if [ $tags_in_orig -eq 0 ]; then
        echo "1.00"  # No tags to cover
    else
        echo "scale=2; $tags_in_summ / $tags_in_orig" | bc
    fi
}

# Check if summary has required sections
check_required_sections() {
    local summary="$1"
    local detail_level="${2:-standard}"

    local score=1.0
    local required_sections=()

    case "$detail_level" in
        brief)
            # Brief summaries should be concise narrative
            if [ $(estimate_tokens "$summary") -gt 400 ]; then
                score=0.5
            fi
            ;;
        standard)
            required_sections=("Decision" "Solution" "Outcome")
            ;;
        detailed)
            required_sections=("Decision" "Solution" "Insight" "Outcome" "Code")
            ;;
    esac

    # Check for required sections
    local missing=0
    for section in "${required_sections[@]}"; do
        if ! echo "$summary" | grep -qi "$section"; then
            ((missing++))
        fi
    done

    if [ ${#required_sections[@]} -gt 0 ]; then
        local present=$((${#required_sections[@]} - missing))
        score=$(echo "scale=2; $present / ${#required_sections[@]}" | bc)
    fi

    echo "$score"
}

# Overall quality score
score_summary() {
    local original="$1"
    local summary="$2"
    local detail_level="${3:-standard}"

    # Calculate individual scores
    local completeness=$(check_key_points_present "$original" "$summary")
    local accuracy=$(semantic_similarity "$original" "$summary")

    # Calculate compression ratio
    local orig_tokens=$(estimate_tokens "$original")
    local summ_tokens=$(estimate_tokens "$summary")
    local compression_ratio=$(echo "scale=1; $orig_tokens / $summ_tokens" | bc)
    local conciseness=$(score_compression "$compression_ratio")

    # Calculate searchability
    local searchability=$(tag_coverage_score "$original" "$summary")

    # Check sections
    local structure=$(check_required_sections "$summary" "$detail_level")

    # Weighted score
    # Completeness: 25%
    # Accuracy: 30%
    # Conciseness: 20%
    # Searchability: 15%
    # Structure: 10%
    local overall=$(echo "scale=2; \
        $completeness * 0.25 + \
        $accuracy * 0.30 + \
        $conciseness * 0.20 + \
        $searchability * 0.15 + \
        $structure * 0.10" | bc)

    # Return detailed scores as JSON
    jq -n \
        --arg completeness "$completeness" \
        --arg accuracy "$accuracy" \
        --arg conciseness "$conciseness" \
        --arg searchability "$searchability" \
        --arg structure "$structure" \
        --arg overall "$overall" \
        --arg compression_ratio "$compression_ratio" \
        --arg orig_tokens "$orig_tokens" \
        --arg summ_tokens "$summ_tokens" \
        '{
            overall: ($overall | tonumber),
            scores: {
                completeness: ($completeness | tonumber),
                accuracy: ($accuracy | tonumber),
                conciseness: ($conciseness | tonumber),
                searchability: ($searchability | tonumber),
                structure: ($structure | tonumber)
            },
            metrics: {
                compression_ratio: ($compression_ratio | tonumber),
                original_tokens: ($orig_tokens | tonumber),
                summary_tokens: ($summ_tokens | tonumber)
            }
        }'
}

# Get quality rating
get_quality_rating() {
    local score="$1"

    # Convert to comparable number
    local score_int=$(echo "$score * 100" | bc | cut -d. -f1)

    if [ $score_int -ge 90 ]; then
        echo "Excellent"
    elif [ $score_int -ge 80 ]; then
        echo "Good"
    elif [ $score_int -ge 70 ]; then
        echo "Acceptable"
    elif [ $score_int -ge 60 ]; then
        echo "Poor"
    else
        echo "Failed"
    fi
}

# Generate quality report
generate_quality_report() {
    local scores_json="$1"

    local overall=$(echo "$scores_json" | jq -r '.overall')
    local completeness=$(echo "$scores_json" | jq -r '.scores.completeness')
    local accuracy=$(echo "$scores_json" | jq -r '.scores.accuracy')
    local conciseness=$(echo "$scores_json" | jq -r '.scores.conciseness')
    local searchability=$(echo "$scores_json" | jq -r '.scores.searchability')
    local structure=$(echo "$scores_json" | jq -r '.scores.structure')
    local compression=$(echo "$scores_json" | jq -r '.metrics.compression_ratio')
    local orig_tokens=$(echo "$scores_json" | jq -r '.metrics.original_tokens')
    local summ_tokens=$(echo "$scores_json" | jq -r '.metrics.summary_tokens')

    local rating=$(get_quality_rating "$overall")

    cat <<EOF
Summary Quality Report
======================

Overall Score: $(printf "%.2f" $overall) / 1.00 [$rating]

Dimension Scores:
  Completeness:   $(printf "%.2f" $completeness) / 1.00  (Key points preserved)
  Accuracy:       $(printf "%.2f" $accuracy) / 1.00  (Semantic similarity)
  Conciseness:    $(printf "%.2f" $conciseness) / 1.00  (Compression quality)
  Searchability:  $(printf "%.2f" $searchability) / 1.00  (Tag coverage)
  Structure:      $(printf "%.2f" $structure) / 1.00  (Required sections)

Metrics:
  Original tokens:  $orig_tokens
  Summary tokens:   $summ_tokens
  Compression:      ${compression}:1

$(if [ $(echo "$overall < 0.70" | bc) -eq 1 ]; then
    echo "⚠️  WARNING: Score below minimum threshold (0.70)"
    echo "   Consider regenerating with more detail"
elif [ $(echo "$overall < 0.80" | bc) -eq 1 ]; then
    echo "⚠️  Score below target (0.80)"
    echo "   Summary is acceptable but could be improved"
else
    echo "✅ Score meets quality standards"
fi)

Recommendations:
$(if [ $(echo "$completeness < 0.70" | bc) -eq 1 ]; then
    echo "  - Increase completeness: Add more key points from original"
fi)
$(if [ $(echo "$accuracy < 0.70" | bc) -eq 1 ]; then
    echo "  - Improve accuracy: Better preserve original meaning"
fi)
$(if [ $(echo "$conciseness < 0.70" | bc) -eq 1 ]; then
    echo "  - Adjust conciseness: Target 8:1 to 12:1 compression ratio"
fi)
$(if [ $(echo "$searchability < 0.70" | bc) -eq 1 ]; then
    echo "  - Enhance searchability: Include more technical keywords/tags"
fi)
$(if [ $(echo "$structure < 0.70" | bc) -eq 1 ]; then
    echo "  - Fix structure: Add missing required sections"
fi)
EOF
}

# CLI interface
main() {
    local command="${1:-score}"

    case "$command" in
        score)
            local original_file="$2"
            local summary_file="$3"
            local detail_level="${4:-standard}"

            if [ -z "$original_file" ] || [ -z "$summary_file" ]; then
                echo "Usage: $0 score <original_file> <summary_file> [detail_level]" >&2
                exit 1
            fi

            score_summary "$(cat "$original_file")" "$(cat "$summary_file")" "$detail_level"
            ;;
        report)
            local original_file="$2"
            local summary_file="$3"
            local detail_level="${4:-standard}"

            if [ -z "$original_file" ] || [ -z "$summary_file" ]; then
                echo "Usage: $0 report <original_file> <summary_file> [detail_level]" >&2
                exit 1
            fi

            local scores=$(score_summary "$(cat "$original_file")" "$(cat "$summary_file")" "$detail_level")
            generate_quality_report "$scores"
            ;;
        check)
            local original_file="$2"
            local summary_file="$3"
            local min_score="${4:-0.70}"

            if [ -z "$original_file" ] || [ -z "$summary_file" ]; then
                echo "Usage: $0 check <original_file> <summary_file> [min_score]" >&2
                exit 1
            fi

            local scores=$(score_summary "$(cat "$original_file")" "$(cat "$summary_file")")
            local overall=$(echo "$scores" | jq -r '.overall')

            if [ $(echo "$overall >= $min_score" | bc) -eq 1 ]; then
                echo "✅ Quality check passed: $overall >= $min_score"
                exit 0
            else
                echo "❌ Quality check failed: $overall < $min_score"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 {score|report|check} <original_file> <summary_file> [params]" >&2
            echo "" >&2
            echo "Commands:" >&2
            echo "  score   - Calculate quality scores (JSON output)" >&2
            echo "  report  - Generate detailed quality report" >&2
            echo "  check   - Check if summary meets minimum score" >&2
            exit 1
            ;;
    esac
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
