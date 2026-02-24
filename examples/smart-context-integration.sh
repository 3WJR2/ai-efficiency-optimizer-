#!/usr/bin/env bash
# smart-context-integration.sh
# Example integration of 3-Tier Smart Context Management into session startup

set -euo pipefail

# ============================================================================
# Example 1: Basic Session Startup Integration
# ============================================================================

# Add this to your session-startup-hook.sh or similar

basic_integration() {
    local session_dir="$1"
    local initial_prompt="${2:-general}"

    echo "Loading smart context for session..."

    # Source the context tier manager
    source ~/.claude/scripts/context-tier-manager.sh

    # Build and inject context
    on_session_start "$session_dir" "$initial_prompt"

    echo "Smart context loaded successfully!"
}

# ============================================================================
# Example 2: Advanced Integration with Metrics
# ============================================================================

advanced_integration() {
    local session_dir="$1"
    local initial_prompt="${2:-general}"
    local working_dir="${3:-$(pwd)}"

    echo "Building 3-tier smart context..."

    # Build context
    local context=$(~/.claude/scripts/context-tier-manager.sh build \
        "$(basename "$session_dir")" \
        "$initial_prompt" \
        "$working_dir" 2>&1)

    # Extract metrics from stderr
    local tokens=$(echo "$context" | grep "Total:" | sed 's/.*Total: \([0-9]*\).*/\1/')
    local cost=$(echo "$context" | grep "Tokens:" | sed 's/.*(\$\([0-9.]*\)).*/\1/')
    local time=$(echo "$context" | grep "Build time:" | sed 's/.*Build time: \([0-9]*\)s.*/\1/')

    # Save context
    echo "$context" > "$session_dir/.session-context.md"

    # Log metrics
    cat >> "$session_dir/context-metrics.json" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "tokens": ${tokens:-0},
  "cost": ${cost:-0},
  "build_time_seconds": ${time:-0}
}
EOF

    echo "Context loaded: ${tokens:-0} tokens, \$${cost:-0}, ${time:-0}s"
}

# ============================================================================
# Example 3: Conditional Loading Based on Task
# ============================================================================

conditional_integration() {
    local session_dir="$1"
    local task_type="${2:-general}"

    # Determine context needs based on task
    case "$task_type" in
        debug|fix|troubleshoot)
            # Load more related sessions for debugging context
            export TIER2_MAX_SESSIONS=15
            echo "Debug task detected: loading extra context..."
            ;;
        new|create|implement)
            # Standard context for new features
            export TIER2_MAX_SESSIONS=10
            echo "Implementation task: loading standard context..."
            ;;
        refactor|optimize)
            # Load recent context only
            export TIER1_MAX_SESSIONS=3
            export TIER2_MAX_SESSIONS=5
            echo "Refactoring task: loading focused context..."
            ;;
        *)
            # Default context
            echo "General task: loading balanced context..."
            ;;
    esac

    # Build context with adjusted settings
    source ~/.claude/scripts/context-tier-manager.sh
    on_session_start "$session_dir" "$task_type"
}

# ============================================================================
# Example 4: Pre-Session Context Preview
# ============================================================================

preview_context() {
    local task="$1"

    echo "Previewing context for task: $task"
    echo ""

    # Show what would be loaded
    local selection=$(~/.claude/scripts/session-selector.sh all "$task")

    local tier1_count=$(echo "$selection" | jq -r '.summary.tier1_count')
    local tier2_count=$(echo "$selection" | jq -r '.summary.tier2_count')

    echo "Would load:"
    echo "  - $tier1_count recent sessions (full detail)"
    echo "  - $tier2_count related sessions (summaries)"

    # Show estimated cost
    local estimate=$(~/.claude/scripts/context-tier-manager.sh estimate "" "$task" 2>&1)
    echo ""
    echo "$estimate"
}

# ============================================================================
# Example 5: Context Refresh During Session
# ============================================================================

refresh_context() {
    local session_dir="$1"
    local new_task="${2:-general}"

    echo "Refreshing context for new task: $new_task"

    # Rebuild context with new task focus
    local context=$(~/.claude/scripts/context-tier-manager.sh build \
        "$(basename "$session_dir")" \
        "$new_task" \
        "$(pwd)")

    # Append to existing context (or replace)
    echo "" >> "$session_dir/.session-context.md"
    echo "---" >> "$session_dir/.session-context.md"
    echo "# Updated Context for: $new_task" >> "$session_dir/.session-context.md"
    echo "$(date)" >> "$session_dir/.session-context.md"
    echo "" >> "$session_dir/.session-context.md"
    echo "$context" >> "$session_dir/.session-context.md"

    echo "Context refreshed and saved"
}

# ============================================================================
# Example 6: Multi-Project Context
# ============================================================================

multi_project_integration() {
    local session_dir="$1"
    local project_name="${2:-default}"
    local task="${3:-general}"

    echo "Loading context for project: $project_name"

    # Create project-specific context
    local context=$(~/.claude/scripts/context-tier-manager.sh build \
        "$(basename "$session_dir")" \
        "$task" \
        "~/projects/$project_name")

    # Save with project prefix
    echo "$context" > "$session_dir/.session-context-${project_name}.md"

    echo "Project context loaded: $project_name"
}

# ============================================================================
# Example 7: Smart Context with Knowledge Assistant
# ============================================================================

knowledge_assistant_integration() {
    local session_dir="$1"
    local initial_prompt="${2:-general}"

    echo "Integrating smart context with knowledge assistant..."

    # Build smart context
    source ~/.claude/scripts/context-tier-manager.sh
    local context=$(build_session_context \
        "$(basename "$session_dir")" \
        "$initial_prompt" \
        "$(pwd)")

    # Extract relevant knowledge
    local relevant_knowledge=$(~/.claude/scripts/knowledge-assistant.sh search \
        "$initial_prompt" 5 2>/dev/null || echo "")

    # Combine smart context + knowledge
    cat > "$session_dir/.combined-context.md" <<EOF
# Session Context

## Smart Context (3-Tier)
$context

---

## Relevant Knowledge
$relevant_knowledge

EOF

    echo "Combined context created"
}

# ============================================================================
# Example 8: Context with Cost Monitoring
# ============================================================================

monitored_integration() {
    local session_dir="$1"
    local task="${2:-general}"
    local cost_limit="${3:-0.25}"  # Default $0.25 limit

    echo "Building context with cost monitoring..."

    # Estimate first
    local estimate=$(~/.claude/scripts/context-tier-manager.sh estimate "" "$task" 2>&1)
    local estimated_cost=$(echo "$estimate" | grep "Estimated Cost" | sed 's/.*\$\([0-9.]*\).*/\1/')

    # Check if within budget
    local over_budget=$(echo "$estimated_cost > $cost_limit" | bc -l)

    if [[ $over_budget -eq 1 ]]; then
        echo "Warning: Estimated cost \$$estimated_cost exceeds limit \$$cost_limit"
        echo "Reducing context size..."

        # Reduce tier 2 sessions
        export TIER2_MAX_SESSIONS=5
    fi

    # Build context
    source ~/.claude/scripts/context-tier-manager.sh
    on_session_start "$session_dir" "$task"

    # Log final cost
    echo "Context loaded within budget: \$$estimated_cost / \$$cost_limit"
}

# ============================================================================
# Main CLI for Testing Examples
# ============================================================================

show_usage() {
    cat <<EOF
Smart Context Integration Examples

Usage:
  $(basename "$0") <example> [args...]

Examples:
  basic <session_dir> [prompt]           Basic integration
  advanced <session_dir> [prompt] [dir]  Advanced with metrics
  conditional <session_dir> <task_type>  Task-based loading
  preview <task>                         Preview context
  refresh <session_dir> <new_task>       Refresh during session
  multi-project <session_dir> <project>  Multi-project context
  knowledge <session_dir> [prompt]       With knowledge assistant
  monitored <session_dir> [task] [limit] With cost monitoring

Task Types (for conditional):
  - debug, fix, troubleshoot (more context)
  - new, create, implement (standard)
  - refactor, optimize (focused)

EOF
}

main() {
    local example="${1:-help}"

    case "$example" in
        basic)
            basic_integration "${2:-/tmp/test-session}" "${3:-general}"
            ;;
        advanced)
            advanced_integration "${2:-/tmp/test-session}" "${3:-general}" "${4:-.}"
            ;;
        conditional)
            conditional_integration "${2:-/tmp/test-session}" "${3:-general}"
            ;;
        preview)
            preview_context "${2:-general}"
            ;;
        refresh)
            refresh_context "${2:-/tmp/test-session}" "${3:-general}"
            ;;
        multi-project)
            multi_project_integration "${2:-/tmp/test-session}" "${3:-default}" "${4:-general}"
            ;;
        knowledge)
            knowledge_assistant_integration "${2:-/tmp/test-session}" "${3:-general}"
            ;;
        monitored)
            monitored_integration "${2:-/tmp/test-session}" "${3:-general}" "${4:-0.25}"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            echo "Unknown example: $example"
            show_usage
            exit 1
            ;;
    esac
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
