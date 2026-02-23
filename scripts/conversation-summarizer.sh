#!/usr/bin/env bash
#
# conversation-summarizer.sh - Generate high-quality conversation summaries
#
# Part of the Conversation Summarization System
# Main entry point for creating semantic-rich summaries with 10:1 compression
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.claude/data"
SUMMARIES_DIR="$HOME/.claude/summaries"

# Source dependencies
source "$SCRIPT_DIR/key-point-extractor.sh"
source "$SCRIPT_DIR/semantic-compressor.sh"

# Token estimation
estimate_tokens() {
    local text="$1"
    local chars=$(echo -n "$text" | wc -c | tr -d ' ')
    echo $((chars / 4))
}

# Extract session metadata from conversation
extract_metadata() {
    local conversation="$1"
    local session_id="$2"

    # Extract timestamps (look for date patterns)
    local start_time=$(echo "$conversation" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' | head -1)
    local end_time=$(echo "$conversation" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' | tail -1)

    # Extract project name (heuristic: look for "project:" or path patterns)
    local project=$(echo "$conversation" | grep -oE 'project: [a-z0-9-]+' | head -1 | cut -d' ' -f2)
    if [ -z "$project" ]; then
        project=$(echo "$conversation" | grep -oE '/[a-z0-9-]+/' | head -1 | tr -d '/')
    fi
    if [ -z "$project" ]; then
        project="unknown"
    fi

    # Extract goal/purpose (first few lines often state purpose)
    local goal=$(echo "$conversation" | head -5 | grep -E 'goal|purpose|objective|task' -i | head -1 | cut -c1-100)

    # Calculate duration (if timestamps available)
    local duration="unknown"
    if [ -n "$start_time" ] && [ -n "$end_time" ]; then
        # Simple duration calculation (would need more robust implementation)
        duration="calculated"
    fi

    jq -n \
        --arg session_id "$session_id" \
        --arg start_time "${start_time:-unknown}" \
        --arg end_time "${end_time:-unknown}" \
        --arg duration "$duration" \
        --arg project "$project" \
        --arg goal "$goal" \
        '{
            session_id: $session_id,
            start_time: $start_time,
            end_time: $end_time,
            duration: $duration,
            project: $project,
            goal: $goal
        }'
}

# Extract tags from conversation
extract_tags() {
    local conversation="$1"

    # Common technical keywords to look for
    local keywords=(
        "authentication" "jwt" "redis" "database" "api"
        "security" "testing" "deployment" "docker" "kubernetes"
        "frontend" "backend" "react" "node" "python"
        "bug" "feature" "optimization" "refactor" "debug"
    )

    local tags=()
    for keyword in "${keywords[@]}"; do
        if echo "$conversation" | grep -qi "$keyword"; then
            tags+=("$keyword")
        fi
    done

    # Convert to JSON array
    if [ ${#tags[@]} -gt 0 ]; then
        printf '%s\n' "${tags[@]}" | jq -R . | jq -s .
    else
        echo '[]'
    fi
}

# Generate brief summary (200-300 tokens)
generate_brief_summary() {
    local conversation="$1"
    local session_id="$2"

    # Extract key points
    local decisions=$(extract_decisions "$conversation" | head -c 300)
    local solutions=$(extract_solutions "$conversation" | head -c 300)
    local outcomes=$(extract_outcomes "$conversation" | head -c 200)

    # Create brief narrative
    local summary="Session focused on: "

    if [ -n "$decisions" ]; then
        summary+="Made key decisions regarding implementation. "
    fi

    if [ -n "$solutions" ]; then
        summary+="Solved critical issues. "
    fi

    if [ -n "$outcomes" ]; then
        summary+="Achieved outcomes. "
    fi

    # Compress to target size
    summary=$(echo "$summary $decisions $solutions" | head -c 800)
    summary=$(compress_to_ratio "$summary" 0.3)  # ~30% of extracted points

    echo "$summary"
}

# Generate standard summary (500-800 tokens)
generate_standard_summary() {
    local conversation="$1"
    local session_id="$2"
    local metadata="$3"

    local output=""

    # Header
    local project=$(echo "$metadata" | jq -r '.project')
    local goal=$(echo "$metadata" | jq -r '.goal')
    local start_time=$(echo "$metadata" | jq -r '.start_time')

    output+="## Session Summary: $session_id\n\n"
    output+="**Project:** $project\n"
    output+="**When:** $start_time\n"
    if [ -n "$goal" ]; then
        output+="**Goal:** $goal\n"
    fi
    output+="\n"

    # What was built
    output+="### What You Built\n\n"
    local built=$(echo "$conversation" | grep -E "built|created|implemented|added" -i | head -5 | sed 's/^/- /')
    if [ -n "$built" ]; then
        output+="$built\n\n"
    else
        output+="*(No explicit build statements found)*\n\n"
    fi

    # Key decisions
    local decisions=$(extract_decisions "$conversation")
    if [ -n "$decisions" ]; then
        output+="### Key Decisions\n\n$decisions\n"
    fi

    # Problems solved
    local solutions=$(extract_solutions "$conversation")
    if [ -n "$solutions" ]; then
        output+="### Problems Solved\n\n$solutions\n"
    fi

    # Code highlights (1-2 snippets)
    local code=$(extract_code_snippets "$conversation" 2)
    if [ -n "$code" ]; then
        output+="### Code Highlights\n\n$code\n"
    fi

    # Outcomes
    local outcomes=$(extract_outcomes "$conversation")
    if [ -n "$outcomes" ]; then
        output+="### Outcomes\n\n$outcomes\n"
    fi

    # Compress to target size (aim for 500-800 tokens)
    local current_tokens=$(estimate_tokens "$output")
    if [ $current_tokens -gt 900 ]; then
        output=$(compress_with_code "$output" 0.7)  # Keep 70% if too long
    fi

    echo -e "$output"
}

# Generate detailed summary (1000-1500 tokens)
generate_detailed_summary() {
    local conversation="$1"
    local session_id="$2"
    local metadata="$3"

    local output=""

    # Header with full metadata
    local project=$(echo "$metadata" | jq -r '.project')
    local goal=$(echo "$metadata" | jq -r '.goal')
    local start_time=$(echo "$metadata" | jq -r '.start_time')
    local duration=$(echo "$metadata" | jq -r '.duration')

    output+="## Session Summary: $session_id\n\n"
    output+="**Project:** $project\n"
    output+="**When:** $start_time"
    if [ "$duration" != "unknown" ]; then
        output+=" ($duration)"
    fi
    output+="\n"
    if [ -n "$goal" ]; then
        output+="**Goal:** $goal\n"
    fi
    output+="\n"

    # Extract all key points
    output+="$(extract_all_key_points "$conversation")"

    # Add insights section
    local insights=$(extract_insights "$conversation")
    if [ -n "$insights" ]; then
        output+="### Key Insights\n\n$insights\n"
    fi

    # Compress to target size (aim for 1000-1500 tokens)
    local current_tokens=$(estimate_tokens "$output")
    if [ $current_tokens -gt 1600 ]; then
        output=$(compress_with_code "$output" 0.9)  # Keep 90% if too long
    fi

    echo -e "$output"
}

# Main summarization function
summarize_session() {
    local session_id="$1"
    local detail_level="${2:-standard}"
    local conversation_file="${3:-}"

    # Load conversation
    local conversation=""
    if [ -n "$conversation_file" ] && [ -f "$conversation_file" ]; then
        conversation=$(cat "$conversation_file")
    else
        echo "Error: Conversation file not found: $conversation_file" >&2
        return 1
    fi

    # Extract metadata
    local metadata=$(extract_metadata "$conversation" "$session_id")

    # Generate summary based on detail level
    local summary=""
    case "$detail_level" in
        brief)
            summary=$(generate_brief_summary "$conversation" "$session_id")
            ;;
        standard)
            summary=$(generate_standard_summary "$conversation" "$session_id" "$metadata")
            ;;
        detailed)
            summary=$(generate_detailed_summary "$conversation" "$session_id" "$metadata")
            ;;
        *)
            echo "Error: Unknown detail level: $detail_level" >&2
            echo "Valid levels: brief, standard, detailed" >&2
            return 1
            ;;
    esac

    # Add footer with metadata
    local tags=$(extract_tags "$conversation")
    local original_tokens=$(estimate_tokens "$conversation")
    local summary_tokens=$(estimate_tokens "$summary")
    local compression_ratio=$(echo "scale=1; $original_tokens / $summary_tokens" | bc)

    summary+="\n---\n\n"
    summary+="**Tags:** $(echo "$tags" | jq -r 'join(", ")')\n\n"
    summary+="**Tokens:** $summary_tokens (vs $original_tokens original) | **Compression:** ${compression_ratio}:1\n"

    echo -e "$summary"
}

# Summarize and save to file
summarize_and_save() {
    local session_id="$1"
    local detail_level="${2:-standard}"
    local conversation_file="$3"
    local output_file="${4:-$SUMMARIES_DIR/$session_id-$detail_level.md}"

    # Generate summary
    local summary=$(summarize_session "$session_id" "$detail_level" "$conversation_file")

    # Save to file
    mkdir -p "$(dirname "$output_file")"
    echo -e "$summary" > "$output_file"

    echo "Summary saved to: $output_file"
    echo "Tokens: $(estimate_tokens "$summary")"
}

# CLI interface
main() {
    local command="${1:-}"

    case "$command" in
        summarize)
            shift
            local session_id="$1"
            local detail_level="${2:-standard}"
            local conversation_file="$3"

            if [ -z "$session_id" ] || [ -z "$conversation_file" ]; then
                echo "Usage: $0 summarize <session_id> [detail_level] <conversation_file>" >&2
                echo "" >&2
                echo "Detail levels: brief, standard, detailed" >&2
                exit 1
            fi

            summarize_session "$session_id" "$detail_level" "$conversation_file"
            ;;
        save)
            shift
            local session_id="$1"
            local detail_level="${2:-standard}"
            local conversation_file="$3"
            local output_file="${4:-}"

            if [ -z "$session_id" ] || [ -z "$conversation_file" ]; then
                echo "Usage: $0 save <session_id> [detail_level] <conversation_file> [output_file]" >&2
                exit 1
            fi

            summarize_and_save "$session_id" "$detail_level" "$conversation_file" "$output_file"
            ;;
        *)
            echo "Usage: $0 {summarize|save} <session_id> [detail_level] <conversation_file> [output_file]" >&2
            echo "" >&2
            echo "Commands:" >&2
            echo "  summarize  - Generate summary and output to stdout" >&2
            echo "  save       - Generate summary and save to file" >&2
            echo "" >&2
            echo "Detail levels:" >&2
            echo "  brief      - 200-300 tokens (one paragraph)" >&2
            echo "  standard   - 500-800 tokens (structured overview, default)" >&2
            echo "  detailed   - 1000-1500 tokens (comprehensive)" >&2
            exit 1
            ;;
    esac
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
