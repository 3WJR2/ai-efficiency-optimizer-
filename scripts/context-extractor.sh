#!/usr/bin/env bash

# context-extractor.sh
# Extract comprehensive context for code exploration
# Part of Deep Codebase Understanding System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_DIR="${HOME}/.claude/indexes"

# Dependencies
CODE_SEARCH="${SCRIPT_DIR}/code-search.sh"
DEPENDENCY_ANALYZER="${SCRIPT_DIR}/dependency-analyzer.sh"

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
# Context Extraction Functions
# ============================================================================

# Extract full context for a code element
extract_context() {
    local codebase_path="$1"
    local location="$2"  # Format: filepath:line or just filepath
    codebase_path=$(cd "$codebase_path" && pwd)

    log "Extracting context for: $location"

    # Parse location
    local filepath
    local line_num
    if [[ "$location" == *:* ]]; then
        filepath="${location%:*}"
        line_num="${location##*:}"
    else
        filepath="$location"
        line_num="1"
    fi

    # Check file exists
    [[ -f "$filepath" ]] || error "File not found: $filepath"

    # Initialize context report
    local report=""

    report+="# Code Context Report\n"
    report+="\n"
    report+="**Location:** \`$location\`\n"
    report+="**Generated:** $(date)\n"
    report+="\n"

    # 1. Definition and surrounding code
    report+="## Definition\n\n"
    report+=$(get_definition "$filepath" "$line_num")
    report+="\n\n"

    # 2. Documentation/comments
    report+="## Documentation\n\n"
    report+=$(get_documentation "$filepath" "$line_num")
    report+="\n\n"

    # 3. Dependencies
    report+="## Dependencies\n\n"
    report+="### Imports\n\n"
    report+=$(get_imports "$filepath")
    report+="\n\n"

    # 4. Callers (if it's a function)
    report+="### Callers (Who calls this?)\n\n"
    report+=$(get_callers "$codebase_path" "$filepath" "$line_num" 2>/dev/null || echo "N/A")
    report+="\n\n"

    # 5. Callees (what does it call?)
    report+="### Callees (What does this call?)\n\n"
    report+=$(get_callees_context "$filepath" "$line_num")
    report+="\n\n"

    # 6. Similar code
    report+="## Similar Code\n\n"
    report+=$(get_similar_code "$codebase_path" "$filepath")
    report+="\n\n"

    # 7. Related tests
    report+="## Related Tests\n\n"
    report+=$(get_tests "$codebase_path" "$filepath")
    report+="\n\n"

    # 8. Recent changes
    report+="## Recent Changes\n\n"
    report+=$(get_recent_changes "$filepath")
    report+="\n\n"

    # Output report
    echo -e "$report"
}

# Get definition and surrounding code
get_definition() {
    local filepath="$1"
    local line_num="$2"
    local context_lines=20

    local start_line=$((line_num - context_lines / 2))
    [[ $start_line -lt 1 ]] && start_line=1
    local end_line=$((line_num + context_lines / 2))

    echo "\`\`\`$(get_language "$filepath")"
    sed -n "${start_line},${end_line}p" "$filepath" | cat -n
    echo "\`\`\`"
}

# Get documentation/comments near code
get_documentation() {
    local filepath="$1"
    local line_num="$2"

    # Look for comments in preceding lines
    local doc_start=$((line_num - 20))
    [[ $doc_start -lt 1 ]] && doc_start=1

    local doc=""
    for ((i=doc_start; i<line_num; i++)); do
        local line
        line=$(sed -n "${i}p" "$filepath")

        # Check if it's a comment line
        if [[ "$line" =~ ^[[:space:]]*# ]] || \
           [[ "$line" =~ ^[[:space:]]*// ]] || \
           [[ "$line" =~ ^[[:space:]]*\* ]] || \
           [[ "$line" =~ ^[[:space:]]*/\* ]]; then
            doc+="$line\n"
        fi
    done

    if [[ -n "$doc" ]]; then
        echo -e "\`\`\`\n$doc\`\`\`"
    else
        echo "No documentation found"
    fi
}

# Get imports from file
get_imports() {
    local filepath="$1"
    local ext="${filepath##*.}"

    case "$ext" in
        py)
            grep -E "^(import|from) " "$filepath" 2>/dev/null || echo "None"
            ;;
        js|ts|jsx|tsx)
            grep -E "^import " "$filepath" 2>/dev/null || echo "None"
            ;;
        sh|bash|zsh)
            grep -E "^(source|\.) " "$filepath" 2>/dev/null || echo "None"
            ;;
        *)
            echo "N/A for this file type"
            ;;
    esac
}

# Get callers of a function
get_callers() {
    local codebase_path="$1"
    local filepath="$2"
    local line_num="$3"

    # Get function name at this location
    local func_name
    func_name=$(get_function_name "$filepath" "$line_num")

    if [[ -z "$func_name" ]]; then
        echo "Not a function"
        return
    fi

    # Use dependency analyzer to find callers
    source "$DEPENDENCY_ANALYZER"
    get_call_graph "$codebase_path" "$func_name" 2>/dev/null | \
        jq -r '.callers[] | "- `\(.from)` (\(.type))"' || echo "None found"
}

# Get what this code calls
get_callees_context() {
    local filepath="$1"
    local line_num="$2"
    local context_lines=20

    local start_line=$((line_num))
    local end_line=$((line_num + context_lines))

    # Extract function calls from the code
    sed -n "${start_line},${end_line}p" "$filepath" | \
        grep -oE "[a-zA-Z_][a-zA-Z0-9_]*\(" | \
        sed 's/($//' | \
        sort -u | \
        head -10 | \
        sed 's/^/- `/' | \
        sed 's/$/`/' || echo "None found"
}

# Get similar code
get_similar_code() {
    local codebase_path="$1"
    local filepath="$2"

    # Use code search to find similar files
    source "$CODE_SEARCH"
    search_similar_to_file "$codebase_path" "$filepath" 5 2>/dev/null | \
        jq -r '.[] | "- `\(.metadata.file)` (score: \(.score))"' || echo "None found"
}

# Get related tests
get_tests() {
    local codebase_path="$1"
    local filepath="$2"

    local basename
    basename=$(basename "$filepath" | sed 's/\.[^.]*$//')

    # Look for test files with similar names
    find "$codebase_path" -type f \
        \( -name "test_${basename}*" -o -name "${basename}_test*" -o -name "${basename}.test.*" -o -name "${basename}.spec.*" \) \
        2>/dev/null | head -10 | sed 's/^/- `/' | sed 's/$/`/' || echo "None found"
}

# Get recent changes from git
get_recent_changes() {
    local filepath="$1"

    if ! git -C "$(dirname "$filepath")" rev-parse --git-dir &>/dev/null; then
        echo "Not a git repository"
        return
    fi

    # Get last 5 commits affecting this file
    git -C "$(dirname "$filepath")" log --oneline -5 -- "$(basename "$filepath")" 2>/dev/null || echo "No git history"
}

# Get function name at line
get_function_name() {
    local filepath="$1"
    local line_num="$2"

    local ext="${filepath##*.}"
    local line
    line=$(sed -n "${line_num}p" "$filepath")

    case "$ext" in
        py)
            if [[ "$line" =~ def[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
            ;;
        js|ts|jsx|tsx)
            if [[ "$line" =~ function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                echo "${BASH_REMATCH[1]}"
            elif [[ "$line" =~ (const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*= ]]; then
                echo "${BASH_REMATCH[2]}"
            fi
            ;;
        sh|bash|zsh)
            if [[ "$line" =~ ([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\) ]]; then
                echo "${BASH_REMATCH[1]}"
            elif [[ "$line" =~ function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                echo "${BASH_REMATCH[1]}"
            fi
            ;;
    esac
}

# Get language for syntax highlighting
get_language() {
    local filepath="$1"
    local ext="${filepath##*.}"

    case "$ext" in
        py) echo "python" ;;
        js) echo "javascript" ;;
        ts) echo "typescript" ;;
        jsx|tsx) echo "javascript" ;;
        sh|bash|zsh) echo "bash" ;;
        rb) echo "ruby" ;;
        java) echo "java" ;;
        go) echo "go" ;;
        rs) echo "rust" ;;
        c|h) echo "c" ;;
        cpp|hpp) echo "cpp" ;;
        *) echo "" ;;
    esac
}

# ============================================================================
# Quick Lookup Functions
# ============================================================================

# Get definition of a symbol
get_symbol_definition() {
    local codebase_path="$1"
    local symbol="$2"
    codebase_path=$(cd "$codebase_path" && pwd)

    log "Finding definition of: $symbol"

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local embeddings_file="${index_path}/embeddings.jsonl"

    if [[ ! -f "$embeddings_file" ]]; then
        error "Index not found. Run codebase-indexer.sh first"
    fi

    # Search for symbol in index
    jq --arg name "$symbol" \
        'select(.name == $name) | {path, type, name, content}' \
        "$embeddings_file" | head -1
}

# Get all usages of a symbol
get_symbol_usage() {
    local codebase_path="$1"
    local symbol="$2"
    codebase_path=$(cd "$codebase_path" && pwd)

    log "Finding usages of: $symbol"

    # Search for symbol in all files
    find "$codebase_path" -type f \
        \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" \) \
        -exec grep -l "\b$symbol\b" {} \; 2>/dev/null | head -20
}

# ============================================================================
# CLI Interface
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> <codebase> [options]

Commands:
    extract <codebase> <location>       Extract full context for code element
                                        Location format: filepath:line or filepath

    definition <codebase> <symbol>      Find where symbol is defined
    usage <codebase> <symbol>           Find all usages of symbol

Options:
    --format <format>                   Output format: markdown (default), json
    -h, --help                          Show this help message

Examples:
    # Extract full context
    $(basename "$0") extract ~/my-project app.py:45

    # Find definition
    $(basename "$0") definition ~/my-project "authenticate"

    # Find usages
    $(basename "$0") usage ~/my-project "authenticate"

    # Output as JSON
    $(basename "$0") extract ~/my-project app.py:45 --format json

EOF
}

main() {
    local format="markdown"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            extract|definition|usage)
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
    case "${command:-}" in
        extract)
            [[ $# -ge 2 ]] || error "Usage: extract <codebase> <location>"
            extract_context "$1" "$2"
            ;;
        definition)
            [[ $# -ge 2 ]] || error "Usage: definition <codebase> <symbol>"
            get_symbol_definition "$1" "$2"
            ;;
        usage)
            [[ $# -ge 2 ]] || error "Usage: usage <codebase> <symbol>"
            get_symbol_usage "$1" "$2"
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
