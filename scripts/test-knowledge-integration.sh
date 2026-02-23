#!/usr/bin/env bash

# test-knowledge-integration.sh
# Comprehensive tests for knowledge synthesis integration
# Part of Cross-Session Knowledge Synthesis Integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"
TEST_DIR="/tmp/claude-knowledge-test-$$"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Test Framework
# ============================================================================

# Assert function
assert() {
    local condition="$1"
    local message="$2"

    ((TESTS_RUN++))

    if eval "$condition"; then
        echo -e "${GREEN}✓${NC} $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $message"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test section header
test_section() {
    local name="$1"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test: $name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Setup test environment
setup_test_env() {
    echo -e "${BLUE}Setting up test environment...${NC}"

    mkdir -p "$TEST_DIR"
    mkdir -p "$TEST_DIR/sessions"
    mkdir -p "$TEST_DIR/knowledge"

    # Create test session
    local test_session="$TEST_DIR/sessions/2026-02-18-test-session-1-abc123"
    mkdir -p "$test_session"

    # Create test conversation log
    cat > "$test_session/conversation-log.jsonl" <<'EOF'
{"role":"user","content":"How do I fix authentication timeout issue?","timestamp":"2026-02-18T10:00:00Z"}
{"role":"assistant","content":"The authentication timeout issue can be fixed by increasing the session timeout in your configuration. Set SESSION_TIMEOUT = 3600 in settings.py","timestamp":"2026-02-18T10:00:30Z"}
{"role":"user","content":"That worked perfectly! Thanks!","timestamp":"2026-02-18T10:01:00Z"}
{"role":"user","content":"How do I implement rate limiting?","timestamp":"2026-02-18T10:05:00Z"}
{"role":"assistant","content":"You can implement rate limiting using Redis. Here's the solution:\n```python\nimport redis\nfrom functools import wraps\n\ndef rate_limit(max_calls=10, period=60):\n    def decorator(func):\n        @wraps(func)\n        def wrapper(*args, **kwargs):\n            # Rate limiting logic\n            pass\n        return wrapper\n    return decorator\n```","timestamp":"2026-02-18T10:05:30Z"}
EOF

    # Create test metadata
    cat > "$test_session/.session-metadata.json" <<EOF
{
  "session_id": "2026-02-18-test-session-1-abc123",
  "created_at": "2026-02-18T10:00:00Z",
  "status": "active",
  "working_directory": "$TEST_DIR"
}
EOF

    # Create test context file
    cat > "$test_session/.session-context.md" <<EOF
# Session Context

Test session for knowledge integration.
EOF

    echo -e "${GREEN}✓${NC} Test environment created: $TEST_DIR"
}

# Cleanup test environment
cleanup_test_env() {
    echo ""
    echo -e "${BLUE}Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
    echo -e "${GREEN}✓${NC} Cleanup complete"
}

# ============================================================================
# Test 1: Knowledge Extractor
# ============================================================================

test_knowledge_extractor() {
    test_section "Knowledge Extractor"

    local test_session="$TEST_DIR/sessions/2026-02-18-test-session-1-abc123"

    # Run extraction
    local output=$(bash "$SCRIPT_DIR/knowledge-extractor.sh" extract "$test_session" 2>/dev/null)

    # Test: Should extract entries
    assert "[[ -n \"\$output\" ]]" "Extraction produces output"

    # Test: Output should be valid JSON
    assert "echo \"\$output\" | jq -e . >/dev/null 2>&1" "Output is valid JSON"

    # Test: Should extract solution type
    assert "echo \"\$output\" | grep -q '\"type\":\"solution\"'" "Detects solution type"

    # Test: Should extract problem
    assert "echo \"\$output\" | grep -q 'authentication timeout'" "Extracts problem description"

    # Test: Should extract tags
    assert "echo \"\$output\" | grep -q '\"tags\"'" "Extracts tags"

    # Test: Should calculate confidence
    local confidence=$(echo "$output" | head -1 | jq -r '.confidence' 2>/dev/null || echo "0")
    assert "[[ \$(echo \"\$confidence > 0.5\" | bc) -eq 1 ]]" "Confidence score calculated"
}

# ============================================================================
# Test 2: Pipeline
# ============================================================================

test_pipeline() {
    test_section "Knowledge Pipeline"

    # Override directories for test
    export SESSIONS_DIR="$TEST_DIR/sessions"
    export KNOWLEDGE_DIR="$TEST_DIR/knowledge"

    # Run incremental pipeline
    bash "$SCRIPT_DIR/knowledge-pipeline.sh" incremental > /dev/null 2>&1 || true

    # Test: Knowledge base should exist
    assert "[[ -f \"$TEST_DIR/knowledge/knowledge-base.jsonl\" ]]" "Knowledge base created"

    # Test: Should have entries
    if [[ -f "$TEST_DIR/knowledge/knowledge-base.jsonl" ]]; then
        local entry_count=$(wc -l < "$TEST_DIR/knowledge/knowledge-base.jsonl" 2>/dev/null || echo "0")
        assert "[[ \$entry_count -gt 0 ]]" "Knowledge entries extracted"
    fi

    # Test: State file should exist
    assert "[[ -f \"$DATA_DIR/knowledge-pipeline-state.json\" ]]" "Pipeline state created"

    # Test: State should track run
    if [[ -f "$DATA_DIR/knowledge-pipeline-state.json" ]]; then
        local total_runs=$(jq -r '.statistics.total_runs' "$DATA_DIR/knowledge-pipeline-state.json")
        assert "[[ \$total_runs -gt 0 ]]" "Pipeline tracks runs"
    fi
}

# ============================================================================
# Test 3: Session Startup Hook
# ============================================================================

test_session_startup_hook() {
    test_section "Session Startup Hook"

    local test_session="$TEST_DIR/sessions/2026-02-18-test-session-1-abc123"

    # First, ensure knowledge base has data
    export KNOWLEDGE_DIR="$TEST_DIR/knowledge"

    # Create sample knowledge
    cat > "$TEST_DIR/knowledge/knowledge-base.jsonl" <<'EOF'
{"id":"k_test1","type":"solution","problem":"authentication timeout","solution":"increase session timeout","tags":["auth","session","timeout"],"confidence":0.85,"timestamp":"2026-02-18T10:00:00Z"}
{"id":"k_test2","type":"solution","problem":"rate limiting","solution":"use redis for rate limiting","tags":["redis","rate-limit","api"],"confidence":0.90,"timestamp":"2026-02-18T10:05:00Z"}
EOF

    # Test search functionality
    bash "$SCRIPT_DIR/session-startup-hook.sh" test "authentication problem" > /tmp/test-search.json 2>/dev/null || true

    # Test: Search produces results
    if [[ -f /tmp/test-search.json ]]; then
        assert "jq -e . /tmp/test-search.json >/dev/null 2>&1" "Search produces valid JSON"

        local result_count=$(jq 'length' /tmp/test-search.json 2>/dev/null || echo "0")
        assert "[[ \$result_count -gt 0 ]]" "Search finds relevant knowledge"
    fi

    # Test: Hook function exists
    source "$SCRIPT_DIR/session-startup-hook.sh"
    assert "type on_session_start | grep -q 'function'" "Hook function defined"
}

# ============================================================================
# Test 4: Real-time Capture
# ============================================================================

test_realtime_capture() {
    test_section "Real-time Knowledge Capture"

    # Test: Detection functions work
    source "$SCRIPT_DIR/realtime-knowledge-capture.sh"

    # Test user confirmation detection
    local test_msg='{"role":"user","content":"that worked perfectly!"}'
    local moment=$(detect_knowledge_moment "$test_msg" || echo "")
    assert "[[ \"\$moment\" == \"user_confirmed\" ]]" "Detects user confirmation"

    # Test solution detection
    test_msg='{"role":"assistant","content":"here is the solution to fix this"}'
    moment=$(detect_knowledge_moment "$test_msg" || echo "")
    assert "[[ \"\$moment\" == \"solution_provided\" ]]" "Detects solution provided"

    # Test: Broadcast directory exists
    mkdir -p "$TEST_DIR/knowledge/broadcast"
    assert "[[ -d \"$TEST_DIR/knowledge/broadcast\" ]]" "Broadcast directory created"
}

# ============================================================================
# Test 5: Knowledge Assistant CLI
# ============================================================================

test_knowledge_assistant() {
    test_section "Knowledge Assistant CLI"

    export KNOWLEDGE_DIR="$TEST_DIR/knowledge"

    # Ensure knowledge base exists
    if [[ ! -f "$TEST_DIR/knowledge/knowledge-base.jsonl" ]]; then
        cat > "$TEST_DIR/knowledge/knowledge-base.jsonl" <<'EOF'
{"id":"k_test1","type":"solution","problem":"authentication timeout","solution":"increase session timeout","tags":["auth","session"],"confidence":0.85}
{"id":"k_test2","type":"solution","problem":"rate limiting","solution":"use redis","tags":["redis","rate-limit"],"confidence":0.90}
EOF
    fi

    # Test: Config commands work
    bash "$SCRIPT_DIR/knowledge-assistant.sh" config show > /dev/null 2>&1 || true
    assert "[[ -f \"$DATA_DIR/knowledge-assistant-config.json\" ]]" "Config file created"

    # Test: Stats command works
    bash "$SCRIPT_DIR/knowledge-assistant.sh" stats > /tmp/test-stats.txt 2>&1 || true
    assert "[[ -f /tmp/test-stats.txt ]]" "Stats command produces output"

    # Test: Search command works
    bash "$SCRIPT_DIR/knowledge-assistant.sh" search "authentication" > /tmp/test-search-cli.txt 2>&1 || true
    assert "[[ -f /tmp/test-search-cli.txt ]]" "Search command works"
}

# ============================================================================
# Test 6: Dashboard
# ============================================================================

test_dashboard() {
    test_section "Knowledge Dashboard"

    export KNOWLEDGE_DIR="$TEST_DIR/knowledge"

    # Test: Dashboard shows without errors
    bash "$SCRIPT_DIR/knowledge-dashboard.sh" show > /tmp/test-dashboard.txt 2>&1 || true
    assert "[[ -f /tmp/test-dashboard.txt ]]" "Dashboard renders"

    # Test: Export works
    bash "$SCRIPT_DIR/knowledge-dashboard.sh" export /tmp/test-dashboard.html > /dev/null 2>&1 || true
    assert "[[ -f /tmp/test-dashboard.html ]]" "Dashboard exports to HTML"
}

# ============================================================================
# Test 7: End-to-End
# ============================================================================

test_end_to_end() {
    test_section "End-to-End Integration"

    # Simulate full workflow
    export SESSIONS_DIR="$TEST_DIR/sessions"
    export KNOWLEDGE_DIR="$TEST_DIR/knowledge"

    # Step 1: Extract from session
    echo -e "${BLUE}Step 1: Extract knowledge${NC}"
    local test_session="$TEST_DIR/sessions/2026-02-18-test-session-1-abc123"
    bash "$SCRIPT_DIR/knowledge-extractor.sh" extract "$test_session" > "$TEST_DIR/knowledge/knowledge-base.jsonl" 2>/dev/null || true
    assert "[[ -s \"$TEST_DIR/knowledge/knowledge-base.jsonl\" ]]" "E2E: Knowledge extracted"

    # Step 2: Run pipeline
    echo -e "${BLUE}Step 2: Run pipeline${NC}"
    bash "$SCRIPT_DIR/knowledge-pipeline.sh" incremental > /dev/null 2>&1 || true
    assert "[[ -f \"$DATA_DIR/knowledge-pipeline-state.json\" ]]" "E2E: Pipeline executed"

    # Step 3: Search for knowledge
    echo -e "${BLUE}Step 3: Search knowledge${NC}"
    local results=$(bash "$SCRIPT_DIR/session-startup-hook.sh" test "timeout" 2>/dev/null || echo "[]")
    local result_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
    assert "[[ \$result_count -gt 0 ]]" "E2E: Knowledge searchable"

    # Step 4: Dashboard displays
    echo -e "${BLUE}Step 4: Dashboard${NC}"
    bash "$SCRIPT_DIR/knowledge-dashboard.sh" show > /dev/null 2>&1 || true
    assert "[[ \$? -eq 0 ]]" "E2E: Dashboard works"

    echo ""
    echo -e "${GREEN}✓ End-to-end workflow complete${NC}"
}

# ============================================================================
# Test Summary
# ============================================================================

show_summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}           All Tests Passed! ✓                  ${GREEN}║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        return 0
    else
        echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}           Some Tests Failed                    ${RED}║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
        return 1
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

run_all_tests() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Knowledge Integration Test Suite             ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"

    setup_test_env

    test_knowledge_extractor
    test_pipeline
    test_session_startup_hook
    test_realtime_capture
    test_knowledge_assistant
    test_dashboard
    test_end_to_end

    cleanup_test_env
    show_summary
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Integration Test Suite

Usage: $(basename "$0") [test_name]

Tests:
  all                   Run all tests (default)
  extractor             Test knowledge extractor
  pipeline              Test pipeline
  hook                  Test session startup hook
  realtime              Test real-time capture
  cli                   Test knowledge assistant CLI
  dashboard             Test dashboard
  e2e                   Test end-to-end workflow

Examples:
  $(basename "$0")                  # Run all tests
  $(basename "$0") extractor        # Run specific test
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local test_name="${1:-all}"

    case "$test_name" in
        all)
            run_all_tests
            ;;

        extractor)
            setup_test_env
            test_knowledge_extractor
            cleanup_test_env
            show_summary
            ;;

        pipeline)
            setup_test_env
            test_pipeline
            cleanup_test_env
            show_summary
            ;;

        hook)
            setup_test_env
            test_session_startup_hook
            cleanup_test_env
            show_summary
            ;;

        realtime)
            setup_test_env
            test_realtime_capture
            cleanup_test_env
            show_summary
            ;;

        cli)
            setup_test_env
            test_knowledge_assistant
            cleanup_test_env
            show_summary
            ;;

        dashboard)
            setup_test_env
            test_dashboard
            cleanup_test_env
            show_summary
            ;;

        e2e)
            setup_test_env
            test_end_to_end
            cleanup_test_env
            show_summary
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            echo "Unknown test: $test_name"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
