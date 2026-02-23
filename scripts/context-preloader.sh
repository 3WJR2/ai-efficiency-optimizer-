#!/usr/bin/env bash

################################################################################
# context-preloader.sh - Intelligent context preloading for agents
# Version: 1.0.0
#
# Features:
# - Analyze request to predict needed context
# - Search index for relevant code
# - Extract full context (dependencies, callers, etc.)
# - Package as markdown for agent consumption
# - Cache results for reuse
################################################################################

set -euo pipefail

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"
DATA_DIR="${CLAUDE_HOME}/data"
CACHE_DIR="${CLAUDE_HOME}/cache/contexts"
LOGS_DIR="${CLAUDE_HOME}/logs"
INDEXES_DIR="${CLAUDE_HOME}/indexes"

# Log file
LOG_FILE="${LOGS_DIR}/context-preloader.log"

# Ensure directories exist
mkdir -p "${DATA_DIR}" "${CACHE_DIR}" "${LOGS_DIR}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*" | tee -a "${LOG_FILE}"
}

# Generate cache key
generate_cache_key() {
    local request="$1"
    echo -n "${request}" | md5sum | cut -d' ' -f1
}

# Check cache
check_cache() {
    local cache_key="$1"
    local cache_file="${CACHE_DIR}/${cache_key}.md"

    if [[ -f "${cache_file}" ]]; then
        # Check if cache is fresh (< 1 hour old)
        local now=$(date +%s)
        local mtime=$(stat -f "%m" "${cache_file}" 2>/dev/null || echo "0")
        local age=$((now - mtime))

        if [[ ${age} -lt 3600 ]]; then
            log "Cache hit: ${cache_key}"
            cat "${cache_file}"
            return 0
        else
            log "Cache expired: ${cache_key}"
            rm -f "${cache_file}"
        fi
    fi

    return 1
}

# Save to cache
save_to_cache() {
    local cache_key="$1"
    local content="$2"
    local cache_file="${CACHE_DIR}/${cache_key}.md"

    echo "${content}" > "${cache_file}"
    log "Cached context: ${cache_key}"
}

# Extract keywords from request
extract_keywords() {
    local request="$1"

    # Simple keyword extraction (split on whitespace, remove common words)
    local common_words="a an the is are was were be been being have has had do does did will would should could may might must can to of in on for with at by from as into through"

    echo "${request}" | \
        tr '[:upper:]' '[:lower:]' | \
        tr -cs '[:alnum:]' '\n' | \
        grep -vE "^(${common_words// /|})$" | \
        sort -u
}

# Predict relevant files
predict_relevant_files() {
    local request="$1"

    log "Predicting relevant files for: ${request}"

    # Extract keywords
    local keywords=$(extract_keywords "${request}")

    # Search indexes for matching files
    local results=""

    # Use vector search if available
    if [[ -f "${SCRIPTS_DIR}/vector-search.sh" ]]; then
        results=$(bash "${SCRIPTS_DIR}/vector-search.sh" search "${request}" 2>/dev/null || echo "")
    else
        # Fallback: search in indexes
        for keyword in ${keywords}; do
            # Search in all indexes
            find "${INDEXES_DIR}" -name "*.index.json" -exec jq -r \
                ".files[] | select(.content | test(\"${keyword}\"; \"i\")) | .path" {} \; 2>/dev/null
        done | sort -u
    fi

    echo "${results}"
}

# Extract function context
extract_function_context() {
    local file="$1"
    local function_name="$2"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    # Find function definition and extract with context
    # This is a simplified version - real implementation would use AST parsing
    local start_line=$(grep -n "def ${function_name}\|function ${function_name}\|func ${function_name}" "${file}" | cut -d: -f1 | head -1)

    if [[ -z "${start_line}" ]]; then
        return 1
    fi

    # Extract function (assume max 50 lines)
    local end_line=$((start_line + 50))

    sed -n "${start_line},${end_line}p" "${file}"
}

# Extract file context
extract_file_context() {
    local file="$1"
    local max_lines="${2:-200}"

    if [[ ! -f "${file}" ]]; then
        error "File not found: ${file}"
        return 1
    fi

    # Get file info
    local line_count=$(wc -l < "${file}" | tr -d ' ')

    # If file is small, return all
    if [[ ${line_count} -le ${max_lines} ]]; then
        cat "${file}"
        return 0
    fi

    # For large files, return top portion
    head -n "${max_lines}" "${file}"
    echo ""
    echo "... (${line_count} lines total, showing first ${max_lines})"
}

# Find dependencies
find_dependencies() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    # Extract imports/requires
    local imports=$(grep -E "^import |^from .* import |^require\(|^#include" "${file}" 2>/dev/null || echo "")

    if [[ -n "${imports}" ]]; then
        echo "Dependencies:"
        echo "${imports}"
        echo ""
    fi
}

# Find callers
find_callers() {
    local function_name="$1"
    local directory="${2:-.}"

    # Search for function calls
    grep -r "${function_name}(" "${directory}" --include="*.py" --include="*.js" --include="*.ts" 2>/dev/null | \
        head -10 | \
        sed 's/^/  /'
}

# Package context as markdown
package_context() {
    local request="$1"
    local files="$2"

    local output=""

    # Header
    output+="# Preloaded Context for: ${request}\n\n"
    output+="Generated at: $(date '+%Y-%m-%d %H:%M:%S')\n\n"

    # Files section
    if [[ -n "${files}" ]]; then
        output+="## Relevant Files\n\n"

        local count=0
        while IFS= read -r file; do
            if [[ -z "${file}" ]]; then
                continue
            fi

            count=$((count + 1))

            output+="### ${count}. ${file}\n\n"

            # File metadata
            if [[ -f "${file}" ]]; then
                local lines=$(wc -l < "${file}" | tr -d ' ')
                local size=$(du -h "${file}" | cut -f1)
                output+="**Lines:** ${lines} | **Size:** ${size}\n\n"

                # Dependencies
                local deps=$(find_dependencies "${file}")
                if [[ -n "${deps}" ]]; then
                    output+="${deps}\n"
                fi

                # File content
                output+="**Content:**\n\n"
                output+="\`\`\`\n"
                output+="$(extract_file_context "${file}")\n"
                output+="\`\`\`\n\n"
            else
                output+="*File not found*\n\n"
            fi

            # Limit to 5 files
            if [[ ${count} -ge 5 ]]; then
                break
            fi
        done <<< "${files}"

        if [[ ${count} -eq 0 ]]; then
            output+="*No relevant files found*\n\n"
        fi
    fi

    # Keywords section
    output+="## Extracted Keywords\n\n"
    local keywords=$(extract_keywords "${request}")
    for keyword in ${keywords}; do
        output+="- ${keyword}\n"
    done
    output+="\n"

    # Suggestions
    output+="## Suggested Investigation Points\n\n"
    output+="1. Review the files listed above\n"
    output+="2. Check dependencies and imports\n"
    output+="3. Look for related test files\n"
    output+="4. Consider edge cases and error handling\n"

    echo -e "${output}"
}

# Preload context
preload_context() {
    local request="$1"
    local directory="${2:-${PWD}}"

    log "Preloading context for: ${request}"

    # Check cache
    local cache_key=$(generate_cache_key "${request}")
    if check_cache "${cache_key}"; then
        return 0
    fi

    # Predict relevant files
    local files=$(predict_relevant_files "${request}")

    # Package context
    local context=$(package_context "${request}" "${files}")

    # Save to cache
    save_to_cache "${cache_key}" "${context}"

    # Output
    echo "${context}"

    success "Context preloaded and cached"
}

# Clear cache
clear_cache() {
    local pattern="${1:-*}"

    log "Clearing cache: ${pattern}"

    local count=$(find "${CACHE_DIR}" -name "${pattern}.md" -type f 2>/dev/null | wc -l | tr -d ' ')

    find "${CACHE_DIR}" -name "${pattern}.md" -type f -delete 2>/dev/null

    success "Cleared ${count} cached context(s)"
}

# Show cache stats
show_cache_stats() {
    echo "Context Cache Statistics"
    echo "════════════════════════════════════════"
    echo ""

    local total=$(find "${CACHE_DIR}" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    local size=$(du -sh "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo "0B")

    echo "Total cached contexts: ${total}"
    echo "Cache size: ${size}"
    echo "Cache location: ${CACHE_DIR}"
    echo ""

    if [[ ${total} -gt 0 ]]; then
        echo "Recent contexts:"
        find "${CACHE_DIR}" -name "*.md" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | \
            sort -rn | \
            head -5 | \
            while read -r mtime file; do
                local age=$(($(date +%s) - mtime))
                local age_min=$((age / 60))
                echo "  - $(basename "${file}" .md) (${age_min} minutes ago)"
            done
    fi

    echo ""
    echo "════════════════════════════════════════"
}

# Test preloader
test_preloader() {
    echo "Testing context preloader..."
    echo ""

    # Test 1: Extract keywords
    echo "Test 1: Extract keywords"
    local keywords=$(extract_keywords "Debug authentication timeout issue")
    echo "Keywords: ${keywords}"
    echo ""

    # Test 2: Predict files
    echo "Test 2: Predict relevant files"
    local files=$(predict_relevant_files "authentication")
    if [[ -n "${files}" ]]; then
        echo "Found files:"
        echo "${files}" | head -3
    else
        echo "No files found"
    fi
    echo ""

    # Test 3: Package context
    echo "Test 3: Package context"
    local context=$(preload_context "test request")
    local lines=$(echo "${context}" | wc -l | tr -d ' ')
    echo "Generated context: ${lines} lines"
    echo ""

    # Test 4: Cache
    echo "Test 4: Cache functionality"
    local cache_key=$(generate_cache_key "test request")
    if check_cache "${cache_key}" > /dev/null 2>&1; then
        echo "✓ Cache hit"
    else
        echo "✗ Cache miss"
    fi
    echo ""

    success "All tests completed"
}

# Usage
usage() {
    cat <<EOF
Context Preloader - Intelligent context preloading for agents

USAGE:
    context-preloader.sh <command> [options]

COMMANDS:
    preload <request> [directory]  Preload context for request
    predict <request>              Predict relevant files only
    package <request> <files>      Package files as context

    clear-cache [pattern]          Clear cache (default: all)
    stats                          Show cache statistics
    test                           Run test suite

OPTIONS:
    --help                         Show this help

EXAMPLES:
    # Preload context
    context-preloader.sh preload "Fix authentication bug"

    # Predict files
    context-preloader.sh predict "login timeout"

    # Clear cache
    context-preloader.sh clear-cache

    # Show stats
    context-preloader.sh stats

EOF
}

# Main
main() {
    local command="${1:-}"

    case "${command}" in
        preload)
            shift
            preload_context "$@"
            ;;
        predict)
            shift
            predict_relevant_files "$@"
            ;;
        package)
            shift
            package_context "$@"
            ;;
        clear-cache)
            shift
            clear_cache "$@"
            ;;
        stats)
            show_cache_stats
            ;;
        test)
            test_preloader
            ;;
        --help|-h|"")
            usage
            ;;
        *)
            error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
