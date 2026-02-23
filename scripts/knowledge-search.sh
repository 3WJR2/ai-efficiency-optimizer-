#!/usr/bin/env bash

# knowledge-search.sh
# Search knowledge base with semantic similarity
# Part of Cross-Session Knowledge Extraction System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-${HOME}/.claude/knowledge}"
INDEXER="${SCRIPT_DIR}/knowledge-indexer.sh"

# Default search parameters
DEFAULT_TOP_K=10
DEFAULT_MIN_CONFIDENCE=0.0

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
# Embedding Functions (from indexer)
# ============================================================================

# Generate embedding for text using simple TF-IDF approach
generate_embedding_tfidf() {
    local text="$1"
    local cache_key=$(echo -n "$text" | md5)

    # Check cache
    local cache_dir="${HOME}/.claude/cache/embeddings"
    mkdir -p "$cache_dir"
    local cache_file="${cache_dir}/${cache_key}.json"
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    # Simple TF-IDF embedding (terms with frequency weights)
    # Extract words and calculate term frequencies
    local words=$(echo "$text" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{3,15}\b' | sort)
    local total_words=$(echo "$words" | wc -l)

    # Build term frequency map
    local tf_map=$(echo "$words" | uniq -c | awk '{print "{\"term\":\"" $2 "\",\"frequency\":" $1 "}"}' | jq -s '.')

    # Create embedding vector (top 50 terms)
    local embedding=$(echo "$tf_map" | jq -c 'sort_by(-.frequency) | .[:50]')

    # Cache result
    echo "$embedding" > "$cache_file"
    echo "$embedding"
}

# Calculate cosine similarity between two TF-IDF embeddings
calculate_similarity() {
    local embedding1="$1"
    local embedding2="$2"

    # Extract term sets
    local terms1=$(echo "$embedding1" | jq -r '.[].term' | sort)
    local terms2=$(echo "$embedding2" | jq -r '.[].term' | sort)

    # Count common terms
    local common_terms=$(comm -12 <(echo "$terms1") <(echo "$terms2") | wc -l)
    local total_terms1=$(echo "$terms1" | wc -l)
    local total_terms2=$(echo "$terms2" | wc -l)

    # Calculate Jaccard similarity (approximation of cosine)
    # similarity = |intersection| / |union|
    local union_size=$((total_terms1 + total_terms2 - common_terms))

    if [[ $union_size -eq 0 ]]; then
        echo "0.0"
        return
    fi

    # Use bc for floating point division
    local result=$(echo "scale=4; $common_terms / $union_size" | bc)
    # Add leading zero if missing
    if [[ "$result" == .* ]]; then
        echo "0$result"
    else
        echo "$result"
    fi
}

# ============================================================================
# Search Functions
# ============================================================================

# Semantic search by query
search_knowledge() {
    local query="$1"
    local top_k="${2:-$DEFAULT_TOP_K}"
    local index_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Searching for: $query"

    local start_time=$(date +%s%3N)

    # Generate embedding for query
    local query_embedding=$(generate_embedding_tfidf "$query")

    # Read all entries
    local entries=$(jq -s '.' "$index_file")
    local total=$(echo "$entries" | jq 'length')

    log "Searching through $total entries"

    # Calculate similarity for each entry
    local results=()
    for ((i=0; i<total; i++)); do
        local entry=$(echo "$entries" | jq ".[$i]")
        local entry_embedding=$(echo "$entry" | jq -c '.embeddings.combined_embedding')

        # Calculate similarity
        local similarity=$(calculate_similarity "$query_embedding" "$entry_embedding")

        # Store result
        local result=$(echo "$entry" | jq \
            --arg score "$similarity" \
            '. + {score: ($score | tonumber)}')

        results+=("$result")
    done

    # Sort by score and take top K
    local sorted_results=$(printf '%s\n' "${results[@]}" | jq -s 'sort_by(-.score) | .[:'"$top_k"']')

    local end_time=$(date +%s%3N)
    local search_time=$((end_time - start_time))

    # Format output
    jq -n \
        --arg query "$query" \
        --argjson results "$sorted_results" \
        --argjson total "$(echo "$sorted_results" | jq 'length')" \
        --argjson search_time "$search_time" \
        '{
            query: $query,
            results: $results,
            total: $total,
            search_time_ms: $search_time
        }'
}

# Search by problem description
search_by_problem() {
    local problem_desc="$1"
    local top_k="${2:-$DEFAULT_TOP_K}"
    local index_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Searching for similar problems: $problem_desc"

    # Generate embedding for problem
    local problem_embedding=$(generate_embedding_tfidf "$problem_desc")

    # Read all entries
    local entries=$(jq -s '.' "$index_file")
    local total=$(echo "$entries" | jq 'length')

    # Calculate similarity using problem embeddings
    local results=()
    for ((i=0; i<total; i++)); do
        local entry=$(echo "$entries" | jq ".[$i]")
        local entry_problem_embedding=$(echo "$entry" | jq -c '.embeddings.problem_embedding')

        local similarity=$(calculate_similarity "$problem_embedding" "$entry_problem_embedding")

        local result=$(echo "$entry" | jq \
            --arg score "$similarity" \
            '. + {score: ($score | tonumber)}')

        results+=("$result")
    done

    # Sort and format
    printf '%s\n' "${results[@]}" | jq -s 'sort_by(-.score) | .[:'"$top_k"']'
}

# Search by tags
search_by_tags() {
    local tags_input="$1"
    local top_k="${2:-$DEFAULT_TOP_K}"
    local index_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    # Convert comma-separated tags to array
    IFS=',' read -ra tags <<< "$tags_input"

    log "Searching by tags: ${tags[*]}"

    # Filter entries by tags
    local filter_expr='['
    for tag in "${tags[@]}"; do
        filter_expr+=".tags[] | select(. == \"$tag\"),"
    done
    filter_expr="${filter_expr%,}]"

    # Search and rank by number of matching tags
    jq -s \
        --argjson tags "$(printf '%s\n' "${tags[@]}" | jq -R . | jq -s .)" \
        '[.[] | select(.tags as $entry_tags | $tags | map(. as $tag | $entry_tags | index($tag)) | any)] | sort_by([.tags as $entry_tags | $tags | map(. as $tag | if ($entry_tags | index($tag)) then 1 else 0 end) | add] | -.[0]) | .[:'"$top_k"']' \
        "$index_file"
}

# Search by domain
search_by_domain() {
    local domain="$1"
    local language="${2:-}"
    local top_k="${3:-$DEFAULT_TOP_K}"
    local index_file="${4:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Searching by domain: $domain${language:+ (language: $language)}"

    if [[ -n "$language" ]]; then
        jq -s \
            --arg domain "$domain" \
            --arg language "$language" \
            '[.[] | select((.domain | index($domain)) and (.language | index($language)))] | .[:'"$top_k"']' \
            "$index_file"
    else
        jq -s \
            --arg domain "$domain" \
            '[.[] | select(.domain | index($domain))] | .[:'"$top_k"']' \
            "$index_file"
    fi
}

# Search by knowledge type
search_by_type() {
    local knowledge_type="$1"
    local top_k="${2:-$DEFAULT_TOP_K}"
    local index_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Searching by type: $knowledge_type"

    jq -s \
        --arg type "$knowledge_type" \
        '[.[] | select(.type == $type)] | sort_by(-.confidence) | .[:'"$top_k"']' \
        "$index_file"
}

# Search recent knowledge (temporal)
search_recent() {
    local days="${1:-7}"
    local top_k="${2:-$DEFAULT_TOP_K}"
    local index_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    local cutoff_date=$(date -v-${days}d +"%Y-%m-%d" 2>/dev/null || date -d "${days} days ago" +"%Y-%m-%d")

    log "Searching for entries since: $cutoff_date"

    jq -s \
        --arg cutoff "$cutoff_date" \
        '[.[] | select(.timestamp >= $cutoff)] | sort_by(-.timestamp) | .[:'"$top_k"']' \
        "$index_file"
}

# Search high-confidence knowledge
search_by_confidence() {
    local min_confidence="${1:-0.7}"
    local top_k="${2:-$DEFAULT_TOP_K}"
    local index_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Searching for high-confidence entries (min: $min_confidence)"

    jq -s \
        --argjson min_conf "$min_confidence" \
        '[.[] | select(.confidence >= $min_conf)] | sort_by(-.confidence) | .[:'"$top_k"']' \
        "$index_file"
}

# Get related knowledge entries
get_related_knowledge() {
    local knowledge_id="$1"
    local top_k="${2:-5}"
    local index_file="${3:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Finding related knowledge for: $knowledge_id"

    # Get the entry
    local entry=$(jq -s --arg id "$knowledge_id" '.[] | select(.id == $id)' "$index_file")
    [[ -z "$entry" ]] && error "Knowledge entry not found: $knowledge_id"

    # Get its embedding
    local entry_embedding=$(echo "$entry" | jq -c '.embeddings.combined_embedding')

    # Find similar entries (excluding itself)
    local entries=$(jq -s '.' "$index_file")
    local total=$(echo "$entries" | jq 'length')

    local results=()
    for ((i=0; i<total; i++)); do
        local other_entry=$(echo "$entries" | jq ".[$i]")
        local other_id=$(echo "$other_entry" | jq -r '.id')

        # Skip self
        [[ "$other_id" == "$knowledge_id" ]] && continue

        local other_embedding=$(echo "$other_entry" | jq -c '.embeddings.combined_embedding')
        local similarity=$(calculate_similarity "$entry_embedding" "$other_embedding")

        local result=$(echo "$other_entry" | jq \
            --arg score "$similarity" \
            '. + {score: ($score | tonumber)}')

        results+=("$result")
    done

    # Sort by similarity
    printf '%s\n' "${results[@]}" | jq -s 'sort_by(-.score) | .[:'"$top_k"']'
}

# ============================================================================
# Output Formatting
# ============================================================================

# Format search results for display
format_results() {
    local results="$1"
    local format="${2:-summary}"  # summary, detailed, json

    case "$format" in
        json)
            echo "$results" | jq .
            ;;
        detailed)
            echo "$results" | jq -r '.results[] |
                "ID: \(.id)\n" +
                "Type: \(.type) | Confidence: \(.confidence) | Score: \(.score)\n" +
                "Problem: \(.problem | .[0:200])...\n" +
                "Solution: \(.solution | .[0:200])...\n" +
                "Tags: \(.tags | join(", "))\n" +
                "Session: \(.session_id)\n" +
                "---"'
            ;;
        summary|*)
            echo "$results" | jq -r '.results[] |
                "[\(.score | tostring | .[0:4])] \(.type) - \(.problem | .[0:80])... (confidence: \(.confidence))"'
            ;;
    esac
}

# ============================================================================
# Advanced Search
# ============================================================================

# Multi-field search with filters
advanced_search() {
    local query="$1"
    local filters="$2"  # JSON object with filters
    local top_k="${3:-$DEFAULT_TOP_K}"
    local index_file="${4:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Advanced search: $query"
    log "Filters: $filters"

    # Generate query embedding
    local query_embedding=$(generate_embedding_tfidf "$query")

    # Read and filter entries
    local filtered_entries=$(jq -s \
        --argjson filters "$filters" \
        '[.[] | select(
            (if $filters.type then .type == $filters.type else true end) and
            (if $filters.domain then (.domain | index($filters.domain)) else true end) and
            (if $filters.language then (.language | index($filters.language)) else true end) and
            (if $filters.min_confidence then .confidence >= $filters.min_confidence else true end)
        )]' \
        "$index_file")

    local total=$(echo "$filtered_entries" | jq 'length')
    log "Filtered to $total entries"

    # Calculate similarities
    local results=()
    for ((i=0; i<total; i++)); do
        local entry=$(echo "$filtered_entries" | jq ".[$i]")
        local entry_embedding=$(echo "$entry" | jq -c '.embeddings.combined_embedding')

        local similarity=$(calculate_similarity "$query_embedding" "$entry_embedding")

        local result=$(echo "$entry" | jq \
            --arg score "$similarity" \
            '. + {score: ($score | tonumber)}')

        results+=("$result")
    done

    # Sort and return
    printf '%s\n' "${results[@]}" | jq -s 'sort_by(-.score) | .[:'"$top_k"']'
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Search - Search knowledge base with semantic similarity

Usage: $(basename "$0") <command> [options]

Commands:
  search <query> [top_k]              Semantic search by query
  problem <description> [top_k]       Find similar problems
  tags <tag1,tag2,...> [top_k]        Search by tags
  domain <domain> [language] [top_k]  Search by domain/language
  type <type> [top_k]                 Search by knowledge type
  recent [days] [top_k]               Search recent entries
  confidence [min] [top_k]            High-confidence entries
  related <id> [top_k]                Find related entries
  advanced <query> <filters_json>     Advanced filtered search
  help                                Show this help message

Examples:
  $(basename "$0") search "authentication timeout bug" 5
  $(basename "$0") problem "session expires too quickly"
  $(basename "$0") tags "python,error,index"
  $(basename "$0") domain "backend" "python" 10
  $(basename "$0") type "solution" 10
  $(basename "$0") recent 7 10
  $(basename "$0") confidence 0.8 10
  $(basename "$0") related "k_session1_msg45_20260218"
  $(basename "$0") advanced "api error" '{"type":"solution","domain":"backend"}'

Output formats: --format=summary (default), --format=detailed, --format=json
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"

    # Parse format option
    local format="summary"
    for arg in "$@"; do
        if [[ "$arg" =~ ^--format= ]]; then
            format="${arg#--format=}"
        fi
    done

    case "$command" in
        search)
            [[ $# -lt 2 ]] && error "Usage: $0 search <query> [top_k]"
            results=$(search_knowledge "${@:2}")
            format_results "$results" "$format"
            ;;
        problem)
            [[ $# -lt 2 ]] && error "Usage: $0 problem <description> [top_k]"
            results=$(search_by_problem "${@:2}")
            echo "$results" | jq .
            ;;
        tags)
            [[ $# -lt 2 ]] && error "Usage: $0 tags <tag1,tag2,...> [top_k]"
            results=$(search_by_tags "${@:2}")
            echo "$results" | jq .
            ;;
        domain)
            [[ $# -lt 2 ]] && error "Usage: $0 domain <domain> [language] [top_k]"
            results=$(search_by_domain "${@:2}")
            echo "$results" | jq .
            ;;
        type)
            [[ $# -lt 2 ]] && error "Usage: $0 type <type> [top_k]"
            results=$(search_by_type "${@:2}")
            echo "$results" | jq .
            ;;
        recent)
            results=$(search_recent "${2:-7}" "${3:-$DEFAULT_TOP_K}")
            echo "$results" | jq .
            ;;
        confidence)
            results=$(search_by_confidence "${2:-0.7}" "${3:-$DEFAULT_TOP_K}")
            echo "$results" | jq .
            ;;
        related)
            [[ $# -lt 2 ]] && error "Usage: $0 related <id> [top_k]"
            results=$(get_related_knowledge "${@:2}")
            echo "$results" | jq .
            ;;
        advanced)
            [[ $# -lt 3 ]] && error "Usage: $0 advanced <query> <filters_json> [top_k]"
            results=$(advanced_search "${@:2}")
            echo "$results" | jq .
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
