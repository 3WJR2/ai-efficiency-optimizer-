#!/usr/bin/env bash
# relevance-scorer.sh - Score session relevance for context loading
# Part of 3-Tier Smart Context Management System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"
CACHE_DIR="${HOME}/.claude/cache/relevance"

# Weights for scoring algorithm
WEIGHT_SEMANTIC=0.40
WEIGHT_TAGS=0.20
WEIGHT_TEMPORAL=0.15
WEIGHT_FILES=0.15
WEIGHT_CONTEXT=0.10

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Initialization
# ============================================================================

# Initialize cache directory
init_cache() {
    mkdir -p "$CACHE_DIR"
}

# ============================================================================
# Semantic Similarity
# ============================================================================

# Calculate semantic similarity using embeddings
calculate_semantic_similarity() {
    local text1="$1"
    local text2="$2"

    # Try to use existing embedding tools
    if [[ -x "$SCRIPT_DIR/get-embedding.sh" ]]; then
        # Get embeddings
        local emb1=$(echo "$text1" | "$SCRIPT_DIR/get-embedding.sh" 2>/dev/null || echo "")
        local emb2=$(echo "$text2" | "$SCRIPT_DIR/get-embedding.sh" 2>/dev/null || echo "")

        if [[ -n "$emb1" ]] && [[ -n "$emb2" ]]; then
            # Calculate cosine similarity using Python
            local similarity=$(python3 - <<PYTHON
import json
import math

emb1 = json.loads('$emb1')
emb2 = json.loads('$emb2')

# Cosine similarity
dot_product = sum(a * b for a, b in zip(emb1, emb2))
magnitude1 = math.sqrt(sum(a * a for a in emb1))
magnitude2 = math.sqrt(sum(b * b for b in emb2))

similarity = dot_product / (magnitude1 * magnitude2) if magnitude1 and magnitude2 else 0
print(f"{similarity:.4f}")
PYTHON
            )
            echo "$similarity"
            return 0
        fi
    fi

    # Fallback: simple word overlap similarity
    calculate_word_overlap "$text1" "$text2"
}

# Fallback: calculate word overlap similarity
calculate_word_overlap() {
    local text1="$1"
    local text2="$2"

    # Convert to lowercase and extract words
    local words1=$(echo "$text1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u)
    local words2=$(echo "$text2" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u)

    # Count unique words in each
    local count1=$(echo "$words1" | wc -l)
    local count2=$(echo "$words2" | wc -l)

    # Count common words
    local common=$(comm -12 <(echo "$words1") <(echo "$words2") | wc -l)

    # Jaccard similarity: |intersection| / |union|
    local union=$((count1 + count2 - common))
    if [[ $union -eq 0 ]]; then
        echo "0.0"
        return
    fi

    local similarity=$(echo "scale=4; $common / $union" | bc)
    echo "$similarity"
}

# ============================================================================
# Session Metadata Extraction
# ============================================================================

# Extract session themes/topics
extract_session_themes() {
    local session_id="$1"
    local session_dir="$SESSIONS_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        echo "[]"
        return 1
    fi

    # Try to extract from session context or metadata
    local context_file="$session_dir/.session-context.md"
    local metadata_file="$session_dir/metadata.json"

    local themes=()

    # Extract from metadata if exists
    if [[ -f "$metadata_file" ]]; then
        local tags=$(jq -r '.tags[]?' "$metadata_file" 2>/dev/null || echo "")
        while IFS= read -r tag; do
            [[ -n "$tag" ]] && themes+=("$tag")
        done <<< "$tags"
    fi

    # Extract from context file
    if [[ -f "$context_file" ]]; then
        # Look for common patterns: ## Tags:, Topics:, etc.
        local found_tags=$(grep -i "tags\|topics\|keywords" "$context_file" | head -5 || echo "")
        while IFS= read -r line; do
            # Extract comma-separated values
            local extracted=$(echo "$line" | sed 's/.*://g' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            while IFS= read -r tag; do
                [[ -n "$tag" ]] && themes+=("$tag")
            done <<< "$extracted"
        done <<< "$found_tags"
    fi

    # Return unique themes as JSON array
    printf '%s\n' "${themes[@]}" | sort -u | jq -R . | jq -s .
}

# Get session metadata summary
get_session_metadata() {
    local session_id="$1"
    local session_dir="$SESSIONS_DIR/$session_id"

    if [[ ! -d "$session_dir" ]]; then
        echo "{}"
        return 1
    fi

    # Extract date from session ID (YYYY-MM-DD-session-N-HASH)
    local date_part=$(echo "$session_id" | cut -d'-' -f1-3)
    local session_date=$(date -j -f "%Y-%m-%d" "$date_part" "+%s" 2>/dev/null || echo "0")

    # Get file list if available
    local files="[]"
    if [[ -f "$session_dir/files-touched.txt" ]]; then
        files=$(cat "$session_dir/files-touched.txt" | jq -R . | jq -s .)
    fi

    # Get themes
    local themes=$(extract_session_themes "$session_id")

    # Check for conversation log
    local has_conversation="false"
    [[ -f "$session_dir/conversation-log.jsonl" ]] && has_conversation="true"

    cat <<EOF
{
  "session_id": "$session_id",
  "date": "$date_part",
  "timestamp": $session_date,
  "themes": $themes,
  "files": $files,
  "has_conversation": $has_conversation
}
EOF
}

# ============================================================================
# Temporal Proximity Scoring
# ============================================================================

# Calculate temporal proximity score (1.0 = today, decays over time)
calculate_temporal_score() {
    local session_date_str="$1"  # YYYY-MM-DD format
    local current_date=$(date +%s)

    # Parse session date
    local session_date=$(date -j -f "%Y-%m-%d" "$session_date_str" "+%s" 2>/dev/null || echo "0")

    if [[ $session_date -eq 0 ]]; then
        echo "0.0"
        return
    fi

    # Calculate days difference
    local diff_seconds=$((current_date - session_date))
    local diff_days=$((diff_seconds / 86400))

    # Decay function
    local score
    if [[ $diff_days -eq 0 ]]; then
        score="1.0"
    elif [[ $diff_days -eq 1 ]]; then
        score="0.9"
    elif [[ $diff_days -le 7 ]]; then
        score="0.7"
    elif [[ $diff_days -le 30 ]]; then
        score="0.4"
    else
        score="0.2"
    fi

    echo "$score"
}

# ============================================================================
# Tag/Theme Matching
# ============================================================================

# Calculate tag overlap score
calculate_tag_score() {
    local session_themes="$1"  # JSON array
    local current_themes="$2"  # JSON array

    # Get unique tags from both
    local session_tags=$(echo "$session_themes" | jq -r '.[]?' | sort -u)
    local current_tags=$(echo "$current_themes" | jq -r '.[]?' | sort -u)

    if [[ -z "$session_tags" ]] || [[ -z "$current_tags" ]]; then
        echo "0.0"
        return
    fi

    # Count matching tags
    local matches=$(comm -12 <(echo "$session_tags") <(echo "$current_tags") | wc -l | tr -d ' ')
    local total=$(echo "$current_tags" | wc -l | tr -d ' ')

    if [[ $total -eq 0 ]]; then
        echo "0.0"
        return
    fi

    # Calculate score: matches / total_current_tags
    local score=$(echo "scale=4; $matches / $total" | bc)
    echo "$score"
}

# ============================================================================
# File Overlap Scoring
# ============================================================================

# Calculate file overlap score
calculate_file_score() {
    local session_files="$1"  # JSON array
    local current_files="$2"  # JSON array

    # Get unique files from both
    local session_file_list=$(echo "$session_files" | jq -r '.[]?' | sort -u)
    local current_file_list=$(echo "$current_files" | jq -r '.[]?' | sort -u)

    if [[ -z "$session_file_list" ]] || [[ -z "$current_file_list" ]]; then
        echo "0.0"
        return
    fi

    # Count matching files
    local matches=$(comm -12 <(echo "$session_file_list") <(echo "$current_file_list") | wc -l | tr -d ' ')
    local total=$(echo "$current_file_list" | wc -l | tr -d ' ')

    if [[ $total -eq 0 ]]; then
        echo "0.0"
        return
    fi

    # Calculate score
    local score=$(echo "scale=4; $matches / $total" | bc)
    echo "$score"
}

# ============================================================================
# Context Similarity
# ============================================================================

# Calculate context similarity (people, decisions, outcomes mentioned)
calculate_context_score() {
    local session_context="$1"
    local current_context="$2"

    # For now, use simple text similarity
    # Future: could extract entities, decisions, outcomes specifically
    calculate_word_overlap "$session_context" "$current_context"
}

# ============================================================================
# Overall Relevance Scoring
# ============================================================================

# Score a session's relevance to current task
score_session_relevance() {
    local session_id="$1"
    local current_task="$2"
    local current_context="${3:-{}}"  # JSON with themes, files, etc.

    # Get session metadata
    local session_meta=$(get_session_metadata "$session_id")

    if [[ "$session_meta" == "{}" ]]; then
        echo "0.0"
        return 1
    fi

    # Extract current context components
    local current_themes=$(echo "$current_context" | jq -c '.themes // []')
    local current_files=$(echo "$current_context" | jq -c '.files // []')

    # Extract session components
    local session_date=$(echo "$session_meta" | jq -r '.date')
    local session_themes=$(echo "$session_meta" | jq -c '.themes')
    local session_files=$(echo "$session_meta" | jq -c '.files')

    # Get session summary for semantic comparison
    local session_summary="$session_id"
    local session_context_file="$SESSIONS_DIR/$session_id/.session-context.md"
    if [[ -f "$session_context_file" ]]; then
        session_summary=$(head -100 "$session_context_file" | tr '\n' ' ')
    fi

    # Calculate component scores
    local semantic_score=$(calculate_word_overlap "$session_summary" "$current_task")
    local tag_score=$(calculate_tag_score "$session_themes" "$current_themes")
    local temporal_score=$(calculate_temporal_score "$session_date")
    local file_score=$(calculate_file_score "$session_files" "$current_files")
    local context_score=$(calculate_context_score "$session_summary" "$current_task")

    # Weighted combination
    local total_score=$(echo "scale=4; \
        ($semantic_score * $WEIGHT_SEMANTIC) + \
        ($tag_score * $WEIGHT_TAGS) + \
        ($temporal_score * $WEIGHT_TEMPORAL) + \
        ($file_score * $WEIGHT_FILES) + \
        ($context_score * $WEIGHT_CONTEXT)" | bc)

    echo "$total_score"
}

# ============================================================================
# Batch Scoring & Ranking
# ============================================================================

# Find most relevant sessions
find_related_sessions() {
    local current_task="$1"
    local top_k="${2:-10}"
    local current_context="${3:-{}}"

    init_cache

    # Get all sessions
    local sessions=($(ls -1 "$SESSIONS_DIR" 2>/dev/null | sort -r))

    if [[ ${#sessions[@]} -eq 0 ]]; then
        echo "[]"
        return 1
    fi

    # Score each session and collect results
    local results_file=$(mktemp)

    for session_id in "${sessions[@]}"; do
        local score=$(score_session_relevance "$session_id" "$current_task" "$current_context")

        echo "$score|$session_id" >> "$results_file"
    done

    # Sort by score (descending) and return top K
    sort -t'|' -k1 -rn "$results_file" | head -n "$top_k" | while IFS='|' read -r score session_id; do
        cat <<EOF
{
  "session_id": "$session_id",
  "relevance_score": $score
}
EOF
    done | jq -s .

    rm -f "$results_file"
}

# Rank sessions by relevance and return detailed info
rank_sessions() {
    local current_task="$1"
    local top_k="${2:-10}"
    local current_context="${3:-{}}"

    local related=$(find_related_sessions "$current_task" "$top_k" "$current_context")

    # Enhance with metadata
    echo "$related" | jq -c '.[]' | while read -r entry; do
        local session_id=$(echo "$entry" | jq -r '.session_id')
        local score=$(echo "$entry" | jq -r '.relevance_score')
        local metadata=$(get_session_metadata "$session_id")

        echo "$metadata" | jq --arg score "$score" '. + {"relevance_score": ($score | tonumber)}'
    done | jq -s .
}

# ============================================================================
# Main CLI
# ============================================================================

show_usage() {
    cat <<EOF
Relevance Scorer - Score session relevance for context loading

Usage:
  $(basename "$0") score <session_id> <task> [context]     Score a session
  $(basename "$0") find <task> [top_k] [context]           Find relevant sessions
  $(basename "$0") rank <task> [top_k] [context]           Rank sessions with details
  $(basename "$0") themes <session_id>                     Extract session themes
  $(basename "$0") metadata <session_id>                   Get session metadata

Examples:
  # Score a specific session
  $(basename "$0") score 2026-02-18-session-1-abc "implement auth"

  # Find top 5 relevant sessions
  $(basename "$0") find "authentication JWT" 5

  # Rank sessions with full details
  $(basename "$0") rank "build TUI" 10

  # Extract themes
  $(basename "$0") themes 2026-02-18-session-1-abc
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        score)
            score_session_relevance "${2:-}" "${3:-}" "${4:-{}}"
            ;;
        find)
            find_related_sessions "${2:-}" "${3:-10}" "${4:-{}}"
            ;;
        rank)
            rank_sessions "${2:-}" "${3:-10}" "${4:-{}}"
            ;;
        themes)
            extract_session_themes "${2:-}"
            ;;
        metadata)
            get_session_metadata "${2:-}" | jq .
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
