#!/usr/bin/env bash

# code-search.sh
# Semantic search engine for code
# Part of Deep Codebase Understanding System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_DIR="${HOME}/.claude/indexes"

# Dependencies
CODE_EMBEDDER="${SCRIPT_DIR}/code-embedder.sh"

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

# Generate unique hash for a directory path
path_hash() {
    local path="$1"
    echo -n "$path" | md5 | cut -c1-16
}

# Get index directory for a codebase
get_index_path() {
    local codebase_path="$1"
    local hash
    hash=$(path_hash "$codebase_path")
    echo "${INDEX_DIR}/${hash}"
}

# Check if index exists
index_exists() {
    local codebase_path="$1"
    local index_path
    index_path=$(get_index_path "$codebase_path")
    [[ -f "${index_path}/metadata.json" ]]
}

# ============================================================================
# Vector Math Functions
# ============================================================================

# Calculate cosine similarity between two vectors
cosine_similarity() {
    local vec1="$1"
    local vec2="$2"

    # Parse vectors
    IFS=',' read -ra v1 <<< "$vec1"
    IFS=',' read -ra v2 <<< "$vec2"

    # Check dimensions match
    if [[ ${#v1[@]} -ne ${#v2[@]} ]]; then
        echo "0"
        return 1
    fi

    # Calculate dot product and magnitudes
    local dot_product=0
    local mag1=0
    local mag2=0

    for i in "${!v1[@]}"; do
        # Dot product
        local prod
        prod=$(echo "scale=6; ${v1[$i]} * ${v2[$i]}" | bc)
        dot_product=$(echo "scale=6; $dot_product + $prod" | bc)

        # Magnitude 1
        local sq1
        sq1=$(echo "scale=6; ${v1[$i]} * ${v1[$i]}" | bc)
        mag1=$(echo "scale=6; $mag1 + $sq1" | bc)

        # Magnitude 2
        local sq2
        sq2=$(echo "scale=6; ${v2[$i]} * ${v2[$i]}" | bc)
        mag2=$(echo "scale=6; $mag2 + $sq2" | bc)
    done

    # Calculate magnitudes (square root)
    mag1=$(echo "scale=6; sqrt($mag1)" | bc)
    mag2=$(echo "scale=6; sqrt($mag2)" | bc)

    # Calculate cosine similarity
    if [[ "$mag1" == "0" ]] || [[ "$mag2" == "0" ]]; then
        echo "0"
    else
        echo "scale=6; $dot_product / ($mag1 * $mag2)" | bc
    fi
}

# ============================================================================
# Search Functions
# ============================================================================

# Generate embedding for query text
generate_query_embedding() {
    local query="$1"

    # Use code embedder to generate embedding
    source "$CODE_EMBEDDER"
    generate_embedding "$query"
}

# Search code by semantic similarity
search_code() {
    local codebase_path="$1"
    local query="$2"
    local top_k="${3:-10}"
    local filter_type="${4:-}"
    local filter_pattern="${5:-}"

    # Resolve absolute path
    codebase_path=$(cd "$codebase_path" && pwd)

    # Check index exists
    if ! index_exists "$codebase_path"; then
        error "Index not found for: $codebase_path"
    fi

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local embeddings_file="${index_path}/embeddings.jsonl"

    if [[ ! -f "$embeddings_file" ]]; then
        error "Embeddings file not found: $embeddings_file"
    fi

    log "Searching for: $query"

    # Generate query embedding
    local query_embedding
    query_embedding=$(generate_query_embedding "$query")

    # Search embeddings
    local results_temp
    results_temp=$(mktemp)

    while IFS= read -r line; do
        # Parse embedding
        local code_embedding
        code_embedding=$(echo "$line" | jq -r '.embedding | map(tostring) | join(",")')

        # Calculate similarity
        local similarity
        similarity=$(cosine_similarity "$query_embedding" "$code_embedding")

        # Add similarity score to result
        echo "$line" | jq --argjson score "$similarity" '. + {score: $score}' >> "$results_temp"

    done < "$embeddings_file"

    # Filter by type if specified
    local filtered_results="$results_temp"
    if [[ -n "$filter_type" ]]; then
        local temp_filter
        temp_filter=$(mktemp)
        jq --arg type "$filter_type" 'select(.type == $type)' "$results_temp" > "$temp_filter"
        filtered_results="$temp_filter"
    fi

    # Filter by pattern if specified
    if [[ -n "$filter_pattern" ]]; then
        local temp_filter2
        temp_filter2=$(mktemp)
        jq --arg pattern "$filter_pattern" 'select(.path | contains($pattern))' "$filtered_results" > "$temp_filter2"
        filtered_results="$temp_filter2"
    fi

    # Sort by score and get top-k
    jq -s --argjson k "$top_k" \
        'sort_by(-.score) | .[:$k]' \
        "$filtered_results"

    # Cleanup
    rm -f "$results_temp" "$filtered_results"
}

# Search for a function by name
search_function() {
    local codebase_path="$1"
    local function_name="$2"

    codebase_path=$(cd "$codebase_path" && pwd)

    if ! index_exists "$codebase_path"; then
        error "Index not found for: $codebase_path"
    fi

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local embeddings_file="${index_path}/embeddings.jsonl"

    log "Searching for function: $function_name"

    # Search by name
    jq --arg name "$function_name" \
        'select(.type == "function" and .name == $name)' \
        "$embeddings_file"
}

# Find similar code to a given file
search_similar_to_file() {
    local codebase_path="$1"
    local filepath="$2"
    local top_k="${3:-10}"

    codebase_path=$(cd "$codebase_path" && pwd)

    if ! index_exists "$codebase_path"; then
        error "Index not found for: $codebase_path"
    fi

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local embeddings_file="${index_path}/embeddings.jsonl"

    log "Finding code similar to: $filepath"

    # Get embeddings for the file
    local file_embeddings
    file_embeddings=$(jq --arg path "$filepath" \
        'select(.metadata.file == $path)' \
        "$embeddings_file")

    if [[ -z "$file_embeddings" ]]; then
        error "File not found in index: $filepath"
    fi

    # Get first embedding from file
    local reference_embedding
    reference_embedding=$(echo "$file_embeddings" | head -1 | jq -r '.embedding | map(tostring) | join(",")')

    # Search for similar embeddings
    local results_temp
    results_temp=$(mktemp)

    while IFS= read -r line; do
        # Skip same file
        local current_file
        current_file=$(echo "$line" | jq -r '.metadata.file')
        if [[ "$current_file" == "$filepath" ]]; then
            continue
        fi

        # Calculate similarity
        local code_embedding
        code_embedding=$(echo "$line" | jq -r '.embedding | map(tostring) | join(",")')
        local similarity
        similarity=$(cosine_similarity "$reference_embedding" "$code_embedding")

        # Add similarity score
        echo "$line" | jq --argjson score "$similarity" '. + {score: $score}' >> "$results_temp"

    done < "$embeddings_file"

    # Sort by score and get top-k
    jq -s --argjson k "$top_k" \
        'sort_by(-.score) | .[:$k]' \
        "$results_temp"

    rm -f "$results_temp"
}

# Hybrid search: semantic + keyword pattern
search_by_pattern() {
    local codebase_path="$1"
    local query="$2"
    local pattern="$3"
    local top_k="${4:-10}"

    codebase_path=$(cd "$codebase_path" && pwd)

    log "Hybrid search: query='$query', pattern='$pattern'"

    # First, do semantic search
    local semantic_results
    semantic_results=$(search_code "$codebase_path" "$query" 100)

    # Then filter by pattern
    echo "$semantic_results" | jq --arg pattern "$pattern" \
        --argjson k "$top_k" \
        'map(select(.content | test($pattern))) | .[:$k]'
}

# Search with context extraction
search_with_context() {
    local codebase_path="$1"
    local query="$2"
    local top_k="${3:-10}"
    local context_lines="${4:-5}"

    codebase_path=$(cd "$codebase_path" && pwd)

    # Perform search
    local results
    results=$(search_code "$codebase_path" "$query" "$top_k")

    # Add context for each result
    echo "$results" | jq -c '.[]' | while IFS= read -r result; do
        local filepath
        local line_num
        filepath=$(echo "$result" | jq -r '.metadata.file')
        line_num=$(echo "$result" | jq -r '.metadata.line')

        # Extract context
        local context=""
        if [[ -f "$filepath" ]]; then
            local start_line=$((line_num - context_lines))
            [[ $start_line -lt 1 ]] && start_line=1
            local end_line=$((line_num + context_lines))

            context=$(sed -n "${start_line},${end_line}p" "$filepath" | cat -n)
        fi

        # Add context to result
        echo "$result" | jq --arg ctx "$context" '. + {context: $ctx}'
    done | jq -s '.'
}

# ============================================================================
# Formatting Functions
# ============================================================================

# Format search results as markdown
format_results_markdown() {
    local results="$1"

    echo "# Search Results"
    echo ""

    echo "$results" | jq -r '.[] |
        "## \(.name) (\(.type))\n",
        "**File:** `\(.metadata.file):\(.metadata.line)`\n",
        "**Score:** \(.score)\n",
        "**Lines of Code:** \(.metadata.loc)\n",
        "\n```\n\(.content)\n```\n"
    '
}

# Format search results as JSON (pretty)
format_results_json() {
    local results="$1"
    echo "$results" | jq '.'
}

# Format search results as table
format_results_table() {
    local results="$1"

    printf "%-50s %-15s %-50s %s\n" "Name" "Type" "File" "Score"
    printf "%s\n" "$(printf '=%.0s' {1..130})"

    echo "$results" | jq -r '.[] |
        "\(.name)|\(.type)|\(.metadata.file)|\(.score)"
    ' | while IFS='|' read -r name type file score; do
        printf "%-50s %-15s %-50s %.3f\n" \
            "${name:0:50}" \
            "${type:0:15}" \
            "${file:0:50}" \
            "$score"
    done
}

# ============================================================================
# CLI Interface
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> <codebase> [options]

Commands:
    search <codebase> <query> [top_k]
        Semantic search for code

    function <codebase> <name>
        Find function by exact name

    similar <codebase> <filepath> [top_k]
        Find code similar to given file

    pattern <codebase> <query> <regex> [top_k]
        Hybrid semantic + keyword search

    context <codebase> <query> [top_k] [context_lines]
        Search with surrounding code context

Options:
    --format <format>    Output format: json (default), markdown, table
    --type <type>        Filter by type: function, class, file
    --filter <pattern>   Filter results by file path pattern
    -h, --help           Show this help message

Examples:
    # Basic semantic search
    $(basename "$0") search ~/my-project "authentication logic"

    # Find function by name
    $(basename "$0") function ~/my-project "authenticate"

    # Find similar code
    $(basename "$0") similar ~/my-project auth/login.py

    # Hybrid search
    $(basename "$0") pattern ~/my-project "database query" "SELECT.*FROM"

    # Search with context
    $(basename "$0") context ~/my-project "error handling" 10 5

    # Formatted output
    $(basename "$0") search ~/my-project "API endpoint" --format markdown

EOF
}

main() {
    local format="json"
    local filter_type=""
    local filter_pattern=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            --type)
                filter_type="$2"
                shift 2
                ;;
            --filter)
                filter_pattern="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            search|function|similar|pattern|context)
                local command="$1"
                shift
                break
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Execute command
    local results=""
    case "${command:-}" in
        search)
            [[ $# -ge 2 ]] || error "Usage: search <codebase> <query> [top_k]"
            results=$(search_code "$1" "$2" "${3:-10}" "$filter_type" "$filter_pattern")
            ;;
        function)
            [[ $# -ge 2 ]] || error "Usage: function <codebase> <name>"
            results=$(search_function "$1" "$2")
            ;;
        similar)
            [[ $# -ge 2 ]] || error "Usage: similar <codebase> <filepath> [top_k]"
            results=$(search_similar_to_file "$1" "$2" "${3:-10}")
            ;;
        pattern)
            [[ $# -ge 3 ]] || error "Usage: pattern <codebase> <query> <regex> [top_k]"
            results=$(search_by_pattern "$1" "$2" "$3" "${4:-10}")
            ;;
        context)
            [[ $# -ge 2 ]] || error "Usage: context <codebase> <query> [top_k] [context_lines]"
            results=$(search_with_context "$1" "$2" "${3:-10}" "${4:-5}")
            ;;
        *)
            usage
            exit 1
            ;;
    esac

    # Format output
    case "$format" in
        json)
            format_results_json "$results"
            ;;
        markdown)
            format_results_markdown "$results"
            ;;
        table)
            format_results_table "$results"
            ;;
        *)
            error "Unknown format: $format"
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
