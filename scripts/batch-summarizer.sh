#!/usr/bin/env bash
#
# batch-summarizer.sh - Batch summarization of multiple sessions
#
# Part of the Conversation Summarization System
# Efficiently summarizes multiple sessions with progress tracking
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.claude/data"
SUMMARIES_DIR="$HOME/.claude/summaries"

# Source dependencies
source "$SCRIPT_DIR/conversation-summarizer.sh"
source "$SCRIPT_DIR/summary-cache-manager.sh"

# Progress tracking
declare -g TOTAL_SESSIONS=0
declare -g COMPLETED_SESSIONS=0
declare -g FAILED_SESSIONS=0
declare -g START_TIME=0

# Initialize progress tracking
init_progress() {
    TOTAL_SESSIONS="$1"
    COMPLETED_SESSIONS=0
    FAILED_SESSIONS=0
    START_TIME=$(date +%s)
}

# Update progress
update_progress() {
    local session_id="$1"
    local status="$2"  # success or failed

    if [ "$status" = "success" ]; then
        ((COMPLETED_SESSIONS++))
    else
        ((FAILED_SESSIONS++))
    fi

    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local remaining=$((TOTAL_SESSIONS - COMPLETED_SESSIONS - FAILED_SESSIONS))
    local rate=0

    if [ $elapsed -gt 0 ]; then
        rate=$(echo "scale=2; $COMPLETED_SESSIONS / $elapsed" | bc)
    fi

    local eta="N/A"
    if [ $(echo "$rate > 0" | bc) -eq 1 ]; then
        local eta_seconds=$(echo "scale=0; $remaining / $rate" | bc)
        eta=$(printf "%02d:%02d" $((eta_seconds / 60)) $((eta_seconds % 60)))
    fi

    printf "\rProgress: %d/%d completed, %d failed | Rate: %.2f/sec | ETA: %s" \
        "$COMPLETED_SESSIONS" "$TOTAL_SESSIONS" "$FAILED_SESSIONS" "$rate" "$eta"
}

# Show final summary
show_summary() {
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))

    echo ""
    echo ""
    echo "Batch Summarization Complete"
    echo "============================"
    echo "Total sessions:    $TOTAL_SESSIONS"
    echo "Completed:         $COMPLETED_SESSIONS"
    echo "Failed:            $FAILED_SESSIONS"
    echo "Total time:        ${total_time}s"

    if [ $COMPLETED_SESSIONS -gt 0 ]; then
        local avg_time=$(echo "scale=2; $total_time / $COMPLETED_SESSIONS" | bc)
        echo "Average per session: ${avg_time}s"
    fi
}

# Find session files
find_session_files() {
    local search_path="$1"
    local pattern="${2:-*.txt}"

    if [ -d "$search_path" ]; then
        find "$search_path" -name "$pattern" -type f
    else
        echo ""
    fi
}

# Extract session ID from filename
extract_session_id() {
    local filename="$1"
    basename "$filename" | sed 's/\.[^.]*$//'
}

# Summarize all sessions in directory
summarize_all_sessions() {
    local sessions_dir="${1:-$DATA_DIR/sessions}"
    local detail_level="${2:-standard}"
    local force_regenerate="${3:-false}"

    if [ ! -d "$sessions_dir" ]; then
        echo "Error: Sessions directory not found: $sessions_dir" >&2
        return 1
    fi

    # Find all session files
    local session_files=$(find_session_files "$sessions_dir" "*.txt")
    local session_count=$(echo "$session_files" | grep -c . || echo 0)

    if [ $session_count -eq 0 ]; then
        echo "No session files found in: $sessions_dir" >&2
        return 1
    fi

    echo "Found $session_count sessions to summarize"
    echo "Detail level: $detail_level"
    echo ""

    init_progress "$session_count"

    # Process each session
    while IFS= read -r session_file; do
        local session_id=$(extract_session_id "$session_file")

        # Check cache first unless force regenerate
        if [ "$force_regenerate" != "true" ]; then
            local cached=$(lookup_cache "$session_id" "$detail_level" 2>/dev/null || echo "")
            if [ -n "$cached" ]; then
                update_progress "$session_id" "success"
                continue
            fi
        fi

        # Generate summary
        local output_file="$SUMMARIES_DIR/${session_id}-${detail_level}.md"

        if summarize_and_save "$session_id" "$detail_level" "$session_file" "$output_file" 2>/dev/null; then
            update_progress "$session_id" "success"
        else
            update_progress "$session_id" "failed"
            echo "" >&2
            echo "Failed to summarize: $session_id" >&2
        fi
    done <<< "$session_files"

    show_summary
}

# Summarize recent sessions
summarize_recent() {
    local days="${1:-7}"
    local detail_level="${2:-standard}"
    local sessions_dir="${3:-$DATA_DIR/sessions}"
    local force_regenerate="${4:-false}"

    if [ ! -d "$sessions_dir" ]; then
        echo "Error: Sessions directory not found: $sessions_dir" >&2
        return 1
    fi

    echo "Summarizing sessions from last $days days"

    # Find files modified in last N days
    local session_files=$(find "$sessions_dir" -name "*.txt" -type f -mtime -"$days")
    local session_count=$(echo "$session_files" | grep -c . || echo 0)

    if [ $session_count -eq 0 ]; then
        echo "No recent session files found" >&2
        return 1
    fi

    echo "Found $session_count recent sessions"
    echo "Detail level: $detail_level"
    echo ""

    init_progress "$session_count"

    # Process each session
    while IFS= read -r session_file; do
        local session_id=$(extract_session_id "$session_file")

        # Check cache first unless force regenerate
        if [ "$force_regenerate" != "true" ]; then
            local cached=$(lookup_cache "$session_id" "$detail_level" 2>/dev/null || echo "")
            if [ -n "$cached" ]; then
                update_progress "$session_id" "success"
                continue
            fi
        fi

        # Generate summary
        local output_file="$SUMMARIES_DIR/${session_id}-${detail_level}.md"

        if summarize_and_save "$session_id" "$detail_level" "$session_file" "$output_file" 2>/dev/null; then
            update_progress "$session_id" "success"
        else
            update_progress "$session_id" "failed"
        fi
    done <<< "$session_files"

    show_summary
}

# Update outdated summaries
update_summaries() {
    local age_days="${1:-30}"
    local detail_level="${2:-standard}"
    local sessions_dir="${3:-$DATA_DIR/sessions}"

    echo "Updating summaries older than $age_days days"

    # Find summaries older than age_days
    local old_summaries=$(find "$SUMMARIES_DIR" -name "*-${detail_level}.md" -type f -mtime +"$age_days")
    local summary_count=$(echo "$old_summaries" | grep -c . || echo 0)

    if [ $summary_count -eq 0 ]; then
        echo "No summaries need updating"
        return 0
    fi

    echo "Found $summary_count summaries to update"
    echo ""

    init_progress "$summary_count"

    # Process each old summary
    while IFS= read -r summary_file; do
        local filename=$(basename "$summary_file")
        local session_id=$(echo "$filename" | sed "s/-${detail_level}\.md$//")

        # Find corresponding session file
        local session_file=$(find "$sessions_dir" -name "${session_id}.txt" -type f | head -1)

        if [ -z "$session_file" ]; then
            update_progress "$session_id" "failed"
            continue
        fi

        # Invalidate cache and regenerate
        invalidate_cache "$session_id" "$detail_level" 2>/dev/null

        local output_file="$SUMMARIES_DIR/${session_id}-${detail_level}.md"

        if summarize_and_save "$session_id" "$detail_level" "$session_file" "$output_file" 2>/dev/null; then
            update_progress "$session_id" "success"
        else
            update_progress "$session_id" "failed"
        fi
    done <<< "$old_summaries"

    show_summary
}

# Parallel batch processing
summarize_parallel() {
    local sessions_dir="${1:-$DATA_DIR/sessions}"
    local detail_level="${2:-standard}"
    local max_parallel="${3:-4}"

    echo "Running parallel summarization (max $max_parallel concurrent)"

    local session_files=$(find_session_files "$sessions_dir" "*.txt")
    local session_count=$(echo "$session_files" | grep -c . || echo 0)

    if [ $session_count -eq 0 ]; then
        echo "No session files found" >&2
        return 1
    fi

    init_progress "$session_count"

    # Process in parallel
    echo "$session_files" | xargs -P "$max_parallel" -I {} bash -c '
        session_file="$1"
        detail_level="$2"
        session_id=$(basename "$session_file" | sed "s/\.[^.]*$//")
        output_file="$SUMMARIES_DIR/${session_id}-${detail_level}.md"

        source "'$SCRIPT_DIR'/conversation-summarizer.sh"
        summarize_and_save "$session_id" "$detail_level" "$session_file" "$output_file" 2>/dev/null
    ' _ {} "$detail_level"

    show_summary
}

# CLI interface
main() {
    local command="${1:-}"

    case "$command" in
        all)
            shift
            local sessions_dir="${1:-$DATA_DIR/sessions}"
            local detail_level="${2:-standard}"
            local force="${3:-false}"

            summarize_all_sessions "$sessions_dir" "$detail_level" "$force"
            ;;
        recent)
            shift
            local days="${1:-7}"
            local detail_level="${2:-standard}"
            local sessions_dir="${3:-$DATA_DIR/sessions}"

            summarize_recent "$days" "$detail_level" "$sessions_dir"
            ;;
        update)
            shift
            local age_days="${1:-30}"
            local detail_level="${2:-standard}"
            local sessions_dir="${3:-$DATA_DIR/sessions}"

            update_summaries "$age_days" "$detail_level" "$sessions_dir"
            ;;
        parallel)
            shift
            local sessions_dir="${1:-$DATA_DIR/sessions}"
            local detail_level="${2:-standard}"
            local max_parallel="${3:-4}"

            summarize_parallel "$sessions_dir" "$detail_level" "$max_parallel"
            ;;
        *)
            echo "Usage: $0 {all|recent|update|parallel} [params]" >&2
            echo "" >&2
            echo "Commands:" >&2
            echo "  all      - Summarize all sessions in directory" >&2
            echo "            Usage: $0 all [sessions_dir] [detail_level] [force]" >&2
            echo "" >&2
            echo "  recent   - Summarize recent sessions" >&2
            echo "            Usage: $0 recent [days] [detail_level] [sessions_dir]" >&2
            echo "" >&2
            echo "  update   - Update outdated summaries" >&2
            echo "            Usage: $0 update [age_days] [detail_level] [sessions_dir]" >&2
            echo "" >&2
            echo "  parallel - Parallel batch summarization" >&2
            echo "            Usage: $0 parallel [sessions_dir] [detail_level] [max_parallel]" >&2
            exit 1
            ;;
    esac
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
