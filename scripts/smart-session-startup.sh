#!/usr/bin/env bash
# smart-session-startup.sh - Inject relevant knowledge at session start
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
RECOMMENDER="${SCRIPT_DIR}/solution-recommender.sh"
CONTEXT_RANKER="${SCRIPT_DIR}/context-ranker.sh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Detect task from initial prompt
detect_task_from_prompt() {
    local prompt="$1"

    # Simple keyword-based detection
    local task_type="general"
    local keywords=()

    if echo "$prompt" | grep -qiE "auth|login|session|oauth|jwt"; then
        task_type="authentication"
        keywords+=("auth" "security")
    elif echo "$prompt" | grep -qiE "websocket|realtime|live|socket\.io"; then
        task_type="realtime"
        keywords+=("websocket" "realtime")
    elif echo "$prompt" | grep -qiE "api|rest|endpoint|route"; then
        task_type="api"
        keywords+=("api" "rest")
    elif echo "$prompt" | grep -qiE "database|db|sql|query|model"; then
        task_type="database"
        keywords+=("database" "sql")
    elif echo "$prompt" | grep -qiE "test|testing|spec|unit|integration"; then
        task_type="testing"
        keywords+=("testing" "qa")
    elif echo "$prompt" | grep -qiE "ui|frontend|component|react|vue"; then
        task_type="frontend"
        keywords+=("frontend" "ui")
    fi

    jq -n \
        --arg type "$task_type" \
        --argjson keywords "$(printf '%s\n' "${keywords[@]}" | jq -R . | jq -s .)" \
        '{
            task_type: $type,
            keywords: $keywords,
            prompt: "'"$prompt"'"
        }'
}

# Format knowledge for injection
format_knowledge_for_injection() {
    local recommendations="$1"

    cat <<EOF
## Relevant Past Solutions

You've solved similar problems before. Here's what worked:

EOF

    echo "$recommendations" | jq -r '.recommendations[] |
        "### " + (.rank|tostring) + ". " + .problem + " (" + (.knowledge_id | split("_")[3]) + ")",
        "**Score:** " + ((.score * 100) | floor | tostring) + "% relevance",
        "**Solution:** " + .solution,
        "**Tags:** " + (.context.tags // [] | join(", ")),
        "**Confidence:** " + ((.why_relevant.confidence * 100) | floor | tostring) + "%",
        "**Success Rate:** " + ((.why_relevant.success_rate * 100) | floor | tostring) + "%",
        "",
        "**Why relevant:**",
        "- Semantic similarity: " + ((.why_relevant.semantic_similarity * 100) | floor | tostring) + "%",
        "- Recency: " + ((.why_relevant.recency_score * 100) | floor | tostring) + "%",
        "",
        "---",
        ""
    ' || echo "No recommendations available"

    cat <<EOF

**View full knowledge graph:** ~/.claude/knowledge/knowledge-graph.json

**Tip:** Reference these solutions by ID when asking for implementation details.

EOF
}

# Inject knowledge into session context
inject_into_context() {
    local session_dir="$1"
    local knowledge_markdown="$2"

    local context_file="${session_dir}/.session-context.md"

    # Create or append to context file
    if [[ ! -f "$context_file" ]]; then
        cat > "$context_file" <<EOF
# Session Context

## Knowledge Base
EOF
    fi

    # Append knowledge
    echo "" >> "$context_file"
    echo "$knowledge_markdown" >> "$context_file"

    log_success "Knowledge injected into: $context_file"
}

# Main startup knowledge injection
startup_knowledge_injection() {
    local session_dir="${1:-.}"
    local initial_prompt="${2:-}"
    local top_k="${3:-3}"

    log_info "Starting smart session with knowledge injection..."

    # Check if recommender script exists
    if [[ ! -x "$RECOMMENDER" ]]; then
        log_error "Recommender script not found or not executable: $RECOMMENDER"
        return 1
    fi

    # Detect task from prompt if provided
    local task_info=""
    if [[ -n "$initial_prompt" ]]; then
        log_info "Detecting task from prompt..."
        task_info=$(detect_task_from_prompt "$initial_prompt")
        log_info "Detected task type: $(echo "$task_info" | jq -r '.task_type')"
    fi

    # Get recommendations
    local recommendations=""
    if [[ -n "$initial_prompt" ]]; then
        log_info "Finding relevant solutions..."
        recommendations=$("$RECOMMENDER" recommend "$initial_prompt" "$top_k" 2>/dev/null || echo '{"recommendations":[]}')
    else
        # Use context-based recommendation
        log_info "Using context-based recommendation..."
        if [[ -x "$CONTEXT_RANKER" ]]; then
            recommendations=$("$CONTEXT_RANKER" recommend "$top_k" 2>/dev/null || echo '{"recommendations":[]}')
        else
            log_warn "Context ranker not available, skipping..."
            return 0
        fi
    fi

    # Check if we got any recommendations
    local rec_count=$(echo "$recommendations" | jq -r '.recommendations | length' 2>/dev/null || echo "0")

    if [[ "$rec_count" -eq 0 ]]; then
        log_warn "No relevant knowledge found for this session."
        return 0
    fi

    log_info "Found $rec_count relevant solution(s)"

    # Format knowledge for injection
    local knowledge_markdown=$(format_knowledge_for_injection "$recommendations")

    # Inject into session context
    if [[ -d "$session_dir" ]]; then
        inject_into_context "$session_dir" "$knowledge_markdown"
    else
        # Just output to stdout if no session dir
        echo "$knowledge_markdown"
    fi

    log_success "Smart session startup complete!"
}

# Quick recommendation without session injection
quick_recommend() {
    local prompt="$1"
    local top_k="${2:-5}"

    log_info "Quick recommendation for: $prompt"

    if [[ ! -x "$RECOMMENDER" ]]; then
        log_error "Recommender not available"
        return 1
    fi

    local recommendations=$("$RECOMMENDER" recommend "$prompt" "$top_k" 2>/dev/null)

    echo ""
    echo "=== Recommendations ==="
    echo ""

    echo "$recommendations" | jq -r '.recommendations[] |
        "[\(.rank)] \(.problem)",
        "    Solution: \(.solution)",
        "    Relevance: \((.score * 100) | floor)%",
        "    ID: \(.knowledge_id)",
        ""'
}

# Interactive session starter
interactive_start() {
    echo ""
    echo "=== Smart Session Startup ==="
    echo ""
    echo "I'll help you start a session with relevant knowledge from your past work."
    echo ""

    read -p "What are you working on? " user_prompt

    if [[ -z "$user_prompt" ]]; then
        log_error "No prompt provided"
        return 1
    fi

    echo ""
    startup_knowledge_injection "." "$user_prompt" 3
}

# Main command dispatcher
main() {
    case "${1:-interactive}" in
        inject)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 inject <session_dir> [prompt] [top_k]"
                exit 1
            fi
            startup_knowledge_injection "$2" "${3:-}" "${4:-3}"
            ;;
        quick)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 quick <prompt> [top_k]"
                exit 1
            fi
            quick_recommend "$2" "${3:-5}"
            ;;
        detect)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 detect <prompt>"
                exit 1
            fi
            detect_task_from_prompt "$2"
            ;;
        interactive|*)
            interactive_start
            ;;
    esac
}

# Run main
main "$@"
