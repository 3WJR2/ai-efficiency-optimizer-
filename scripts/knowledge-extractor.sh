#!/usr/bin/env bash

# knowledge-extractor.sh
# Extract learnings and knowledge from conversation logs
# Part of Cross-Session Knowledge Extraction System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-${HOME}/.claude/data}"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-${HOME}/.claude/knowledge}"
SESSIONS_DIR="${SESSIONS_DIR:-${HOME}/Desktop/multi-claude-sessions/sessions}"

# Knowledge types
KNOWLEDGE_TYPES=("solution" "pattern" "error" "decision" "approach" "learning" "tip" "caveat")

# Initialize
mkdir -p "$KNOWLEDGE_DIR"

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

# Generate unique ID for knowledge entry
generate_knowledge_id() {
    local session_id="$1"
    local msg_index="$2"
    local timestamp="$3"

    local date_part=$(echo "$timestamp" | cut -d'T' -f1 | tr -d '-')
    echo "k_${session_id}_msg${msg_index}_${date_part}"
}

# Calculate confidence score based on success indicators
calculate_confidence() {
    local indicators_json="$1"

    # Count positive indicators
    local user_confirmed=$(echo "$indicators_json" | jq 'contains(["user_confirmed"]) | if . then 1 else 0 end' 2>/dev/null || echo 0)
    local no_errors=$(echo "$indicators_json" | jq 'contains(["no_errors_after"]) | if . then 1 else 0 end' 2>/dev/null || echo 0)
    local tests_passed=$(echo "$indicators_json" | jq 'contains(["tests_passed"]) | if . then 1 else 0 end' 2>/dev/null || echo 0)
    local positive_feedback=$(echo "$indicators_json" | jq 'contains(["positive_feedback"]) | if . then 1 else 0 end' 2>/dev/null || echo 0)

    # Base confidence: 0.5
    # Add 0.15 for each indicator (max 0.60)
    local total=$((user_confirmed + no_errors + tests_passed + positive_feedback))

    # Use bc for floating point calculation and ensure leading zero
    local result=$(echo "scale=2; 0.5 + ($total * 0.15)" | bc)
    # Add leading zero if missing
    if [[ "$result" == .* ]]; then
        echo "0$result"
    else
        echo "$result"
    fi
}

# ============================================================================
# Detection Heuristics
# ============================================================================

# Detect if message contains a solution
detect_solution() {
    local content="$1"

    # Solution indicators
    if echo "$content" | grep -qiE "(fixed|solved|working|success|resolved|here's the fix|corrected)"; then
        return 0
    fi

    # Code snippet with explanation
    if echo "$content" | grep -qE '```.*```' && echo "$content" | grep -qiE "(change|update|replace|modify)"; then
        return 0
    fi

    return 1
}

# Detect if message contains a pattern
detect_pattern() {
    local content="$1"

    if echo "$content" | grep -qiE "(pattern|approach|typically|usually|common way|standard practice|best practice|generally)"; then
        return 0
    fi

    return 1
}

# Detect if message contains error resolution
detect_error() {
    local content="$1"

    # Look for error messages or stack traces
    if echo "$content" | grep -qiE "(error|exception|traceback|stack trace|failed)"; then
        return 0
    fi

    return 1
}

# Detect if message contains a decision
detect_decision() {
    local content="$1"

    if echo "$content" | grep -qiE "(decided to|chose|went with|because|rationale|reason why|opted for)"; then
        return 0
    fi

    return 1
}

# Detect if message contains an approach
detect_approach() {
    local content="$1"

    if echo "$content" | grep -qiE "(approach|methodology|strategy|technique|method|way to)"; then
        return 0
    fi

    return 1
}

# Detect if message contains a learning
detect_learning() {
    local content="$1"

    if echo "$content" | grep -qiE "(learned|discovered|realized|found that|turns out|interesting)"; then
        return 0
    fi

    return 1
}

# Detect if message contains a tip
detect_tip() {
    local content="$1"

    if echo "$content" | grep -qiE "(tip|trick|hint|optimization|pro tip|note:|important:)"; then
        return 0
    fi

    return 1
}

# Detect if message contains a caveat
detect_caveat() {
    local content="$1"

    if echo "$content" | grep -qiE "(warning|caveat|gotcha|watch out|be careful|note that|however)"; then
        return 0
    fi

    return 1
}

# Determine knowledge type
identify_knowledge_type() {
    local content="$1"

    # Priority order: solution > error > pattern > decision > learning > approach > tip > caveat
    if detect_solution "$content"; then
        echo "solution"
    elif detect_error "$content"; then
        echo "error"
    elif detect_pattern "$content"; then
        echo "pattern"
    elif detect_decision "$content"; then
        echo "decision"
    elif detect_learning "$content"; then
        echo "learning"
    elif detect_approach "$content"; then
        echo "approach"
    elif detect_tip "$content"; then
        echo "tip"
    elif detect_caveat "$content"; then
        echo "caveat"
    else
        echo "unknown"
    fi
}

# ============================================================================
# Success Indicator Detection
# ============================================================================

# Detect success indicators from user messages
detect_success_indicators() {
    local content="$1"
    local indicators=()

    # User confirmation
    if echo "$content" | grep -qiE "(perfect|thanks|great|worked|excellent|that fixed it|that solved it)"; then
        indicators+=("user_confirmed")
    fi

    # Positive feedback
    if echo "$content" | grep -qiE "(thank you|appreciate|helpful)"; then
        indicators+=("positive_feedback")
    fi

    # Tests passed
    if echo "$content" | grep -qiE "(tests pass|all tests|tests are green)"; then
        indicators+=("tests_passed")
    fi

    # Convert to JSON array
    if [[ ${#indicators[@]} -gt 0 ]]; then
        printf '%s\n' "${indicators[@]}" | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

# Check for errors after a message
has_errors_after() {
    local messages_json="$1"
    local current_index="$2"

    # Check next 3 messages for error indicators
    local next_messages=$(echo "$messages_json" | jq -r ".[$((current_index + 1)):$((current_index + 4))] | .[] | .content" 2>/dev/null || echo "")

    if echo "$next_messages" | grep -qiE "(error|exception|failed|traceback)"; then
        return 0
    fi

    return 1
}

# ============================================================================
# Context Extraction
# ============================================================================

# Extract surrounding context for a message
extract_context() {
    local messages_json="$1"
    local index="$2"
    local context_window="${3:-2}"  # Default: 2 messages before/after

    # Get messages from index-window to index+window
    local start=$((index - context_window))
    [[ $start -lt 0 ]] && start=0

    local end=$((index + context_window + 1))

    # Extract and format context
    echo "$messages_json" | jq -r ".[$start:$end] | .[] | \"\(.role): \(.content | .[0:200])\"" | tr '\n' ' '
}

# Extract problem description from context
extract_problem() {
    local content="$1"
    local context="$2"

    # Look for user question in context
    local user_msg=$(echo "$context" | grep -oE "user: [^}]+" | head -1 | sed 's/^user: //')

    if [[ -n "$user_msg" ]]; then
        echo "$user_msg" | head -c 500
    else
        # Fallback: extract from content
        echo "$content" | head -c 500
    fi
}

# Extract solution from assistant message
extract_solution() {
    local content="$1"

    # Try to extract concise solution
    # Look for sentences with solution keywords
    local solution=$(echo "$content" | grep -oE "[^.!?]*\b(fix|solution|change|replace|use|set)\b[^.!?]*[.!?]" | head -3 | tr '\n' ' ')

    if [[ -n "$solution" ]]; then
        echo "$solution" | head -c 1000
    else
        echo "$content" | head -c 1000
    fi
}

# Extract code snippets
extract_code_snippets() {
    local content="$1"

    # Extract code blocks
    echo "$content" | grep -Pzo '```[^`]*```' 2>/dev/null | tr '\0' '\n' | head -c 2000 || echo ""
}

# Extract tags from content
extract_tags() {
    local content="$1"
    local tags=()

    # Technical terms (simple extraction)
    local words=$(echo "$content" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{3,15}\b' | sort -u)

    # Filter for likely technical terms
    for word in $words; do
        if echo "$word" | grep -qE "(python|javascript|typescript|rust|golang|react|django|docker|redis|postgres|api|database|auth|session|timeout|index|error|bug|fix|test)"; then
            tags+=("$word")
        fi
    done

    # Limit to 10 tags and convert to JSON
    if [[ ${#tags[@]} -gt 0 ]]; then
        printf '%s\n' "${tags[@]}" | head -10 | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

# ============================================================================
# Main Extraction Functions
# ============================================================================

# Extract knowledge from a single message pair (user + assistant)
extract_from_message_pair() {
    local session_id="$1"
    local messages_json="$2"
    local index="$3"

    local assistant_msg=$(echo "$messages_json" | jq -r ".[$index]")
    local content=$(echo "$assistant_msg" | jq -r '.content')
    local timestamp=$(echo "$assistant_msg" | jq -r '.timestamp')
    local role=$(echo "$assistant_msg" | jq -r '.role')

    # Only process assistant messages
    [[ "$role" != "assistant" ]] && return 0

    # Identify knowledge type
    local knowledge_type=$(identify_knowledge_type "$content")
    [[ "$knowledge_type" == "unknown" ]] && return 0

    # Extract context
    local context=$(extract_context "$messages_json" "$index" 2)

    # Extract problem and solution
    local problem=$(extract_problem "$content" "$context")
    local solution=$(extract_solution "$content")

    # Extract code snippets
    local code_snippet=$(extract_code_snippets "$content")

    # Extract tags
    local tags=$(extract_tags "$content")

    # Check for success indicators
    local next_user_msg=$(echo "$messages_json" | jq -r ".[$((index + 1))] | select(.role == \"user\") | .content" 2>/dev/null || echo "")
    local success_indicators=$(detect_success_indicators "$next_user_msg")

    # Check for errors after
    if ! has_errors_after "$messages_json" "$index"; then
        success_indicators=$(echo "$success_indicators" | jq '. + ["no_errors_after"]')
    fi

    # Calculate confidence
    local confidence=$(calculate_confidence "$success_indicators")

    # Generate ID
    local knowledge_id=$(generate_knowledge_id "$session_id" "$index" "$timestamp")

    # Build knowledge entry (compact JSON)
    jq -nc \
        --arg id "$knowledge_id" \
        --arg type "$knowledge_type" \
        --arg session_id "$session_id" \
        --arg timestamp "$timestamp" \
        --arg problem "$problem" \
        --arg solution "$solution" \
        --arg context "$context" \
        --arg code_snippet "$code_snippet" \
        --argjson tags "$tags" \
        --argjson confidence "$confidence" \
        --argjson success_indicators "$success_indicators" \
        '{
            id: $id,
            type: $type,
            session_id: $session_id,
            timestamp: $timestamp,
            problem: $problem,
            solution: $solution,
            context: $context,
            code_snippet: $code_snippet,
            tags: $tags,
            confidence: $confidence,
            success_indicators: $success_indicators,
            related_files: [],
            links: []
        }'
}

# Extract knowledge from a single session
extract_from_session() {
    local session_dir="$1"
    local session_id=$(basename "$session_dir")
    local conversation_log="${session_dir}/conversation-log.jsonl"

    [[ ! -f "$conversation_log" ]] && {
        log "No conversation log found: $conversation_log"
        return 1
    }

    log "Extracting from session: $session_id"

    # Read all messages into JSON array
    local messages_json=$(jq -s '.' "$conversation_log")
    local message_count=$(echo "$messages_json" | jq 'length')

    log "Processing $message_count messages"

    # Extract knowledge from each message pair
    local extracted=0
    for ((i=0; i<message_count; i++)); do
        local knowledge=$(extract_from_message_pair "$session_id" "$messages_json" "$i")

        if [[ -n "$knowledge" ]] && echo "$knowledge" | jq -e . >/dev/null 2>&1; then
            echo "$knowledge"
            ((extracted++))
        fi
    done

    log "Extracted $extracted knowledge entries from $session_id"
}

# Extract knowledge from all sessions
extract_from_all_sessions() {
    local output_file="${1:-$KNOWLEDGE_DIR/knowledge-base.jsonl}"

    log "Extracting knowledge from all sessions"
    log "Sessions directory: $SESSIONS_DIR"
    log "Output file: $output_file"

    # Clear output file
    > "$output_file"

    # Process each session
    local session_count=0
    local total_extracted=0

    while IFS= read -r session_dir; do
        local session_id=$(basename "$session_dir")

        # Extract knowledge and append to file
        local extracted=$(extract_from_session "$session_dir" | tee -a "$output_file" | wc -l)

        ((session_count++))
        total_extracted=$((total_extracted + extracted))

    done < <(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

    log "Completed extraction from $session_count sessions"
    log "Total knowledge entries: $total_extracted"
    log "Output written to: $output_file"

    # Generate summary
    cat <<EOF

Extraction Summary:
==================
Sessions processed: $session_count
Total entries: $total_extracted
Output file: $output_file

Knowledge types:
$(jq -r '.type' "$output_file" | sort | uniq -c | sort -rn)

Average confidence: $(jq -s 'map(.confidence) | add / length' "$output_file")
EOF
}

# Extract from sessions since date
extract_since_date() {
    local since_date="$1"
    local output_file="${2:-$KNOWLEDGE_DIR/knowledge-base-recent.jsonl}"

    log "Extracting knowledge from sessions since $since_date"

    # Clear output file
    > "$output_file"

    # Process sessions since date
    while IFS= read -r session_dir; do
        extract_from_session "$session_dir" >> "$output_file"
    done < <(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name "${since_date}*" | sort)

    log "Extraction complete: $output_file"
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Extractor - Extract learnings from conversation logs

Usage: $(basename "$0") <command> [options]

Commands:
  extract <session_dir>          Extract from single session
  extract-all                    Extract from all sessions
  extract-since <date>           Extract from sessions since date
  stats <file>                   Show statistics for knowledge file
  help                           Show this help message

Examples:
  $(basename "$0") extract ~/Desktop/multi-claude-sessions/sessions/2026-02-17-session-1-df2f
  $(basename "$0") extract-all
  $(basename "$0") extract-since 2026-02-01
  $(basename "$0") stats ~/.claude/knowledge/knowledge-base.jsonl
EOF
}

# Show statistics for knowledge file
show_stats() {
    local file="$1"

    [[ ! -f "$file" ]] && error "File not found: $file"

    local total=$(wc -l < "$file")

    cat <<EOF
Knowledge Base Statistics
=========================
File: $file
Total entries: $total

By type:
$(jq -r '.type' "$file" | sort | uniq -c | sort -rn)

By confidence:
High (0.8-1.0):   $(jq 'select(.confidence >= 0.8)' "$file" | wc -l)
Medium (0.5-0.8): $(jq 'select(.confidence >= 0.5 and .confidence < 0.8)' "$file" | wc -l)
Low (0.0-0.5):    $(jq 'select(.confidence < 0.5)' "$file" | wc -l)

Average confidence: $(jq -s 'map(.confidence) | add / length' "$file")

Top tags:
$(jq -r '.tags[]' "$file" | sort | uniq -c | sort -rn | head -10)
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"

    case "$command" in
        extract)
            [[ $# -lt 2 ]] && error "Usage: $0 extract <session_dir>"
            extract_from_session "$2"
            ;;
        extract-all)
            extract_from_all_sessions
            ;;
        extract-since)
            [[ $# -lt 2 ]] && error "Usage: $0 extract-since <date>"
            extract_since_date "$2"
            ;;
        stats)
            [[ $# -lt 2 ]] && error "Usage: $0 stats <file>"
            show_stats "$2"
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
