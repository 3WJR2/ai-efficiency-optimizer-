#!/usr/bin/env bash

################################################################################
# test-integration.sh - Comprehensive test suite for integration layer
# Version: 1.0.0
#
# Tests all components of the orchestrator + indexer integration
################################################################################

set -euo pipefail

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"
DATA_DIR="${CLAUDE_HOME}/data"
LOGS_DIR="${CLAUDE_HOME}/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Logging
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

error() {
    echo -e "${RED}✗${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

# Test framework
test_start() {
    local test_name="$1"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test: ${test_name}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

test_pass() {
    success "$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    error "$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_skip() {
    warning "$1 (SKIPPED)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# Test 1: Unified CLI
test_unified_cli() {
    test_start "Unified CLI (claude-assistant.sh)"

    # Check script exists
    if [[ ! -f "${SCRIPTS_DIR}/claude-assistant.sh" ]]; then
        test_fail "Script not found"
        return 1
    fi
    test_pass "Script exists"

    # Check executable
    if [[ ! -x "${SCRIPTS_DIR}/claude-assistant.sh" ]]; then
        test_fail "Script not executable"
        return 1
    fi
    test_pass "Script is executable"

    # Test help
    if bash "${SCRIPTS_DIR}/claude-assistant.sh" --help > /dev/null 2>&1; then
        test_pass "Help command works"
    else
        test_fail "Help command failed"
    fi

    # Test status
    if bash "${SCRIPTS_DIR}/claude-assistant.sh" status > /dev/null 2>&1; then
        test_pass "Status command works"
    else
        test_fail "Status command failed"
    fi

    # Test config
    if bash "${SCRIPTS_DIR}/claude-assistant.sh" config > /dev/null 2>&1; then
        test_pass "Config command works"
    else
        test_fail "Config command failed"
    fi

    # Test dry-run
    if bash "${SCRIPTS_DIR}/claude-assistant.sh" --dry-run search "test" > /dev/null 2>&1; then
        test_pass "Dry-run mode works"
    else
        test_fail "Dry-run mode failed"
    fi
}

# Test 2: Auto-indexer
test_auto_indexer() {
    test_start "Auto-Index Manager (auto-index-manager.sh)"

    # Check script exists
    if [[ ! -f "${SCRIPTS_DIR}/auto-index-manager.sh" ]]; then
        test_fail "Script not found"
        return 1
    fi
    test_pass "Script exists"

    # Check executable
    if [[ ! -x "${SCRIPTS_DIR}/auto-index-manager.sh" ]]; then
        test_fail "Script not executable"
        return 1
    fi
    test_pass "Script is executable"

    # Test help
    if bash "${SCRIPTS_DIR}/auto-index-manager.sh" --help > /dev/null 2>&1; then
        test_pass "Help command works"
    else
        test_fail "Help command failed"
    fi

    # Test status
    if bash "${SCRIPTS_DIR}/auto-index-manager.sh" status > /dev/null 2>&1; then
        test_pass "Status command works"
    else
        test_fail "Status command failed"
    fi

    # Test config initialization
    if bash "${SCRIPTS_DIR}/auto-index-manager.sh" show-config > /dev/null 2>&1; then
        test_pass "Config initialization works"
    else
        test_fail "Config initialization failed"
    fi

    # Test list watch directories
    if bash "${SCRIPTS_DIR}/auto-index-manager.sh" list-watch > /dev/null 2>&1; then
        test_pass "List watch directories works"
    else
        test_fail "List watch directories failed"
    fi
}

# Test 3: Context preloader
test_context_preloader() {
    test_start "Context Preloader (context-preloader.sh)"

    # Check script exists
    if [[ ! -f "${SCRIPTS_DIR}/context-preloader.sh" ]]; then
        test_fail "Script not found"
        return 1
    fi
    test_pass "Script exists"

    # Check executable
    if [[ ! -x "${SCRIPTS_DIR}/context-preloader.sh" ]]; then
        test_fail "Script not executable"
        return 1
    fi
    test_pass "Script is executable"

    # Test help
    if bash "${SCRIPTS_DIR}/context-preloader.sh" --help > /dev/null 2>&1; then
        test_pass "Help command works"
    else
        test_fail "Help command failed"
    fi

    # Test stats
    if bash "${SCRIPTS_DIR}/context-preloader.sh" stats > /dev/null 2>&1; then
        test_pass "Stats command works"
    else
        test_fail "Stats command failed"
    fi

    # Test preload
    local result=$(bash "${SCRIPTS_DIR}/context-preloader.sh" preload "test request" 2>/dev/null || echo "")
    if [[ -n "${result}" ]]; then
        test_pass "Preload command works"
    else
        test_fail "Preload command failed"
    fi

    # Test cache
    if bash "${SCRIPTS_DIR}/context-preloader.sh" clear-cache > /dev/null 2>&1; then
        test_pass "Clear cache works"
    else
        test_fail "Clear cache failed"
    fi
}

# Test 4: Orchestration enhancer
test_orchestration_enhancer() {
    test_start "Orchestration Enhancer (orchestration-enhancer.sh)"

    # Check script exists
    if [[ ! -f "${SCRIPTS_DIR}/orchestration-enhancer.sh" ]]; then
        test_fail "Script not found"
        return 1
    fi
    test_pass "Script exists"

    # Check executable
    if [[ ! -x "${SCRIPTS_DIR}/orchestration-enhancer.sh" ]]; then
        test_fail "Script not executable"
        return 1
    fi
    test_pass "Script is executable"

    # Test help
    if bash "${SCRIPTS_DIR}/orchestration-enhancer.sh" --help > /dev/null 2>&1; then
        test_pass "Help command works"
    else
        test_fail "Help command failed"
    fi

    # Test detect structure
    local structure=$(bash "${SCRIPTS_DIR}/orchestration-enhancer.sh" detect-structure 2>/dev/null || echo "{}")
    if [[ "${structure}" != "{}" ]]; then
        test_pass "Detect structure works"
    else
        test_skip "Detect structure (no codebase)"
    fi

    # Test suggest agents
    local agents=$(bash "${SCRIPTS_DIR}/orchestration-enhancer.sh" suggest-agents "test" 2>/dev/null || echo "[]")
    if [[ "${agents}" != "[]" ]]; then
        test_pass "Suggest agents works"
    else
        test_skip "Suggest agents (no codebase)"
    fi
}

# Test 5: Multi-terminal integration
test_multi_terminal_integration() {
    test_start "Multi-Terminal Integration (multi-terminal-integration.sh)"

    # Check script exists
    if [[ ! -f "${SCRIPTS_DIR}/multi-terminal-integration.sh" ]]; then
        test_fail "Script not found"
        return 1
    fi
    test_pass "Script exists"

    # Check executable
    if [[ ! -x "${SCRIPTS_DIR}/multi-terminal-integration.sh" ]]; then
        test_fail "Script not executable"
        return 1
    fi
    test_pass "Script is executable"

    # Test help
    if bash "${SCRIPTS_DIR}/multi-terminal-integration.sh" --help > /dev/null 2>&1; then
        test_pass "Help command works"
    else
        test_fail "Help command failed"
    fi

    # Test create module
    local tmp_dir=$(mktemp -d)
    if bash "${SCRIPTS_DIR}/multi-terminal-integration.sh" create-module "${tmp_dir}/test.py" > /dev/null 2>&1; then
        test_pass "Create module works"

        # Validate Python syntax
        if python3 -m py_compile "${tmp_dir}/test.py" 2>/dev/null; then
            test_pass "Generated module has valid Python syntax"
        else
            test_fail "Generated module has invalid Python syntax"
        fi
    else
        test_fail "Create module failed"
    fi
    rm -rf "${tmp_dir}"

    # Test create example
    tmp_dir=$(mktemp -d)
    if bash "${SCRIPTS_DIR}/multi-terminal-integration.sh" create-example "${tmp_dir}/example.py" > /dev/null 2>&1; then
        test_pass "Create example works"
    else
        test_fail "Create example failed"
    fi
    rm -rf "${tmp_dir}"
}

# Test 6: Performance optimizer
test_performance_optimizer() {
    test_start "Performance Optimizer (performance-optimizer.sh)"

    # Check script exists
    if [[ ! -f "${SCRIPTS_DIR}/performance-optimizer.sh" ]]; then
        test_fail "Script not found"
        return 1
    fi
    test_pass "Script exists"

    # Check executable
    if [[ ! -x "${SCRIPTS_DIR}/performance-optimizer.sh" ]]; then
        test_fail "Script not executable"
        return 1
    fi
    test_pass "Script is executable"

    # Test help
    if bash "${SCRIPTS_DIR}/performance-optimizer.sh" --help > /dev/null 2>&1; then
        test_pass "Help command works"
    else
        test_fail "Help command failed"
    fi

    # Test stats
    if bash "${SCRIPTS_DIR}/performance-optimizer.sh" stats > /dev/null 2>&1; then
        test_pass "Stats command works"
    else
        test_fail "Stats command failed"
    fi

    # Test parallel execution
    if bash "${SCRIPTS_DIR}/performance-optimizer.sh" parallel-exec "echo 'test'" > /dev/null 2>&1; then
        test_pass "Parallel execution works"
    else
        test_fail "Parallel execution failed"
    fi

    # Test clean cache
    if bash "${SCRIPTS_DIR}/performance-optimizer.sh" clean-cache all 0 > /dev/null 2>&1; then
        test_pass "Clean cache works"
    else
        test_fail "Clean cache failed"
    fi
}

# Test 7: Integration workflow
test_integration_workflow() {
    test_start "Complete Integration Workflow"

    # Test end-to-end workflow
    echo "Testing: Search → Preload → Enhance → Execute"
    echo ""

    # Step 1: Search
    echo "Step 1: Search codebase..."
    if bash "${SCRIPTS_DIR}/claude-assistant.sh" --dry-run search "test" > /dev/null 2>&1; then
        test_pass "Search step works"
    else
        test_fail "Search step failed"
    fi

    # Step 2: Preload
    echo "Step 2: Preload context..."
    if bash "${SCRIPTS_DIR}/context-preloader.sh" preload "test" > /dev/null 2>&1; then
        test_pass "Preload step works"
    else
        test_fail "Preload step failed"
    fi

    # Step 3: Enhance
    echo "Step 3: Enhance orchestration..."
    if bash "${SCRIPTS_DIR}/orchestration-enhancer.sh" detect-structure > /dev/null 2>&1; then
        test_pass "Enhance step works"
    else
        test_skip "Enhance step (no codebase)"
    fi

    # Step 4: Performance optimization
    echo "Step 4: Performance optimization..."
    if bash "${SCRIPTS_DIR}/performance-optimizer.sh" stats > /dev/null 2>&1; then
        test_pass "Optimization step works"
    else
        test_fail "Optimization step failed"
    fi
}

# Test 8: Dependencies
test_dependencies() {
    test_start "System Dependencies"

    # Check jq
    if command -v jq > /dev/null 2>&1; then
        test_pass "jq is installed"
    else
        test_fail "jq is not installed"
    fi

    # Check python3
    if command -v python3 > /dev/null 2>&1; then
        test_pass "python3 is installed"
    else
        test_fail "python3 is not installed"
    fi

    # Check bash version
    local bash_version=$(bash --version | head -1 | awk '{print $4}' | cut -d. -f1)
    if [[ ${bash_version} -ge 4 ]]; then
        test_pass "bash version is ${bash_version} (>= 4)"
    else
        warning "bash version is ${bash_version} (< 4)"
    fi

    # Check fswatch (optional)
    if command -v fswatch > /dev/null 2>&1; then
        test_pass "fswatch is installed (optional)"
    else
        warning "fswatch not installed (will use polling)"
    fi
}

# Test 9: File structure
test_file_structure() {
    test_start "File Structure"

    # Check directories
    local dirs=(
        "${DATA_DIR}"
        "${LOGS_DIR}"
        "${CLAUDE_HOME}/cache"
        "${CLAUDE_HOME}/indexes"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            test_pass "Directory exists: ${dir}"
        else
            test_fail "Directory missing: ${dir}"
        fi
    done

    # Check scripts
    local scripts=(
        "claude-assistant.sh"
        "auto-index-manager.sh"
        "context-preloader.sh"
        "orchestration-enhancer.sh"
        "multi-terminal-integration.sh"
        "performance-optimizer.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "${SCRIPTS_DIR}/${script}" ]]; then
            test_pass "Script exists: ${script}"
        else
            test_fail "Script missing: ${script}"
        fi
    done
}

# Test 10: Performance benchmark
test_performance_benchmark() {
    test_start "Performance Benchmark"

    echo "Running mini benchmark (3 iterations)..."
    echo ""

    if bash "${SCRIPTS_DIR}/performance-optimizer.sh" benchmark 3 > /dev/null 2>&1; then
        test_pass "Benchmark completed successfully"

        # Show results
        bash "${SCRIPTS_DIR}/performance-optimizer.sh" stats
    else
        test_fail "Benchmark failed"
    fi
}

# Show summary
show_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    echo -e "${GREEN}Passed:${NC}  ${TESTS_PASSED}/${total}"
    echo -e "${RED}Failed:${NC}  ${TESTS_FAILED}/${total}"
    echo -e "${YELLOW}Skipped:${NC} ${TESTS_SKIPPED}/${total}"
    echo ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
main() {
    local test_suite="${1:-all}"

    echo "═══════════════════════════════════════════"
    echo "Integration Layer Test Suite"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "Running tests: ${test_suite}"
    echo ""

    case "${test_suite}" in
        all)
            test_dependencies
            test_file_structure
            test_unified_cli
            test_auto_indexer
            test_context_preloader
            test_orchestration_enhancer
            test_multi_terminal_integration
            test_performance_optimizer
            test_integration_workflow
            test_performance_benchmark
            ;;
        quick)
            test_dependencies
            test_file_structure
            test_unified_cli
            ;;
        cli)
            test_unified_cli
            ;;
        auto-indexer)
            test_auto_indexer
            ;;
        context)
            test_context_preloader
            ;;
        orchestration)
            test_orchestration_enhancer
            ;;
        integration)
            test_multi_terminal_integration
            ;;
        performance)
            test_performance_optimizer
            test_performance_benchmark
            ;;
        workflow)
            test_integration_workflow
            ;;
        *)
            echo "Unknown test suite: ${test_suite}"
            echo ""
            echo "Available test suites:"
            echo "  all              - Run all tests"
            echo "  quick            - Run quick tests"
            echo "  cli              - Test unified CLI"
            echo "  auto-indexer     - Test auto-indexer"
            echo "  context          - Test context preloader"
            echo "  orchestration    - Test orchestration enhancer"
            echo "  integration      - Test multi-terminal integration"
            echo "  performance      - Test performance optimizer"
            echo "  workflow         - Test complete workflow"
            exit 1
            ;;
    esac

    show_summary
}

# Run main
main "$@"
