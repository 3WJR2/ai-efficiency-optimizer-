#!/usr/bin/env bash

# session-learning-bridge.sh - Orchestrates feedback loop between sessions and learning
# Version: 1.0.0
# Part of Phase B: Learning Integration Engine

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
INSIGHT_INJECTOR="${SCRIPT_DIR}/insight-injector.sh"
OUTCOME_TRACKER="${SCRIPT_DIR}/outcome-tracker.sh"
SESSION_FILE="${DATA_DIR}/.current-session"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check dependencies
check_dependencies() {
    local missing=()

    if [[ ! -f "$INSIGHT_INJECTOR" ]]; then
        missing+=("insight-injector.sh")
    fi

    if [[ ! -f "$OUTCOME_TRACKER" ]]; then
        missing+=("outcome-tracker.sh")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
    fi

    # Ensure scripts are executable
    chmod +x "$INSIGHT_INJECTOR" "$OUTCOME_TRACKER" 2>/dev/null || true
}

# Generate session ID
generate_session_id() {
    local project_name="${1:-unknown}"
    local timestamp=$(date +%s)
    local random=$(openssl rand -hex 4)
    echo "session-${project_name}-${timestamp}-${random}"
}

# Start a new session
start_session() {
    local project_dir="${1:-.}"
    local confidence_threshold="${2:-0.70}"

    check_dependencies

    # Get project name from directory
    local project_name=$(basename "$(cd "$project_dir" && pwd)")

    # Generate session ID
    local session_id=$(generate_session_id "$project_name")

    log "Starting session: $session_id"
    log "Project: $project_name"
    log "Directory: $project_dir"

    # Initialize session tracking
    log "Initializing session tracking..."
    "$OUTCOME_TRACKER" track-session-start "$session_id" >/dev/null

    # Inject insights
    log "Injecting learning insights..."
    local inject_result=$("$INSIGHT_INJECTOR" auto "$project_dir" "$confidence_threshold")

    local insights_count=$(echo "$inject_result" | jq -r '.total_insights // 0' 2>/dev/null || echo "0")

    # Update session with insights flag
    if [[ $insights_count -gt 0 ]]; then
        local session_history="${DATA_DIR}/session-history.json"
        if [[ -f "$session_history" ]]; then
            jq --arg sid "$session_id" \
               '(.sessions[] | select(.session_id == $sid) | .insights_injected) = true' \
               "$session_history" > "$session_history.tmp"
            mv "$session_history.tmp" "$session_history"
        fi
    fi

    # Store current session info
    cat > "$SESSION_FILE" <<EOF
{
  "session_id": "$session_id",
  "project_name": "$project_name",
  "project_dir": "$project_dir",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "insights_count": $insights_count
}
EOF

    log "Session started successfully"

    # Output session info
    cat <<EOF
{
  "status": "started",
  "session_id": "$session_id",
  "project_name": "$project_name",
  "project_dir": "$project_dir",
  "insights_injected": $insights_count,
  "context_file": "${project_dir}/.claude/project-context.md"
}
EOF
}

# Track outcome during session
track_outcome() {
    local outcome="${1:-success}"
    local details="${2:-}"

    if [[ ! -f "$SESSION_FILE" ]]; then
        log "Warning: No active session found"
        return
    fi

    local session_id=$(jq -r '.session_id' "$SESSION_FILE")

    log "Tracking outcome: $outcome"

    "$OUTCOME_TRACKER" track-session-outcome "$session_id" "$outcome" "$details"

    cat <<EOF
{
  "status": "tracked",
  "session_id": "$session_id",
  "outcome": "$outcome",
  "details": "$details"
}
EOF
}

# End current session
end_session() {
    local outcome="${1:-success}"
    local satisfaction="${2:-7}"

    if [[ ! -f "$SESSION_FILE" ]]; then
        log "Warning: No active session found"
        return
    fi

    check_dependencies

    local session_id=$(jq -r '.session_id' "$SESSION_FILE")
    local project_name=$(jq -r '.project_name' "$SESSION_FILE")
    local started_at=$(jq -r '.started_at' "$SESSION_FILE")

    log "Ending session: $session_id"
    log "Outcome: $outcome"
    log "Satisfaction: $satisfaction/10"

    # Finalize session tracking
    "$OUTCOME_TRACKER" track-session-end "$session_id" "$outcome" "$satisfaction"

    # Calculate session duration
    local ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local duration="unknown"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        local start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null || echo "0")
        local end_epoch=$(date +%s)
        if [[ $start_epoch -gt 0 ]]; then
            duration=$((end_epoch - start_epoch))
        fi
    fi

    # Generate session report
    cat <<EOF
{
  "status": "ended",
  "session_id": "$session_id",
  "project_name": "$project_name",
  "started_at": "$started_at",
  "ended_at": "$ended_at",
  "duration_seconds": $duration,
  "outcome": "$outcome",
  "satisfaction": $satisfaction,
  "effectiveness_report": "Session completed and learning data updated"
}
EOF

    # Clean up session file
    rm -f "$SESSION_FILE"

    log "Session ended successfully"
}

# Get current session info
current_session() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        echo '{"status": "no_active_session"}'
        return
    fi

    local session_info=$(cat "$SESSION_FILE")
    local session_id=$(echo "$session_info" | jq -r '.session_id')

    # Add elapsed time
    local started_at=$(echo "$session_info" | jq -r '.started_at')
    local elapsed="unknown"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        local start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null || echo "0")
        local current_epoch=$(date +%s)
        if [[ $start_epoch -gt 0 ]]; then
            elapsed=$((current_epoch - start_epoch))
        fi
    fi

    echo "$session_info" | jq --argjson elapsed "$elapsed" '. + {elapsed_seconds: $elapsed}'
}

# Generate effectiveness report
generate_report() {
    local session_id="${1:-}"

    check_dependencies

    if [[ -z "$session_id" ]]; then
        if [[ -f "$SESSION_FILE" ]]; then
            session_id=$(jq -r '.session_id' "$SESSION_FILE")
        else
            error "No session ID provided and no active session"
        fi
    fi

    log "Generating effectiveness report for: $session_id"

    local session_history="${DATA_DIR}/session-history.json"

    if [[ ! -f "$session_history" ]]; then
        error "Session history not found"
    fi

    # Extract session data
    local session_data=$(jq --arg sid "$session_id" \
        '.sessions[] | select(.session_id == $sid)' \
        "$session_history")

    if [[ -z "$session_data" || "$session_data" == "null" ]]; then
        error "Session not found: $session_id"
    fi

    # Build report
    local started=$(echo "$session_data" | jq -r '.started_at')
    local ended=$(echo "$session_data" | jq -r '.ended_at // "in progress"')
    local outcome=$(echo "$session_data" | jq -r '.outcome')
    local satisfaction=$(echo "$session_data" | jq -r '.satisfaction_score // "N/A"')
    local operations=$(echo "$session_data" | jq '.operations | length')
    local insights=$(echo "$session_data" | jq -r '.insights_injected')

    cat <<EOF
=== Session Effectiveness Report ===

Session ID: $session_id
Started: $started
Ended: $ended
Outcome: $outcome
Satisfaction: $satisfaction/10
Operations: $operations
Insights Injected: $insights

--- Operations ---
EOF

    echo "$session_data" | jq -r '.operations[] | "[\(.timestamp)] \(.outcome): \(.details)"'

    cat <<EOF

--- Learning Impact ---
EOF

    # Check if learning data was updated
    "$OUTCOME_TRACKER" session-stats

    echo
    echo "Report generated successfully"
}

# Complete workflow for automated session management
auto_session() {
    local project_dir="${1:-.}"
    local action="${2:-start}"

    case "$action" in
        start)
            start_session "$project_dir"
            ;;
        track)
            track_outcome "${3:-success}" "${4:-}"
            ;;
        end)
            end_session "${3:-success}" "${4:-7}"
            ;;
        status)
            current_session
            ;;
        report)
            generate_report "${3:-}"
            ;;
        *)
            error "Unknown action: $action"
            ;;
    esac
}

# CLI Interface
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Orchestrate feedback loop between sessions and learning system.

COMMANDS:
  start [dir] [threshold]     Start new session with insight injection
  track [outcome] [details]   Track outcome during session
  end [outcome] [satisfaction] End session and update learning
  current                     Show current session info
  report [session_id]         Generate effectiveness report
  auto [dir] [action]         Automated session management

  Session Lifecycle:
    1. start    - Initialize session + inject insights
    2. track    - Track operations (call multiple times)
    3. end      - Finalize session + update learning

OPTIONS:
  dir                         Project directory (default: .)
  threshold                   Confidence threshold 0.0-1.0 (default: 0.70)
  outcome                     success|failure|partial (default: success)
  satisfaction                Rating 0-10 (default: 7)
  details                     Additional details (optional)

EXAMPLES:
  # Full workflow
  $(basename "$0") start /path/to/project
  $(basename "$0") track success "Implemented feature X"
  $(basename "$0") track success "Fixed bug Y"
  $(basename "$0") end success 9

  # Quick status check
  $(basename "$0") current

  # Generate report
  $(basename "$0") report session-myproject-1234567890-abc123

  # Automated (single command)
  $(basename "$0") auto . start
  $(basename "$0") auto . end

OUTPUT:
  JSON objects with session status and results

EOF
}

# Main CLI handling
main() {
    local command="${1:-start}"

    case "$command" in
        start)
            start_session "${2:-.}" "${3:-0.70}"
            ;;
        track)
            track_outcome "${2:-success}" "${3:-}"
            ;;
        end)
            end_session "${2:-success}" "${3:-7}"
            ;;
        current|status)
            current_session
            ;;
        report)
            generate_report "${2:-}"
            ;;
        auto)
            auto_session "${2:-.}" "${3:-start}" "${4:-}" "${5:-}"
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown command: $command. Use -h for help."
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
