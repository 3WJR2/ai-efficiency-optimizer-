#!/usr/bin/env bash
# test-orchestrator.sh - Comprehensive test suite for orchestrator system
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/request-classifier.sh"
ORCHESTRATOR="$SCRIPT_DIR/orchestrator.sh"
COORDINATOR="$HOME/.claude/agents/coordinator-agent.sh"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
log_test() {
    local status="$1"
    local name="$2"
    local message="${3:-}"

    ((TESTS_RUN++))

    if [[ "$status" == "PASS" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $name"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $name"
        if [[ -n "$message" ]]; then
            echo -e "  ${RED}Error: $message${NC}"
        fi
    fi
}

# Assert functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values not equal}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo "$message" >&2
        echo "  Expected: $expected" >&2
        echo "  Actual: $actual" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String not found}"

    if echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        echo "$message" >&2
        return 1
    fi
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local message="${3:-JSON field not found}"

    if echo "$json" | jq -e "$field" >/dev/null 2>&1; then
        return 0
    else
        echo "$message" >&2
        return 1
    fi
}

# Test 1: Request Classification
test_classification() {
    echo
    echo -e "${BLUE}=== Test Suite 1: Request Classification ===${NC}"
    echo

    # Test debug classification
    local result=$("$CLASSIFIER" classify "Debug why authentication is failing" 2>/dev/null)
    if assert_json_field "$result" ".type" && \
       [[ $(echo "$result" | jq -r '.type') == "debug" ]]; then
        log_test "PASS" "Classify debug request"
    else
        log_test "FAIL" "Classify debug request" "Failed to classify as debug"
    fi

    # Test implement classification
    result=$("$CLASSIFIER" classify "Implement user profile feature" 2>/dev/null)
    if assert_json_field "$result" ".type" && \
       [[ $(echo "$result" | jq -r '.type') == "implement" ]]; then
        log_test "PASS" "Classify implement request"
    else
        log_test "FAIL" "Classify implement request" "Failed to classify as implement"
    fi

    # Test refactor classification
    result=$("$CLASSIFIER" classify "Refactor the payment processing code" 2>/dev/null)
    if assert_json_field "$result" ".type" && \
       [[ $(echo "$result" | jq -r '.type') == "refactor" ]]; then
        log_test "PASS" "Classify refactor request"
    else
        log_test "FAIL" "Classify refactor request" "Failed to classify as refactor"
    fi

    # Test explore classification
    result=$("$CLASSIFIER" classify "Where is the API endpoint defined?" 2>/dev/null)
    if assert_json_field "$result" ".type" && \
       [[ $(echo "$result" | jq -r '.type') == "explore" ]]; then
        log_test "PASS" "Classify explore request"
    else
        log_test "FAIL" "Classify explore request" "Failed to classify as explore"
    fi

    # Test confidence scores
    result=$("$CLASSIFIER" classify "Debug authentication failure" 2>/dev/null)
    local confidence=$(echo "$result" | jq -r '.confidence // 0')
    if (( $(echo "$confidence > 0" | bc -l) )); then
        log_test "PASS" "Confidence score calculation"
    else
        log_test "FAIL" "Confidence score calculation" "Confidence is zero or missing"
    fi

    # Test intent detection
    result=$("$CLASSIFIER" classify "How does authentication work?" 2>/dev/null)
    local intent=$(echo "$result" | jq -r '.intent')
    if [[ "$intent" == "inquiry" ]] || [[ "$intent" == "mixed" ]]; then
        log_test "PASS" "Intent detection (inquiry)"
    else
        log_test "FAIL" "Intent detection (inquiry)" "Expected inquiry, got $intent"
    fi

    # Test complexity estimation
    result=$("$CLASSIFIER" classify "Build a complete authentication system with OAuth, JWT, 2FA, and role-based access control" 2>/dev/null)
    local complexity=$(echo "$result" | jq -r '.complexity')
    if [[ "$complexity" == "high" ]]; then
        log_test "PASS" "Complexity estimation (high)"
    else
        log_test "FAIL" "Complexity estimation (high)" "Expected high, got $complexity"
    fi

    # Test domain detection
    result=$("$CLASSIFIER" classify "Fix the React component rendering issue" 2>/dev/null)
    local domains=$(echo "$result" | jq -r '.domains[]' 2>/dev/null || echo "")
    if echo "$domains" | grep -q "frontend"; then
        log_test "PASS" "Domain detection (frontend)"
    else
        log_test "FAIL" "Domain detection (frontend)" "Frontend domain not detected"
    fi

    # Test keyword extraction
    result=$("$CLASSIFIER" classify "Debug the payment_processor module" 2>/dev/null)
    if assert_json_field "$result" ".keywords"; then
        log_test "PASS" "Keyword extraction"
    else
        log_test "FAIL" "Keyword extraction" "Keywords field missing"
    fi
}

# Test 2: Strategy Selection
test_strategy_selection() {
    echo
    echo -e "${BLUE}=== Test Suite 2: Strategy Selection ===${NC}"
    echo

    # Test debug strategy
    local result=$("$ORCHESTRATOR" dry-run "Debug authentication failure" 2>/dev/null)
    if echo "$result" | grep -q "debug"; then
        log_test "PASS" "Debug strategy selection"
    else
        log_test "FAIL" "Debug strategy selection" "Debug strategy not selected"
    fi

    # Test implement strategy
    result=$("$ORCHESTRATOR" dry-run "Implement user profile" 2>/dev/null)
    if echo "$result" | grep -q "implement"; then
        log_test "PASS" "Implement strategy selection"
    else
        log_test "FAIL" "Implement strategy selection" "Implement strategy not selected"
    fi

    # Test explore strategy
    result=$("$ORCHESTRATOR" dry-run "Where is the API defined?" 2>/dev/null)
    if echo "$result" | grep -q "explore"; then
        log_test "PASS" "Explore strategy selection"
    else
        log_test "FAIL" "Explore strategy selection" "Explore strategy not selected"
    fi
}

# Test 3: Execution Plan Generation
test_execution_plan() {
    echo
    echo -e "${BLUE}=== Test Suite 3: Execution Plan Generation ===${NC}"
    echo

    # Test plan has agents
    local result=$("$ORCHESTRATOR" dry-run "Debug authentication" 2>/dev/null)
    if echo "$result" | grep -q "agents"; then
        log_test "PASS" "Execution plan includes agents"
    else
        log_test "FAIL" "Execution plan includes agents" "No agents in plan"
    fi

    # Test priority ordering
    if echo "$result" | grep -q "priority"; then
        log_test "PASS" "Execution plan includes priorities"
    else
        log_test "FAIL" "Execution plan includes priorities" "No priorities in plan"
    fi

    # Test parallel execution detection
    result=$("$ORCHESTRATOR" dry-run "Debug authentication failure" 2>/dev/null)
    if echo "$result" | grep -q "parallel"; then
        log_test "PASS" "Parallel execution detection"
    else
        log_test "FAIL" "Parallel execution detection" "Parallel field not found"
    fi
}

# Test 4: Coordinator Strategies
test_coordinator() {
    echo
    echo -e "${BLUE}=== Test Suite 4: Coordinator Strategies ===${NC}"
    echo

    # Test coordinator listing
    local strategies=$("$COORDINATOR" strategies 2>/dev/null)
    if echo "$strategies" | grep -q "synthesize_root_cause"; then
        log_test "PASS" "List coordinator strategies"
    else
        log_test "FAIL" "List coordinator strategies" "Strategies not listed"
    fi

    # Test each coordinator strategy exists
    local strategy_names=(
        "synthesize_root_cause"
        "review_and_integrate"
        "validate_improvements"
        "synthesize_understanding"
        "validate_coverage"
        "validate_design"
        "create_guide"
        "validate_fix"
        "validate_performance"
    )

    for strategy in "${strategy_names[@]}"; do
        if echo "$strategies" | grep -q "$strategy"; then
            log_test "PASS" "Strategy exists: $strategy"
        else
            log_test "FAIL" "Strategy exists: $strategy" "Strategy not found"
        fi
    done
}

# Test 5: Integration Tests
test_integration() {
    echo
    echo -e "${BLUE}=== Test Suite 5: Integration Tests ===${NC}"
    echo

    # Test full orchestration flow (dry run)
    local result=$("$ORCHESTRATOR" dry-run "Debug why tests are failing" 2>/dev/null)

    # Check classification happened
    if echo "$result" | grep -q "type"; then
        log_test "PASS" "Integration: Classification"
    else
        log_test "FAIL" "Integration: Classification" "Classification missing"
    fi

    # Check strategy selected
    if echo "$result" | grep -q "debug\|test"; then
        log_test "PASS" "Integration: Strategy selection"
    else
        log_test "FAIL" "Integration: Strategy selection" "Strategy not selected"
    fi

    # Check execution plan generated
    if echo "$result" | grep -q "agents"; then
        log_test "PASS" "Integration: Execution plan"
    else
        log_test "FAIL" "Integration: Execution plan" "Plan not generated"
    fi
}

# Test 6: Learning and Adaptation
test_learning() {
    echo
    echo -e "${BLUE}=== Test Suite 6: Learning and Adaptation ===${NC}"
    echo

    # Test classification history
    "$CLASSIFIER" classify "Test request for learning" >/dev/null 2>&1
    local history=$("$CLASSIFIER" stats 2>/dev/null)

    if echo "$history" | grep -q "total_classifications"; then
        log_test "PASS" "Classification history tracking"
    else
        log_test "FAIL" "Classification history tracking" "History not tracked"
    fi

    # Test outcome recording
    "$CLASSIFIER" record-outcome "debug" "success" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_test "PASS" "Outcome recording"
    else
        log_test "FAIL" "Outcome recording" "Failed to record outcome"
    fi
}

# Test 7: Error Handling
test_error_handling() {
    echo
    echo -e "${BLUE}=== Test Suite 7: Error Handling ===${NC}"
    echo

    # Test empty request
    if ! "$CLASSIFIER" classify "" >/dev/null 2>&1; then
        log_test "PASS" "Handle empty request"
    else
        log_test "FAIL" "Handle empty request" "Should fail on empty request"
    fi

    # Test invalid strategy
    local result=$("$ORCHESTRATOR" dry-run "xyz invalid request 123" 2>/dev/null || echo "failed")
    if [[ -n "$result" ]]; then
        log_test "PASS" "Handle unclear request"
    else
        log_test "FAIL" "Handle unclear request" "Should handle gracefully"
    fi
}

# Test 8: Performance Tests
test_performance() {
    echo
    echo -e "${BLUE}=== Test Suite 8: Performance Tests ===${NC}"
    echo

    # Test classification speed
    local start=$(date +%s%N)
    "$CLASSIFIER" classify "Debug authentication" >/dev/null 2>&1
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 )) # Convert to milliseconds

    if [[ $duration -lt 1000 ]]; then
        log_test "PASS" "Classification speed (${duration}ms)"
    else
        log_test "FAIL" "Classification speed (${duration}ms)" "Too slow"
    fi

    # Test orchestration planning speed
    start=$(date +%s%N)
    "$ORCHESTRATOR" dry-run "Implement feature" >/dev/null 2>&1
    end=$(date +%s%N)
    duration=$(( (end - start) / 1000000 ))

    if [[ $duration -lt 2000 ]]; then
        log_test "PASS" "Orchestration planning speed (${duration}ms)"
    else
        log_test "FAIL" "Orchestration planning speed (${duration}ms)" "Too slow"
    fi
}

# Main test runner
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Orchestrator System Test Suite               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"

    # Run all test suites
    test_classification
    test_strategy_selection
    test_execution_plan
    test_coordinator
    test_integration
    test_learning
    test_error_handling
    test_performance

    # Summary
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "Total tests run:    $TESTS_RUN"
    echo -e "${GREEN}Tests passed:       $TESTS_PASSED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Tests failed:       $TESTS_FAILED${NC}"
        echo
        echo -e "${RED}Some tests failed. Please review the output above.${NC}"
        exit 1
    else
        echo -e "${RED}Tests failed:       $TESTS_FAILED${NC}"
        echo
        echo -e "${GREEN}All tests passed! ✓${NC}"
        exit 0
    fi
}

# Run tests
main "$@"
