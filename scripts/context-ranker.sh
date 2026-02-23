#!/usr/bin/env bash
# context-ranker.sh - Rank knowledge by relevance to current context
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
GRAPH_FILE="${KNOWLEDGE_DIR}/knowledge-graph.json"
CONTEXT_CACHE="${KNOWLEDGE_DIR}/context-cache.json"

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

# Detect current working context
detect_current_context() {
    log_info "Detecting current working context..."

    local cwd="${PWD}"
    local project_type="unknown"
    local language=""
    local framework=""
    local technologies=()

    # Detect project type from files
    if [[ -f "package.json" ]]; then
        project_type="nodejs"
        language="javascript"

        # Detect framework from dependencies
        if command -v jq &>/dev/null && [[ -f "package.json" ]]; then
            local deps=$(jq -r '.dependencies // {} | keys[]' package.json 2>/dev/null || echo "")

            if echo "$deps" | grep -q "react"; then
                framework="react"
                technologies+=("react")
            fi
            if echo "$deps" | grep -q "vue"; then
                framework="vue"
                technologies+=("vue")
            fi
            if echo "$deps" | grep -q "angular"; then
                framework="angular"
                technologies+=("angular")
            fi
            if echo "$deps" | grep -q "express"; then
                technologies+=("express")
            fi
            if echo "$deps" | grep -q "socket.io"; then
                technologies+=("websocket")
            fi
        fi
    elif [[ -f "requirements.txt" || -f "setup.py" || -f "pyproject.toml" ]]; then
        project_type="python"
        language="python"

        # Detect Python frameworks
        if [[ -f "requirements.txt" ]]; then
            if grep -q "django" requirements.txt 2>/dev/null; then
                framework="django"
                technologies+=("django")
            fi
            if grep -q "flask" requirements.txt 2>/dev/null; then
                framework="flask"
                technologies+=("flask")
            fi
            if grep -q "fastapi" requirements.txt 2>/dev/null; then
                framework="fastapi"
                technologies+=("fastapi")
            fi
        fi
    elif [[ -f "go.mod" ]]; then
        project_type="golang"
        language="go"
    elif [[ -f "Cargo.toml" ]]; then
        project_type="rust"
        language="rust"
    elif [[ -f "pom.xml" || -f "build.gradle" ]]; then
        project_type="java"
        language="java"
    elif [[ -f "Gemfile" ]]; then
        project_type="ruby"
        language="ruby"

        if grep -q "rails" Gemfile 2>/dev/null; then
            framework="rails"
            technologies+=("rails")
        fi
    fi

    # Detect recent files accessed (via git if available)
    local recent_files=()
    if git rev-parse --git-dir &>/dev/null; then
        while IFS= read -r file; do
            recent_files+=("$file")
        done < <(git log --name-only --pretty=format: -10 2>/dev/null | sort -u | head -20)
    fi

    # Infer current focus from recent files
    local focus_areas=()
    for file in "${recent_files[@]}"; do
        if [[ "$file" =~ test|spec ]]; then
            focus_areas+=("testing")
        fi
        if [[ "$file" =~ api|route|endpoint ]]; then
            focus_areas+=("api")
        fi
        if [[ "$file" =~ auth|login|session ]]; then
            focus_areas+=("authentication")
        fi
        if [[ "$file" =~ db|model|schema ]]; then
            focus_areas+=("database")
        fi
        if [[ "$file" =~ ui|component|view ]]; then
            focus_areas+=("frontend")
        fi
    done

    # Remove duplicates
    focus_areas=($(printf '%s\n' "${focus_areas[@]}" | sort -u))
    technologies=($(printf '%s\n' "${technologies[@]}" | sort -u))

    # Build context JSON
    jq -n \
        --arg cwd "$cwd" \
        --arg type "$project_type" \
        --arg lang "$language" \
        --arg framework "$framework" \
        --argjson tech "$(printf '%s\n' "${technologies[@]}" | jq -R . | jq -s .)" \
        --argjson focus "$(printf '%s\n' "${focus_areas[@]}" | jq -R . | jq -s .)" \
        --argjson files "$(printf '%s\n' "${recent_files[@]}" | jq -R . | jq -s .)" \
        '{
            working_directory: $cwd,
            project_type: $type,
            language: $lang,
            framework: $framework,
            technologies: $tech,
            focus_areas: $focus,
            recent_files: $files,
            detected_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Calculate context relevance score
calculate_context_relevance() {
    local knowledge_node="$1"
    local context="$2"

    # Extract from knowledge node
    local node_tags=$(echo "$knowledge_node" | jq -c '.tags // []')
    local node_meta=$(echo "$knowledge_node" | jq -c '.metadata // {}')

    # Extract from context
    local ctx_lang=$(echo "$context" | jq -r '.language // ""')
    local ctx_framework=$(echo "$context" | jq -r '.framework // ""')
    local ctx_tech=$(echo "$context" | jq -c '.technologies // []')
    local ctx_focus=$(echo "$context" | jq -c '.focus_areas // []')

    # Build context tags
    local context_tags="[]"
    if [[ -n "$ctx_lang" ]]; then
        context_tags=$(echo "$context_tags" | jq --arg l "$ctx_lang" '. += [$l]')
    fi
    if [[ -n "$ctx_framework" ]]; then
        context_tags=$(echo "$context_tags" | jq --arg f "$ctx_framework" '. += [$f]')
    fi

    # Merge technologies and focus areas
    context_tags=$(echo "$context_tags $ctx_tech $ctx_focus" | jq -s 'add | unique')

    # Calculate tag overlap
    local node_array=($(echo "$node_tags" | jq -r '.[]' 2>/dev/null || echo ""))
    local ctx_array=($(echo "$context_tags" | jq -r '.[]' 2>/dev/null || echo ""))

    if [[ ${#ctx_array[@]} -eq 0 ]]; then
        echo "0.0"
        return
    fi

    local intersection=0
    for tag in "${node_array[@]}"; do
        if [[ " ${ctx_array[@]} " =~ " ${tag} " ]]; then
            ((intersection++)) || true
        fi
    done

    local union=$((${#node_array[@]} + ${#ctx_array[@]} - intersection))

    if [[ $union -eq 0 ]]; then
        echo "0.0"
    else
        echo "scale=3; $intersection / $union" | bc
    fi
}

# Rank knowledge by context
rank_by_context() {
    local knowledge_ids="$1"  # JSON array of IDs
    local context="$2"

    log_info "Ranking knowledge by context..."

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found", "ranked": []}'
        return 1
    fi

    # Parse knowledge IDs
    local ids=($(echo "$knowledge_ids" | jq -r '.[]'))

    # Rank each node
    local ranked=()

    for id in "${ids[@]}"; do
        # Get node
        local node=$(jq --arg id "$id" '.nodes[] | select(.id == $id)' "${GRAPH_FILE}")

        if [[ -z "$node" ]]; then
            log_warn "Node not found: $id"
            continue
        fi

        # Calculate relevance score
        local relevance=$(calculate_context_relevance "$node" "$context")
        local confidence=$(echo "$node" | jq -r '.confidence // 0.5')

        # Combined score
        local score=$(echo "scale=3; ($relevance * 0.7) + ($confidence * 0.3)" | bc)

        local entry=$(jq -n \
            --arg id "$id" \
            --argjson score "$score" \
            --argjson relevance "$relevance" \
            --argjson conf "$confidence" \
            '{
                knowledge_id: $id,
                score: $score,
                context_relevance: $relevance,
                confidence: $conf
            }')

        ranked+=("$entry")
    done

    # Sort by score
    local sorted=$(printf '%s\n' "${ranked[@]}" | jq -s 'sort_by(-.score)')

    jq -n \
        --argjson context "$context" \
        --argjson ranked "$sorted" \
        '{
            context: $context,
            ranked_knowledge: $ranked,
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Explain ranking
explain_ranking() {
    local knowledge_id="$1"
    local context="$2"

    log_info "Explaining ranking for: $knowledge_id"

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Get node
    local node=$(jq --arg id "$knowledge_id" '.nodes[] | select(.id == $id)' "${GRAPH_FILE}")

    if [[ -z "$node" ]]; then
        log_error "Node not found: $knowledge_id"
        echo '{"error": "Node not found"}'
        return 1
    fi

    # Calculate relevance
    local relevance=$(calculate_context_relevance "$node" "$context")
    local node_tags=$(echo "$node" | jq -c '.tags // []')

    # Extract context tags
    local ctx_lang=$(echo "$context" | jq -r '.language // ""')
    local ctx_framework=$(echo "$context" | jq -r '.framework // ""')
    local ctx_tech=$(echo "$context" | jq -c '.technologies // []')

    # Find matching tags
    local matching_tags="[]"
    if [[ -n "$ctx_lang" ]]; then
        if echo "$node_tags" | jq -e --arg l "$ctx_lang" 'index($l)' &>/dev/null; then
            matching_tags=$(echo "$matching_tags" | jq --arg l "$ctx_lang" '. += [$l]')
        fi
    fi
    if [[ -n "$ctx_framework" ]]; then
        if echo "$node_tags" | jq -e --arg f "$ctx_framework" 'index($f)' &>/dev/null; then
            matching_tags=$(echo "$matching_tags" | jq --arg f "$ctx_framework" '. += [$f]')
        fi
    fi

    jq -n \
        --arg id "$knowledge_id" \
        --argjson node "$node" \
        --argjson context "$context" \
        --argjson relevance "$relevance" \
        --argjson matching "$matching_tags" \
        '{
            knowledge_id: $id,
            context_relevance: $relevance,
            explanation: {
                matching_tags: $matching,
                current_language: $context.language,
                current_framework: $context.framework,
                current_focus: $context.focus_areas,
                interpretation: (if ($relevance > 0.7) then "Highly relevant to current context"
                                elif ($relevance > 0.5) then "Relevant to current context"
                                elif ($relevance > 0.3) then "Somewhat relevant"
                                else "Not closely related to current context" end)
            },
            node: $node
        }'
}

# Get context summary
get_context_summary() {
    local context=$(detect_current_context)

    log_info "Current Working Context Summary:"
    echo ""

    echo "$context" | jq -r '
    "Working Directory: " + .working_directory,
    "Project Type: " + .project_type,
    "Language: " + (.language // "unknown"),
    "Framework: " + (.framework // "none"),
    "",
    "Technologies:",
    (.technologies | map("  - " + .) | join("\n")),
    "",
    "Focus Areas:",
    (.focus_areas | map("  - " + .) | join("\n")),
    "",
    "Recent Files (" + (.recent_files | length | tostring) + "):",
    (.recent_files[0:5] | map("  - " + .) | join("\n"))
    '

    echo ""
    echo "Detected at: $(echo "$context" | jq -r '.detected_at')"
}

# Cache current context
cache_context() {
    local context=$(detect_current_context)

    mkdir -p "${KNOWLEDGE_DIR}"

    echo "$context" > "${CONTEXT_CACHE}"

    log_success "Context cached to: ${CONTEXT_CACHE}"
}

# Load cached context
load_cached_context() {
    if [[ -f "${CONTEXT_CACHE}" ]]; then
        cat "${CONTEXT_CACHE}"
    else
        log_warn "No cached context found. Detecting..."
        detect_current_context
    fi
}

# Recommend knowledge for current context
recommend_for_context() {
    local top_k="${1:-10}"

    log_info "Recommending knowledge for current context..."

    # Detect context
    local context=$(detect_current_context)

    # Get all knowledge IDs
    local all_ids=$(jq -c '[.nodes[].id]' "${GRAPH_FILE}" 2>/dev/null || echo "[]")

    if [[ "$all_ids" == "[]" ]]; then
        log_error "No knowledge found in graph."
        echo '{"error": "No knowledge found", "recommendations": []}'
        return 1
    fi

    # Rank by context
    local ranked=$(rank_by_context "$all_ids" "$context")

    # Take top K
    echo "$ranked" | jq --argjson k "$top_k" '.ranked_knowledge[0:$k]'
}

# Main command dispatcher
main() {
    case "${1:-detect}" in
        detect)
            detect_current_context
            ;;
        rank)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 rank <knowledge_ids_json> [context_json]"
                exit 1
            fi
            local context="${3:-}"
            if [[ -z "$context" ]]; then
                context=$(detect_current_context)
            fi
            rank_by_context "$2" "$context"
            ;;
        explain)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 explain <knowledge_id> [context_json]"
                exit 1
            fi
            local context="${3:-}"
            if [[ -z "$context" ]]; then
                context=$(detect_current_context)
            fi
            explain_ranking "$2" "$context"
            ;;
        summary)
            get_context_summary
            ;;
        cache)
            cache_context
            ;;
        load)
            load_cached_context
            ;;
        recommend)
            recommend_for_context "${2:-10}"
            ;;
        *)
            cat <<EOF
Usage: $0 {detect|rank|explain|summary|cache|load|recommend}

Commands:
  detect
      Detect current working context

  rank <knowledge_ids_json> [context_json]
      Rank knowledge by relevance to context

  explain <knowledge_id> [context_json]
      Explain why knowledge is ranked highly

  summary
      Show current context summary

  cache
      Cache current context to file

  load
      Load cached context

  recommend [top_k]
      Recommend knowledge for current context

Examples:
  $0 detect
  $0 rank '["k_auth_basic_20260115","k_websocket_realtime_20260205"]'
  $0 explain "k_auth_oauth_20260201"
  $0 recommend 5
EOF
            exit 1
            ;;
    esac
}

# Run main
main "$@"
