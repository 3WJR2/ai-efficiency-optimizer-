#!/usr/bin/env bash

# knowledge-categorizer.sh
# Categorize and enhance extracted knowledge with domains, languages, frameworks
# Part of Cross-Session Knowledge Extraction System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-${HOME}/.claude/knowledge}"

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

# ============================================================================
# Domain Detection
# ============================================================================

detect_domain() {
    local content="$1"
    local domains=()

    # Frontend
    if echo "$content" | grep -qiE "(react|vue|angular|frontend|css|html|dom|browser|ui|ux|component)"; then
        domains+=("frontend")
    fi

    # Backend
    if echo "$content" | grep -qiE "(backend|server|api|endpoint|route|controller|service|middleware)"; then
        domains+=("backend")
    fi

    # Database
    if echo "$content" | grep -qiE "(database|sql|query|postgres|mysql|mongodb|redis|table|index|schema)"; then
        domains+=("database")
    fi

    # DevOps
    if echo "$content" | grep -qiE "(docker|kubernetes|deployment|ci/cd|pipeline|jenkins|github actions|devops)"; then
        domains+=("devops")
    fi

    # Security
    if echo "$content" | grep -qiE "(security|authentication|authorization|oauth|jwt|encryption|vulnerability)"; then
        domains+=("security")
    fi

    # Testing
    if echo "$content" | grep -qiE "(test|testing|pytest|jest|unittest|spec|mock|assertion)"; then
        domains+=("testing")
    fi

    # Performance
    if echo "$content" | grep -qiE "(performance|optimization|cache|caching|latency|throughput|bottleneck)"; then
        domains+=("performance")
    fi

    # Networking
    if echo "$content" | grep -qiE "(network|http|https|tcp|udp|websocket|rest|graphql)"; then
        domains+=("networking")
    fi

    # Data Science
    if echo "$content" | grep -qiE "(data science|machine learning|pandas|numpy|tensorflow|pytorch|model|dataset)"; then
        domains+=("data-science")
    fi

    # General if no specific domain
    [[ ${#domains[@]} -eq 0 ]] && domains+=("general")

    # Convert to JSON array
    printf '%s\n' "${domains[@]}" | jq -R . | jq -s .
}

# ============================================================================
# Language Detection
# ============================================================================

detect_language() {
    local content="$1"
    local languages=()

    # Python
    if echo "$content" | grep -qiE "(python|\.py\b|pip|django|flask|pandas|numpy)"; then
        languages+=("python")
    fi

    # JavaScript
    if echo "$content" | grep -qiE "(javascript|\.js\b|node|npm|yarn)"; then
        languages+=("javascript")
    fi

    # TypeScript
    if echo "$content" | grep -qiE "(typescript|\.ts\b|\.tsx\b)"; then
        languages+=("typescript")
    fi

    # Shell/Bash
    if echo "$content" | grep -qiE "(bash|shell|\.sh\b|zsh)"; then
        languages+=("shell")
    fi

    # Go
    if echo "$content" | grep -qiE "\b(go|golang|\.go\b)\b"; then
        languages+=("go")
    fi

    # Rust
    if echo "$content" | grep -qiE "(rust|cargo|\.rs\b)"; then
        languages+=("rust")
    fi

    # Java
    if echo "$content" | grep -qiE "(java|\.java\b|maven|gradle)"; then
        languages+=("java")
    fi

    # Ruby
    if echo "$content" | grep -qiE "(ruby|\.rb\b|gem|bundler)"; then
        languages+=("ruby")
    fi

    # PHP
    if echo "$content" | grep -qiE "(php|\.php\b|composer)"; then
        languages+=("php")
    fi

    # C/C++
    if echo "$content" | grep -qiE "(\bc\b|c\+\+|\.cpp\b|\.h\b|gcc|clang)"; then
        languages+=("c/c++")
    fi

    # SQL
    if echo "$content" | grep -qiE "(sql|select|insert|update|delete|create table)"; then
        languages+=("sql")
    fi

    # Convert to JSON array
    if [[ ${#languages[@]} -gt 0 ]]; then
        printf '%s\n' "${languages[@]}" | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

# ============================================================================
# Framework Detection
# ============================================================================

detect_framework() {
    local content="$1"
    local frameworks=()

    # Python Frameworks
    if echo "$content" | grep -qiE "\bdjango\b"; then
        frameworks+=("django")
    fi
    if echo "$content" | grep -qiE "\bflask\b"; then
        frameworks+=("flask")
    fi
    if echo "$content" | grep -qiE "\bfastapi\b"; then
        frameworks+=("fastapi")
    fi
    if echo "$content" | grep -qiE "\btextual\b"; then
        frameworks+=("textual")
    fi

    # JavaScript Frameworks
    if echo "$content" | grep -qiE "\breact\b"; then
        frameworks+=("react")
    fi
    if echo "$content" | grep -qiE "\bvue\b"; then
        frameworks+=("vue")
    fi
    if echo "$content" | grep -qiE "\bangular\b"; then
        frameworks+=("angular")
    fi
    if echo "$content" | grep -qiE "\bnext\.js\b"; then
        frameworks+=("nextjs")
    fi
    if echo "$content" | grep -qiE "\bexpress\b"; then
        frameworks+=("express")
    fi
    if echo "$content" | grep -qiE "\bnest\.js\b"; then
        frameworks+=("nestjs")
    fi

    # Testing Frameworks
    if echo "$content" | grep -qiE "\bpytest\b"; then
        frameworks+=("pytest")
    fi
    if echo "$content" | grep -qiE "\bjest\b"; then
        frameworks+=("jest")
    fi
    if echo "$content" | grep -qiE "\bmocha\b"; then
        frameworks+=("mocha")
    fi

    # Databases
    if echo "$content" | grep -qiE "\bpostgres\b"; then
        frameworks+=("postgresql")
    fi
    if echo "$content" | grep -qiE "\bmysql\b"; then
        frameworks+=("mysql")
    fi
    if echo "$content" | grep -qiE "\bmongodb\b"; then
        frameworks+=("mongodb")
    fi
    if echo "$content" | grep -qiE "\bredis\b"; then
        frameworks+=("redis")
    fi

    # DevOps Tools
    if echo "$content" | grep -qiE "\bdocker\b"; then
        frameworks+=("docker")
    fi
    if echo "$content" | grep -qiE "\bkubernetes\b"; then
        frameworks+=("kubernetes")
    fi

    # Convert to JSON array
    if [[ ${#frameworks[@]} -gt 0 ]]; then
        printf '%s\n' "${frameworks[@]}" | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

# ============================================================================
# Complexity Detection
# ============================================================================

detect_complexity() {
    local content="$1"
    local code_snippet="$2"

    # Factors for complexity
    local has_multiple_steps=false
    local has_code=false
    local has_config=false
    local has_architecture=false

    # Check for multiple steps
    if echo "$content" | grep -qE "(step [0-9]|first|second|third|then|next|finally)"; then
        has_multiple_steps=true
    fi

    # Check for code snippets
    if [[ -n "$code_snippet" ]]; then
        has_code=true
    fi

    # Check for configuration
    if echo "$content" | grep -qiE "(config|configuration|setting|parameter)"; then
        has_config=true
    fi

    # Check for architectural concepts
    if echo "$content" | grep -qiE "(architecture|design|pattern|structure|component)"; then
        has_architecture=true
    fi

    # Determine complexity
    if $has_architecture || ($has_multiple_steps && $has_code); then
        echo "complex"
    elif $has_multiple_steps || $has_code || $has_config; then
        echo "moderate"
    else
        echo "simple"
    fi
}

# ============================================================================
# Reusability Detection
# ============================================================================

detect_reusability() {
    local content="$1"
    local knowledge_type="$2"

    # Patterns and approaches are generally reusable
    if [[ "$knowledge_type" == "pattern" ]] || [[ "$knowledge_type" == "approach" ]]; then
        echo "generalizable"
    fi

    # Check for specific references (file names, paths, etc.)
    if echo "$content" | grep -qE "(/[a-z0-9_/-]+\.(py|js|ts|sh)|[A-Z][a-z]+\.[a-z]+)"; then
        echo "specific"
    fi

    # Check for generalizable language
    if echo "$content" | grep -qiE "(in general|typically|usually|any|all|most|common)"; then
        echo "generalizable"
    fi

    # Check for pattern-like structure
    if echo "$content" | grep -qiE "(pattern|template|boilerplate|structure)"; then
        echo "pattern"
    fi

    # Default
    echo "specific"
}

# ============================================================================
# Enhanced Tag Extraction
# ============================================================================

extract_enhanced_tags() {
    local content="$1"
    local existing_tags="$2"
    local all_tags=()

    # Merge existing tags
    while IFS= read -r tag; do
        all_tags+=("$tag")
    done < <(echo "$existing_tags" | jq -r '.[]')

    # Error types
    if echo "$content" | grep -qiE "indexerror"; then
        all_tags+=("index-error")
    fi
    if echo "$content" | grep -qiE "keyerror"; then
        all_tags+=("key-error")
    fi
    if echo "$content" | grep -qiE "typeerror"; then
        all_tags+=("type-error")
    fi
    if echo "$content" | grep -qiE "valueerror"; then
        all_tags+=("value-error")
    fi
    if echo "$content" | grep -qiE "attributeerror"; then
        all_tags+=("attribute-error")
    fi

    # Common operations
    if echo "$content" | grep -qiE "\brefactor"; then
        all_tags+=("refactoring")
    fi
    if echo "$content" | grep -qiE "\bdebug"; then
        all_tags+=("debugging")
    fi
    if echo "$content" | grep -qiE "\boptimiz"; then
        all_tags+=("optimization")
    fi

    # Deduplicate and convert to JSON
    if [[ ${#all_tags[@]} -gt 0 ]]; then
        printf '%s\n' "${all_tags[@]}" | sort -u | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

# ============================================================================
# Main Categorization Function
# ============================================================================

categorize_knowledge() {
    local entry="$1"

    # Extract fields
    local content=$(echo "$entry" | jq -r '.problem + " " + .solution + " " + .context')
    local code_snippet=$(echo "$entry" | jq -r '.code_snippet // ""')
    local existing_tags=$(echo "$entry" | jq -r '.tags')
    local knowledge_type=$(echo "$entry" | jq -r '.type')

    # Detect categories
    local domains=$(detect_domain "$content")
    local languages=$(detect_language "$content")
    local frameworks=$(detect_framework "$content")
    local complexity=$(detect_complexity "$content" "$code_snippet")
    local reusability=$(detect_reusability "$content" "$knowledge_type")
    local enhanced_tags=$(extract_enhanced_tags "$content" "$existing_tags")

    # Merge with original entry (compact JSON)
    echo "$entry" | jq -c \
        --argjson domains "$domains" \
        --argjson languages "$languages" \
        --argjson frameworks "$frameworks" \
        --arg complexity "$complexity" \
        --arg reusability "$reusability" \
        --argjson tags "$enhanced_tags" \
        '. + {
            domain: $domains,
            language: $languages,
            framework: $frameworks,
            complexity: $complexity,
            reusability: $reusability,
            tags: $tags
        }'
}

# Categorize all entries in a file
categorize_file() {
    local input_file="$1"
    local output_file="${2:-${input_file%.jsonl}-categorized.jsonl}"

    [[ ! -f "$input_file" ]] && error "Input file not found: $input_file"

    log "Categorizing knowledge from: $input_file"
    log "Output file: $output_file"

    # Clear output file
    > "$output_file"

    local count=0
    while IFS= read -r entry; do
        categorize_knowledge "$entry" >> "$output_file"
        ((count++))
        [[ $((count % 10)) -eq 0 ]] && log "Processed $count entries"
    done < "$input_file"

    log "Categorization complete: $count entries"
    log "Output: $output_file"
}

# ============================================================================
# Statistics
# ============================================================================

show_categorization_stats() {
    local file="$1"

    [[ ! -f "$file" ]] && error "File not found: $file"

    cat <<EOF
Categorization Statistics
=========================
File: $file

By Domain:
$(jq -r '.domain[]' "$file" | sort | uniq -c | sort -rn)

By Language:
$(jq -r '.language[]' "$file" | sort | uniq -c | sort -rn)

By Framework:
$(jq -r '.framework[]' "$file" | sort | uniq -c | sort -rn)

By Complexity:
$(jq -r '.complexity' "$file" | sort | uniq -c | sort -rn)

By Reusability:
$(jq -r '.reusability' "$file" | sort | uniq -c | sort -rn)

Top Tags (Enhanced):
$(jq -r '.tags[]' "$file" | sort | uniq -c | sort -rn | head -20)
EOF
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Categorizer - Enhance knowledge with categories and tags

Usage: $(basename "$0") <command> [options]

Commands:
  categorize <input_file> [output_file]   Categorize knowledge entries
  stats <file>                            Show categorization statistics
  help                                    Show this help message

Examples:
  $(basename "$0") categorize ~/.claude/knowledge/knowledge-base.jsonl
  $(basename "$0") stats ~/.claude/knowledge/knowledge-base-categorized.jsonl
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"

    case "$command" in
        categorize)
            [[ $# -lt 2 ]] && error "Usage: $0 categorize <input_file> [output_file]"
            categorize_file "${@:2}"
            ;;
        stats)
            [[ $# -lt 2 ]] && error "Usage: $0 stats <file>"
            show_categorization_stats "$2"
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
