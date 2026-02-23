#!/usr/bin/env bash

################################################################################
# auto-index-manager.sh - Automatic index management daemon
# Version: 1.0.0
#
# Features:
# - Watch file system for changes
# - Trigger incremental index updates
# - Background daemon mode
# - Smart throttling and batching
################################################################################

set -euo pipefail

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"
DATA_DIR="${CLAUDE_HOME}/data"
LOGS_DIR="${CLAUDE_HOME}/logs"
RUN_DIR="${CLAUDE_HOME}/run"

# Files
CONFIG_FILE="${DATA_DIR}/auto-index-config.json"
PID_FILE="${RUN_DIR}/auto-indexer.pid"
LOG_FILE="${LOGS_DIR}/auto-indexer.log"

# Ensure directories exist
mkdir -p "${DATA_DIR}" "${LOGS_DIR}" "${RUN_DIR}"

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

# Initialize configuration
init_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" <<EOF
{
  "enabled": true,
  "watch_directories": [],
  "update_frequency_seconds": 30,
  "auto_start": false,
  "ignore_patterns": [
    "*.log",
    "node_modules",
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    "*.pyc",
    ".DS_Store",
    "*.swp",
    ".idea",
    ".vscode"
  ],
  "file_extensions": [
    ".py",
    ".js",
    ".ts",
    ".jsx",
    ".tsx",
    ".go",
    ".rs",
    ".java",
    ".cpp",
    ".c",
    ".h",
    ".sh",
    ".md"
  ],
  "max_file_size_mb": 10
}
EOF
        log "Initialized auto-index configuration"
    fi
}

# Get config value
get_config() {
    local key="$1"
    init_config
    jq -r ".${key} // empty" "${CONFIG_FILE}"
}

# Set config value
set_config() {
    local key="$1"
    local value="$2"

    init_config

    local tmp_file="${CONFIG_FILE}.tmp"
    jq ".${key} = ${value}" "${CONFIG_FILE}" > "${tmp_file}"
    mv "${tmp_file}" "${CONFIG_FILE}"

    success "Set ${key} = ${value}"
}

# Add watch directory
add_watch_directory() {
    local directory="$1"

    if [[ ! -d "${directory}" ]]; then
        error "Directory not found: ${directory}"
        return 1
    fi

    # Normalize path
    directory=$(cd "${directory}" && pwd)

    init_config

    # Check if already watching
    local existing=$(jq -r ".watch_directories[] | select(. == \"${directory}\")" "${CONFIG_FILE}")
    if [[ -n "${existing}" ]]; then
        log "Already watching: ${directory}"
        return 0
    fi

    # Add to watch list
    local tmp_file="${CONFIG_FILE}.tmp"
    jq ".watch_directories += [\"${directory}\"]" "${CONFIG_FILE}" > "${tmp_file}"
    mv "${tmp_file}" "${CONFIG_FILE}"

    success "Added watch directory: ${directory}"

    # Trigger initial index
    bash "${SCRIPTS_DIR}/codebase-indexer.sh" index "${directory}"
}

# Remove watch directory
remove_watch_directory() {
    local directory="$1"

    # Normalize path
    directory=$(cd "${directory}" && pwd)

    init_config

    local tmp_file="${CONFIG_FILE}.tmp"
    jq ".watch_directories = (.watch_directories - [\"${directory}\"])" "${CONFIG_FILE}" > "${tmp_file}"
    mv "${tmp_file}" "${CONFIG_FILE}"

    success "Removed watch directory: ${directory}"
}

# List watch directories
list_watch_directories() {
    init_config

    local dirs=$(jq -r '.watch_directories[]' "${CONFIG_FILE}" 2>/dev/null)

    if [[ -z "${dirs}" ]]; then
        echo "No directories being watched"
    else
        echo "Watching directories:"
        echo "${dirs}" | sed 's/^/  /'
    fi
}

# Check if should ignore file
should_ignore_file() {
    local file="$1"

    # Get ignore patterns
    local patterns=$(jq -r '.ignore_patterns[]' "${CONFIG_FILE}" 2>/dev/null)

    # Check each pattern
    while IFS= read -r pattern; do
        if [[ -z "${pattern}" ]]; then
            continue
        fi

        # Match pattern
        case "${file}" in
            *${pattern}*)
                return 0
                ;;
        esac
    done <<< "${patterns}"

    # Check file extension
    local extensions=$(jq -r '.file_extensions[]' "${CONFIG_FILE}" 2>/dev/null)
    local file_ext=".${file##*.}"

    local found=false
    while IFS= read -r ext; do
        if [[ "${file_ext}" == "${ext}" ]]; then
            found=true
            break
        fi
    done <<< "${extensions}"

    if [[ "${found}" == "false" ]]; then
        return 0
    fi

    # Check file size
    local max_size=$(get_config "max_file_size_mb")
    if [[ -n "${max_size}" ]] && [[ -f "${file}" ]]; then
        local file_size_mb=$(du -m "${file}" | cut -f1)
        if [[ ${file_size_mb} -gt ${max_size} ]]; then
            return 0
        fi
    fi

    return 1
}

# Process changed files
process_changed_files() {
    local directory="$1"
    local changed_files="$2"

    log "Processing ${changed_files} changed file(s) in ${directory}"

    # Trigger incremental index update
    if [[ -f "${SCRIPTS_DIR}/codebase-indexer.sh" ]]; then
        bash "${SCRIPTS_DIR}/codebase-indexer.sh" update "${directory}" &
    else
        error "Codebase indexer not found"
    fi
}

# Watch directory using polling
watch_directory_polling() {
    local directory="$1"
    local update_frequency=$(get_config "update_frequency_seconds")

    log "Watching ${directory} (polling every ${update_frequency}s)"

    # Track file modification times
    local state_file="${DATA_DIR}/watch-state-$(echo "${directory}" | md5sum | cut -d' ' -f1).json"

    if [[ ! -f "${state_file}" ]]; then
        echo '{}' > "${state_file}"
    fi

    while true; do
        local changed=0

        # Find all relevant files
        while IFS= read -r file; do
            if should_ignore_file "${file}"; then
                continue
            fi

            # Get current modification time
            local mtime=$(stat -f "%m" "${file}" 2>/dev/null || echo "0")

            # Get stored modification time
            local stored_mtime=$(jq -r ".[\"${file}\"] // 0" "${state_file}" 2>/dev/null)

            # Check if changed
            if [[ "${mtime}" != "${stored_mtime}" ]]; then
                changed=$((changed + 1))

                # Update state
                local tmp_file="${state_file}.tmp"
                jq ".[\"${file}\"] = ${mtime}" "${state_file}" > "${tmp_file}"
                mv "${tmp_file}" "${state_file}"
            fi
        done < <(find "${directory}" -type f 2>/dev/null)

        # Process changes if any
        if [[ ${changed} -gt 0 ]]; then
            process_changed_files "${directory}" "${changed}"
        fi

        # Sleep
        sleep "${update_frequency}"
    done
}

# Watch directory using fswatch (if available)
watch_directory_fswatch() {
    local directory="$1"
    local update_frequency=$(get_config "update_frequency_seconds")

    log "Watching ${directory} using fswatch"

    # Build ignore patterns
    local ignore_args=""
    local patterns=$(jq -r '.ignore_patterns[]' "${CONFIG_FILE}" 2>/dev/null)
    while IFS= read -r pattern; do
        if [[ -n "${pattern}" ]]; then
            ignore_args="${ignore_args} --exclude='${pattern}'"
        fi
    done <<< "${patterns}"

    # Track changes for batching
    local pending_changes=0
    local last_update=$(date +%s)

    # Watch for changes
    eval "fswatch -r ${ignore_args} '${directory}'" | while read -r changed_file; do
        if should_ignore_file "${changed_file}"; then
            continue
        fi

        pending_changes=$((pending_changes + 1))

        # Check if should trigger update
        local now=$(date +%s)
        local elapsed=$((now - last_update))

        if [[ ${elapsed} -ge ${update_frequency} ]] && [[ ${pending_changes} -gt 0 ]]; then
            process_changed_files "${directory}" "${pending_changes}"
            pending_changes=0
            last_update=${now}
        fi
    done
}

# Watch directory (auto-detect method)
watch_directory() {
    local directory="$1"

    # Check if fswatch is available
    if command -v fswatch > /dev/null 2>&1; then
        watch_directory_fswatch "${directory}"
    else
        log "fswatch not available, using polling method"
        watch_directory_polling "${directory}"
    fi
}

# Start daemon
start_daemon() {
    # Check if already running
    if [[ -f "${PID_FILE}" ]]; then
        local pid=$(cat "${PID_FILE}")
        if ps -p "${pid}" > /dev/null 2>&1; then
            error "Auto-indexer already running (PID: ${pid})"
            return 1
        else
            log "Removing stale PID file"
            rm -f "${PID_FILE}"
        fi
    fi

    # Check if enabled
    local enabled=$(get_config "enabled")
    if [[ "${enabled}" != "true" ]]; then
        error "Auto-indexing is disabled. Enable with: configure enabled true"
        return 1
    fi

    # Get watch directories
    local dirs=$(jq -r '.watch_directories[]' "${CONFIG_FILE}" 2>/dev/null)

    if [[ -z "${dirs}" ]]; then
        error "No directories to watch. Add with: add-watch <directory>"
        return 1
    fi

    log "Starting auto-indexer daemon..."

    # Start in background
    nohup bash -c "
        set -euo pipefail

        # Write PID
        echo \$\$ > '${PID_FILE}'

        # Log startup
        echo '[$(date '+%Y-%m-%d %H:%M:%S')] Auto-indexer started (PID: \$\$)' >> '${LOG_FILE}'

        # Watch each directory in parallel
        $(jq -r '.watch_directories[]' "${CONFIG_FILE}" | while read -r dir; do
            echo "bash '${SCRIPTS_DIR}/auto-index-manager.sh' _watch '${dir}' &"
        done)

        # Wait for all watchers
        wait
    " >> "${LOG_FILE}" 2>&1 &

    local daemon_pid=$!

    # Wait a moment to ensure it started
    sleep 1

    if ps -p "${daemon_pid}" > /dev/null 2>&1; then
        success "Auto-indexer started (PID: ${daemon_pid})"
        return 0
    else
        error "Failed to start auto-indexer"
        return 1
    fi
}

# Stop daemon
stop_daemon() {
    if [[ ! -f "${PID_FILE}" ]]; then
        log "Auto-indexer not running"
        return 0
    fi

    local pid=$(cat "${PID_FILE}")

    if ps -p "${pid}" > /dev/null 2>&1; then
        log "Stopping auto-indexer (PID: ${pid})..."
        kill "${pid}"

        # Wait for graceful shutdown
        local timeout=10
        while [[ ${timeout} -gt 0 ]]; do
            if ! ps -p "${pid}" > /dev/null 2>&1; then
                break
            fi
            sleep 1
            timeout=$((timeout - 1))
        done

        # Force kill if still running
        if ps -p "${pid}" > /dev/null 2>&1; then
            log "Force killing auto-indexer..."
            kill -9 "${pid}"
        fi

        rm -f "${PID_FILE}"
        success "Auto-indexer stopped"
    else
        log "Removing stale PID file"
        rm -f "${PID_FILE}"
    fi
}

# Get daemon status
get_status() {
    echo "Auto-Indexer Status"
    echo "════════════════════════════════════════"
    echo ""

    # Running status
    if [[ -f "${PID_FILE}" ]]; then
        local pid=$(cat "${PID_FILE}")
        if ps -p "${pid}" > /dev/null 2>&1; then
            echo "Status: Running (PID: ${pid})"

            # Uptime
            local start_time=$(ps -o lstart= -p "${pid}" 2>/dev/null || echo "unknown")
            echo "Started: ${start_time}"

            # Memory usage
            local mem=$(ps -o rss= -p "${pid}" 2>/dev/null | awk '{print int($1/1024)"MB"}')
            echo "Memory: ${mem}"
        else
            echo "Status: Stopped (stale PID file)"
        fi
    else
        echo "Status: Stopped"
    fi
    echo ""

    # Configuration
    echo "Configuration:"
    local enabled=$(get_config "enabled")
    local frequency=$(get_config "update_frequency_seconds")
    local auto_start=$(get_config "auto_start")

    echo "  Enabled: ${enabled}"
    echo "  Update frequency: ${frequency}s"
    echo "  Auto-start: ${auto_start}"
    echo ""

    # Watch directories
    list_watch_directories
    echo ""

    # Recent activity
    if [[ -f "${LOG_FILE}" ]]; then
        echo "Recent Activity (last 5 entries):"
        tail -5 "${LOG_FILE}" | sed 's/^/  /'
    fi

    echo ""
    echo "════════════════════════════════════════"
}

# Usage
usage() {
    cat <<EOF
Auto-Index Manager - Automatic index updates

USAGE:
    auto-index-manager.sh <command> [options]

COMMANDS:
    start                    Start auto-indexer daemon
    stop                     Stop auto-indexer daemon
    restart                  Restart auto-indexer daemon
    status                   Show daemon status

    add-watch <directory>    Add directory to watch list
    remove-watch <directory> Remove directory from watch list
    list-watch               List watched directories

    configure <key> <value>  Set configuration value
    show-config              Show configuration

OPTIONS:
    --help                   Show this help

EXAMPLES:
    # Start daemon
    auto-index-manager.sh start

    # Add directory to watch
    auto-index-manager.sh add-watch /path/to/project

    # Check status
    auto-index-manager.sh status

    # Configure update frequency
    auto-index-manager.sh configure update_frequency_seconds 60

EOF
}

# Main
main() {
    local command="${1:-}"

    case "${command}" in
        start)
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        restart)
            stop_daemon
            sleep 1
            start_daemon
            ;;
        status)
            get_status
            ;;
        add-watch)
            shift
            add_watch_directory "$@"
            ;;
        remove-watch)
            shift
            remove_watch_directory "$@"
            ;;
        list-watch)
            list_watch_directories
            ;;
        configure)
            shift
            set_config "$@"
            ;;
        show-config)
            init_config
            jq . "${CONFIG_FILE}"
            ;;
        _watch)
            # Internal: watch directory (called by daemon)
            shift
            watch_directory "$@"
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
