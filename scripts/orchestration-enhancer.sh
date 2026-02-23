#!/usr/bin/env bash

################################################################################
# orchestration-enhancer.sh - Enhance orchestrator with index intelligence
# Version: 1.0.0
#
# Features:
# - Search index before spawning agents
# - Pass preloaded context to agents
# - Adjust strategy based on codebase structure
# - Track which code sections agents access
################################################################################

set -euo pipefail

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"
DATA_DIR="${CLAUDE_HOME}/data"
LOGS_DIR="${CLAUDE_HOME}/logs"
INDEXES_DIR="${CLAUDE_HOME}/indexes"

# Log file
LOG_FILE="${LOGS_DIR}/orchestration-enhancer.log"

# Ensure directories exist
mkdir -p "${DATA_DIR}" "${LOGS_DIR}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*" | tee -a "${LOG_FILE}"
}

# Detect codebase structure
detect_codebase_structure() {
    local directory="${1:-${PWD}}"

    log "Detecting codebase structure in: ${directory}"

    local structure='{}'

    # Detect language
    local py_files=$(find "${directory}" -name "*.py" 2>/dev/null | wc -l | tr -d ' ')
    local js_files=$(find "${directory}" -name "*.js" -o -name "*.ts" 2>/dev/null | wc -l | tr -d ' ')
    local go_files=$(find "${directory}" -name "*.go" 2>/dev/null | wc -l | tr -d ' ')
    local rs_files=$(find "${directory}" -name "*.rs" 2>/dev/null | wc -l | tr -d ' ')

    local languages='[]'
    if [[ ${py_files} -gt 0 ]]; then
        languages=$(echo "${languages}" | jq '. += ["python"]')
    fi
    if [[ ${js_files} -gt 0 ]]; then
        languages=$(echo "${languages}" | jq '. += ["javascript"]')
    fi
    if [[ ${go_files} -gt 0 ]]; then
        languages=$(echo "${languages}" | jq '. += ["go"]')
    fi
    if [[ ${rs_files} -gt 0 ]]; then
        languages=$(echo "${languages}" | jq '. += ["rust"]')
    fi

    structure=$(echo "${structure}" | jq ".languages = ${languages}")

    # Detect testing framework
    local has_pytest=false
    local has_jest=false
    local has_go_test=false

    if [[ -f "${directory}/pytest.ini" ]] || [[ -f "${directory}/setup.py" ]]; then
        has_pytest=true
    fi

    if [[ -f "${directory}/package.json" ]]; then
        if grep -q "jest" "${directory}/package.json" 2>/dev/null; then
            has_jest=true
        fi
    fi

    if [[ -d "${directory}/tests" ]] || [[ ${go_files} -gt 0 ]]; then
        has_go_test=true
    fi

    structure=$(echo "${structure}" | jq ".testing.pytest = ${has_pytest}")
    structure=$(echo "${structure}" | jq ".testing.jest = ${has_jest}")
    structure=$(echo "${structure}" | jq ".testing.go_test = ${has_go_test}")

    # Detect build system
    local has_makefile=false
    local has_docker=false
    local has_ci=false

    if [[ -f "${directory}/Makefile" ]]; then
        has_makefile=true
    fi

    if [[ -f "${directory}/Dockerfile" ]] || [[ -f "${directory}/docker-compose.yml" ]]; then
        has_docker=true
    fi

    if [[ -d "${directory}/.github/workflows" ]] || [[ -f "${directory}/.gitlab-ci.yml" ]]; then
        has_ci=true
    fi

    structure=$(echo "${structure}" | jq ".build.makefile = ${has_makefile}")
    structure=$(echo "${structure}" | jq ".build.docker = ${has_docker}")
    structure=$(echo "${structure}" | jq ".build.ci = ${has_ci}")

    echo "${structure}"
}

# Suggest agents based on codebase structure
suggest_agents() {
    local request="$1"
    local structure="$2"

    log "Suggesting agents for: ${request}"

    local agents='[]'

    # Always include core agents
    agents=$(echo "${agents}" | jq '. += ["explore-agent", "analyze-agent"]')

    # Language-specific agents
    local languages=$(echo "${structure}" | jq -r '.languages[]' 2>/dev/null)
    if echo "${languages}" | grep -q "python"; then
        agents=$(echo "${agents}" | jq '. += ["python-agent"]')
    fi

    if echo "${languages}" | grep -q "javascript"; then
        agents=$(echo "${agents}" | jq '. += ["javascript-agent"]')
    fi

    # Testing agents
    local has_pytest=$(echo "${structure}" | jq -r '.testing.pytest // false')
    local has_jest=$(echo "${structure}" | jq -r '.testing.jest // false')

    if [[ "${has_pytest}" == "true" ]] || [[ "${has_jest}" == "true" ]]; then
        agents=$(echo "${agents}" | jq '. += ["test-runner-agent"]')
    fi

    # Task-specific agents
    if echo "${request}" | grep -iq "debug\|fix\|error\|bug"; then
        agents=$(echo "${agents}" | jq '. += ["debug-agent"]')
    fi

    if echo "${request}" | grep -iq "test\|coverage"; then
        agents=$(echo "${agents}" | jq '. += ["test-runner-agent"]')
    fi

    if echo "${request}" | grep -iq "refactor\|optimize"; then
        agents=$(echo "${agents}" | jq '. += ["refactor-agent"]')
    fi

    if echo "${request}" | grep -iq "document\|readme"; then
        agents=$(echo "${agents}" | jq '. += ["documentation-agent"]')
    fi

    # Remove duplicates
    agents=$(echo "${agents}" | jq 'unique')

    echo "${agents}"
}

# Build enhanced prompt
build_enhanced_prompt() {
    local request="$1"
    local context="$2"
    local structure="$3"

    local prompt=""

    # Original request
    prompt+="# Task Request\n\n"
    prompt+="${request}\n\n"

    # Preloaded context
    if [[ -n "${context}" ]]; then
        prompt+="# Preloaded Context\n\n"
        prompt+="${context}\n\n"
    fi

    # Codebase structure
    prompt+="# Codebase Structure\n\n"
    prompt+="\`\`\`json\n"
    prompt+="${structure}\n"
    prompt+="\`\`\`\n\n"

    # Guidance
    prompt+="# Guidance\n\n"
    prompt+="- Start with the preloaded context above\n"
    prompt+="- Consider the codebase structure\n"
    prompt+="- Focus on the most relevant files first\n"
    prompt+="- Report your findings clearly\n"

    echo -e "${prompt}"
}

# Track agent access
track_agent_access() {
    local agent="$1"
    local file="$2"
    local timestamp=$(date +%s)

    local tracking_file="${DATA_DIR}/agent-access-tracking.json"

    if [[ ! -f "${tracking_file}" ]]; then
        echo '{"accesses": []}' > "${tracking_file}"
    fi

    local entry=$(jq -n \
        --arg agent "${agent}" \
        --arg file "${file}" \
        --arg timestamp "${timestamp}" \
        '{agent: $agent, file: $file, timestamp: $timestamp}')

    local tmp_file="${tracking_file}.tmp"
    jq ".accesses += [${entry}]" "${tracking_file}" > "${tmp_file}"
    mv "${tmp_file}" "${tracking_file}"

    log "Tracked: ${agent} accessed ${file}"
}

# Analyze agent access patterns
analyze_access_patterns() {
    local tracking_file="${DATA_DIR}/agent-access-tracking.json"

    if [[ ! -f "${tracking_file}" ]]; then
        echo "No tracking data available"
        return 0
    fi

    echo "Agent Access Patterns"
    echo "════════════════════════════════════════"
    echo ""

    # Most accessed files
    echo "Most Accessed Files:"
    jq -r '.accesses[] | .file' "${tracking_file}" | \
        sort | uniq -c | sort -rn | head -10 | \
        awk '{print "  " $1 " times: " $2}'
    echo ""

    # Agent activity
    echo "Agent Activity:"
    jq -r '.accesses[] | .agent' "${tracking_file}" | \
        sort | uniq -c | sort -rn | \
        awk '{print "  " $1 " accesses: " $2}'
    echo ""

    # Recent activity
    echo "Recent Activity (last 10):"
    jq -r '.accesses[-10:] | .[] | "\(.agent): \(.file)"' "${tracking_file}" | \
        sed 's/^/  /'

    echo ""
    echo "════════════════════════════════════════"
}

# Enhance orchestration
enhance_orchestration() {
    local request="$1"
    local directory="${2:-${PWD}}"
    local dry_run="${3:-false}"

    log "Enhancing orchestration for: ${request}"

    if [[ "${dry_run}" == "true" ]]; then
        echo "[DRY RUN] Would enhance orchestration for: ${request}"
        return 0
    fi

    # Step 1: Detect codebase structure
    echo "Step 1/4: Detecting codebase structure..."
    local structure=$(detect_codebase_structure "${directory}")
    echo "Detected: $(echo "${structure}" | jq -r '.languages | join(", ")')"
    echo ""

    # Step 2: Preload context
    echo "Step 2/4: Preloading context..."
    local context=""
    if [[ -f "${SCRIPTS_DIR}/context-preloader.sh" ]]; then
        context=$(bash "${SCRIPTS_DIR}/context-preloader.sh" preload "${request}" "${directory}" 2>/dev/null || echo "")
    fi
    echo ""

    # Step 3: Suggest agents
    echo "Step 3/4: Suggesting agents..."
    local agents=$(suggest_agents "${request}" "${structure}")
    echo "Suggested agents: $(echo "${agents}" | jq -r 'join(", ")')"
    echo ""

    # Step 4: Build enhanced prompt
    echo "Step 4/4: Building enhanced prompt..."
    local enhanced_prompt=$(build_enhanced_prompt "${request}" "${context}" "${structure}")

    # Save enhanced prompt
    local prompt_file="${DATA_DIR}/last-enhanced-prompt.md"
    echo "${enhanced_prompt}" > "${prompt_file}"

    echo ""
    success "Enhanced orchestration prepared"
    echo ""
    echo "Enhanced prompt saved to: ${prompt_file}"
    echo "Suggested agents: $(echo "${agents}" | jq -r 'join(", ")')"
    echo ""
    echo "Next step: Launch orchestration with enhanced prompt"
}

# Test enhancer
test_enhancer() {
    echo "Testing orchestration enhancer..."
    echo ""

    # Test 1: Detect structure
    echo "Test 1: Detect codebase structure"
    local structure=$(detect_codebase_structure ".")
    echo "Structure: $(echo "${structure}" | jq -c .)"
    echo ""

    # Test 2: Suggest agents
    echo "Test 2: Suggest agents"
    local agents=$(suggest_agents "Debug authentication" "${structure}")
    echo "Agents: $(echo "${agents}" | jq -r 'join(", ")')"
    echo ""

    # Test 3: Build prompt
    echo "Test 3: Build enhanced prompt"
    local prompt=$(build_enhanced_prompt "test request" "test context" "${structure}")
    local lines=$(echo "${prompt}" | wc -l | tr -d ' ')
    echo "Prompt: ${lines} lines"
    echo ""

    success "All tests completed"
}

# Usage
usage() {
    cat <<EOF
Orchestration Enhancer - Enhance orchestrator with index intelligence

USAGE:
    orchestration-enhancer.sh <command> [options]

COMMANDS:
    enhance <request> [directory]   Enhance orchestration for request
    detect-structure [directory]    Detect codebase structure
    suggest-agents <request>        Suggest agents for request
    build-prompt <request>          Build enhanced prompt

    track <agent> <file>            Track agent access
    analyze-access                  Analyze access patterns
    test                            Run test suite

OPTIONS:
    --dry-run                       Show what would be done
    --help                          Show this help

EXAMPLES:
    # Enhance orchestration
    orchestration-enhancer.sh enhance "Fix login bug"

    # Detect structure
    orchestration-enhancer.sh detect-structure

    # Suggest agents
    orchestration-enhancer.sh suggest-agents "Debug authentication"

    # Analyze access patterns
    orchestration-enhancer.sh analyze-access

EOF
}

# Main
main() {
    local command="${1:-}"

    case "${command}" in
        enhance)
            shift
            enhance_orchestration "$@"
            ;;
        detect-structure)
            shift
            detect_codebase_structure "$@"
            ;;
        suggest-agents)
            shift
            local structure=$(detect_codebase_structure ".")
            suggest_agents "$@" "${structure}"
            ;;
        build-prompt)
            shift
            local structure=$(detect_codebase_structure ".")
            local context=$(bash "${SCRIPTS_DIR}/context-preloader.sh" preload "$@" 2>/dev/null || echo "")
            build_enhanced_prompt "$@" "${context}" "${structure}"
            ;;
        track)
            shift
            track_agent_access "$@"
            ;;
        analyze-access)
            analyze_access_patterns
            ;;
        test)
            test_enhancer
            ;;
        --help|-h|"")
            usage
            ;;
        *)
            error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
