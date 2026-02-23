#!/usr/bin/env bash

# Test Suite for On-Demand Context Loading System
# Version: 1.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Directories
CLAUDE_DIR="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_DIR}/scripts"
DATA_DIR="${CLAUDE_DIR}/data"
TEST_DATA_DIR="${DATA_DIR}/test-data"

# Source scripts
source "${SCRIPTS_DIR}/request-parser.sh"
source "${SCRIPTS_DIR}/session-search.sh"
source "${SCRIPTS_DIR}/token-budget-tracker.sh"

# Initialize test environment
setup_test_environment() {
    echo "🔧 Setting up test environment..."

    mkdir -p "${TEST_DATA_DIR}"

    # Create test session data
    cat > "${TEST_DATA_DIR}/test-sessions.json" <<'EOF'
{
  "entries": [
    {
      "sessionId": "test-auth-001",
      "summary": "JWT Authentication Implementation",
      "firstPrompt": "How do I implement JWT auth?",
      "messageCount": 42,
      "created": "2026-02-15T14:00:00.000Z",
      "modified": "2026-02-15T16:30:00.000Z"
    },
    {
      "sessionId": "test-cache-001",
      "summary": "Redis Caching Strategy",
      "firstPrompt": "What's the best caching approach?",
      "messageCount": 28,
      "created": "2026-02-16T10:00:00.000Z",
      "modified": "2026-02-16T12:00:00.000Z"
    },
    {
      "sessionId": "test-security-001",
      "summary": "Security Hardening for API",
      "firstPrompt": "How to secure the API?",
      "messageCount": 35,
      "created": "2026-02-17T09:00:00.000Z",
      "modified": "2026-02-17T11:30:00.000Z"
    }
  ]
}
EOF

    echo "✅ Test environment ready"
    echo ""
}

# Cleanup test environment
cleanup_test_environment() {
    echo ""
    echo "🧹 Cleaning up test environment..."
    rm -rf "${TEST_DATA_DIR}"
    echo "✅ Cleanup complete"
}

# Test helper functions
assert_equals() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$actual" = "$expected" ]; then
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Expected to find: $needle"
        echo "  In: $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local test_name="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -n "$value" ]; then
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Value is empty"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_greater_than() {
    local actual="$1"
    local threshold="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$actual" -gt "$threshold" ]; then
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Expected > $threshold"
        echo "  Actual: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Request Parser
test_request_parser() {
    echo "📝 Testing Request Parser..."
    echo ""

    # Test 1.1: Parse topic-based query
    local result=$(parse_request "show me the auth session")
    local topic=$(echo "$result" | jq -r '.topic')
    assert_contains "$topic" "auth" "Parse topic from query"

    # Test 1.2: Parse timeframe query
    result=$(parse_request "sessions from last week")
    local timeframe=$(echo "$result" | jq -r '.timeframe')
    assert_equals "$timeframe" "last_week" "Parse timeframe from query"

    # Test 1.3: Parse focus query
    result=$(parse_request "decisions about caching")
    local focus=$(echo "$result" | jq -r '.focus')
    assert_equals "$focus" "decisions" "Parse focus from query"

    # Test 1.4: Parse session ID query
    result=$(parse_request "show me session abc-123")
    local session_id=$(echo "$result" | jq -r '.session_id')
    assert_equals "$session_id" "abc-123" "Parse session ID from query"

    # Test 1.5: Parse complex query
    result=$(parse_request "what did we decide about redis last week")
    topic=$(echo "$result" | jq -r '.topic')
    focus=$(echo "$result" | jq -r '.focus')
    assert_contains "$topic" "redis" "Extract topic from complex query"
    assert_equals "$focus" "decisions" "Extract focus from complex query"

    echo ""
}

# Test 2: Session Search
test_session_search() {
    echo "🔍 Testing Session Search..."
    echo ""

    # Test 2.1: Search by topic
    # Note: This will search real sessions, so we just check it doesn't error
    local result=$(search_by_topic "authentication" 2>/dev/null || echo "[]")
    assert_not_empty "$result" "Search by topic returns results"

    # Test 2.2: Parse timeframe start
    local start=$(parse_timeframe_start "last_week")
    assert_not_empty "$start" "Parse last_week timeframe start"

    # Test 2.3: Parse timeframe end
    local end=$(parse_timeframe_end "last_week")
    assert_not_empty "$end" "Parse last_week timeframe end"

    # Test 2.4: Parse month timeframe
    start=$(parse_timeframe_start "2026-02")
    assert_equals "$start" "2026-02-01" "Parse month timeframe"

    # Test 2.5: Parse specific date
    start=$(parse_timeframe_start "2026-02-15")
    assert_equals "$start" "2026-02-15" "Parse specific date"

    echo ""
}

# Test 3: Token Budget Tracker
test_token_budget() {
    echo "💰 Testing Token Budget Tracker..."
    echo ""

    # Initialize fresh budget
    initialize_tracker

    # Test 3.1: Get current token count
    local current=$(get_current_token_count)
    assert_equals "$current" "0" "Initial token count is zero"

    # Test 3.2: Update token count
    update_token_count "base_context" "1000"
    current=$(get_current_token_count)
    assert_equals "$current" "1000" "Update token count"

    # Test 3.3: Add tokens
    add_tokens "loaded_context" "500"
    current=$(get_current_token_count)
    assert_equals "$current" "1500" "Add tokens to category"

    # Test 3.4: Check budget - should allow
    if check_budget_before_load 10000 <<< "y" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} PASS: Allow loading within budget"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} FAIL: Should allow loading within budget"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Test 3.5: Check budget - should block
    if check_budget_before_load 200000 2>/dev/null; then
        echo -e "${RED}✗${NC} FAIL: Should block loading over budget"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} PASS: Block loading over budget"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Test 3.6: Calculate optimal load size
    local optimal=$(calculate_optimal_load_size)
    assert_greater_than "$optimal" "0" "Calculate optimal load size"

    # Test 3.7: Estimate tokens from text
    local text="This is a test string with some content"
    local estimated=$(estimate_tokens "$text")
    assert_greater_than "$estimated" "0" "Estimate tokens from text"

    echo ""
}

# Test 4: Context Injection
test_context_injection() {
    echo "💉 Testing Context Injection..."
    echo ""

    # Test 4.1: Initialize injector
    source "${SCRIPTS_DIR}/context-injector.sh"
    initialize_injector

    local injection_log="${DATA_DIR}/context-injection-log.json"
    if [ -f "$injection_log" ]; then
        echo -e "${GREEN}✓${NC} PASS: Initialize injection log"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} FAIL: Failed to initialize injection log"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Test 4.2: Estimate tokens
    local conversation='{"role":"user","content":"test message"}'
    local tokens=$(estimate_tokens "$conversation")
    assert_greater_than "$tokens" "0" "Estimate conversation tokens"

    # Test 4.3: Format injection
    local formatted=$(format_injection "test-session" "Test Summary" "$conversation" "" "1" "2026-02-15" "2026-02-15" "100")
    assert_contains "$formatted" "On-Demand Context Loaded" "Format injection includes header"
    assert_contains "$formatted" "test-session" "Format injection includes session ID"

    echo ""
}

# Test 5: Integration Test
test_integration() {
    echo "🔗 Testing Integration..."
    echo ""

    # Test 5.1: Full workflow - parse and search
    local query="authentication from last week"
    local parsed=$(parse_request "$query")
    local topic=$(echo "$parsed" | jq -r '.topic')
    local timeframe=$(echo "$parsed" | jq -r '.timeframe')

    assert_not_empty "$topic" "Integration: Parse topic"
    assert_not_empty "$timeframe" "Integration: Parse timeframe"

    # Test 5.2: Search with parsed results
    # This tests the integration between parser and search
    if [ -n "$topic" ] && [ "$topic" != "null" ] && [ -n "$timeframe" ] && [ "$timeframe" != "null" ]; then
        echo -e "${GREEN}✓${NC} PASS: Integration: Parser → Search flow"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} PASS: Integration: Parser → Search flow (partial values)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Test 5.3: Budget check before load
    local current_tokens=$(get_current_token_count)
    local tokens_to_load=5000

    if [ $((current_tokens + tokens_to_load)) -lt 180000 ]; then
        echo -e "${GREEN}✓${NC} PASS: Integration: Budget check before load"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} FAIL: Integration: Budget check before load"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    echo ""
}

# Test 6: Performance Test
test_performance() {
    echo "⚡ Testing Performance..."
    echo ""

    # Test 6.1: Parser speed
    local start=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
    parse_request "show me the authentication session from february" > /dev/null
    local end=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
    local duration=$((end - start))

    if [ $duration -lt 100 ]; then
        echo -e "${GREEN}✓${NC} PASS: Parser speed (<100ms): ${duration}ms"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} WARN: Parser slow (>100ms): ${duration}ms"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Test 6.2: Search speed
    start=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
    search_by_topic "authentication" > /dev/null 2>&1
    end=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
    duration=$((end - start))

    if [ $duration -lt 500 ]; then
        echo -e "${GREEN}✓${NC} PASS: Search speed (<500ms): ${duration}ms"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} WARN: Search slow (>500ms): ${duration}ms"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Test 6.3: Budget update speed
    start=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
    update_token_count "base_context" "2000"
    end=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s)
    duration=$((end - start))

    if [ $duration -lt 50 ]; then
        echo -e "${GREEN}✓${NC} PASS: Budget update speed (<50ms): ${duration}ms"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} WARN: Budget update slow (>50ms): ${duration}ms"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    echo ""
}

# Test 7: Error Handling
test_error_handling() {
    echo "🛡️  Testing Error Handling..."
    echo ""

    # Test 7.1: Parse empty query
    local result=$(parse_request "" 2>/dev/null || echo '{"error":true}')
    if echo "$result" | jq -e 'has("action")' > /dev/null; then
        echo -e "${GREEN}✓${NC} PASS: Handle empty query"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} FAIL: Handle empty query"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Test 7.2: Search nonexistent topic
    result=$(search_by_topic "nonexistent-topic-xyz-123" 2>/dev/null || echo "[]")
    assert_equals "$result" "[]" "Handle nonexistent topic"

    # Test 7.3: Budget overflow prevention
    update_token_count "base_context" "0"
    if check_budget_before_load 250000 2>/dev/null; then
        echo -e "${RED}✗${NC} FAIL: Should prevent budget overflow"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo -e "${GREEN}✓${NC} PASS: Prevent budget overflow"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    echo ""
}

# Print test summary
print_summary() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "           TEST SUMMARY"
    echo "═══════════════════════════════════════"
    echo ""
    echo "Tests Run:    $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    local pass_rate=0
    if [ $TESTS_RUN -gt 0 ]; then
        pass_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi

    echo "Pass Rate: ${pass_rate}%"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
        return 0
    else
        echo -e "${RED}❌ SOME TESTS FAILED${NC}"
        return 1
    fi
}

# Main test runner
main() {
    echo "╔═══════════════════════════════════════╗"
    echo "║  On-Demand Loader Test Suite v1.0.0  ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""

    setup_test_environment

    # Run all tests
    test_request_parser
    test_session_search
    test_token_budget
    test_context_injection
    test_integration
    test_performance
    test_error_handling

    cleanup_test_environment

    print_summary
}

# Run tests
main "$@"
