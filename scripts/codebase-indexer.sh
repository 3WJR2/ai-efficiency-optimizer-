#!/usr/bin/env bash

# codebase-indexer.sh
# Build and maintain searchable code index
# Part of Deep Codebase Understanding System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_DIR="${HOME}/.claude/indexes"
DATA_DIR="${HOME}/.claude/data"

# Dependencies
CODE_EMBEDDER="${SCRIPT_DIR}/code-embedder.sh"

# Initialize
mkdir -p "$INDEX_DIR" "$DATA_DIR"

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

# ============================================================================
# Index Management Functions
# ============================================================================

# Initialize a new index
init_index() {
    local codebase_path="$1"
    local index_path
    index_path=$(get_index_path "$codebase_path")

    log "Initializing index at: $index_path"
    mkdir -p "$index_path"

    # Create metadata file
    jq -n \
        --arg codebase "$codebase_path" \
        --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg version "1.0.0" \
        '{
            codebase_path: $codebase,
            created_at: $created,
            updated_at: $created,
            version: $version,
            stats: {
                files_indexed: 0,
                total_definitions: 0,
                total_loc: 0,
                last_scan: null
            },
            config: {
                excluded_dirs: ["node_modules", "venv", ".git", "build", "dist", "target", ".next", ".cache", "__pycache__", "vendor"],
                max_file_size_kb: 1024
            }
        }' > "${index_path}/metadata.json"

    log "Index initialized"
}

# Check if index exists
index_exists() {
    local codebase_path="$1"
    local index_path
    index_path=$(get_index_path "$codebase_path")
    [[ -f "${index_path}/metadata.json" ]]
}

# Get index metadata
get_index_metadata() {
    local codebase_path="$1"
    local index_path
    index_path=$(get_index_path "$codebase_path")

    if [[ ! -f "${index_path}/metadata.json" ]]; then
        echo "{}"
        return 1
    fi

    cat "${index_path}/metadata.json"
}

# Update index metadata
update_index_metadata() {
    local codebase_path="$1"
    local key="$2"
    local value="$3"
    local index_path
    index_path=$(get_index_path "$codebase_path")

    local temp
    temp=$(mktemp)

    jq --arg key "$key" --arg val "$value" \
        '.[$key] = $val | .updated_at = (now | todateiso8601)' \
        "${index_path}/metadata.json" > "$temp"

    mv "$temp" "${index_path}/metadata.json"
}

# ============================================================================
# File Tracking Functions
# ============================================================================

# Get list of files to index
get_indexable_files() {
    local codebase_path="$1"
    local index_path
    index_path=$(get_index_path "$codebase_path")

    # Get excluded directories from metadata
    local excluded_dirs
    excluded_dirs=$(jq -r '.config.excluded_dirs | join("|")' "${index_path}/metadata.json")

    # Get max file size
    local max_size_kb
    max_size_kb=$(jq -r '.config.max_file_size_kb' "${index_path}/metadata.json")

    # Find files
    find "$codebase_path" -type f \
        \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \
        -o -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \
        -o -name "*.rb" -o -name "*.java" -o -name "*.go" -o -name "*.rs" \
        -o -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \
        -o -name "*.php" -o -name "*.swift" -o -name "*.kt" \) \
        2>/dev/null | \
        grep -vE "/(${excluded_dirs})/" | \
        while read -r file; do
            # Check file size
            local size_kb
            size_kb=$(du -k "$file" | cut -f1)
            if [[ $size_kb -le $max_size_kb ]]; then
                echo "$file"
            fi
        done
}

# Get file modification time
get_file_mtime() {
    local filepath="$1"
    if [[ -f "$filepath" ]]; then
        stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null
    else
        echo "0"
    fi
}

# Check if file needs re-indexing
needs_reindex() {
    local filepath="$1"
    local index_path="$2"
    local file_tracker="${index_path}/file_tracker.json"

    # If tracker doesn't exist, need to index
    [[ -f "$file_tracker" ]] || return 0

    # Get current modification time
    local current_mtime
    current_mtime=$(get_file_mtime "$filepath")

    # Get stored modification time
    local stored_mtime
    stored_mtime=$(jq -r --arg path "$filepath" '.[$path] // "0"' "$file_tracker" 2>/dev/null || echo "0")

    # Compare
    [[ "$current_mtime" != "$stored_mtime" ]]
}

# Update file tracker
update_file_tracker() {
    local filepath="$1"
    local index_path="$2"
    local file_tracker="${index_path}/file_tracker.json"

    # Initialize if doesn't exist
    [[ -f "$file_tracker" ]] || echo "{}" > "$file_tracker"

    # Get modification time
    local mtime
    mtime=$(get_file_mtime "$filepath")

    # Update tracker
    local temp
    temp=$(mktemp)
    jq --arg path "$filepath" --arg mtime "$mtime" \
        '.[$path] = $mtime' \
        "$file_tracker" > "$temp"
    mv "$temp" "$file_tracker"
}

# ============================================================================
# Indexing Functions
# ============================================================================

# Index a codebase (full scan)
index_codebase() {
    local codebase_path="$1"
    local force="${2:-false}"

    # Resolve absolute path
    codebase_path=$(cd "$codebase_path" && pwd)

    log "Indexing codebase: $codebase_path"

    # Initialize index if doesn't exist
    if ! index_exists "$codebase_path"; then
        init_index "$codebase_path"
    elif [[ "$force" == "true" ]]; then
        log "Force rebuild requested, reinitializing index"
        local index_path
        index_path=$(get_index_path "$codebase_path")
        rm -rf "$index_path"
        init_index "$codebase_path"
    fi

    local index_path
    index_path=$(get_index_path "$codebase_path")

    # Get files to index
    log "Scanning for files..."
    local files
    files=$(get_indexable_files "$codebase_path")
    local file_count
    file_count=$(echo "$files" | wc -l | tr -d ' ')

    if [[ -z "$files" ]] || [[ "$file_count" -eq 0 ]]; then
        log "No files found to index"
        return 0
    fi

    log "Found $file_count files to process"

    # Embed files
    local embeddings_file="${index_path}/embeddings.jsonl"
    local temp_embeddings
    temp_embeddings=$(mktemp)

    local processed=0
    local skipped=0

    while IFS= read -r file; do
        # Check if needs reindexing
        if ! needs_reindex "$file" "$index_path"; then
            ((skipped++))
            continue
        fi

        # Embed file
        if "$CODE_EMBEDDER" file "$file" >> "$temp_embeddings" 2>/dev/null; then
            update_file_tracker "$file" "$index_path"
            ((processed++))

            if ((processed % 10 == 0)); then
                log "Processed $processed/$file_count files..."
            fi
        else
            log "Warning: Failed to embed $file"
        fi
    done <<< "$files"

    # Merge with existing embeddings (if any)
    if [[ -f "$embeddings_file" ]]; then
        # Remove old embeddings for reindexed files
        local files_to_remove
        files_to_remove=$(echo "$files" | while read -r f; do
            echo "$f:"
        done | paste -sd '|' -)

        grep -vE "^{\"path\":\"($files_to_remove)" "$embeddings_file" > "${embeddings_file}.tmp" || true
        cat "$temp_embeddings" >> "${embeddings_file}.tmp"
        mv "${embeddings_file}.tmp" "$embeddings_file"
    else
        mv "$temp_embeddings" "$embeddings_file"
    fi

    rm -f "$temp_embeddings"

    # Update statistics
    local total_defs
    total_defs=$(wc -l < "$embeddings_file" | tr -d ' ')
    local total_loc
    total_loc=$(jq -s 'map(.metadata.loc) | add' "$embeddings_file")

    local temp_meta
    temp_meta=$(mktemp)
    jq --argjson files "$file_count" \
       --argjson defs "$total_defs" \
       --argjson loc "$total_loc" \
       --arg scan "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.stats.files_indexed = $files |
        .stats.total_definitions = $defs |
        .stats.total_loc = $loc |
        .stats.last_scan = $scan |
        .updated_at = (now | todateiso8601)' \
        "${index_path}/metadata.json" > "$temp_meta"
    mv "$temp_meta" "${index_path}/metadata.json"

    log "Indexing complete: $processed files processed, $skipped skipped"
    log "Total definitions: $total_defs"
    log "Index path: $index_path"
}

# Update index (incremental)
update_index() {
    local codebase_path="$1"

    # Resolve absolute path
    codebase_path=$(cd "$codebase_path" && pwd)

    if ! index_exists "$codebase_path"; then
        log "Index doesn't exist, performing full indexing"
        index_codebase "$codebase_path"
        return $?
    fi

    log "Updating index for: $codebase_path"

    # Same as full index, but needs_reindex will skip unchanged files
    index_codebase "$codebase_path" "false"
}

# Rebuild index from scratch
rebuild_index() {
    local codebase_path="$1"
    codebase_path=$(cd "$codebase_path" && pwd)

    log "Rebuilding index for: $codebase_path"
    index_codebase "$codebase_path" "true"
}

# ============================================================================
# Index Query Functions
# ============================================================================

# Get index statistics
get_index_stats() {
    local codebase_path="$1"
    codebase_path=$(cd "$codebase_path" && pwd)

    if ! index_exists "$codebase_path"; then
        echo "Index not found for: $codebase_path"
        return 1
    fi

    local index_path
    index_path=$(get_index_path "$codebase_path")

    log "Index Statistics"
    log "================"

    local metadata="${index_path}/metadata.json"
    local embeddings="${index_path}/embeddings.jsonl"

    # Basic stats
    jq -r '
        "Codebase: \(.codebase_path)",
        "Created: \(.created_at)",
        "Updated: \(.updated_at)",
        "",
        "Files indexed: \(.stats.files_indexed)",
        "Definitions: \(.stats.total_definitions)",
        "Lines of code: \(.stats.total_loc)",
        "Last scan: \(.stats.last_scan // "never")",
        ""
    ' "$metadata"

    # File size
    if [[ -f "$embeddings" ]]; then
        local size
        size=$(du -h "$embeddings" | cut -f1)
        echo "Index size: $size"
    fi

    # Breakdown by type
    if [[ -f "$embeddings" ]]; then
        echo ""
        echo "Definitions by type:"
        jq -r '.type' "$embeddings" | sort | uniq -c | sort -rn
    fi

    # Top files by definitions
    echo ""
    echo "Top 10 files by definitions:"
    jq -r '.metadata.file' "$embeddings" | sort | uniq -c | sort -rn | head -10
}

# List all indexes
list_indexes() {
    log "Available Indexes"
    log "================="

    if [[ ! -d "$INDEX_DIR" ]] || [[ -z "$(ls -A "$INDEX_DIR" 2>/dev/null)" ]]; then
        echo "No indexes found"
        return 0
    fi

    for index_dir in "$INDEX_DIR"/*; do
        if [[ -f "${index_dir}/metadata.json" ]]; then
            local codebase
            local updated
            local files
            local defs

            codebase=$(jq -r '.codebase_path' "${index_dir}/metadata.json")
            updated=$(jq -r '.updated_at' "${index_dir}/metadata.json")
            files=$(jq -r '.stats.files_indexed' "${index_dir}/metadata.json")
            defs=$(jq -r '.stats.total_definitions' "${index_dir}/metadata.json")

            echo ""
            echo "Codebase: $codebase"
            echo "  Updated: $updated"
            echo "  Files: $files, Definitions: $defs"
        fi
    done
}

# Delete an index
delete_index() {
    local codebase_path="$1"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")

    if [[ ! -d "$index_path" ]]; then
        log "Index not found for: $codebase_path"
        return 1
    fi

    log "Deleting index: $index_path"
    rm -rf "$index_path"
    log "Index deleted"
}

# ============================================================================
# CLI Interface
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
    index <directory>           Index a codebase (full scan)
    update <directory>          Update index (incremental)
    rebuild <directory>         Rebuild index from scratch
    stats <directory>           Show index statistics
    list                        List all indexes
    delete <directory>          Delete an index

Options:
    -h, --help                  Show this help message

Examples:
    # Index a codebase
    $(basename "$0") index ~/my-project

    # Update existing index
    $(basename "$0") update ~/my-project

    # Show statistics
    $(basename "$0") stats ~/my-project

    # List all indexes
    $(basename "$0") list

    # Delete index
    $(basename "$0") delete ~/my-project

EOF
}

main() {
    # Parse command
    case "${1:-}" in
        index)
            [[ $# -ge 2 ]] || error "Missing directory argument"
            index_codebase "$2"
            ;;
        update)
            [[ $# -ge 2 ]] || error "Missing directory argument"
            update_index "$2"
            ;;
        rebuild)
            [[ $# -ge 2 ]] || error "Missing directory argument"
            rebuild_index "$2"
            ;;
        stats)
            [[ $# -ge 2 ]] || error "Missing directory argument"
            get_index_stats "$2"
            ;;
        list)
            list_indexes
            ;;
        delete)
            [[ $# -ge 2 ]] || error "Missing directory argument"
            delete_index "$2"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
