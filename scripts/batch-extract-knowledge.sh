#!/usr/bin/env bash

# batch-extract-knowledge.sh
# Batch processing for knowledge extraction pipeline
# Part of Cross-Session Knowledge Extraction System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-${HOME}/.claude/knowledge}"
SESSIONS_DIR="${SESSIONS_DIR:-${HOME}/Desktop/multi-claude-sessions/sessions}"

# Scripts
EXTRACTOR="${SCRIPT_DIR}/knowledge-extractor.sh"
CATEGORIZER="${SCRIPT_DIR}/knowledge-categorizer.sh"
INDEXER="${SCRIPT_DIR}/knowledge-indexer.sh"
SCORER="${SCRIPT_DIR}/knowledge-quality-scorer.sh"

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

# Check if required scripts exist
check_dependencies() {
    local missing=()

    [[ ! -f "$EXTRACTOR" ]] && missing+=("knowledge-extractor.sh")
    [[ ! -f "$CATEGORIZER" ]] && missing+=("knowledge-categorizer.sh")
    [[ ! -f "$INDEXER" ]] && missing+=("knowledge-indexer.sh")
    [[ ! -f "$SCORER" ]] && missing+=("knowledge-quality-scorer.sh")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required scripts: ${missing[*]}"
    fi
}

# ============================================================================
# Full Pipeline
# ============================================================================

# Run complete extraction and indexing pipeline
run_full_pipeline() {
    local output_base="${KNOWLEDGE_DIR}/knowledge-base"

    log "Starting full knowledge extraction pipeline"
    log "================================================"

    # Step 1: Extract knowledge from all sessions
    log "Step 1/5: Extracting knowledge from sessions"
    "$EXTRACTOR" extract-all > "${output_base}.jsonl" 2>&1

    local extracted_count=$(wc -l < "${output_base}.jsonl")
    log "Extracted $extracted_count knowledge entries"

    # Step 2: Categorize knowledge
    log "Step 2/5: Categorizing knowledge"
    "$CATEGORIZER" categorize "${output_base}.jsonl" "${output_base}-categorized.jsonl"

    # Step 3: Score quality
    log "Step 3/5: Scoring quality"
    "$SCORER" score "${output_base}-categorized.jsonl" "${output_base}-scored.jsonl"

    # Step 4: Index for search
    log "Step 4/5: Building search index"
    "$INDEXER" index "${output_base}-scored.jsonl"

    # Step 5: Deduplicate
    log "Step 5/5: Deduplicating entries"
    "$INDEXER" deduplicate

    log "Pipeline complete!"
    log "================================================"

    # Show summary
    show_pipeline_summary
}

# Run incremental update (only new sessions)
run_incremental_update() {
    local since_date="$1"

    log "Starting incremental knowledge update since: $since_date"
    log "================================================"

    local new_entries="${KNOWLEDGE_DIR}/new-entries-${since_date}.jsonl"

    # Extract from recent sessions
    log "Step 1/5: Extracting from recent sessions"
    "$EXTRACTOR" extract-since "$since_date" "$new_entries"

    local new_count=$(wc -l < "$new_entries")
    log "Extracted $new_count new entries"

    [[ $new_count -eq 0 ]] && {
        log "No new entries found"
        return 0
    }

    # Categorize
    log "Step 2/5: Categorizing new entries"
    "$CATEGORIZER" categorize "$new_entries" "${new_entries%.jsonl}-categorized.jsonl"

    # Score
    log "Step 3/5: Scoring quality"
    "$SCORER" score "${new_entries%.jsonl}-categorized.jsonl" "${new_entries%.jsonl}-scored.jsonl"

    # Update index
    log "Step 4/5: Updating search index"
    "$INDEXER" update "${new_entries%.jsonl}-scored.jsonl"

    # Deduplicate
    log "Step 5/5: Deduplicating"
    "$INDEXER" deduplicate

    log "Incremental update complete!"
    log "Added $new_count new entries"
}

# Rebuild entire index from scratch
rebuild_index() {
    log "Rebuilding entire knowledge index"
    log "================================================"

    # Backup existing data
    if [[ -f "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" ]]; then
        local backup_file="${KNOWLEDGE_DIR}/knowledge-embeddings-backup-$(date +%Y%m%d-%H%M%S).jsonl"
        cp "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" "$backup_file"
        log "Backed up existing index to: $backup_file"
    fi

    # Clear existing index
    rm -f "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl"
    rm -f "${KNOWLEDGE_DIR}/knowledge-metadata.json"
    rm -f "${KNOWLEDGE_DIR}/duplicates.csv"

    # Run full pipeline
    run_full_pipeline
}

# ============================================================================
# Maintenance Tasks
# ============================================================================

# Daily maintenance: extract new sessions
daily_maintenance() {
    log "Running daily maintenance"

    # Extract from yesterday
    local yesterday=$(date -v-1d +"%Y-%m-%d" 2>/dev/null || date -d "yesterday" +"%Y-%m-%d")

    run_incremental_update "$yesterday"
}

# Weekly maintenance: deduplicate and cleanup
weekly_maintenance() {
    log "Running weekly maintenance"

    # Deduplicate
    log "Deduplicating knowledge base"
    "$INDEXER" deduplicate

    # Rescore based on new applications
    log "Rescoring knowledge entries"
    "$SCORER" rescore

    # Clean up old temporary files
    log "Cleaning up temporary files"
    find "$KNOWLEDGE_DIR" -name "new-entries-*.jsonl" -mtime +30 -delete
    find "$KNOWLEDGE_DIR" -name "*-backup-*.jsonl" -mtime +90 -delete
}

# Monthly maintenance: full cleanup
monthly_maintenance() {
    log "Running monthly maintenance"

    # Run weekly tasks
    weekly_maintenance

    # Archive low-quality entries
    log "Archiving low-quality entries"
    local archive_file="${KNOWLEDGE_DIR}/archive/low-quality-$(date +%Y%m).jsonl"
    mkdir -p "${KNOWLEDGE_DIR}/archive"

    jq 'select(.confidence < 0.3)' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" > "$archive_file"

    # Remove from main index
    local temp_file=$(mktemp)
    jq 'select(.confidence >= 0.3)' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" > "$temp_file"
    mv "$temp_file" "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl"

    log "Archived $(wc -l < "$archive_file") low-quality entries"
}

# ============================================================================
# Summary and Statistics
# ============================================================================

show_pipeline_summary() {
    log "Knowledge Base Summary"
    log "====================="

    # File sizes
    log "Files created:"
    ls -lh "$KNOWLEDGE_DIR"/knowledge-*.jsonl 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'

    # Statistics
    if [[ -f "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" ]]; then
        local total=$(wc -l < "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl")
        log ""
        log "Total knowledge entries: $total"

        log ""
        log "By type:"
        jq -r '.type' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" | sort | uniq -c | sort -rn

        log ""
        log "By quality:"
        local high=$(jq 'select(.confidence >= 0.7)' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" | wc -l)
        local medium=$(jq 'select(.confidence >= 0.5 and .confidence < 0.7)' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" | wc -l)
        local low=$(jq 'select(.confidence < 0.5)' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" | wc -l)

        log "  High (≥0.7): $high"
        log "  Medium (0.5-0.7): $medium"
        log "  Low (<0.5): $low"

        log ""
        log "Average confidence: $(jq -s 'map(.confidence) | add / length' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl")"
    fi
}

# Show extraction progress
show_progress() {
    log "Extraction Progress"
    log "==================="

    # Count sessions
    local total_sessions=$(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    log "Total sessions: $total_sessions"

    # Count extracted knowledge
    if [[ -f "${KNOWLEDGE_DIR}/knowledge-base.jsonl" ]]; then
        local extracted=$(wc -l < "${KNOWLEDGE_DIR}/knowledge-base.jsonl")
        log "Extracted entries: $extracted"

        local sessions_with_knowledge=$(jq -r '.session_id' "${KNOWLEDGE_DIR}/knowledge-base.jsonl" | sort -u | wc -l)
        log "Sessions with knowledge: $sessions_with_knowledge"

        log "Average entries per session: $(echo "scale=2; $extracted / $sessions_with_knowledge" | bc)"
    fi

    # Show recent activity
    if [[ -f "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" ]]; then
        log ""
        log "Recent knowledge (last 7 days):"
        local cutoff=$(date -v-7d +"%Y-%m-%d" 2>/dev/null || date -d "7 days ago" +"%Y-%m-%d")
        local recent=$(jq --arg cutoff "$cutoff" 'select(.timestamp >= $cutoff)' "${KNOWLEDGE_DIR}/knowledge-embeddings.jsonl" | wc -l)
        log "  $recent entries"
    fi
}

# ============================================================================
# Testing
# ============================================================================

# Run test extraction on sample
test_extraction() {
    log "Running test extraction"

    # Find a recent session
    local test_session=$(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | head -1)

    if [[ -z "$test_session" ]]; then
        error "No sessions found for testing"
    fi

    log "Testing on session: $(basename "$test_session")"

    # Extract
    "$EXTRACTOR" extract "$test_session" > "${KNOWLEDGE_DIR}/test-extraction.jsonl"

    local count=$(wc -l < "${KNOWLEDGE_DIR}/test-extraction.jsonl")
    log "Extracted $count entries"

    # Show sample
    if [[ $count -gt 0 ]]; then
        log "Sample entry:"
        head -1 "${KNOWLEDGE_DIR}/test-extraction.jsonl" | jq '.'
    fi
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Batch Knowledge Extraction - Run full extraction pipeline

Usage: $(basename "$0") <command> [options]

Commands:
  extract-all           Run full extraction pipeline on all sessions
  extract-since <date>  Incremental update from sessions since date
  rebuild               Rebuild entire index from scratch
  daily                 Daily maintenance (extract yesterday)
  weekly                Weekly maintenance (deduplicate, rescore)
  monthly               Monthly maintenance (archive low-quality)
  progress              Show extraction progress
  summary               Show knowledge base summary
  test                  Test extraction on sample session
  help                  Show this help message

Examples:
  $(basename "$0") extract-all
  $(basename "$0") extract-since 2026-02-01
  $(basename "$0") rebuild
  $(basename "$0") daily
  $(basename "$0") summary

Recommended Cron Schedule:
  # Daily extraction at 2 AM
  0 2 * * * ~/.claude/scripts/$(basename "$0") daily >> ~/.claude/logs/knowledge-extraction.log 2>&1

  # Weekly maintenance on Sunday at 3 AM
  0 3 * * 0 ~/.claude/scripts/$(basename "$0") weekly >> ~/.claude/logs/knowledge-maintenance.log 2>&1

  # Monthly cleanup on 1st at 4 AM
  0 4 1 * * ~/.claude/scripts/$(basename "$0") monthly >> ~/.claude/logs/knowledge-cleanup.log 2>&1
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"

    # Check dependencies
    check_dependencies

    case "$command" in
        extract-all)
            run_full_pipeline
            ;;
        extract-since)
            [[ $# -lt 2 ]] && error "Usage: $0 extract-since <date>"
            run_incremental_update "$2"
            ;;
        rebuild)
            rebuild_index
            ;;
        daily)
            daily_maintenance
            ;;
        weekly)
            weekly_maintenance
            ;;
        monthly)
            monthly_maintenance
            ;;
        progress)
            show_progress
            ;;
        summary)
            show_pipeline_summary
            ;;
        test)
            test_extraction
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: $command\nRun '$0 help' for usage"
            ;;
    esac
}

main "$@"
