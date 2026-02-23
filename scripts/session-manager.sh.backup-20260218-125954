#!/usr/bin/env bash
# session-manager.sh - Initialize and manage per-session directories
# Part of Per-Session Context System (Phase A)

set -euo pipefail

# Configuration
SESSIONS_BASE_DIR="${SESSIONS_BASE_DIR:-$HOME/Desktop/multi-claude-sessions/sessions}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Initialize a new session directory
initialize_session() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        # Generate session ID: YYYY-MM-DD-session-N-HASH
        local date_prefix=$(date +%Y-%m-%d)
        local session_num=1
        local random_hash=$(openssl rand -hex 2)

        # Find next available session number for today
        while [[ -d "$SESSIONS_BASE_DIR/${date_prefix}-session-${session_num}-${random_hash}" ]]; do
            session_num=$((session_num + 1))
            random_hash=$(openssl rand -hex 2)
        done

        session_id="${date_prefix}-session-${session_num}-${random_hash}"
    fi

    local session_dir="$SESSIONS_BASE_DIR/$session_id"

    # Check if already exists
    if [[ -d "$session_dir" ]]; then
        log_warn "Session directory already exists: $session_dir"
        echo "$session_dir"
        return 0
    fi

    # Create directory structure
    log_info "Creating session directory: $session_id"
    mkdir -p "$session_dir"

    # Initialize conversation log (JSONL format)
    log_debug "Initializing conversation-log.jsonl"
    touch "$session_dir/conversation-log.jsonl"

    # Initialize token usage tracking
    log_debug "Initializing token-usage.json"
    cat > "$session_dir/token-usage.json" <<EOF
{
  "session_id": "$session_id",
  "start_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "last_update": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_tokens": {
    "input": 0,
    "output": 0,
    "total": 0
  },
  "message_count": 0,
  "interactions": []
}
EOF

    # Create session context file
    log_debug "Creating .session-context.md"
    cat > "$session_dir/.session-context.md" <<EOF
# Session Context: $session_id

**Created:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Status:** Active

## Session Summary

This session is currently active. Context will be generated as the conversation progresses.

## Active Topics

- (No topics yet)

## Recent Commands

- (No commands yet)

## Known Issues and Solutions

- (None yet)

## User Preferences Observed

- (Learning in progress)

---

*This file is automatically updated by the session context system.*
*Last updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")*
EOF

    # Create insights placeholder
    log_debug "Creating insights.md"
    cat > "$session_dir/insights.md" <<EOF
# Session Insights: $session_id

**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Overview

Insights will be generated after sufficient conversation data is collected.

## Patterns Detected

- (Analyzing...)

## Successful Interactions

- (Collecting data...)

## Failed Interactions

- (Monitoring...)

## Recommendations

- (Will be generated after analysis)

---

*This file is automatically updated by the insights generator.*
*Minimum 5 interactions required for meaningful insights.*
EOF

    # Create session metadata file
    log_debug "Creating .session-metadata.json"
    cat > "$session_dir/.session-metadata.json" <<EOF
{
  "session_id": "$session_id",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "last_activity": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "active",
  "working_directory": "$(pwd)",
  "user": "$(whoami)",
  "hostname": "$(hostname)",
  "claude_version": "${CLAUDE_VERSION:-unknown}",
  "tags": [],
  "notes": ""
}
EOF

    log_info "Session initialized successfully: $session_dir"
    echo "$session_dir"
}

# Get current active session
get_active_session() {
    local active_session_file="$SESSIONS_BASE_DIR/.active-session"

    if [[ -f "$active_session_file" ]]; then
        cat "$active_session_file"
    else
        echo ""
    fi
}

# Set active session
set_active_session() {
    local session_dir="$1"
    local active_session_file="$SESSIONS_BASE_DIR/.active-session"

    echo "$session_dir" > "$active_session_file"
    log_info "Active session set to: $session_dir"
}

# End a session
end_session() {
    local session_dir="${1:-$(get_active_session)}"

    if [[ -z "$session_dir" ]] || [[ ! -d "$session_dir" ]]; then
        log_error "No active session to end"
        return 1
    fi

    local metadata_file="$session_dir/.session-metadata.json"

    if [[ -f "$metadata_file" ]]; then
        # Update status to closed
        local tmp_file=$(mktemp)
        jq --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.status = "closed" | .ended_at = $timestamp | .last_activity = $timestamp' \
           "$metadata_file" > "$tmp_file" && mv "$tmp_file" "$metadata_file"

        log_info "Session ended: $session_dir"

        # Generate final insights
        if [[ -x "$SCRIPT_DIR/insights-generator.sh" ]]; then
            log_info "Generating final insights..."
            "$SCRIPT_DIR/insights-generator.sh" "$session_dir" || log_warn "Failed to generate insights"
        fi

        # Clear active session
        local active_session_file="$SESSIONS_BASE_DIR/.active-session"
        rm -f "$active_session_file"
    else
        log_error "Session metadata not found: $metadata_file"
        return 1
    fi
}

# List sessions
list_sessions() {
    local filter="${1:-all}" # all, active, closed
    local limit="${2:-20}"

    log_info "Listing sessions (filter: $filter, limit: $limit):"
    echo ""

    local count=0
    while IFS= read -r session_dir; do
        if [[ $count -ge $limit ]]; then
            break
        fi

        local session_name=$(basename "$session_dir")
        local metadata_file="$session_dir/.session-metadata.json"

        if [[ -f "$metadata_file" ]]; then
            local status=$(jq -r '.status' "$metadata_file")
            local created=$(jq -r '.created_at' "$metadata_file")
            local message_count=0

            local token_file="$session_dir/token-usage.json"
            if [[ -f "$token_file" ]]; then
                message_count=$(jq -r '.message_count // 0' "$token_file")
            fi

            # Apply filter
            if [[ "$filter" == "all" ]] || [[ "$filter" == "$status" ]]; then
                local status_color="${GREEN}"
                [[ "$status" == "closed" ]] && status_color="${YELLOW}"

                echo -e "  ${status_color}[$status]${NC} $session_name"
                echo "    Created: $created | Messages: $message_count"
                echo ""

                count=$((count + 1))
            fi
        fi
    done < <(find "$SESSIONS_BASE_DIR" -maxdepth 1 -type d -name "20*" | sort -r)

    if [[ $count -eq 0 ]]; then
        echo "  No sessions found matching filter: $filter"
    fi
}

# Get session info
get_session_info() {
    local session_dir="$1"

    if [[ ! -d "$session_dir" ]]; then
        log_error "Session directory not found: $session_dir"
        return 1
    fi

    local metadata_file="$session_dir/.session-metadata.json"
    local token_file="$session_dir/token-usage.json"
    local context_file="$session_dir/.session-context.md"

    echo ""
    echo "Session Information"
    echo "==================="
    echo ""

    if [[ -f "$metadata_file" ]]; then
        echo "Session ID: $(jq -r '.session_id' "$metadata_file")"
        echo "Status: $(jq -r '.status' "$metadata_file")"
        echo "Created: $(jq -r '.created_at' "$metadata_file")"
        echo "Last Activity: $(jq -r '.last_activity' "$metadata_file")"
        echo "Working Directory: $(jq -r '.working_directory' "$metadata_file")"
    fi

    echo ""

    if [[ -f "$token_file" ]]; then
        echo "Token Usage:"
        echo "  Messages: $(jq -r '.message_count' "$token_file")"
        echo "  Input Tokens: $(jq -r '.total_tokens.input' "$token_file")"
        echo "  Output Tokens: $(jq -r '.total_tokens.output' "$token_file")"
        echo "  Total Tokens: $(jq -r '.total_tokens.total' "$token_file")"
    fi

    echo ""

    if [[ -f "$context_file" ]]; then
        echo "Context File: $context_file"
    fi

    echo ""
}

# Main command dispatcher
main() {
    local command="${1:-help}"
    shift || true

    # Ensure base directory exists
    mkdir -p "$SESSIONS_BASE_DIR"

    case "$command" in
        init|initialize)
            initialize_session "$@"
            ;;

        active|get-active)
            get_active_session
            ;;

        set-active)
            if [[ $# -eq 0 ]]; then
                log_error "Usage: $0 set-active <session_dir>"
                exit 1
            fi
            set_active_session "$1"
            ;;

        end|close)
            end_session "$@"
            ;;

        list|ls)
            list_sessions "$@"
            ;;

        info|show)
            if [[ $# -eq 0 ]]; then
                session_dir=$(get_active_session)
            else
                session_dir="$1"
            fi
            get_session_info "$session_dir"
            ;;

        help|--help|-h)
            cat <<EOF
Session Manager - Initialize and manage per-session directories

USAGE:
    $0 <command> [options]

COMMANDS:
    init|initialize [session_id]    Initialize a new session directory
    active|get-active               Get the current active session
    set-active <session_dir>        Set the active session
    end|close [session_dir]         End a session (defaults to active)
    list|ls [filter] [limit]        List sessions (filter: all|active|closed)
    info|show [session_dir]         Show session information
    help                            Show this help message

EXAMPLES:
    # Initialize new session
    $0 init

    # Initialize with specific ID
    $0 init 2026-02-17-session-1-abc123

    # Get active session
    $0 active

    # List last 10 active sessions
    $0 list active 10

    # Show info for active session
    $0 info

    # End active session
    $0 end

ENVIRONMENT:
    SESSIONS_BASE_DIR    Base directory for sessions (default: ~/Desktop/multi-claude-sessions/sessions)
    DEBUG                Enable debug output (set to 1)

EOF
            ;;

        *)
            log_error "Unknown command: $command"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
