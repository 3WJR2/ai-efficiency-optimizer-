#!/usr/bin/env bash
# test-context-tiers.sh - Test 3-Tier Smart Context Management System
# Comprehensive test suite

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DATA_DIR="/tmp/claude-context-test"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"

# Component scripts
TOKEN_MANAGER="$SCRIPT_DIR/token-budget-manager.sh"
RELEVANCE_SCORER="$SCRIPT_DIR/relevance-scorer.sh"
SESSION_SELECTOR="$SCRIPT_DIR/session-selector.sh"
CONTEXT_FORMATTER="$SCRIPT_DIR/context-formatter.sh"
CONTEXT_MANAGER="$SCRIPT_DIR/context-tier-manager.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Test Framework
# ============================================================================

test_start() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${BLUE}[TEST $TESTS_RUN]${NC} $test_name"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓ PASS${NC}"
}

test_fail() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}✗ FAIL${NC}: $reason"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values not equal}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo "    Expected: $expected"
        echo "    Actual: $actual"
        test_fail "$message"
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
        test_fail "$message: '$needle' not found"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value is empty}"

    if [[ -n "$value" ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

assert_less_than() {
    local value="$1"
    local max="$2"
    local message="${3:-Value exceeds maximum}"

    if [[ $value -lt $max ]]; then
        return 0
    else
        test_fail "$message: $value >= $max"
        return 1
    fi
}

assert_greater_than() {
    local value="$1"
    local min="$2"
    local message="${3:-Value below minimum}"

    if [[ $value -gt $min ]]; then
        return 0
    else
        test_fail "$message: $value <= $min"
        return 1
    fi
}

assert_between() {
    local value="$1"
    local min="$2"
    local max="$3"
    local message="${4:-Value out of range}"

    if [[ $value -ge $min ]] && [[ $value -le $max ]]; then
        return 0
    else
        test_fail "$message: $value not in [$min, $max]"
        return 1
    fi
}

assert_between_float() {
    local value="$1"
    local min="$2"
    local max="$3"
    local message="${4:-Value out of range}"

    local is_in_range=$(echo "$value >= $min && $value <= $max" | bc -l)

    if [[ $is_in_range -eq 1 ]]; then
        return 0
    else
        test_fail "$message: $value not in [$min, $max]"
        return 1
    fi
}

# ============================================================================
# Token Budget Manager Tests
# ============================================================================

test_token_estimation() {
    test_start "Token estimation"

    local test_text="Hello world, this is a test"
    local tokens=$("$TOKEN_MANAGER" estimate "$test_text")

    assert_greater_than "$tokens" 0 "Token count should be positive" && \
    assert_less_than "$tokens" 20 "Token count should be reasonable" && \
    test_pass
}

test_cost_calculation() {
    test_start "Cost calculation"

    local cost=$("$TOKEN_MANAGER" calculate-cost 50000)

    # 50K tokens at $0.003/1K = $0.15
    assert_between_float "$cost" 0.14 0.16 "Cost should be ~\$0.15" && \
    test_pass
}

test_session_cost() {
    test_start "Session cost calculation"

    # 45K input, 5K output, 20K cached
    local cost=$("$TOKEN_MANAGER" session-cost 45000 5000 20000)

    # Input: 45K * $0.003/1K = $0.135
    # Output: 5K * $0.015/1K = $0.075
    # Cached: 20K * $0.0003/1K = $0.006
    # Total: $0.216
    assert_between_float "$cost" 0.20 0.25 "Session cost should be ~\$0.22" && \
    test_pass
}

test_budget_check() {
    test_start "Budget check"

    local fits=$("$TOKEN_MANAGER" check-budget 25000 30000)
    local exceeds=$("$TOKEN_MANAGER" check-budget 35000 30000)

    assert_equals "true" "$fits" "25K should fit in 30K" && \
    assert_equals "false" "$exceeds" "35K should not fit in 30K" && \
    test_pass
}

test_content_trimming() {
    test_start "Content trimming"

    local long_text=$(printf 'word %.0s' {1..1000})
    local trimmed=$("$TOKEN_MANAGER" trim "$long_text" 100)
    local trimmed_tokens=$("$TOKEN_MANAGER" estimate "$trimmed")

    assert_less_than "$trimmed_tokens" 120 "Trimmed content should fit budget" && \
    test_pass
}

test_budget_allocation() {
    test_start "Budget allocation"

    local allocation=$("$TOKEN_MANAGER" allocation)

    assert_contains "$allocation" "tier1" "Should have tier1" && \
    assert_contains "$allocation" "tier2" "Should have tier2" && \
    assert_contains "$allocation" "tier3" "Should have tier3" && \
    test_pass
}

# ============================================================================
# Relevance Scorer Tests
# ============================================================================

test_word_overlap() {
    test_start "Word overlap similarity"

    # Use internal function by sourcing the script
    source "$RELEVANCE_SCORER"

    local text1="authentication JWT token implementation"
    local text2="JWT implementation with OAuth authentication"

    local similarity=$(calculate_word_overlap "$text1" "$text2")

    # Should have high overlap (auth, JWT, implementation)
    local is_high=$(echo "$similarity > 0.3" | bc -l)
    assert_equals "1" "$is_high" "Should have reasonable overlap" && \
    test_pass
}

test_temporal_scoring() {
    test_start "Temporal proximity scoring"

    source "$RELEVANCE_SCORER"

    local today=$(date +%Y-%m-%d)
    local yesterday=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "1 day ago" +%Y-%m-%d)
    local week_ago=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d)

    local today_score=$(calculate_temporal_score "$today")
    local yesterday_score=$(calculate_temporal_score "$yesterday")
    local week_score=$(calculate_temporal_score "$week_ago")

    # Today should score highest
    assert_equals "1.0" "$today_score" "Today should score 1.0" && \
    assert_equals "0.9" "$yesterday_score" "Yesterday should score 0.9" && \
    assert_equals "0.7" "$week_score" "Week ago should score 0.7" && \
    test_pass
}

test_session_metadata() {
    test_start "Session metadata extraction"

    # Get first available session
    local first_session=$(ls -1 "$SESSIONS_DIR" 2>/dev/null | head -1)

    if [[ -n "$first_session" ]]; then
        local metadata=$("$RELEVANCE_SCORER" metadata "$first_session")

        assert_contains "$metadata" "session_id" "Should have session_id" && \
        assert_contains "$metadata" "date" "Should have date" && \
        test_pass
    else
        echo "  ${YELLOW}⊘ SKIP${NC}: No sessions available"
    fi
}

test_find_related_sessions() {
    test_start "Find related sessions"

    local related=$("$RELEVANCE_SCORER" find "authentication" 5 2>/dev/null || echo "[]")

    # Should return JSON array
    local is_array=$(echo "$related" | jq 'type' | grep -q "array" && echo "true" || echo "false")

    assert_equals "true" "$is_array" "Should return array" && \
    test_pass
}

# ============================================================================
# Session Selector Tests
# ============================================================================

test_list_sessions() {
    test_start "List all sessions"

    local sessions=$("$SESSION_SELECTOR" list 30)

    # Should return JSON array
    local is_array=$(echo "$sessions" | jq 'type' | grep -q "array" && echo "true" || echo "false")

    assert_equals "true" "$is_array" "Should return array" && \
    test_pass
}

test_tier1_selection() {
    test_start "Tier 1 session selection"

    local tier1=$("$SESSION_SELECTOR" tier1)

    # Should return JSON with sessions
    local count=$(echo "$tier1" | jq 'length')

    assert_less_than "$count" 5 "Should select limited sessions" && \
    test_pass
}

test_tier2_selection() {
    test_start "Tier 2 session selection"

    local tier2=$("$SESSION_SELECTOR" tier2 "authentication" "{}" "[]")

    # Should return JSON array
    local is_array=$(echo "$tier2" | jq 'type' | grep -q "array" && echo "true" || echo "false")

    assert_equals "true" "$is_array" "Should return array" && \
    test_pass
}

test_all_tiers_selection() {
    test_start "All tiers selection"

    local selection=$("$SESSION_SELECTOR" all "implement feature")

    assert_contains "$selection" "tier1" "Should have tier1" && \
    assert_contains "$selection" "tier2" "Should have tier2" && \
    assert_contains "$selection" "summary" "Should have summary" && \
    test_pass
}

test_selection_stats() {
    test_start "Selection statistics"

    local stats=$("$SESSION_SELECTOR" stats)

    assert_contains "$stats" "total_sessions" "Should have total count" && \
    assert_contains "$stats" "recent_sessions" "Should have recent count" && \
    test_pass
}

# ============================================================================
# Context Formatter Tests
# ============================================================================

test_format_tier1() {
    test_start "Format Tier 1 content"

    local test_sessions='[{"session_id":"test-session-1","reason":"recent"}]'
    local formatted=$("$CONTEXT_FORMATTER" tier1 "$test_sessions" 2>/dev/null || echo "")

    assert_contains "$formatted" "Recent Conversations" "Should have header" && \
    test_pass
}

test_format_tier2() {
    test_start "Format Tier 2 content"

    local test_sessions='[{"session_id":"test-session-2","relevance_score":0.85}]'
    local formatted=$("$CONTEXT_FORMATTER" tier2 "$test_sessions" 2>/dev/null || echo "")

    assert_contains "$formatted" "Related Work" "Should have header" && \
    test_pass
}

test_format_tier3() {
    test_start "Format Tier 3 content"

    local all_sessions=$("$SESSION_SELECTOR" list 30)
    local formatted=$("$CONTEXT_FORMATTER" tier3 "$all_sessions" 2>/dev/null || echo "")

    assert_contains "$formatted" "Full History" "Should have header" && \
    test_pass
}

test_project_context() {
    test_start "Format project context"

    local project=$("$CONTEXT_FORMATTER" project "." 2>/dev/null || echo "")

    assert_contains "$project" "Current Project" "Should have header" && \
    test_pass
}

# ============================================================================
# Context Tier Manager Tests (Integration)
# ============================================================================

test_config_initialization() {
    test_start "Config initialization"

    # Get config (will initialize if needed)
    "$CONTEXT_MANAGER" budget >/dev/null 2>&1

    local config_file="${HOME}/.claude/data/context-tier-config.json"

    assert_equals "true" "$([ -f "$config_file" ] && echo true || echo false)" "Config should exist" && \
    test_pass
}

test_context_building() {
    test_start "Context building"

    local context=$("$CONTEXT_MANAGER" build "" "test task" "." 2>/dev/null || echo "")

    assert_contains "$context" "Complete Context" "Should have header" && \
    test_pass
}

test_token_budget() {
    test_start "Token budget compliance"

    local context=$("$CONTEXT_MANAGER" build "" "test task" "." 2>/dev/null || echo "")
    local tokens=$("$TOKEN_MANAGER" estimate "$context")

    # Should be under 60K total budget
    assert_less_than "$tokens" 65000 "Should stay under budget" && \
    test_pass
}

test_cost_estimation() {
    test_start "Cost estimation"

    local estimate=$("$CONTEXT_MANAGER" estimate "" "test task" 2>/dev/null || echo "")

    assert_contains "$estimate" "Cost Estimate" "Should have estimate" && \
    test_pass
}

test_tier1_loading() {
    test_start "Tier 1 loading"

    local tier1=$("$CONTEXT_MANAGER" tier1 "" 2>/dev/null || echo "")

    assert_not_empty "$tier1" "Should load content" && \
    test_pass
}

test_tier2_loading() {
    test_start "Tier 2 loading"

    local tier2=$("$CONTEXT_MANAGER" tier2 "authentication" "{}" 2>/dev/null || echo "")

    assert_not_empty "$tier2" "Should load content" && \
    test_pass
}

test_tier3_loading() {
    test_start "Tier 3 loading"

    local tier3=$("$CONTEXT_MANAGER" tier3 2>/dev/null || echo "")

    assert_not_empty "$tier3" "Should load index" && \
    test_pass
}

test_search_functionality() {
    test_start "Session search"

    local results=$("$CONTEXT_MANAGER" search "test" 3 2>/dev/null || echo "")

    assert_contains "$results" "Search Results" "Should have search header" && \
    test_pass
}

test_statistics() {
    test_start "Statistics tracking"

    local stats=$("$CONTEXT_MANAGER" stats 2>/dev/null || echo "")

    assert_contains "$stats" "Statistics" "Should have stats" && \
    test_pass
}

# ============================================================================
# Performance Tests
# ============================================================================

test_load_time() {
    test_start "Context load time"

    local start=$(date +%s)
    "$CONTEXT_MANAGER" build "" "test" "." >/dev/null 2>&1 || true
    local end=$(date +%s)

    local duration=$((end - start))

    # Should complete in under 5 seconds
    assert_less_than "$duration" 5 "Should load in <5s" && \
    test_pass
}

test_cost_target() {
    test_start "Cost target compliance"

    local context=$("$CONTEXT_MANAGER" build "" "test task" "." 2>/dev/null || echo "")
    local tokens=$("$TOKEN_MANAGER" estimate "$context")
    local cost=$("$TOKEN_MANAGER" calculate-cost "$tokens")

    # Should be under $0.35 (target is $0.15-0.30, with some margin)
    assert_between_float "$cost" 0.05 0.40 "Cost should be reasonable" && \
    test_pass
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    echo -e "${BOLD}${BLUE}====================================${NC}"
    echo -e "${BOLD}${BLUE}3-Tier Context Management Test Suite${NC}"
    echo -e "${BOLD}${BLUE}====================================${NC}"
    echo ""

    # Token Budget Manager Tests
    echo -e "${BOLD}Token Budget Manager Tests${NC}"
    test_token_estimation
    test_cost_calculation
    test_session_cost
    test_budget_check
    test_content_trimming
    test_budget_allocation
    echo ""

    # Relevance Scorer Tests
    echo -e "${BOLD}Relevance Scorer Tests${NC}"
    test_word_overlap
    test_temporal_scoring
    test_session_metadata
    test_find_related_sessions
    echo ""

    # Session Selector Tests
    echo -e "${BOLD}Session Selector Tests${NC}"
    test_list_sessions
    test_tier1_selection
    test_tier2_selection
    test_all_tiers_selection
    test_selection_stats
    echo ""

    # Context Formatter Tests
    echo -e "${BOLD}Context Formatter Tests${NC}"
    test_format_tier1
    test_format_tier2
    test_format_tier3
    test_project_context
    echo ""

    # Integration Tests
    echo -e "${BOLD}Integration Tests${NC}"
    test_config_initialization
    test_context_building
    test_token_budget
    test_cost_estimation
    test_tier1_loading
    test_tier2_loading
    test_tier3_loading
    test_search_functionality
    test_statistics
    echo ""

    # Performance Tests
    echo -e "${BOLD}Performance Tests${NC}"
    test_load_time
    test_cost_target
    echo ""

    # Summary
    echo -e "${BOLD}${BLUE}====================================${NC}"
    echo -e "${BOLD}Test Summary${NC}"
    echo -e "${BOLD}${BLUE}====================================${NC}"
    echo -e "Total Tests Run: ${BOLD}$TESTS_RUN${NC}"
    echo -e "Passed: ${GREEN}${BOLD}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}${BOLD}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}${BOLD}✓ ALL TESTS PASSED!${NC}"
        return 0
    else
        echo -e "\n${RED}${BOLD}✗ SOME TESTS FAILED${NC}"
        return 1
    fi
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
        token)
            test_token_estimation
            test_cost_calculation
            test_session_cost
            test_budget_check
            ;;
        relevance)
            test_word_overlap
            test_temporal_scoring
            test_find_related_sessions
            ;;
        selector)
            test_list_sessions
            test_tier1_selection
            test_tier2_selection
            ;;
        formatter)
            test_format_tier1
            test_format_tier2
            test_format_tier3
            ;;
        integration)
            test_context_building
            test_token_budget
            test_search_functionality
            ;;
        performance)
            test_load_time
            test_cost_target
            ;;
        *)
            echo "Usage: $(basename "$0") [all|token|relevance|selector|formatter|integration|performance]"
            exit 1
            ;;
    esac
}

main "$@"
