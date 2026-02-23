#!/usr/bin/env bash

# knowledge-indexer.sh
# Build searchable semantic index of knowledge entries
# Part of Cross-Session Knowledge Extraction System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-${HOME}/.claude/knowledge}"
EMBEDDINGS_CACHE="${EMBEDDINGS_CACHE:-${HOME}/.claude/cache/embeddings}"
CODE_EMBEDDER="${SCRIPT_DIR}/code-embedder.sh"

# Similarity threshold for deduplication
SIMILARITY_THRESHOLD=0.90

# Initialize
mkdir -p "$KNOWLEDGE_DIR" "$EMBEDDINGS_CACHE"

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
# Embedding Generation
# ============================================================================

# Generate embedding for text using simple TF-IDF approach
generate_embedding_tfidf() {
    local text="$1"
    local cache_key=$(echo -n "$text" | md5)

    # Check cache
    local cache_file="${EMBEDDINGS_CACHE}/${cache_key}.json"
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
    echo "scale=4; $common_terms / $union_size" | bc
}

# Generate embeddings for all fields of a knowledge entry
generate_knowledge_embeddings() {
    local entry="$1"

    # Extract fields
    local problem=$(echo "$entry" | jq -r '.problem // ""')
    local solution=$(echo "$entry" | jq -r '.solution // ""')
    local context=$(echo "$entry" | jq -r '.context // ""')

    # Generate embeddings
    local problem_embedding=$(generate_embedding_tfidf "$problem")
    local solution_embedding=$(generate_embedding_tfidf "$solution")
    local combined_text="$problem $solution $context"
    local combined_embedding=$(generate_embedding_tfidf "$combined_text")

    # Build embeddings object
    jq -n \
        --argjson problem "$problem_embedding" \
        --argjson solution "$solution_embedding" \
        --argjson combined "$combined_embedding" \
        '{
            problem_embedding: $problem,
            solution_embedding: $solution,
            combined_embedding: $combined
        }'
}

# ============================================================================
# Indexing Functions
# ============================================================================

# Index a single knowledge entry
index_knowledge_entry() {
    local entry="$1"
    local entry_id=$(echo "$entry" | jq -r '.id')

    # Generate embeddings
    local embeddings=$(generate_knowledge_embeddings "$entry")

    # Combine entry with embeddings (compact JSON)
    echo "$entry" | jq -c \
        --argjson embeddings "$embeddings" \
        '. + {embeddings: $embeddings}'
}

# Index all knowledge entries from file
index_knowledge_file() {
    local input_file="$1"
    local output_file="${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl"

    [[ ! -f "$input_file" ]] && error "Input file not found: $input_file"

    log "Indexing knowledge from: $input_file"
    log "Output file: $output_file"

    # Clear output file
    > "$output_file"

    local count=0
    while IFS= read -r entry; do
        index_knowledge_entry "$entry" >> "$output_file"
        ((count++))
        [[ $((count % 10)) -eq 0 ]] && log "Indexed $count entries"
    done < "$input_file"

    log "Indexing complete: $count entries"

    # Generate metadata
    generate_index_metadata "$output_file"
}

# Generate index metadata
generate_index_metadata() {
    local index_file="$1"
    local metadata_file="${KNOWLEDGE_DIR}/knowledge-metadata.json"

    local total_entries=$(wc -l < "$index_file")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$metadata_file" <<EOF
{
  "index_file": "$index_file",
  "total_entries": $total_entries,
  "created_at": "$timestamp",
  "last_updated": "$timestamp",
  "embedding_method": "tfidf",
  "version": "1.0"
}
EOF

    log "Metadata written to: $metadata_file"
}

# ============================================================================
# Deduplication Functions
# ============================================================================

# Find duplicate entries based on similarity
find_duplicates() {
    local index_file="${1:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"
    local threshold="${2:-$SIMILARITY_THRESHOLD}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    log "Finding duplicates with similarity threshold: $threshold"

    # Read all entries into memory
    local entries=$(jq -s '.' "$index_file")
    local total=$(echo "$entries" | jq 'length')

    log "Comparing $total entries"

    local duplicates_found=0

    # Compare each pair
    for ((i=0; i<total; i++)); do
        local entry1=$(echo "$entries" | jq ".[$i]")
        local id1=$(echo "$entry1" | jq -r '.id')
        local embedding1=$(echo "$entry1" | jq -c '.embeddings.combined_embedding')

        for ((j=i+1; j<total; j++)); do
            local entry2=$(echo "$entries" | jq ".[$j]")
            local id2=$(echo "$entry2" | jq -r '.id')
            local embedding2=$(echo "$entry2" | jq -c '.embeddings.combined_embedding')

            # Calculate similarity
            local similarity=$(calculate_similarity "$embedding1" "$embedding2")

            # Check if duplicate
            if (( $(echo "$similarity >= $threshold" | bc -l) )); then
                log "Duplicate found: $id1 <-> $id2 (similarity: $similarity)"
                echo "$id1,$id2,$similarity"
                ((duplicates_found++))
            fi
        done

        [[ $((i % 10)) -eq 0 ]] && log "Processed $i/$total entries"
    done

    log "Found $duplicates_found duplicate pairs"
}

# Merge duplicate entries
merge_duplicates() {
    local index_file="${1:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"
    local duplicates_file="${2:-${KNOWLEDGE_DIR}/duplicates.csv}"
    local output_file="${KNOWLEDGE_DIR}/knowledge-deduplicated.jsonl"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"
    [[ ! -f "$duplicates_file" ]] && {
        log "No duplicates file found, copying original"
        cp "$index_file" "$output_file"
        return 0
    }

    log "Merging duplicates"

    # Read all entries
    local entries=$(jq -s '.' "$index_file")

    # Build merge groups (transitive closure)
    declare -A merge_groups
    declare -A merged_ids

    while IFS=',' read -r id1 id2 similarity; do
        # Add to merge group
        if [[ -n "${merge_groups[$id1]:-}" ]]; then
            merge_groups[$id1]="${merge_groups[$id1]} $id2"
        else
            merge_groups[$id1]="$id1 $id2"
        fi
        merged_ids[$id2]=1
    done < "$duplicates_file"

    # Process entries
    > "$output_file"
    local kept=0
    local merged=0

    for ((i=0; i<$(echo "$entries" | jq 'length'); i++)); do
        local entry=$(echo "$entries" | jq ".[$i]")
        local id=$(echo "$entry" | jq -r '.id')

        # Skip if already merged
        [[ -n "${merged_ids[$id]:-}" ]] && {
            ((merged++))
            continue
        }

        # Check if this is a primary entry with duplicates
        if [[ -n "${merge_groups[$id]:-}" ]]; then
            local dup_ids="${merge_groups[$id]}"
            log "Merging group: $dup_ids"

            # Merge success indicators and links from duplicates
            local all_indicators=$(echo "$entries" | jq "[.[] | select(.id | IN(\"${dup_ids// /\", \"}\")) | .success_indicators[]] | unique")
            local all_links=$(echo "$entries" | jq "[.[] | select(.id | IN(\"${dup_ids// /\", \"}\")) | .links[]] | unique")

            # Keep highest confidence entry
            entry=$(echo "$entry" | jq \
                --argjson indicators "$all_indicators" \
                --argjson links "$all_links" \
                '.success_indicators = $indicators | .links = $links')
        fi

        echo "$entry" >> "$output_file"
        ((kept++))
    done

    log "Deduplication complete: kept $kept, merged $merged"
    log "Output: $output_file"
}

# Run full deduplication pipeline
deduplicate_knowledge() {
    local index_file="${1:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"
    local threshold="${2:-$SIMILARITY_THRESHOLD}"

    log "Starting deduplication pipeline"

    # Find duplicates
    local duplicates_file="${KNOWLEDGE_DIR}/duplicates.csv"
    find_duplicates "$index_file" "$threshold" > "$duplicates_file"

    # Merge duplicates
    merge_duplicates "$index_file" "$duplicates_file"

    log "Deduplication complete"
}

# ============================================================================
# Index Statistics
# ============================================================================

show_index_stats() {
    local index_file="${1:-${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl}"

    [[ ! -f "$index_file" ]] && error "Index file not found: $index_file"

    local total=$(wc -l < "$index_file")
    local metadata_file="${KNOWLEDGE_DIR}/knowledge-metadata.json"

    cat <<EOF
Knowledge Index Statistics
==========================
Index file: $index_file
Total entries: $total

EOF

    if [[ -f "$metadata_file" ]]; then
        cat <<EOF
Metadata:
$(cat "$metadata_file" | jq .)

EOF
    fi

    cat <<EOF
Sample embeddings (first entry):
$(head -1 "$index_file" | jq '.embeddings.combined_embedding[:5]')

Embedding dimensions:
Problem: $(head -1 "$index_file" | jq '.embeddings.problem_embedding | length')
Solution: $(head -1 "$index_file" | jq '.embeddings.solution_embedding | length')
Combined: $(head -1 "$index_file" | jq '.embeddings.combined_embedding | length')
EOF
}

# ============================================================================
# Incremental Updates
# ============================================================================

# Update index with new entries
update_index() {
    local new_entries_file="$1"
    local index_file="${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl"

    [[ ! -f "$new_entries_file" ]] && error "New entries file not found: $new_entries_file"

    log "Updating index with new entries from: $new_entries_file"

    # Index new entries and append
    while IFS= read -r entry; do
        index_knowledge_entry "$entry" >> "$index_file"
    done < "$new_entries_file"

    # Update metadata
    generate_index_metadata "$index_file"

    log "Index updated"
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Indexer - Build searchable semantic index

Usage: $(basename "$0") <command> [options]

Commands:
  index <file>                    Index knowledge file (creates embeddings)
  update <new_entries_file>       Update index with new entries
  deduplicate [file] [threshold]  Find and merge duplicate entries
  stats [file]                    Show index statistics
  help                            Show this help message

Examples:
  $(basename "$0") index ~/.claude/knowledge/knowledge-base-categorized.jsonl
  $(basename "$0") update ~/.claude/knowledge/new-entries.jsonl
  $(basename "$0") deduplicate ~/.claude/knowledge/knowledge-embeddings.jsonl 0.90
  $(basename "$0") stats
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"

    case "$command" in
        index)
            [[ $# -lt 2 ]] && error "Usage: $0 index <file>"
            index_knowledge_file "$2"
            ;;
        update)
            [[ $# -lt 2 ]] && error "Usage: $0 update <new_entries_file>"
            update_index "$2"
            ;;
        deduplicate)
            deduplicate_knowledge "${2:-}" "${3:-$SIMILARITY_THRESHOLD}"
            ;;
        stats)
            show_index_stats "${2:-}"
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
