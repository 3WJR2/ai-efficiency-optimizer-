#!/usr/bin/env bash

# insight-injector.sh - Inject learning insights into session context
# Version: 1.0.0
# Part of Phase B: Learning Integration Engine

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
LEARNING_READER="${SCRIPT_DIR}/learning-reader.sh"
SESSION_CONTEXT_FILE=".claude/project-context.md"
CONFIDENCE_THRESHOLD="${CONFIDENCE_THRESHOLD:-0.70}"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Check if learning reader exists
check_dependencies() {
    if [[ ! -f "$LEARNING_READER" ]]; then
        error "Learning reader not found: $LEARNING_READER"
    fi

    if [[ ! -x "$LEARNING_READER" ]]; then
        chmod +x "$LEARNING_READER"
    fi
}

# Format insight for markdown
format_insight_markdown() {
    local insight_json=$1

    local type=$(echo "$insight_json" | jq -r '.type')
    local confidence=$(echo "$insight_json" | jq -r '.confidence')
    local recommendation=$(echo "$insight_json" | jq -r '.insights.recommendation')

    local confidence_pct=$(printf "%.0f%%" $(echo "$confidence * 100" | bc -l))

    case "$type" in
        cache_optimization)
            local hit_rate=$(echo "$insight_json" | jq -r '.insights.average_hit_rate')
            local threshold=$(echo "$insight_json" | jq -r '.insights.optimal_threshold')
            cat <<EOF
### Cache Optimization (Confidence: $confidence_pct)

**Current Performance:**
- Average hit rate: $(printf "%.1f%%" $(echo "$hit_rate * 100" | bc -l))
- Optimal threshold: ${threshold:-Learning...}

**Recommendation:** $recommendation

EOF
            ;;
        parallel_optimization)
            local success_rate=$(echo "$insight_json" | jq -r '.insights.average_success_rate')
            local processes=$(echo "$insight_json" | jq -r '.insights.optimal_processes')
            cat <<EOF
### Parallel Execution (Confidence: $confidence_pct)

**Current Performance:**
- Success rate: $(printf "%.1f%%" $(echo "$success_rate * 100" | bc -l))
- Optimal concurrent processes: ${processes:-Learning...}

**Recommendation:** $recommendation

EOF
            ;;
        user_preferences)
            local stage=$(echo "$insight_json" | jq -r '.insights.learning_stage')
            local prefs=$(echo "$insight_json" | jq -r '.insights.preferences | to_entries | map("\(.key): \(.value)") | join(", ")')
            cat <<EOF
### Your Preferences (Confidence: $confidence_pct)

**Learning Stage:** $stage

**Detected Preferences:**
$prefs

**Recommendation:** $recommendation

EOF
            ;;
        technology_preferences)
            local top_techs=$(echo "$insight_json" | jq -r '.insights.top_technologies | map("\(.key) (used \(.value)x)") | join(", ")')
            cat <<EOF
### Technology Stack (Confidence: $confidence_pct)

**Primary Technologies:** $top_techs

**Recommendation:** $recommendation

EOF
            ;;
        successful_strategies)
            local strategies=$(echo "$insight_json" | jq -r '.insights.strategies | join(", ")')
            cat <<EOF
### Successful Patterns (Confidence: $confidence_pct)

**Proven Strategies:** $strategies

**Recommendation:** $recommendation

EOF
            ;;
        common_pitfalls)
            local pitfalls=$(echo "$insight_json" | jq -r '.insights.pitfalls | map("- \(.)") | join("\n")')
            cat <<EOF
### Known Issues (Confidence: $confidence_pct)

**Common Pitfalls to Avoid:**
$pitfalls

**Recommendation:** $recommendation

EOF
            ;;
        *)
            cat <<EOF
### $type (Confidence: $confidence_pct)

**Recommendation:** $recommendation

EOF
            ;;
    esac
}

# Generate project context markdown
generate_context_markdown() {
    local insights_json=$1
    local target_dir=${2:-.}

    local total_insights=$(echo "$insights_json" | jq '.total_insights')
    local extracted_at=$(echo "$insights_json" | jq -r '.extracted_at')
    local threshold=$(echo "$insights_json" | jq -r '.confidence_threshold')

    # Start building markdown
    cat <<EOF
# Project Context - AI Learning Insights

**Generated:** $extracted_at
**Confidence Threshold:** $threshold
**Total Insights:** $total_insights

---

## Learning System Status

This project context has been automatically generated from the global learning system.
The insights below represent learned patterns from your interactions with Claude.

EOF

    # Add insights if any
    if [[ $total_insights -gt 0 ]]; then
        cat <<EOF
## Actionable Insights

EOF
        # Process each insight
        local insights=$(echo "$insights_json" | jq -c '.insights[]')
        while IFS= read -r insight; do
            format_insight_markdown "$insight"
        done <<< "$insights"
    else
        cat <<EOF
## No Insights Yet

The learning system is still gathering data. As you interact with Claude,
patterns will be detected and insights will appear here.

**How to accelerate learning:**
- Use the system regularly
- Provide feedback on responses
- Try different types of tasks
- Enable session outcome tracking

EOF
    fi

    # Add footer
    cat <<EOF

---

## About This Context

This file is automatically generated by the Learning Integration Engine (Phase B).
It connects your global learning data to this specific session.

**Data Sources:**
- Cache optimization metrics
- Parallel execution performance
- User interaction patterns
- Technology preferences
- Successful strategies from past sessions

**Privacy Note:** All data is stored locally in \`~/.claude/data/\`.
No information is transmitted externally.

**To update this context:**
\`\`\`bash
~/.claude/scripts/insight-injector.sh inject
\`\`\`

**To view raw insights:**
\`\`\`bash
~/.claude/scripts/learning-reader.sh extract
\`\`\`

EOF
}

# Inject insights into session
inject_insights() {
    local target_dir=${1:-.}
    local threshold=${2:-$CONFIDENCE_THRESHOLD}

    log "Injecting insights into: $target_dir"

    check_dependencies

    # Extract insights
    log "Extracting insights with threshold: $threshold"
    local insights_json=$("$LEARNING_READER" extract "$threshold")

    if [[ -z "$insights_json" ]]; then
        error "Failed to extract insights"
    fi

    # Check if .claude directory exists, create if not
    local claude_dir="${target_dir}/.claude"
    if [[ ! -d "$claude_dir" ]]; then
        log "Creating .claude directory: $claude_dir"
        mkdir -p "$claude_dir"
    fi

    # Generate and write context file
    local context_file="${claude_dir}/project-context.md"
    log "Generating context file: $context_file"

    generate_context_markdown "$insights_json" "$target_dir" > "$context_file"

    log "Successfully injected insights into: $context_file"

    # Return summary
    local total_insights=$(echo "$insights_json" | jq -r '.total_insights')
    cat <<EOF
{
  "status": "success",
  "context_file": "$context_file",
  "total_insights": $total_insights,
  "threshold": $threshold,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Update existing context (append mode)
update_context() {
    local target_dir=${1:-.}
    local threshold=${2:-$CONFIDENCE_THRESHOLD}

    local context_file="${target_dir}/.claude/project-context.md"

    if [[ ! -f "$context_file" ]]; then
        log "Context file doesn't exist, creating new one"
        inject_insights "$target_dir" "$threshold"
        return
    fi

    log "Updating existing context: $context_file"

    # Backup existing context
    local backup_file="${context_file}.backup-$(date +%Y%m%d_%H%M%S)"
    cp "$context_file" "$backup_file"
    log "Backed up to: $backup_file"

    # Regenerate (this replaces the file)
    inject_insights "$target_dir" "$threshold"
}

# Show current insights without injecting
show_insights() {
    local threshold=${1:-$CONFIDENCE_THRESHOLD}

    check_dependencies

    log "Extracting insights (preview mode)"
    local insights_json=$("$LEARNING_READER" extract "$threshold")

    if [[ -z "$insights_json" ]]; then
        error "Failed to extract insights"
    fi

    # Generate markdown to stdout
    generate_context_markdown "$insights_json" "."
}

# Check if context needs update
check_context_freshness() {
    local target_dir=${1:-.}
    local max_age_seconds=${2:-3600}  # Default: 1 hour

    local context_file="${target_dir}/.claude/project-context.md"

    if [[ ! -f "$context_file" ]]; then
        echo "missing"
        return
    fi

    # Get file modification time
    local file_mtime
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_mtime=$(stat -f %m "$context_file")
    else
        file_mtime=$(stat -c %Y "$context_file")
    fi

    local current_time=$(date +%s)
    local age=$((current_time - file_mtime))

    if [[ $age -gt $max_age_seconds ]]; then
        echo "stale"
    else
        echo "fresh"
    fi
}

# Auto-inject on session start (idempotent)
auto_inject() {
    local target_dir=${1:-.}
    local threshold=${2:-$CONFIDENCE_THRESHOLD}

    local freshness=$(check_context_freshness "$target_dir" 3600)

    case "$freshness" in
        missing)
            log "Context missing, injecting insights"
            inject_insights "$target_dir" "$threshold"
            ;;
        stale)
            log "Context stale, updating insights"
            update_context "$target_dir" "$threshold"
            ;;
        fresh)
            log "Context is fresh, no update needed"
            echo '{"status": "skipped", "reason": "context is fresh"}'
            ;;
    esac
}

# CLI Interface
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Inject learning insights into session context.

COMMANDS:
  inject [dir] [threshold]    Inject insights into directory (default: .)
  update [dir] [threshold]    Update existing context
  show [threshold]            Preview insights without injecting
  auto [dir] [threshold]      Auto-inject if needed (smart)
  check [dir]                 Check context freshness
  -h, --help                  Show this help message

OPTIONS:
  dir                         Target directory (default: current)
  threshold                   Confidence threshold 0.0-1.0 (default: $CONFIDENCE_THRESHOLD)

EXAMPLES:
  $(basename "$0") inject
  $(basename "$0") inject /path/to/project 0.80
  $(basename "$0") update
  $(basename "$0") show
  $(basename "$0") auto
  $(basename "$0") check

OUTPUT:
  Creates or updates .claude/project-context.md in target directory

EOF
}

# Main CLI handling
main() {
    local command="${1:-inject}"

    case "$command" in
        inject)
            inject_insights "${2:-.}" "${3:-$CONFIDENCE_THRESHOLD}"
            ;;
        update)
            update_context "${2:-.}" "${3:-$CONFIDENCE_THRESHOLD}"
            ;;
        show)
            show_insights "${2:-$CONFIDENCE_THRESHOLD}"
            ;;
        auto)
            auto_inject "${2:-.}" "${3:-$CONFIDENCE_THRESHOLD}"
            ;;
        check)
            check_context_freshness "${2:-.}"
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
