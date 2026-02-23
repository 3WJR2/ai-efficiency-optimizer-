#!/usr/bin/env bash

# knowledge-pipeline.sh
# Automated pipeline for continuous knowledge management
# Part of Cross-Session Knowledge Synthesis Integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"
LOG_DIR="${HOME}/.claude/logs"
PIPELINE_STATE_FILE="${DATA_DIR}/knowledge-pipeline-state.json"
PIPELINE_LOG="${LOG_DIR}/knowledge-pipeline.log"

# Create directories
mkdir -p "$KNOWLEDGE_DIR" "$LOG_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Logging
# ============================================================================

log() {
    local msg="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" | tee -a "$PIPELINE_LOG"
}

log_info() {
    log "$1" "INFO"
}

log_warn() {
    log "$1" "WARN"
}

log_error() {
    log "$1" "ERROR"
}

log_success() {
    log "$1" "SUCCESS"
}

# ============================================================================
# Pipeline State Management
# ============================================================================

# Initialize pipeline state
init_pipeline_state() {
    if [[ ! -f "$PIPELINE_STATE_FILE" ]]; then
        cat > "$PIPELINE_STATE_FILE" <<EOF
{
  "version": "1.0.0",
  "last_run": {
    "timestamp": null,
    "mode": null,
    "sessions_processed": 0,
    "knowledge_extracted": 0,
    "duration_seconds": 0
  },
  "statistics": {
    "total_runs": 0,
    "total_sessions_processed": 0,
    "total_knowledge_extracted": 0,
    "last_full_run": null,
    "last_incremental_run": null
  },
  "sessions": {},
  "daemon": {
    "enabled": false,
    "pid": null,
    "started_at": null
  }
}
EOF
        log_info "Initialized pipeline state file"
    fi
}

# Get last run timestamp
get_last_run_timestamp() {
    jq -r '.last_run.timestamp // empty' "$PIPELINE_STATE_FILE" 2>/dev/null || echo ""
}

# Update pipeline state
update_pipeline_state() {
    local mode="$1"
    local sessions_processed="$2"
    local knowledge_extracted="$3"
    local duration="$4"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp_file=$(mktemp)
    jq --arg mode "$mode" \
       --arg timestamp "$timestamp" \
       --argjson sessions "$sessions_processed" \
       --argjson knowledge "$knowledge_extracted" \
       --argjson duration "$duration" \
       '.last_run = {
          "timestamp": $timestamp,
          "mode": $mode,
          "sessions_processed": $sessions,
          "knowledge_extracted": $knowledge,
          "duration_seconds": $duration
        } |
        .statistics.total_runs += 1 |
        .statistics.total_sessions_processed += $sessions |
        .statistics.total_knowledge_extracted += $knowledge |
        if $mode == "full" then .statistics.last_full_run = $timestamp
        elif $mode == "incremental" then .statistics.last_incremental_run = $timestamp
        else . end' \
       "$PIPELINE_STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$PIPELINE_STATE_FILE"
}

# Mark session as processed
mark_session_processed() {
    local session_id="$1"
    local knowledge_count="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp_file=$(mktemp)
    jq --arg sid "$session_id" \
       --arg timestamp "$timestamp" \
       --argjson count "$knowledge_count" \
       '.sessions[$sid] = {
          "last_processed": $timestamp,
          "knowledge_extracted": $count,
          "checksum": ""
        }' \
       "$PIPELINE_STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$PIPELINE_STATE_FILE"
}

# Check if session needs processing
needs_processing() {
    local session_dir="$1"
    local session_id=$(basename "$session_dir")
    local conversation_log="${session_dir}/conversation-log.jsonl"

    # Check if conversation log exists
    [[ ! -f "$conversation_log" ]] && return 1

    # Check if session has been processed
    local last_processed=$(jq -r ".sessions.\"${session_id}\".last_processed // empty" "$PIPELINE_STATE_FILE" 2>/dev/null)

    if [[ -z "$last_processed" ]]; then
        # Never processed
        return 0
    fi

    # Check if conversation log was modified after last processing
    local log_mtime=$(stat -f %m "$conversation_log" 2>/dev/null || stat -c %Y "$conversation_log" 2>/dev/null || echo "0")
    local processed_timestamp=$(date -d "$last_processed" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_processed" +%s 2>/dev/null || echo "0")

    if [[ $log_mtime -gt $processed_timestamp ]]; then
        return 0
    fi

    return 1
}

# ============================================================================
# Pipeline Stages
# ============================================================================

# Stage 1: Extract knowledge from sessions
stage_extract() {
    local mode="$1"
    local sessions_to_process=()
    local total_knowledge=0

    log_info "Stage 1: Extract - Mode: $mode"

    # Find sessions to process
    if [[ "$mode" == "full" ]]; then
        log_info "Full extraction: processing all sessions"
        while IFS= read -r session_dir; do
            sessions_to_process+=("$session_dir")
        done < <(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name "20*" | sort)
    else
        log_info "Incremental extraction: processing modified sessions"
        while IFS= read -r session_dir; do
            if needs_processing "$session_dir"; then
                sessions_to_process+=("$session_dir")
            fi
        done < <(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name "20*" | sort)
    fi

    log_info "Found ${#sessions_to_process[@]} sessions to process"

    # Process each session
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ "$mode" == "full" ]]; then
        # Clear existing knowledge base for full run
        > "$knowledge_base"
    fi

    for session_dir in "${sessions_to_process[@]}"; do
        local session_id=$(basename "$session_dir")
        log_info "Extracting from session: $session_id"

        # Extract knowledge
        local extracted=$(bash "${SCRIPT_DIR}/knowledge-extractor.sh" extract "$session_dir" 2>/dev/null | tee -a "$knowledge_base" | wc -l)
        total_knowledge=$((total_knowledge + extracted))

        # Mark as processed
        mark_session_processed "$session_id" "$extracted"

        log_success "Extracted $extracted entries from $session_id"
    done

    log_success "Stage 1 complete: $total_knowledge knowledge entries extracted"
    echo "$total_knowledge"
}

# Stage 2: Categorize and tag knowledge
stage_categorize() {
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    log_info "Stage 2: Categorize and tag knowledge"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        log_warn "No knowledge to categorize"
        return 0
    fi

    local total=$(wc -l < "$knowledge_base")
    log_info "Categorizing $total knowledge entries"

    # Add domain categorization
    local categorized="${KNOWLEDGE_DIR}/knowledge-categorized.jsonl"
    > "$categorized"

    while IFS= read -r entry; do
        # Extract tags and determine domain
        local tags=$(echo "$entry" | jq -r '.tags[]' 2>/dev/null || echo "")
        local domain="general"

        # Categorize by domain
        if echo "$tags" | grep -qE "(python|javascript|typescript|golang|rust)"; then
            domain="backend"
        elif echo "$tags" | grep -qE "(react|vue|angular|css|html)"; then
            domain="frontend"
        elif echo "$tags" | grep -qE "(docker|kubernetes|aws|deploy|ci/cd)"; then
            domain="devops"
        elif echo "$tags" | grep -qE "(auth|security|encrypt|vulnerabil)"; then
            domain="security"
        elif echo "$tags" | grep -qE "(database|sql|postgres|redis|mongodb)"; then
            domain="database"
        fi

        # Add domain to entry
        echo "$entry" | jq --arg domain "$domain" '. + {"domain": $domain}' >> "$categorized"
    done < "$knowledge_base"

    # Replace original with categorized
    mv "$categorized" "$knowledge_base"

    log_success "Stage 2 complete: Knowledge categorized"
}

# Stage 3: Index knowledge (semantic search)
stage_index() {
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    log_info "Stage 3: Index knowledge for semantic search"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        log_warn "No knowledge to index"
        return 0
    fi

    # Note: This would integrate with vector search system
    # For now, create a simple text index
    local index_file="${KNOWLEDGE_DIR}/knowledge-index.txt"
    > "$index_file"

    while IFS= read -r entry; do
        local id=$(echo "$entry" | jq -r '.id')
        local problem=$(echo "$entry" | jq -r '.problem')
        local solution=$(echo "$entry" | jq -r '.solution')
        local tags=$(echo "$entry" | jq -r '.tags | join(" ")')

        echo "$id|$problem $solution $tags" >> "$index_file"
    done < "$knowledge_base"

    log_success "Stage 3 complete: Knowledge indexed"
}

# Stage 4: Build knowledge graph
stage_graph() {
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    log_info "Stage 4: Build knowledge graph"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        log_warn "No knowledge to graph"
        return 0
    fi

    # Build simple graph based on tag relationships
    local graph_file="${KNOWLEDGE_DIR}/knowledge-graph.json"

    # Extract all entries with their tags
    local nodes=$(jq -s 'map({id: .id, type: .type, tags: .tags, confidence: .confidence})' "$knowledge_base")

    # Find related entries (share 2+ tags)
    local edges=[]

    echo "$nodes" | jq '{nodes: ., edges: []}' > "$graph_file"

    log_success "Stage 4 complete: Knowledge graph built"
}

# Stage 5: Deduplicate similar entries
stage_deduplicate() {
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    log_info "Stage 5: Deduplicate similar entries"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        log_warn "No knowledge to deduplicate"
        return 0
    fi

    # Simple deduplication based on problem similarity
    # In production, this would use embeddings and cosine similarity
    local deduplicated="${KNOWLEDGE_DIR}/knowledge-deduplicated.jsonl"
    local seen_problems=()

    > "$deduplicated"

    while IFS= read -r entry; do
        local problem=$(echo "$entry" | jq -r '.problem' | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]')
        local is_duplicate=false

        # Check if we've seen a similar problem
        for seen in "${seen_problems[@]}"; do
            # Simple similarity: first 50 chars
            local problem_prefix=${problem:0:50}
            local seen_prefix=${seen:0:50}

            if [[ "$problem_prefix" == "$seen_prefix" ]]; then
                is_duplicate=true
                break
            fi
        done

        if [[ "$is_duplicate" == false ]]; then
            echo "$entry" >> "$deduplicated"
            seen_problems+=("$problem")
        fi
    done < "$knowledge_base"

    local original_count=$(wc -l < "$knowledge_base")
    local deduplicated_count=$(wc -l < "$deduplicated")
    local removed=$((original_count - deduplicated_count))

    mv "$deduplicated" "$knowledge_base"

    log_success "Stage 5 complete: Removed $removed duplicate entries"
}

# Stage 6: Publish knowledge (make available)
stage_publish() {
    log_info "Stage 6: Publish knowledge"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        log_warn "No knowledge to publish"
        return 0
    fi

    # Create summary statistics
    local stats_file="${KNOWLEDGE_DIR}/knowledge-stats.json"

    local total=$(wc -l < "$knowledge_base")
    local by_type=$(jq -s 'group_by(.type) | map({type: .[0].type, count: length})' "$knowledge_base")
    local by_domain=$(jq -s 'group_by(.domain) | map({domain: .[0].domain, count: length})' "$knowledge_base")
    local avg_confidence=$(jq -s 'map(.confidence) | add / length' "$knowledge_base")

    cat > "$stats_file" <<EOF
{
  "total_entries": $total,
  "by_type": $by_type,
  "by_domain": $by_domain,
  "average_confidence": $avg_confidence,
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    log_success "Stage 6 complete: Knowledge published"
}

# ============================================================================
# Pipeline Execution
# ============================================================================

# Run full pipeline
run_pipeline_full() {
    log_info "Starting FULL knowledge pipeline"
    local start_time=$(date +%s)

    # Initialize state
    init_pipeline_state

    # Run all stages
    local total_knowledge=$(stage_extract "full")
    stage_categorize
    stage_index
    stage_graph
    stage_deduplicate
    stage_publish

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Update state
    update_pipeline_state "full" "all" "$total_knowledge" "$duration"

    log_success "Pipeline complete in ${duration}s: $total_knowledge knowledge entries"
}

# Run incremental pipeline
run_pipeline_incremental() {
    log_info "Starting INCREMENTAL knowledge pipeline"
    local start_time=$(date +%s)

    # Initialize state
    init_pipeline_state

    # Run all stages
    local total_knowledge=$(stage_extract "incremental")

    if [[ "$total_knowledge" -gt 0 ]]; then
        stage_categorize
        stage_index
        stage_graph
        stage_deduplicate
        stage_publish
    else
        log_info "No new knowledge to process"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Update state
    update_pipeline_state "incremental" "$total_knowledge" "$total_knowledge" "$duration"

    log_success "Pipeline complete in ${duration}s: $total_knowledge knowledge entries"
}

# Watch for changes and run incremental pipeline
watch_sessions() {
    log_info "Starting watch mode - monitoring for session changes"

    # Update daemon status
    local tmp_file=$(mktemp)
    jq --arg pid "$$" \
       --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.daemon = {
          "enabled": true,
          "pid": $pid,
          "started_at": $timestamp
        }' \
       "$PIPELINE_STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$PIPELINE_STATE_FILE"

    # Watch loop
    while true; do
        # Check for modified sessions
        local has_changes=false

        while IFS= read -r session_dir; do
            if needs_processing "$session_dir"; then
                has_changes=true
                break
            fi
        done < <(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name "20*")

        if [[ "$has_changes" == true ]]; then
            log_info "Changes detected - running incremental pipeline"
            run_pipeline_incremental
        fi

        # Sleep for 5 minutes
        sleep 300
    done
}

# Show pipeline status
show_status() {
    init_pipeline_state

    echo ""
    echo "Knowledge Pipeline Status"
    echo "========================="
    echo ""

    # Last run
    local last_run_timestamp=$(jq -r '.last_run.timestamp // "Never"' "$PIPELINE_STATE_FILE")
    local last_run_mode=$(jq -r '.last_run.mode // "N/A"' "$PIPELINE_STATE_FILE")
    local last_run_sessions=$(jq -r '.last_run.sessions_processed // 0' "$PIPELINE_STATE_FILE")
    local last_run_knowledge=$(jq -r '.last_run.knowledge_extracted // 0' "$PIPELINE_STATE_FILE")

    echo "Last Run:"
    echo "  Time: $last_run_timestamp"
    echo "  Mode: $last_run_mode"
    echo "  Sessions: $last_run_sessions"
    echo "  Knowledge: $last_run_knowledge"
    echo ""

    # Statistics
    local total_runs=$(jq -r '.statistics.total_runs' "$PIPELINE_STATE_FILE")
    local total_sessions=$(jq -r '.statistics.total_sessions_processed' "$PIPELINE_STATE_FILE")
    local total_knowledge=$(jq -r '.statistics.total_knowledge_extracted' "$PIPELINE_STATE_FILE")

    echo "Statistics:"
    echo "  Total Runs: $total_runs"
    echo "  Total Sessions Processed: $total_sessions"
    echo "  Total Knowledge Extracted: $total_knowledge"
    echo ""

    # Daemon status
    local daemon_enabled=$(jq -r '.daemon.enabled' "$PIPELINE_STATE_FILE")
    local daemon_pid=$(jq -r '.daemon.pid // ""' "$PIPELINE_STATE_FILE")

    echo "Daemon:"
    if [[ "$daemon_enabled" == "true" ]] && [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
        echo "  Status: Running (PID: $daemon_pid)"
    else
        echo "  Status: Stopped"
    fi
    echo ""

    # Knowledge base
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"
    if [[ -f "$knowledge_base" ]]; then
        local kb_entries=$(wc -l < "$knowledge_base")
        echo "Knowledge Base:"
        echo "  Entries: $kb_entries"
        echo "  Location: $knowledge_base"
    fi
    echo ""
}

# Show pipeline metrics
show_metrics() {
    init_pipeline_state

    echo ""
    echo "Knowledge Pipeline Metrics"
    echo "=========================="
    echo ""

    bash "${SCRIPT_DIR}/knowledge-extractor.sh" stats "${KNOWLEDGE_DIR}/knowledge-base.jsonl" 2>/dev/null || echo "No knowledge base found"
}

# ============================================================================
# Main CLI
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Pipeline - Automated knowledge management pipeline

Usage: $(basename "$0") <command>

Commands:
  full              Run full pipeline (all sessions)
  incremental       Run incremental pipeline (modified sessions only)
  watch             Watch for changes and auto-run incremental
  status            Show pipeline status
  metrics           Show detailed metrics
  help              Show this help

Examples:
  $(basename "$0") full
  $(basename "$0") incremental
  $(basename "$0") watch
  $(basename "$0") status

Notes:
  - Full pipeline: ~5-10 minutes for 100 sessions
  - Incremental: <30 seconds typically
  - Watch mode: runs as daemon
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        full)
            run_pipeline_full
            ;;
        incremental)
            run_pipeline_incremental
            ;;
        watch)
            watch_sessions
            ;;
        status)
            show_status
            ;;
        metrics)
            show_metrics
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
