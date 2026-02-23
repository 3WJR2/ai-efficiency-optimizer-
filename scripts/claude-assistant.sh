#!/usr/bin/env bash

################################################################################
# claude-assistant.sh - Unified CLI for orchestrator + indexer integration
# Version: 1.0.0
#
# Single entry point for all Claude Assistant features:
# - Code search & indexing
# - Orchestration & agent spawning
# - Context preloading
# - Auto-index management
################################################################################

set -euo pipefail

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"
DATA_DIR="${CLAUDE_HOME}/data"
CACHE_DIR="${CLAUDE_HOME}/cache"
LOGS_DIR="${CLAUDE_HOME}/logs"
INDEXES_DIR="${CLAUDE_HOME}/indexes"

# Log file
LOG_FILE="${LOGS_DIR}/claude-assistant.log"

# Ensure directories exist
mkdir -p "${DATA_DIR}" "${CACHE_DIR}" "${LOGS_DIR}" "${INDEXES_DIR}"

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

# Display usage
usage() {
    cat <<EOF
Claude Assistant - Unified CLI

USAGE:
    claude-assistant <command> [options]

ORCHESTRATION COMMANDS:
    orchestrate <request>          Orchestrate agents for a request
    auto-orchestrate <on|off>      Enable/disable auto-orchestration

CODE SEARCH COMMANDS:
    search <query>                 Search codebase for query
    find-function <name>           Find function by name
    find-file <pattern>            Find files matching pattern
    explain <file:line>            Explain code at location

INDEX MANAGEMENT COMMANDS:
    index [directory]              Index a directory (default: cwd)
    index-status                   Show index status
    index-update                   Update all indexes
    reindex [directory]            Force reindex of directory

COMBINED WORKFLOWS:
    assist <request>               Complete workflow: search + orchestrate
    context <request>              Preload context for request

CONFIGURATION:
    config                         Show configuration
    config set <key> <value>       Set configuration value
    status                         Show system status

OPTIONS:
    --dry-run                      Show what would be done
    --verbose                      Verbose output
    --help                         Show this help

EXAMPLES:
    # Search for authentication code
    claude-assistant search "authentication"

    # Orchestrate agents to fix a bug
    claude-assistant orchestrate "Fix login timeout bug"

    # Complete workflow
    claude-assistant assist "Debug authentication issues"

    # Index current directory
    claude-assistant index .

    # Check status
    claude-assistant status

EOF
}

# Check dependencies
check_dependencies() {
    local missing=()

    # Required scripts
    if [[ ! -f "${SCRIPTS_DIR}/codebase-indexer.sh" ]]; then
        missing+=("codebase-indexer.sh")
    fi

    if [[ ! -f "${SCRIPTS_DIR}/orchestrator.sh" ]]; then
        missing+=("orchestrator.sh")
    fi

    if [[ ! -f "${SCRIPTS_DIR}/context-preloader.sh" ]]; then
        missing+=("context-preloader.sh")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required scripts: ${missing[*]}"
        return 1
    fi

    return 0
}

# Initialize configuration
init_config() {
    local config_file="${DATA_DIR}/claude-assistant-config.json"

    if [[ ! -f "${config_file}" ]]; then
        cat > "${config_file}" <<EOF
{
  "version": "1.0.0",
  "auto_orchestration": false,
  "auto_indexing": true,
  "default_index_dir": "${PWD}",
  "cache_enabled": true,
  "parallel_execution": true,
  "max_concurrent_agents": 5,
  "context_preloading": true,
  "verbose": false
}
EOF
        log "Initialized configuration at ${config_file}"
    fi
}

# Get config value
get_config() {
    local key="$1"
    local config_file="${DATA_DIR}/claude-assistant-config.json"

    if [[ ! -f "${config_file}" ]]; then
        init_config
    fi

    jq -r ".${key} // empty" "${config_file}"
}

# Set config value
set_config() {
    local key="$1"
    local value="$2"
    local config_file="${DATA_DIR}/claude-assistant-config.json"

    if [[ ! -f "${config_file}" ]]; then
        init_config
    fi

    local tmp_file="${config_file}.tmp"
    jq ".${key} = ${value}" "${config_file}" > "${tmp_file}"
    mv "${tmp_file}" "${config_file}"

    success "Set ${key} = ${value}"
}

# Show configuration
show_config() {
    local config_file="${DATA_DIR}/claude-assistant-config.json"

    if [[ ! -f "${config_file}" ]]; then
        init_config
    fi

    echo "Configuration:"
    echo "─────────────────────────────────────────"
    jq -r 'to_entries[] | "  \(.key): \(.value)"' "${config_file}"
    echo "─────────────────────────────────────────"
}

# Show system status
show_status() {
    echo "Claude Assistant Status"
    echo "════════════════════════════════════════"
    echo ""

    # Configuration
    echo "Configuration:"
    show_config
    echo ""

    # Indexes
    echo "Indexes:"
    echo "  Total: $(find "${INDEXES_DIR}" -name "*.index.json" 2>/dev/null | wc -l | tr -d ' ')"
    echo "  Location: ${INDEXES_DIR}"
    echo ""

    # Auto-indexer
    if [[ -f "${DATA_DIR}/auto-indexer.pid" ]]; then
        local pid=$(cat "${DATA_DIR}/auto-indexer.pid")
        if ps -p "${pid}" > /dev/null 2>&1; then
            echo "Auto-indexer: Running (PID: ${pid})"
        else
            echo "Auto-indexer: Stopped (stale PID file)"
        fi
    else
        echo "Auto-indexer: Stopped"
    fi
    echo ""

    # Cache
    local cache_size=$(du -sh "${CACHE_DIR}" 2>/dev/null | cut -f1 || echo "0B")
    echo "Cache:"
    echo "  Size: ${cache_size}"
    echo "  Location: ${CACHE_DIR}"
    echo ""

    # Recent activity
    if [[ -f "${LOG_FILE}" ]]; then
        echo "Recent Activity (last 5 entries):"
        tail -5 "${LOG_FILE}" | sed 's/^/  /'
    fi

    echo ""
    echo "════════════════════════════════════════"
}

# Search codebase
cmd_search() {
    local query="$1"
    local dry_run="${2:-false}"

    log "Searching for: ${query}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Would search for: ${query}"
        return 0
    fi

    # Use vector search if available
    if [[ -f "${SCRIPTS_DIR}/vector-search.sh" ]]; then
        bash "${SCRIPTS_DIR}/vector-search.sh" search "${query}"
    else
        error "Vector search not available"
        return 1
    fi
}

# Find function
cmd_find_function() {
    local name="$1"
    local dry_run="${2:-false}"

    log "Finding function: ${name}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Would find function: ${name}"
        return 0
    fi

    # Search in all indexes
    local results=$(find "${INDEXES_DIR}" -name "*.index.json" -exec jq -r \
        ".functions[] | select(.name == \"${name}\") | \"\(.file):\(.line)\"" {} \; 2>/dev/null)

    if [[ -n "${results}" ]]; then
        echo "Found function '${name}':"
        echo "${results}"
    else
        echo "Function '${name}' not found"
        return 1
    fi
}

# Find file
cmd_find_file() {
    local pattern="$1"
    local dry_run="${2:-false}"

    log "Finding files matching: ${pattern}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Would find files matching: ${pattern}"
        return 0
    fi

    # Search in all indexes
    local results=$(find "${INDEXES_DIR}" -name "*.index.json" -exec jq -r \
        ".files[] | select(.path | test(\"${pattern}\")) | .path" {} \; 2>/dev/null)

    if [[ -n "${results}" ]]; then
        echo "Found files:"
        echo "${results}"
    else
        echo "No files matching '${pattern}'"
        return 1
    fi
}

# Explain code
cmd_explain() {
    local location="$1"
    local dry_run="${2:-false}"

    log "Explaining code at: ${location}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Would explain code at: ${location}"
        return 0
    fi

    # Parse file:line
    local file="${location%%:*}"
    local line="${location##*:}"

    if [[ ! -f "${file}" ]]; then
        error "File not found: ${file}"
        return 1
    fi

    # Show context around line
    local start=$((line - 5))
    local end=$((line + 5))

    echo "Code at ${file}:${line}:"
    echo "─────────────────────────────────────────"
    sed -n "${start},${end}p" "${file}" | nl -v "${start}"
    echo "─────────────────────────────────────────"
}

# Index directory
cmd_index() {
    local directory="${1:-${PWD}}"
    local dry_run="${2:-false}"

    log "Indexing: ${directory}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Would index: ${directory}"
        return 0
    fi

    if [[ ! -d "${directory}" ]]; then
        error "Directory not found: ${directory}"
        return 1
    fi

    bash "${SCRIPTS_DIR}/codebase-indexer.sh" index "${directory}"
    success "Indexed ${directory}"
}

# Show index status
cmd_index_status() {
    echo "Index Status"
    echo "════════════════════════════════════════"
    echo ""

    local total_indexes=$(find "${INDEXES_DIR}" -name "*.index.json" 2>/dev/null | wc -l | tr -d ' ')
    echo "Total indexes: ${total_indexes}"
    echo ""

    if [[ ${total_indexes} -gt 0 ]]; then
        echo "Indexes:"
        find "${INDEXES_DIR}" -name "*.index.json" | while read -r index_file; do
            local index_name=$(basename "${index_file}" .index.json)
            local file_count=$(jq -r '.files | length' "${index_file}" 2>/dev/null || echo "0")
            local last_updated=$(jq -r '.metadata.last_updated // "unknown"' "${index_file}" 2>/dev/null)
            echo "  - ${index_name}: ${file_count} files (updated: ${last_updated})"
        done
    fi

    echo ""
    echo "════════════════════════════════════════"
}

# Orchestrate request
cmd_orchestrate() {
    local request="$1"
    local dry_run="${2:-false}"

    log "Orchestrating: ${request}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Would orchestrate: ${request}"
        return 0
    fi

    # Check if orchestrator exists
    if [[ ! -f "${SCRIPTS_DIR}/orchestrator.sh" ]]; then
        error "Orchestrator not found"
        return 1
    fi

    bash "${SCRIPTS_DIR}/orchestrator.sh" orchestrate "${request}"
}

# Complete assist workflow
cmd_assist() {
    local request="$1"
    local dry_run="${2:-false}"

    log "Assisting with: ${request}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Complete workflow for: ${request}"
        echo "  1. Search codebase"
        echo "  2. Preload context"
        echo "  3. Orchestrate agents"
        echo "  4. Display results"
        return 0
    fi

    echo "Starting assistance workflow..."
    echo ""

    # Step 1: Search codebase
    echo "Step 1/3: Searching codebase..."
    local search_results=$(bash "${SCRIPTS_DIR}/vector-search.sh" search "${request}" 2>/dev/null || echo "")

    if [[ -n "${search_results}" ]]; then
        echo "Found relevant code:"
        echo "${search_results}" | head -10
        echo ""
    fi

    # Step 2: Preload context
    echo "Step 2/3: Preloading context..."
    local context=$(bash "${SCRIPTS_DIR}/context-preloader.sh" preload "${request}" 2>/dev/null || echo "")
    echo ""

    # Step 3: Orchestrate agents
    echo "Step 3/3: Orchestrating agents..."
    bash "${SCRIPTS_DIR}/orchestrator.sh" orchestrate "${request}"

    success "Assistance workflow complete"
}

# Main command router
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Initialize config
    init_config

    # Parse global options
    local dry_run=false
    local verbose=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    # Get command
    local command="${1:-}"
    shift || true

    # Route to command
    case "${command}" in
        search)
            cmd_search "$@" "${dry_run}"
            ;;
        find-function)
            cmd_find_function "$@" "${dry_run}"
            ;;
        find-file)
            cmd_find_file "$@" "${dry_run}"
            ;;
        explain)
            cmd_explain "$@" "${dry_run}"
            ;;
        index)
            cmd_index "$@" "${dry_run}"
            ;;
        index-status)
            cmd_index_status
            ;;
        index-update)
            cmd_index "${PWD}" "${dry_run}"
            ;;
        reindex)
            cmd_index "$@" "${dry_run}"
            ;;
        orchestrate)
            cmd_orchestrate "$@" "${dry_run}"
            ;;
        assist)
            cmd_assist "$@" "${dry_run}"
            ;;
        context)
            bash "${SCRIPTS_DIR}/context-preloader.sh" preload "$@"
            ;;
        config)
            if [[ $# -eq 0 ]]; then
                show_config
            elif [[ "$1" == "set" ]]; then
                shift
                set_config "$@"
            fi
            ;;
        status)
            show_status
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
