#!/usr/bin/env bash
# test-knowledge-graph.sh - Test suite for knowledge graph system
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
GRAPH_BUILDER="${SCRIPT_DIR}/knowledge-graph-builder.sh"
RECOMMENDER="${SCRIPT_DIR}/solution-recommender.sh"
CONTEXT_RANKER="${SCRIPT_DIR}/context-ranker.sh"
LEARNING_TRACKER="${SCRIPT_DIR}/learning-path-tracker.sh"
SESSION_STARTUP="${SCRIPT_DIR}/smart-session-startup.sh"
FEEDBACK="${SCRIPT_DIR}/recommendation-feedback.sh"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_test() { echo -e "${CYAN}[TEST]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((TESTS_FAILED++)); }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }

# Setup test environment
setup_tests() {
    log_info "Setting up test environment..."

    # Backup existing knowledge if present
    if [[ -d "${KNOWLEDGE_DIR}" ]]; then
        local backup_dir="${KNOWLEDGE_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "${KNOWLEDGE_DIR}" "$backup_dir"
        log_info "Backed up existing knowledge to: $backup_dir"
    fi

    mkdir -p "${KNOWLEDGE_DIR}"
}

# Cleanup after tests
cleanup_tests() {
    log_info "Cleaning up test environment..."

    # Could restore backup here if desired
    # For now, just leaving test data in place

    echo ""
    echo "=== Test Results ==="
    echo "Total: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Test 1: Graph Building
test_graph_building() {
    log_test "Test 1: Graph Building"
    ((TESTS_RUN++))

    # Build sample graph
    if ! "$GRAPH_BUILDER" sample &>/dev/null; then
        log_fail "Failed to create sample graph"
        return 1
    fi

    # Verify graph file exists
    if [[ ! -f "${KNOWLEDGE_DIR}/knowledge-graph.json" ]]; then
        log_fail "Graph file not created"
        return 1
    fi

    # Verify graph has nodes and edges
    local nodes=$(jq '.nodes | length' "${KNOWLEDGE_DIR}/knowledge-graph.json")
    local edges=$(jq '.edges | length' "${KNOWLEDGE_DIR}/knowledge-graph.json")

    if [[ $nodes -lt 1 ]]; then
        log_fail "No nodes in graph"
        return 1
    fi

    if [[ $edges -lt 1 ]]; then
        log_fail "No edges in graph"
        return 1
    fi

    log_pass "Graph built with $nodes nodes and $edges edges"
}

# Test 2: Relationship Detection
test_relationships() {
    log_test "Test 2: Relationship Detection"
    ((TESTS_RUN++))

    # Create two test entries
    local entry1='{"id":"test1","tags":["auth","nodejs"],"confidence":0.85,"metadata":{"problem":"User authentication","solution":"JWT tokens"},"created":"2026-01-15T10:00:00Z"}'
    local entry2='{"id":"test2","tags":["auth","oauth"],"confidence":0.90,"metadata":{"problem":"Social login, building on previous auth work","solution":"OAuth 2.0"},"created":"2026-02-01T10:00:00Z"}'

    echo "$entry1" > /tmp/test_entry1.json
    echo "$entry2" > /tmp/test_entry2.json

    # Detect relationships
    local relationships=$("$GRAPH_BUILDER" detect /tmp/test_entry1.json /tmp/test_entry2.json 2>/dev/null)

    # Check if any relationships detected
    local count=$(echo "$relationships" | jq 'length')

    if [[ $count -lt 1 ]]; then
        log_fail "No relationships detected between related entries"
        rm -f /tmp/test_entry1.json /tmp/test_entry2.json
        return 1
    fi

    # Verify "builds-on" or "related-to" detected
    local has_valid=$(echo "$relationships" | jq '[.[] | select(.type == "builds-on" or .type == "related-to")] | length')

    if [[ $has_valid -lt 1 ]]; then
        log_fail "No valid relationships (builds-on/related-to) detected"
        rm -f /tmp/test_entry1.json /tmp/test_entry2.json
        return 1
    fi

    log_pass "Detected $count relationship(s)"
    rm -f /tmp/test_entry1.json /tmp/test_entry2.json
}

# Test 3: Solution Recommendations
test_recommendations() {
    log_test "Test 3: Solution Recommendations"
    ((TESTS_RUN++))

    # Request recommendations
    local query="implement user authentication"
    local recommendations=$("$RECOMMENDER" recommend "$query" 5 2>/dev/null)

    # Verify JSON structure
    if ! echo "$recommendations" | jq empty 2>/dev/null; then
        log_fail "Invalid JSON response from recommender"
        return 1
    fi

    # Check if recommendations returned
    local count=$(echo "$recommendations" | jq '.recommendations | length')

    if [[ $count -lt 1 ]]; then
        log_fail "No recommendations returned"
        return 1
    fi

    # Verify required fields
    local has_score=$(echo "$recommendations" | jq '.recommendations[0].score' 2>/dev/null)

    if [[ -z "$has_score" || "$has_score" == "null" ]]; then
        log_fail "Recommendations missing score field"
        return 1
    fi

    log_pass "Returned $count recommendation(s) with valid scores"
}

# Test 4: Context Ranking
test_context_ranking() {
    log_test "Test 4: Context Ranking"
    ((TESTS_RUN++))

    # Create mock context
    local context='{"language":"javascript","framework":"nodejs","technologies":["auth","express"],"focus_areas":["authentication"]}'

    # Get all knowledge IDs
    local ids=$(jq -c '[.nodes[].id]' "${KNOWLEDGE_DIR}/knowledge-graph.json" 2>/dev/null || echo "[]")

    if [[ "$ids" == "[]" ]]; then
        log_fail "No knowledge IDs found"
        return 1
    fi

    # Rank by context
    local ranked=$("$CONTEXT_RANKER" rank "$ids" "$context" 2>/dev/null)

    # Verify JSON structure
    if ! echo "$ranked" | jq empty 2>/dev/null; then
        log_fail "Invalid JSON response from context ranker"
        return 1
    fi

    # Check if ranking returned
    local count=$(echo "$ranked" | jq '.ranked_knowledge | length')

    if [[ $count -lt 1 ]]; then
        log_fail "No ranked knowledge returned"
        return 1
    fi

    log_pass "Ranked $count knowledge entries by context"
}

# Test 5: Learning Path
test_learning_path() {
    log_test "Test 5: Learning Path"
    ((TESTS_RUN++))

    # Get learning path for "auth" domain
    local path=$("$LEARNING_TRACKER" path "auth" 2>/dev/null)

    # Verify JSON structure
    if ! echo "$path" | jq empty 2>/dev/null; then
        log_fail "Invalid JSON response from learning tracker"
        return 1
    fi

    # Check if path exists
    local steps=$(echo "$path" | jq '.path | length')

    if [[ $steps -lt 1 ]]; then
        log_fail "No learning path found"
        return 1
    fi

    log_pass "Generated learning path with $steps step(s)"
}

# Test 6: Session Startup
test_session_startup() {
    log_test "Test 6: Session Startup"
    ((TESTS_RUN++))

    # Create temporary session directory
    local session_dir="/tmp/test_session_$$"
    mkdir -p "$session_dir"

    # Run session startup
    local prompt="implement authentication with OAuth"
    if ! "$SESSION_STARTUP" inject "$session_dir" "$prompt" 3 &>/dev/null; then
        log_fail "Session startup failed"
        rm -rf "$session_dir"
        return 1
    fi

    # Verify context file created
    if [[ ! -f "$session_dir/.session-context.md" ]]; then
        log_fail "Session context file not created"
        rm -rf "$session_dir"
        return 1
    fi

    # Verify content
    if ! grep -q "Relevant Past Solutions" "$session_dir/.session-context.md"; then
        log_fail "Session context missing expected content"
        rm -rf "$session_dir"
        return 1
    fi

    log_pass "Session startup successful with knowledge injection"
    rm -rf "$session_dir"
}

# Test 7: Feedback Loop
test_feedback() {
    log_test "Test 7: Feedback Loop"
    ((TESTS_RUN++))

    # Track usage
    if ! "$FEEDBACK" track "k_auth_basic_20260115" "success" &>/dev/null; then
        log_fail "Failed to track feedback"
        return 1
    fi

    # Get stats
    local stats=$("$FEEDBACK" stats 2>&1)

    # Verify stats contain usage
    if ! echo "$stats" | grep -q "Total Feedback"; then
        log_fail "Feedback stats not generated"
        return 1
    fi

    log_pass "Feedback tracking operational"
}

# Test 8: Export Functionality
test_export() {
    log_test "Test 8: Graph Export"
    ((TESTS_RUN++))

    # Export as JSON
    local json_export="/tmp/test_graph_export.json"
    if ! "$GRAPH_BUILDER" export json "$json_export" &>/dev/null; then
        log_fail "Failed to export graph as JSON"
        return 1
    fi

    if [[ ! -f "$json_export" ]]; then
        log_fail "JSON export file not created"
        return 1
    fi

    # Export as DOT
    local dot_export="/tmp/test_graph_export.dot"
    if ! "$GRAPH_BUILDER" export dot "$dot_export" &>/dev/null; then
        log_fail "Failed to export graph as DOT"
        rm -f "$json_export"
        return 1
    fi

    if [[ ! -f "$dot_export" ]]; then
        log_fail "DOT export file not created"
        rm -f "$json_export"
        return 1
    fi

    log_pass "Graph export successful (JSON, DOT)"
    rm -f "$json_export" "$dot_export"
}

# Test 9: Performance
test_performance() {
    log_test "Test 9: Performance"
    ((TESTS_RUN++))

    # Measure recommendation time
    local start=$(date +%s%3N)  # milliseconds
    "$RECOMMENDER" recommend "implement authentication" 10 &>/dev/null
    local end=$(date +%s%3N)

    local duration=$((end - start))

    # Should be under 2 seconds (2000ms)
    if [[ $duration -gt 2000 ]]; then
        log_fail "Recommendations too slow: ${duration}ms (target: <2000ms)"
        return 1
    fi

    log_pass "Recommendations completed in ${duration}ms"
}

# Test 10: Integration
test_integration() {
    log_test "Test 10: End-to-End Integration"
    ((TESTS_RUN++))

    # Simulate full workflow:
    # 1. Build graph
    # 2. Get recommendations
    # 3. Track feedback
    # 4. Update weights
    # 5. Get new recommendations

    # Step 1: Graph already built

    # Step 2: Get recommendations
    local recs1=$("$RECOMMENDER" recommend "implement websocket" 3 2>/dev/null)
    local count1=$(echo "$recs1" | jq '.recommendations | length')

    if [[ $count1 -lt 1 ]]; then
        log_fail "Integration: No initial recommendations"
        return 1
    fi

    # Step 3: Track positive feedback
    "$FEEDBACK" track "k_websocket_realtime_20260205" "success" &>/dev/null

    # Step 4: Update weights
    "$FEEDBACK" update-weights &>/dev/null

    # Step 5: Get new recommendations (should prioritize successful ones)
    local recs2=$("$RECOMMENDER" recommend "implement websocket" 3 2>/dev/null)
    local count2=$(echo "$recs2" | jq '.recommendations | length')

    if [[ $count2 -lt 1 ]]; then
        log_fail "Integration: No recommendations after feedback"
        return 1
    fi

    log_pass "End-to-end integration successful"
}

# Run all tests
run_all_tests() {
    echo ""
    echo "=== Knowledge Graph System Test Suite ==="
    echo ""

    setup_tests

    test_graph_building
    test_relationships
    test_recommendations
    test_context_ranking
    test_learning_path
    test_session_startup
    test_feedback
    test_export
    test_performance
    test_integration

    cleanup_tests
}

# Main
main() {
    case "${1:-all}" in
        all)
            run_all_tests
            ;;
        graph)
            setup_tests
            test_graph_building
            cleanup_tests
            ;;
        relationships)
            setup_tests
            test_graph_building
            test_relationships
            cleanup_tests
            ;;
        recommendations)
            setup_tests
            test_graph_building
            test_recommendations
            cleanup_tests
            ;;
        context)
            setup_tests
            test_graph_building
            test_context_ranking
            cleanup_tests
            ;;
        learning)
            setup_tests
            test_graph_building
            test_learning_path
            cleanup_tests
            ;;
        session)
            setup_tests
            test_graph_building
            test_session_startup
            cleanup_tests
            ;;
        feedback)
            setup_tests
            test_graph_building
            test_feedback
            cleanup_tests
            ;;
        export)
            setup_tests
            test_graph_building
            test_export
            cleanup_tests
            ;;
        performance)
            setup_tests
            test_graph_building
            test_performance
            cleanup_tests
            ;;
        integration)
            setup_tests
            test_graph_building
            test_integration
            cleanup_tests
            ;;
        *)
            cat <<EOF
Usage: $0 {all|graph|relationships|recommendations|context|learning|session|feedback|export|performance|integration}

Test Suites:
  all            - Run all tests
  graph          - Test graph building
  relationships  - Test relationship detection
  recommendations- Test solution recommendations
  context        - Test context ranking
  learning       - Test learning path tracking
  session        - Test session startup
  feedback       - Test feedback loop
  export         - Test export functionality
  performance    - Test performance benchmarks
  integration    - Test end-to-end integration
EOF
            exit 1
            ;;
    esac
}

# Run main
main "$@"
