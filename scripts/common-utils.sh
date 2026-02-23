#!/usr/bin/env bash

# Common Utilities
# Shared functions for all scripts
# Version: 1.0.0

# Sponge fallback - writes stdin to file atomically
sponge() {
    local file="$1"
    local tmpfile="${file}.tmp.$$"

    # Read all input to temp file
    cat > "$tmpfile"

    # Move temp file to destination atomically
    mv "$tmpfile" "$file"
}

# Export sponge if command doesn't exist
if ! command -v sponge &> /dev/null; then
    export -f sponge
fi

# JSON safe update - update JSON file safely
json_update() {
    local file="$1"
    local jq_filter="$2"

    if [ ! -f "$file" ]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi

    local tmpfile="${file}.tmp.$$"
    jq "$jq_filter" "$file" > "$tmpfile" && mv "$tmpfile" "$file"
}

# Estimate tokens from text
estimate_tokens_util() {
    local text="$1"
    local char_count=$(echo "$text" | wc -c | tr -d ' ')
    local estimated_tokens=$((char_count / 4))
    echo "$estimated_tokens"
}

# Format timestamp
format_timestamp() {
    local timestamp="${1:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
    echo "$timestamp"
}

# Safe mkdir
safe_mkdir() {
    local dir="$1"
    mkdir -p "$dir" 2>/dev/null || true
}

# Check if JSON file is valid
validate_json() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 1
    fi

    jq empty "$file" 2>/dev/null
}

# Export functions
export -f sponge
export -f json_update
export -f estimate_tokens_util
export -f format_timestamp
export -f safe_mkdir
export -f validate_json
