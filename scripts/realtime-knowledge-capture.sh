#!/usr/bin/env bash

# realtime-knowledge-capture.sh
# Capture knowledge as sessions progress in real-time
# Part of Cross-Session Knowledge Synthesis Integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
LOG_DIR="${HOME}/.claude/logs"
REALTIME_LOG="${LOG_DIR}/realtime-capture.log"
BROADCAST_DIR="${KNOWLEDGE_DIR}/broadcast"

mkdir -p "$LOG_DIR" "$BROADCAST_DIR"

# ============================================================================
# Logging
# ============================================================================

log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$REALTIME_LOG"
}

# ============================================================================
# Knowledge Moment Detection
# ============================================================================

# Detect if a message represents a "knowledge moment"
detect_knowledge_moment() {
    local message="$1"

    local role=$(echo "$message" | jq -r '.role')
    local content=$(echo "$message" | jq -r '.content')

    # User confirmation patterns
    if [[ "$role" == "user" ]]; then
        # Success indicators
        if echo "$content" | grep -qiE "(that worked|perfect|thanks|great|excellent|fixed it|solved it|that did it)"; then
            echo "user_confirmed"
            return 0
        fi

        # Explicit learning statement
        if echo "$content" | grep -qiE "(learned|now i understand|got it|makes sense)"; then
            echo "learning_moment"
            return 0
        fi
    fi

    # Assistant solution patterns
    if [[ "$role" == "assistant" ]]; then
        # Solution with high confidence markers
        if echo "$content" | grep -qiE "(the fix is|here's the solution|this will solve|the issue was)"; then
            echo "solution_provided"
            return 0
        fi

        # Error resolution
        if echo "$content" | grep -qE "error.*fixed|resolved.*issue" -i; then
            echo "error_resolved"
            return 0
        fi
    fi

    echo ""
    return 1
}

# Check if code was committed successfully after message
check_commit_after() {
    local session_dir="$1"
    local message_timestamp="$2"

    # Look for git commits in working directory
    local metadata_file="${session_dir}/.session-metadata.json"
    local working_dir=$(jq -r '.working_directory // ""' "$metadata_file" 2>/dev/null || echo "")

    if [[ -z "$working_dir" ]] || [[ ! -d "$working_dir/.git" ]]; then
        return 1
    fi

    # Check for commits after message timestamp
    local msg_time=$(date -d "$message_timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$message_timestamp" +%s 2>/dev/null || echo "0")
    local recent_commit=$(cd "$working_dir" && git log -1 --format="%ct" 2>/dev/null || echo "0")

    if [[ $recent_commit -gt $msg_time ]]; then
        return 0
    fi

    return 1
}

# ============================================================================
# Real-time Extraction
# ============================================================================

# Extract knowledge immediately from conversation
extract_immediate() {
    local session_dir="$1"
    local conversation_log="$2"
    local message_index="$3"

    local session_id=$(basename "$session_dir")

    # Read conversation up to this point
    local messages=$(head -n "$((message_index + 1))" "$conversation_log" | jq -s '.')

    # Get the triggering message
    local message=$(echo "$messages" | jq ".[$message_index]")
    local role=$(echo "$message" | jq -r '.role')
    local content=$(echo "$message" | jq -r '.content')
    local timestamp=$(echo "$message" | jq -r '.timestamp')

    # Determine knowledge type
    local knowledge_type="learning"
    if echo "$content" | grep -qiE "(fix|solution|resolved)"; then
        knowledge_type="solution"
    elif echo "$content" | grep -qiE "(error|exception)"; then
        knowledge_type="error"
    fi

    # Extract problem and solution
    local problem=""
    local solution=""

    if [[ "$role" == "assistant" ]]; then
        # Look back for user question
        local prev_user_msg=$(echo "$messages" | jq -r ".[$((message_index - 1))] | select(.role == \"user\") | .content" 2>/dev/null || echo "")
        problem="$prev_user_msg"
        solution="$content"
    else
        # User confirmation - look back for assistant response
        local prev_assistant_msg=$(echo "$messages" | jq -r ".[$((message_index - 1))] | select(.role == \"assistant\") | .content" 2>/dev/null || echo "")
        local prev_prev_user_msg=$(echo "$messages" | jq -r ".[$((message_index - 2))] | select(.role == \"user\") | .content" 2>/dev/null || echo "")
        problem="$prev_prev_user_msg"
        solution="$prev_assistant_msg"
    fi

    # Extract code snippets
    local code_snippet=$(echo "$solution" | grep -Pzo '```[^`]*```' 2>/dev/null | tr '\0' '\n' | head -c 1000 || echo "")

    # Extract tags
    local tags=$(echo "$content" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{3,15}\b' | grep -E "(python|javascript|rust|docker|auth|api|test|bug)" | sort -u | head -5 | jq -R . | jq -s .)

    # Calculate confidence
    local confidence=0.65

    # Boost confidence if user confirmed
    if detect_knowledge_moment "$message" | grep -q "user_confirmed"; then
        confidence=0.85
    fi

    # Boost if code was committed
    if check_commit_after "$session_dir" "$timestamp"; then
        confidence=0.90
    fi

    # Generate ID
    local knowledge_id="k_${session_id}_msg${message_index}_realtime_$(date +%Y%m%d%H%M%S)"

    # Build knowledge entry
    cat <<EOF
{
  "id": "$knowledge_id",
  "type": "$knowledge_type",
  "session_id": "$session_id",
  "timestamp": "$timestamp",
  "problem": $(echo "$problem" | head -c 500 | jq -Rs .),
  "solution": $(echo "$solution" | head -c 1000 | jq -Rs .),
  "code_snippet": $(echo "$code_snippet" | jq -Rs .),
  "tags": $tags,
  "confidence": $confidence,
  "extracted_realtime": true,
  "success_indicators": ["realtime_capture"],
  "related_files": [],
  "links": []
}
EOF
}

# ============================================================================
# Broadcasting
# ============================================================================

# Broadcast knowledge to make it immediately available to other sessions
broadcast_knowledge() {
    local knowledge_entry="$1"

    local knowledge_id=$(echo "$knowledge_entry" | jq -r '.id')
    local broadcast_file="${BROADCAST_DIR}/${knowledge_id}.json"

    # Write to broadcast directory
    echo "$knowledge_entry" > "$broadcast_file"

    # Append to knowledge base
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"
    echo "$knowledge_entry" >> "$knowledge_base"

    log "Broadcasted knowledge: $knowledge_id"

    # Update index (simple text index)
    local index_file="${KNOWLEDGE_DIR}/knowledge-index.txt"
    local problem=$(echo "$knowledge_entry" | jq -r '.problem')
    local solution=$(echo "$knowledge_entry" | jq -r '.solution')
    local tags=$(echo "$knowledge_entry" | jq -r '.tags | join(" ")')

    echo "$knowledge_id|$problem $solution $tags" >> "$index_file"
}

# ============================================================================
# Session Monitoring
# ============================================================================

# Watch a single session for knowledge moments
watch_session() {
    local session_dir="$1"
    local session_id=$(basename "$session_dir")
    local conversation_log="${session_dir}/conversation-log.jsonl"

    log "Watching session: $session_id"

    # Track last processed line
    local last_line=0

    while true; do
        # Check if conversation log exists
        if [[ ! -f "$conversation_log" ]]; then
            sleep 5
            continue
        fi

        # Count current lines
        local current_lines=$(wc -l < "$conversation_log" 2>/dev/null || echo "0")

        # Process new messages
        if [[ $current_lines -gt $last_line ]]; then
            log "New messages detected: $((current_lines - last_line))"

            # Process each new message
            for ((i = last_line; i < current_lines; i++)); do
                local message=$(sed -n "$((i + 1))p" "$conversation_log")

                # Detect knowledge moment
                local moment_type=$(detect_knowledge_moment "$message")

                if [[ -n "$moment_type" ]]; then
                    log "Knowledge moment detected: $moment_type (message $i)"

                    # Extract knowledge immediately
                    local knowledge=$(extract_immediate "$session_dir" "$conversation_log" "$i")

                    if [[ -n "$knowledge" ]] && echo "$knowledge" | jq -e . >/dev/null 2>&1; then
                        log "Extracted knowledge in real-time"

                        # Broadcast to make available immediately
                        broadcast_knowledge "$knowledge"
                    fi
                fi
            done

            last_line=$current_lines
        fi

        # Check if session is still active
        local status=$(jq -r '.status // "active"' "${session_dir}/.session-metadata.json" 2>/dev/null || echo "active")
        if [[ "$status" == "closed" ]]; then
            log "Session closed, stopping watch"
            break
        fi

        # Sleep for 10 seconds
        sleep 10
    done
}

# Watch multiple sessions
watch_all_sessions() {
    local sessions_dir="${HOME}/Desktop/multi-claude-sessions/sessions"

    log "Starting real-time knowledge capture for all active sessions"

    while true; do
        # Find active sessions
        while IFS= read -r session_dir; do
            local status=$(jq -r '.status // "active"' "${session_dir}/.session-metadata.json" 2>/dev/null || echo "active")

            if [[ "$status" == "active" ]]; then
                # Check if already being watched
                local session_id=$(basename "$session_dir")
                local watch_marker="/tmp/knowledge-watch-${session_id}.lock"

                if [[ ! -f "$watch_marker" ]]; then
                    # Start watching in background
                    log "Starting watch for session: $session_id"
                    (
                        touch "$watch_marker"
                        watch_session "$session_dir"
                        rm -f "$watch_marker"
                    ) &
                fi
            fi
        done < <(find "$sessions_dir" -mindepth 1 -maxdepth 1 -type d -name "20*" | sort)

        # Check every minute for new sessions
        sleep 60
    done
}

# ============================================================================
# Statistics
# ============================================================================

# Show real-time capture statistics
show_stats() {
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo "No knowledge base found"
        return 0
    fi

    local realtime_count=$(jq 'select(.extracted_realtime == true)' "$knowledge_base" | wc -l)
    local total_count=$(wc -l < "$knowledge_base")
    local realtime_percentage=$(echo "scale=1; $realtime_count * 100 / $total_count" | bc)

    cat <<EOF
Real-time Knowledge Capture Statistics
======================================

Total knowledge entries: $total_count
Real-time captured: $realtime_count ($realtime_percentage%)
Broadcast directory: $BROADCAST_DIR

Recent real-time captures (last 10):
$(jq 'select(.extracted_realtime == true) | "\(.timestamp) - \(.type) - \(.id)"' "$knowledge_base" | tail -10)
EOF
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Real-time Knowledge Capture - Capture knowledge as sessions progress

Usage: $(basename "$0") <command> [options]

Commands:
  watch <session_dir>       Watch a single session
  watch-all                 Watch all active sessions (daemon)
  stats                     Show real-time capture statistics
  help                      Show this help

Examples:
  $(basename "$0") watch ~/sessions/2026-02-18-session-1
  $(basename "$0") watch-all
  $(basename "$0") stats

Use Case:
  Session A: User finds solution
  → Real-time capture extracts and indexes immediately
  → Session B (simultaneous): Searches and finds solution from 5 minutes ago
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        watch)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 watch <session_dir>"
                exit 1
            fi
            watch_session "$2"
            ;;

        watch-all)
            watch_all_sessions
            ;;

        stats)
            show_stats
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
