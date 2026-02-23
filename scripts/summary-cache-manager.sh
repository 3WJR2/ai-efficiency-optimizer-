#!/usr/bin/env bash
#
# summary-cache-manager.sh - Cache management for conversation summaries
#
# Part of the Conversation Summarization System
# Manages caching of summaries to avoid recomputation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUMMARIES_DIR="$HOME/.claude/summaries"
CACHE_FILE="$SUMMARIES_DIR/session-summaries.jsonl"
INDEX_FILE="$SUMMARIES_DIR/summary-index.json"
METADATA_FILE="$SUMMARIES_DIR/metadata.json"

# Initialize cache structure
init_cache() {
    mkdir -p "$SUMMARIES_DIR"

    # Create cache file if it doesn't exist
    if [ ! -f "$CACHE_FILE" ]; then
        touch "$CACHE_FILE"
    fi

    # Create index if it doesn't exist
    if [ ! -f "$INDEX_FILE" ]; then
        echo '{}' > "$INDEX_FILE"
    fi

    # Create metadata if it doesn't exist
    if [ ! -f "$METADATA_FILE" ]; then
        jq -n '{
            created: (now | strftime("%Y-%m-%d %H:%M:%S")),
            last_updated: (now | strftime("%Y-%m-%d %H:%M:%S")),
            total_summaries: 0,
            cache_size_bytes: 0
        }' > "$METADATA_FILE"
    fi
}

# Generate cache key
generate_cache_key() {
    local session_id="$1"
    local detail_level="$2"
    echo "${session_id}:${detail_level}"
}

# Lookup summary in cache
lookup_cache() {
    local session_id="$1"
    local detail_level="$2"

    init_cache

    local cache_key=$(generate_cache_key "$session_id" "$detail_level")

    # Check index first
    local line_num=$(jq -r --arg key "$cache_key" '.[$key]' "$INDEX_FILE")

    if [ "$line_num" = "null" ] || [ -z "$line_num" ]; then
        return 1
    fi

    # Retrieve from cache file
    local entry=$(sed -n "${line_num}p" "$CACHE_FILE")

    if [ -z "$entry" ]; then
        return 1
    fi

    # Extract summary text
    echo "$entry" | jq -r '.summary'
}

# Cache a summary
cache_summary() {
    local session_id="$1"
    local detail_level="$2"
    local summary="$3"
    local metadata="${4:-{}}"

    init_cache

    local cache_key=$(generate_cache_key "$session_id" "$detail_level")
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")

    # Create cache entry
    local entry=$(jq -n \
        --arg session_id "$session_id" \
        --arg detail_level "$detail_level" \
        --arg summary "$summary" \
        --arg timestamp "$timestamp" \
        --argjson metadata "$metadata" \
        '{
            session_id: $session_id,
            detail_level: $detail_level,
            summary: $summary,
            cached_at: $timestamp,
            metadata: $metadata
        }')

    # Append to cache file
    echo "$entry" >> "$CACHE_FILE"

    # Update index
    local line_num=$(wc -l < "$CACHE_FILE" | tr -d ' ')
    local updated_index=$(jq --arg key "$cache_key" --arg line "$line_num" '.[$key] = $line' "$INDEX_FILE")
    echo "$updated_index" > "$INDEX_FILE"

    # Update metadata
    update_cache_metadata
}

# Update cache metadata
update_cache_metadata() {
    local total=$(wc -l < "$CACHE_FILE" | tr -d ' ')
    local size=$(du -b "$CACHE_FILE" 2>/dev/null | cut -f1 || stat -f%z "$CACHE_FILE" 2>/dev/null || echo 0)
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")

    jq --arg total "$total" \
       --arg size "$size" \
       --arg timestamp "$timestamp" \
       '.total_summaries = ($total | tonumber) |
        .cache_size_bytes = ($size | tonumber) |
        .last_updated = $timestamp' \
       "$METADATA_FILE" > "$METADATA_FILE.tmp" && mv "$METADATA_FILE.tmp" "$METADATA_FILE"
}

# Get summary (with caching)
get_summary() {
    local session_id="$1"
    local detail_level="${2:-standard}"
    local conversation_file="${3:-}"
    local force_regenerate="${4:-false}"

    init_cache

    # Check cache unless force regenerate
    if [ "$force_regenerate" != "true" ]; then
        local cached=$(lookup_cache "$session_id" "$detail_level")
        if [ $? -eq 0 ] && [ -n "$cached" ]; then
            echo "$cached"
            return 0
        fi
    fi

    # Generate new summary
    if [ -z "$conversation_file" ]; then
        echo "Error: conversation_file required for new summary generation" >&2
        return 1
    fi

    source "$SCRIPT_DIR/conversation-summarizer.sh"
    local summary=$(summarize_session "$session_id" "$detail_level" "$conversation_file")

    # Cache the result
    cache_summary "$session_id" "$detail_level" "$summary"

    echo "$summary"
}

# Invalidate cache entry
invalidate_cache() {
    local session_id="$1"
    local detail_level="${2:-all}"

    init_cache

    if [ "$detail_level" = "all" ]; then
        # Invalidate all detail levels for this session
        for level in brief standard detailed; do
            local cache_key=$(generate_cache_key "$session_id" "$level")
            local updated_index=$(jq --arg key "$cache_key" 'del(.[$key])' "$INDEX_FILE")
            echo "$updated_index" > "$INDEX_FILE"
        done
    else
        # Invalidate specific detail level
        local cache_key=$(generate_cache_key "$session_id" "$detail_level")
        local updated_index=$(jq --arg key "$cache_key" 'del(.[$key])' "$INDEX_FILE")
        echo "$updated_index" > "$INDEX_FILE"
    fi

    echo "Cache invalidated for session: $session_id ($detail_level)"
}

# Clear entire cache
clear_cache() {
    init_cache

    # Backup before clearing
    local backup_file="$SUMMARIES_DIR/backup-$(date +%Y%m%d-%H%M%S)"
    if [ -f "$CACHE_FILE" ]; then
        cp "$CACHE_FILE" "$backup_file.jsonl"
    fi

    # Clear files
    echo -n > "$CACHE_FILE"
    echo '{}' > "$INDEX_FILE"

    # Reset metadata
    jq '.total_summaries = 0 | .cache_size_bytes = 0 | .last_updated = (now | strftime("%Y-%m-%d %H:%M:%S"))' \
       "$METADATA_FILE" > "$METADATA_FILE.tmp" && mv "$METADATA_FILE.tmp" "$METADATA_FILE"

    echo "Cache cleared. Backup saved to: $backup_file.jsonl"
}

# Get cache statistics
cache_stats() {
    init_cache

    local total=$(jq -r '.total_summaries' "$METADATA_FILE")
    local size=$(jq -r '.cache_size_bytes' "$METADATA_FILE")
    local last_updated=$(jq -r '.last_updated' "$METADATA_FILE")

    # Calculate size in human-readable format
    local size_kb=$(echo "scale=2; $size / 1024" | bc)
    local size_mb=$(echo "scale=2; $size / 1048576" | bc)

    # Count by detail level
    local brief=$(jq -r 'keys[] | select(endswith(":brief"))' "$INDEX_FILE" | wc -l | tr -d ' ')
    local standard=$(jq -r 'keys[] | select(endswith(":standard"))' "$INDEX_FILE" | wc -l | tr -d ' ')
    local detailed=$(jq -r 'keys[] | select(endswith(":detailed"))' "$INDEX_FILE" | wc -l | tr -d ' ')

    cat <<EOF
Summary Cache Statistics
========================

Total summaries:  $total
Cache size:       ${size_kb} KB (${size_mb} MB)
Last updated:     $last_updated

By detail level:
  Brief:     $brief
  Standard:  $standard
  Detailed:  $detailed

Cache files:
  Summaries: $CACHE_FILE
  Index:     $INDEX_FILE
  Metadata:  $METADATA_FILE
EOF
}

# List cached sessions
list_cached_sessions() {
    init_cache

    echo "Cached Sessions:"
    echo "================"
    echo ""

    jq -r 'keys[]' "$INDEX_FILE" | while read -r cache_key; do
        local session_id=$(echo "$cache_key" | cut -d: -f1)
        local detail_level=$(echo "$cache_key" | cut -d: -f2)
        local line_num=$(jq -r --arg key "$cache_key" '.[$key]' "$INDEX_FILE")

        if [ -n "$line_num" ] && [ "$line_num" != "null" ]; then
            local entry=$(sed -n "${line_num}p" "$CACHE_FILE")
            local cached_at=$(echo "$entry" | jq -r '.cached_at')
            local tokens=$(echo "$entry" | jq -r '.summary' | wc -c | awk '{print int($1/4)}')

            printf "%-40s %-10s %6s tokens  %s\n" "$session_id" "$detail_level" "$tokens" "$cached_at"
        fi
    done
}

# Compact cache (remove invalidated entries)
compact_cache() {
    init_cache

    local temp_file="$SUMMARIES_DIR/session-summaries.jsonl.tmp"
    local new_index="{}"

    echo "Compacting cache..."

    # Get valid cache keys from index
    local line_count=0
    jq -r 'keys[]' "$INDEX_FILE" | while read -r cache_key; do
        local line_num=$(jq -r --arg key "$cache_key" '.[$key]' "$INDEX_FILE")

        if [ -n "$line_num" ] && [ "$line_num" != "null" ]; then
            # Copy entry to new file
            local entry=$(sed -n "${line_num}p" "$CACHE_FILE")
            if [ -n "$entry" ]; then
                echo "$entry" >> "$temp_file"
                ((line_count++))

                # Update index with new line number
                new_index=$(echo "$new_index" | jq --arg key "$cache_key" --arg line "$line_count" '.[$key] = $line')
            fi
        fi
    done

    # Replace old files with compacted versions
    if [ -f "$temp_file" ]; then
        mv "$temp_file" "$CACHE_FILE"
    fi

    echo "$new_index" > "$INDEX_FILE"

    # Update metadata
    update_cache_metadata

    echo "Cache compacted. $line_count entries retained."
}

# CLI interface
main() {
    local command="${1:-}"

    case "$command" in
        init)
            init_cache
            echo "Cache initialized at: $SUMMARIES_DIR"
            ;;
        get)
            shift
            local session_id="$1"
            local detail_level="${2:-standard}"
            local conversation_file="${3:-}"
            local force="${4:-false}"

            get_summary "$session_id" "$detail_level" "$conversation_file" "$force"
            ;;
        cache)
            shift
            local session_id="$1"
            local detail_level="$2"
            local summary_file="$3"

            if [ -z "$summary_file" ]; then
                echo "Usage: $0 cache <session_id> <detail_level> <summary_file>" >&2
                exit 1
            fi

            cache_summary "$session_id" "$detail_level" "$(cat "$summary_file")"
            echo "Summary cached: $session_id ($detail_level)"
            ;;
        lookup)
            shift
            local session_id="$1"
            local detail_level="${2:-standard}"

            lookup_cache "$session_id" "$detail_level"
            ;;
        invalidate)
            shift
            local session_id="$1"
            local detail_level="${2:-all}"

            invalidate_cache "$session_id" "$detail_level"
            ;;
        clear)
            clear_cache
            ;;
        stats)
            cache_stats
            ;;
        list)
            list_cached_sessions
            ;;
        compact)
            compact_cache
            ;;
        *)
            echo "Usage: $0 {init|get|cache|lookup|invalidate|clear|stats|list|compact}" >&2
            echo "" >&2
            echo "Commands:" >&2
            echo "  init                - Initialize cache structure" >&2
            echo "  get                 - Get summary (from cache or generate)" >&2
            echo "  cache               - Cache a summary manually" >&2
            echo "  lookup              - Look up cached summary" >&2
            echo "  invalidate          - Invalidate cache entry" >&2
            echo "  clear               - Clear entire cache (with backup)" >&2
            echo "  stats               - Show cache statistics" >&2
            echo "  list                - List all cached sessions" >&2
            echo "  compact             - Compact cache (remove gaps)" >&2
            exit 1
            ;;
    esac
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
