#!/usr/bin/env bash

################################################################################
# performance-optimizer.sh - Performance optimization for integration layer
# Version: 1.0.0
#
# Features:
# - Parallel execution
# - Smart caching
# - Lazy loading
# - Index warming
# - Result streaming
################################################################################

set -euo pipefail

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"
DATA_DIR="${CLAUDE_HOME}/data"
CACHE_DIR="${CLAUDE_HOME}/cache"
LOGS_DIR="${CLAUDE_HOME}/logs"

# Cache subdirectories
SEARCH_CACHE="${CACHE_DIR}/search-results"
CONTEXT_CACHE="${CACHE_DIR}/contexts"
EMBEDDING_CACHE="${CACHE_DIR}/embeddings"
AGENT_CACHE="${CACHE_DIR}/agent-outputs"

# Log file
LOG_FILE="${LOGS_DIR}/performance-optimizer.log"

# Ensure directories exist
mkdir -p "${DATA_DIR}" "${SEARCH_CACHE}" "${CONTEXT_CACHE}" "${EMBEDDING_CACHE}" "${AGENT_CACHE}" "${LOGS_DIR}"

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

# Initialize metrics
init_metrics() {
    local metrics_file="${DATA_DIR}/performance-metrics.json"

    if [[ ! -f "${metrics_file}" ]]; then
        cat > "${metrics_file}" <<EOF
{
  "version": "1.0.0",
  "metrics": {
    "parallel_executions": 0,
    "cache_hits": 0,
    "cache_misses": 0,
    "total_execution_time_ms": 0,
    "average_execution_time_ms": 0,
    "time_saved_ms": 0
  },
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        log "Initialized performance metrics"
    fi
}

# Update metric
update_metric() {
    local key="$1"
    local value="$2"
    local metrics_file="${DATA_DIR}/performance-metrics.json"

    init_metrics

    local tmp_file="${metrics_file}.tmp"
    jq ".metrics.${key} += ${value} | .last_updated = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" \
        "${metrics_file}" > "${tmp_file}"
    mv "${tmp_file}" "${metrics_file}"
}

# Get metric
get_metric() {
    local key="$1"
    local metrics_file="${DATA_DIR}/performance-metrics.json"

    init_metrics

    jq -r ".metrics.${key} // 0" "${metrics_file}"
}

# Generate cache key
generate_cache_key() {
    local input="$1"
    echo -n "${input}" | md5sum | cut -d' ' -f1
}

# Check cache with TTL
check_cache_ttl() {
    local cache_dir="$1"
    local cache_key="$2"
    local ttl="${3:-3600}"  # Default 1 hour

    local cache_file="${cache_dir}/${cache_key}.cache"

    if [[ -f "${cache_file}" ]]; then
        local now=$(date +%s)
        local mtime=$(stat -f "%m" "${cache_file}" 2>/dev/null || echo "0")
        local age=$((now - mtime))

        if [[ ${age} -lt ${ttl} ]]; then
            update_metric "cache_hits" 1
            cat "${cache_file}"
            return 0
        else
            rm -f "${cache_file}"
        fi
    fi

    update_metric "cache_misses" 1
    return 1
}

# Save to cache
save_to_cache() {
    local cache_dir="$1"
    local cache_key="$2"
    local content="$3"

    local cache_file="${cache_dir}/${cache_key}.cache"
    echo "${content}" > "${cache_file}"
}

# Parallel execute
parallel_execute() {
    local -a commands=("$@")
    local -a pids=()
    local -a results=()

    log "Executing ${#commands[@]} commands in parallel"

    local start_time=$(date +%s%3N)

    # Start all commands
    for i in "${!commands[@]}"; do
        local output_file=$(mktemp)
        eval "${commands[i]}" > "${output_file}" 2>&1 &
        pids[i]=$!
        results[i]="${output_file}"
    done

    # Wait for all to complete
    local failed=0
    for i in "${!pids[@]}"; do
        if ! wait "${pids[i]}"; then
            failed=$((failed + 1))
        fi
    done

    local end_time=$(date +%s%3N)
    local elapsed=$((end_time - start_time))

    update_metric "parallel_executions" 1
    update_metric "total_execution_time_ms" "${elapsed}"

    log "Parallel execution completed in ${elapsed}ms (${failed} failed)"

    # Return results
    for result_file in "${results[@]}"; do
        cat "${result_file}"
        rm -f "${result_file}"
    done

    return ${failed}
}

# Lazy load file
lazy_load_file() {
    local file="$1"
    local max_lines="${2:-100}"

    if [[ ! -f "${file}" ]]; then
        return 1
    fi

    # Check file size
    local line_count=$(wc -l < "${file}" | tr -d ' ')

    if [[ ${line_count} -le ${max_lines} ]]; then
        cat "${file}"
    else
        head -n "${max_lines}" "${file}"
        echo ""
        echo "... (${line_count} lines total, showing first ${max_lines})"
    fi
}

# Warm index cache
warm_index_cache() {
    local index_file="$1"

    log "Warming cache for: ${index_file}"

    if [[ ! -f "${index_file}" ]]; then
        error "Index file not found: ${index_file}"
        return 1
    fi

    # Preload frequently accessed data
    local cache_key=$(generate_cache_key "${index_file}")

    # Cache file list
    jq -r '.files[].path' "${index_file}" > "${CACHE_DIR}/${cache_key}.files.cache"

    # Cache function list
    jq -r '.functions[]? | "\(.name):\(.file):\(.line)"' "${index_file}" > "${CACHE_DIR}/${cache_key}.functions.cache" 2>/dev/null || true

    success "Cache warmed for: ${index_file}"
}

# Warm all indexes
warm_all_indexes() {
    log "Warming all index caches..."

    local indexes_dir="${CLAUDE_HOME}/indexes"
    local count=0

    if [[ ! -d "${indexes_dir}" ]]; then
        error "Indexes directory not found"
        return 1
    fi

    find "${indexes_dir}" -name "*.index.json" -type f | while read -r index_file; do
        warm_index_cache "${index_file}"
        count=$((count + 1))
    done

    success "Warmed ${count} index caches"
}

# Stream results
stream_results() {
    local command="$1"

    log "Streaming results from: ${command}"

    # Execute command and stream output line by line
    eval "${command}" | while IFS= read -r line; do
        echo "${line}"
    done
}

# Optimize search
optimize_search() {
    local query="$1"

    log "Optimizing search for: ${query}"

    local cache_key=$(generate_cache_key "search:${query}")

    # Check cache
    if check_cache_ttl "${SEARCH_CACHE}" "${cache_key}" 3600; then
        log "Returning cached search results"
        return 0
    fi

    # Execute search
    local results=""
    if [[ -f "${SCRIPTS_DIR}/vector-search.sh" ]]; then
        results=$(bash "${SCRIPTS_DIR}/vector-search.sh" search "${query}" 2>/dev/null || echo "")
    fi

    # Cache results
    save_to_cache "${SEARCH_CACHE}" "${cache_key}" "${results}"

    echo "${results}"
}

# Optimize context loading
optimize_context_loading() {
    local request="$1"

    log "Optimizing context loading for: ${request}"

    local cache_key=$(generate_cache_key "context:${request}")

    # Check cache
    if check_cache_ttl "${CONTEXT_CACHE}" "${cache_key}" 3600; then
        log "Returning cached context"
        return 0
    fi

    # Execute context preloading
    local context=""
    if [[ -f "${SCRIPTS_DIR}/context-preloader.sh" ]]; then
        context=$(bash "${SCRIPTS_DIR}/context-preloader.sh" preload "${request}" 2>/dev/null || echo "")
    fi

    # Cache context
    save_to_cache "${CONTEXT_CACHE}" "${cache_key}" "${context}"

    echo "${context}"
}

# Clean cache
clean_cache() {
    local cache_type="${1:-all}"
    local max_age="${2:-86400}"  # Default 24 hours

    log "Cleaning cache: ${cache_type} (max age: ${max_age}s)"

    local now=$(date +%s)
    local count=0

    case "${cache_type}" in
        search)
            find "${SEARCH_CACHE}" -name "*.cache" -type f | while read -r file; do
                local mtime=$(stat -f "%m" "${file}" 2>/dev/null || echo "0")
                local age=$((now - mtime))
                if [[ ${age} -gt ${max_age} ]]; then
                    rm -f "${file}"
                    count=$((count + 1))
                fi
            done
            ;;
        context)
            find "${CONTEXT_CACHE}" -name "*.cache" -type f | while read -r file; do
                local mtime=$(stat -f "%m" "${file}" 2>/dev/null || echo "0")
                local age=$((now - mtime))
                if [[ ${age} -gt ${max_age} ]]; then
                    rm -f "${file}"
                    count=$((count + 1))
                fi
            done
            ;;
        all)
            find "${CACHE_DIR}" -name "*.cache" -type f | while read -r file; do
                local mtime=$(stat -f "%m" "${file}" 2>/dev/null || echo "0")
                local age=$((now - mtime))
                if [[ ${age} -gt ${max_age} ]]; then
                    rm -f "${file}"
                    count=$((count + 1))
                fi
            done
            ;;
    esac

    success "Cleaned ${count} cache entries"
}

# Show performance stats
show_performance_stats() {
    local metrics_file="${DATA_DIR}/performance-metrics.json"

    init_metrics

    echo "Performance Statistics"
    echo "════════════════════════════════════════"
    echo ""

    # Metrics
    local parallel_execs=$(get_metric "parallel_executions")
    local cache_hits=$(get_metric "cache_hits")
    local cache_misses=$(get_metric "cache_misses")
    local total_time=$(get_metric "total_execution_time_ms")
    local time_saved=$(get_metric "time_saved_ms")

    echo "Execution:"
    echo "  Parallel executions: ${parallel_execs}"
    if [[ ${parallel_execs} -gt 0 ]]; then
        local avg_time=$((total_time / parallel_execs))
        echo "  Average time: ${avg_time}ms"
    fi
    echo ""

    echo "Cache:"
    echo "  Hits: ${cache_hits}"
    echo "  Misses: ${cache_misses}"
    if [[ $((cache_hits + cache_misses)) -gt 0 ]]; then
        local hit_rate=$((cache_hits * 100 / (cache_hits + cache_misses)))
        echo "  Hit rate: ${hit_rate}%"
    fi
    echo ""

    # Cache sizes
    echo "Cache Sizes:"
    local search_size=$(du -sh "${SEARCH_CACHE}" 2>/dev/null | cut -f1 || echo "0B")
    local context_size=$(du -sh "${CONTEXT_CACHE}" 2>/dev/null | cut -f1 || echo "0B")
    local total_size=$(du -sh "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo "0B")

    echo "  Search: ${search_size}"
    echo "  Context: ${context_size}"
    echo "  Total: ${total_size}"
    echo ""

    # Performance gain
    if [[ ${time_saved} -gt 0 ]]; then
        local time_saved_sec=$((time_saved / 1000))
        echo "Time Saved:"
        echo "  Total: ${time_saved_sec}s"
        echo ""
    fi

    echo "Last updated: $(jq -r '.last_updated' "${metrics_file}")"
    echo ""
    echo "════════════════════════════════════════"
}

# Benchmark
benchmark() {
    echo "Running performance benchmark..."
    echo ""

    local iterations="${1:-10}"

    # Test 1: Search performance
    echo "Test 1: Search performance (${iterations} iterations)"
    local search_start=$(date +%s%3N)
    for i in $(seq 1 ${iterations}); do
        optimize_search "test query ${i}" > /dev/null 2>&1
    done
    local search_end=$(date +%s%3N)
    local search_time=$((search_end - search_start))
    local search_avg=$((search_time / iterations))
    echo "  Average: ${search_avg}ms per search"
    echo ""

    # Test 2: Context loading performance
    echo "Test 2: Context loading (${iterations} iterations)"
    local context_start=$(date +%s%3N)
    for i in $(seq 1 ${iterations}); do
        optimize_context_loading "test request ${i}" > /dev/null 2>&1
    done
    local context_end=$(date +%s%3N)
    local context_time=$((context_end - context_start))
    local context_avg=$((context_time / iterations))
    echo "  Average: ${context_avg}ms per context load"
    echo ""

    # Test 3: Parallel execution
    echo "Test 3: Parallel execution"
    local parallel_start=$(date +%s%3N)
    parallel_execute \
        "echo 'task 1'" \
        "echo 'task 2'" \
        "echo 'task 3'" \
        "echo 'task 4'" \
        > /dev/null 2>&1
    local parallel_end=$(date +%s%3N)
    local parallel_time=$((parallel_end - parallel_start))
    echo "  Time: ${parallel_time}ms for 4 tasks"
    echo ""

    success "Benchmark completed"
}

# Usage
usage() {
    cat <<EOF
Performance Optimizer - Optimize integration layer performance

USAGE:
    performance-optimizer.sh <command> [options]

COMMANDS:
    optimize-search <query>        Optimize search with caching
    optimize-context <request>     Optimize context loading
    parallel-exec <commands...>    Execute commands in parallel

    warm-indexes                   Warm all index caches
    clean-cache [type] [max_age]   Clean old cache entries
    stats                          Show performance statistics
    benchmark [iterations]         Run performance benchmark

OPTIONS:
    --help                         Show this help

EXAMPLES:
    # Optimize search
    performance-optimizer.sh optimize-search "authentication"

    # Parallel execution
    performance-optimizer.sh parallel-exec "cmd1" "cmd2" "cmd3"

    # Warm caches
    performance-optimizer.sh warm-indexes

    # Clean old cache
    performance-optimizer.sh clean-cache all 3600

    # Show stats
    performance-optimizer.sh stats

    # Benchmark
    performance-optimizer.sh benchmark 20

EOF
}

# Main
main() {
    local command="${1:-}"

    case "${command}" in
        optimize-search)
            shift
            optimize_search "$@"
            ;;
        optimize-context)
            shift
            optimize_context_loading "$@"
            ;;
        parallel-exec)
            shift
            parallel_execute "$@"
            ;;
        warm-indexes)
            warm_all_indexes
            ;;
        clean-cache)
            shift
            clean_cache "$@"
            ;;
        stats)
            show_performance_stats
            ;;
        benchmark)
            shift
            benchmark "$@"
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
