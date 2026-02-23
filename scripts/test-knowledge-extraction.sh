#!/usr/bin/env bash

# test-knowledge-extraction.sh
# Comprehensive tests for knowledge extraction system
# Part of Cross-Session Knowledge Extraction System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
TEST_DIR="${KNOWLEDGE_DIR}/test"

# Scripts to test
EXTRACTOR="${SCRIPT_DIR}/knowledge-extractor.sh"
CATEGORIZER="${SCRIPT_DIR}/knowledge-categorizer.sh"
INDEXER="${SCRIPT_DIR}/knowledge-indexer.sh"
SEARCH="${SCRIPT_DIR}/knowledge-search.sh"
SCORER="${SCRIPT_DIR}/knowledge-quality-scorer.sh"
BATCH="${SCRIPT_DIR}/batch-extract-knowledge.sh"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "ERROR: $*"
}

# Setup test environment
setup_test_env() {
    log "Setting up test environment"
    mkdir -p "$TEST_DIR"

    # Create test session directory
    TEST_SESSION_DIR="${TEST_DIR}/test-session-$(date +%s)"
    mkdir -p "$TEST_SESSION_DIR"

    # Create test conversation log
    create_test_conversation_log
}

# Cleanup test environment
cleanup_test_env() {
    log "Cleaning up test environment"
    rm -rf "$TEST_DIR"
}

# Create sample conversation log
create_test_conversation_log() {
    cat > "${TEST_SESSION_DIR}/conversation-log.jsonl" <<'EOF'
{"timestamp":"2026-02-17T20:00:00Z","role":"user","content":"How do I fix IndexError in Python?"}
{"timestamp":"2026-02-17T20:00:01Z","role":"assistant","content":"An IndexError occurs when you try to access an index that doesn't exist in a list. Here's the fix:\n```python\ndata = [1, 2, 3]\nif len(data) > 5:\n    print(data[5])\nelse:\n    print('Index out of range')\n```\nThis checks the length before accessing."}
{"timestamp":"2026-02-17T20:00:02Z","role":"user","content":"Perfect! That fixed it. Thanks!"}
{"timestamp":"2026-02-17T20:01:00Z","role":"user","content":"What's the best practice for error handling?"}
{"timestamp":"2026-02-17T20:01:01Z","role":"assistant","content":"The typical approach for error handling in Python is to use try-except blocks. Here's the pattern:\n```python\ntry:\n    risky_operation()\nexcept SpecificError as e:\n    handle_error(e)\nfinally:\n    cleanup()\n```\nAlways catch specific exceptions rather than using bare except."}
{"timestamp":"2026-02-17T20:01:02Z","role":"user","content":"Great explanation!"}
{"timestamp":"2026-02-17T20:02:00Z","role":"user","content":"Help me debug this TypeError"}
{"timestamp":"2026-02-17T20:02:01Z","role":"assistant","content":"TypeError usually means you're using an operation on incompatible types. Can you share the error message?"}
{"timestamp":"2026-02-17T20:02:02Z","role":"user","content":"'int' object is not subscriptable"}
{"timestamp":"2026-02-17T20:02:03Z","role":"assistant","content":"This error means you're trying to use [] on an integer. The fix is to ensure you're working with a list or string:\n```python\n# Wrong\nnum = 5\nprint(num[0])  # TypeError\n\n# Right\nnum_str = str(5)\nprint(num_str[0])  # '5'\n```"}
{"timestamp":"2026-02-17T20:02:04Z","role":"user","content":"That solved it!"}
EOF

    log "Created test conversation log: ${TEST_SESSION_DIR}/conversation-log.jsonl"
}

# Assert function
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        log "✓ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        error "✗ FAIL: $test_name"
        error "  Expected: $expected"
        error "  Actual: $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local test_name="$2"

    if [[ -f "$filepath" ]]; then
        log "✓ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        error "✗ FAIL: $test_name"
        error "  File not found: $filepath"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_greater_than() {
    local value="$1"
    local threshold="$2"
    local test_name="$3"

    if [[ $value -gt $threshold ]]; then
        log "✓ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        error "✗ FAIL: $test_name"
        error "  Value $value not greater than $threshold"
        ((TESTS_FAILED++))
        return 1
    fi
}

# ============================================================================
# Test Cases
# ============================================================================

# Test 1: Extraction from session
test_extraction() {
    log "Test 1: Extracting knowledge from session"

    local output="${TEST_DIR}/extracted.jsonl"
    "$EXTRACTOR" extract "$TEST_SESSION_DIR" > "$output" 2>/dev/null

    # Check output exists
    assert_file_exists "$output" "Extraction creates output file"

    # Check entries extracted
    local count=$(wc -l < "$output")
    assert_greater_than "$count" 0 "Extracts at least one entry"

    # Check entry structure
    if [[ $count -gt 0 ]]; then
        local first_entry=$(head -1 "$output")

        # Verify required fields
        local has_id=$(echo "$first_entry" | jq -e '.id' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_id" "Entry has ID field"

        local has_type=$(echo "$first_entry" | jq -e '.type' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_type" "Entry has type field"

        local has_problem=$(echo "$first_entry" | jq -e '.problem' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_problem" "Entry has problem field"

        local has_solution=$(echo "$first_entry" | jq -e '.solution' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_solution" "Entry has solution field"
    fi
}

# Test 2: Categorization
test_categorization() {
    log "Test 2: Categorizing knowledge"

    local input="${TEST_DIR}/extracted.jsonl"
    local output="${TEST_DIR}/categorized.jsonl"

    "$CATEGORIZER" categorize "$input" "$output" 2>/dev/null

    # Check output
    assert_file_exists "$output" "Categorization creates output file"

    # Check enhanced fields
    if [[ -f "$output" ]]; then
        local first_entry=$(head -1 "$output")

        local has_domain=$(echo "$first_entry" | jq -e '.domain' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_domain" "Entry has domain field"

        local has_language=$(echo "$first_entry" | jq -e '.language' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_language" "Entry has language field"

        local has_complexity=$(echo "$first_entry" | jq -e '.complexity' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_complexity" "Entry has complexity field"
    fi
}

# Test 3: Indexing
test_indexing() {
    log "Test 3: Building search index"

    local input="${TEST_DIR}/categorized.jsonl"
    local output="${TEST_DIR}/indexed.jsonl"

    # Note: indexer writes to $KNOWLEDGE_DIR by default, so we need to redirect
    KNOWLEDGE_DIR="$TEST_DIR" "$INDEXER" index "$input" 2>/dev/null

    local index_file="${TEST_DIR}/knowledge-embeddings.jsonl"
    assert_file_exists "$index_file" "Indexing creates embeddings file"

    # Check embeddings
    if [[ -f "$index_file" ]]; then
        local first_entry=$(head -1 "$index_file")

        local has_embeddings=$(echo "$first_entry" | jq -e '.embeddings' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_embeddings" "Entry has embeddings field"

        local has_combined=$(echo "$first_entry" | jq -e '.embeddings.combined_embedding' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_combined" "Entry has combined embedding"
    fi

    # Check metadata
    local metadata_file="${TEST_DIR}/knowledge-metadata.json"
    assert_file_exists "$metadata_file" "Indexing creates metadata file"
}

# Test 4: Search
test_search() {
    log "Test 4: Searching knowledge"

    local index_file="${TEST_DIR}/knowledge-embeddings.jsonl"

    [[ ! -f "$index_file" ]] && {
        log "Skipping search test (no index file)"
        return 0
    }

    # Search for "python error"
    local results=$(KNOWLEDGE_DIR="$TEST_DIR" "$SEARCH" search "python error" 5 "$index_file" 2>/dev/null)

    # Check results structure
    local has_query=$(echo "$results" | jq -e '.query' >/dev/null 2>&1 && echo "true" || echo "false")
    assert_equals "true" "$has_query" "Search results have query field"

    local has_results=$(echo "$results" | jq -e '.results' >/dev/null 2>&1 && echo "true" || echo "false")
    assert_equals "true" "$has_results" "Search results have results array"

    local result_count=$(echo "$results" | jq '.results | length')
    assert_greater_than "$result_count" 0 "Search returns at least one result"
}

# Test 5: Quality scoring
test_scoring() {
    log "Test 5: Scoring knowledge quality"

    local input="${TEST_DIR}/categorized.jsonl"
    local output="${TEST_DIR}/scored.jsonl"

    "$SCORER" score "$input" "$output" 2>/dev/null

    assert_file_exists "$output" "Scoring creates output file"

    # Check quality score
    if [[ -f "$output" ]]; then
        local first_entry=$(head -1 "$output")

        local has_quality=$(echo "$first_entry" | jq -e '.quality_score' >/dev/null 2>&1 && echo "true" || echo "false")
        assert_equals "true" "$has_quality" "Entry has quality_score field"

        local confidence=$(echo "$first_entry" | jq -r '.confidence // 0')
        log "  Confidence score: $confidence"
    fi
}

# Test 6: Deduplication
test_deduplication() {
    log "Test 6: Deduplicating knowledge"

    # Create duplicate entries
    local test_index="${TEST_DIR}/knowledge-embeddings.jsonl"

    [[ ! -f "$test_index" ]] && {
        log "Skipping deduplication test (no index file)"
        return 0
    }

    # Duplicate first entry
    local first_entry=$(head -1 "$test_index")
    echo "$first_entry" >> "$test_index"

    local before_count=$(wc -l < "$test_index")

    # Run deduplication
    KNOWLEDGE_DIR="$TEST_DIR" "$INDEXER" deduplicate "$test_index" 0.90 2>/dev/null

    local dedup_file="${TEST_DIR}/knowledge-deduplicated.jsonl"

    if [[ -f "$dedup_file" ]]; then
        local after_count=$(wc -l < "$dedup_file")
        log "  Before: $before_count entries, After: $after_count entries"

        # Should have removed duplicate
        if [[ $after_count -lt $before_count ]]; then
            log "✓ PASS: Deduplication removes duplicates"
            ((TESTS_PASSED++))
        else
            error "✗ FAIL: Deduplication did not reduce entry count"
            ((TESTS_FAILED++))
        fi
    else
        log "Deduplication output file not created"
    fi
}

# Test 7: Batch processing
test_batch_processing() {
    log "Test 7: Batch processing"

    # Test extraction test
    "$BATCH" test 2>/dev/null

    local test_output="${KNOWLEDGE_DIR}/test-extraction.jsonl"

    if [[ -f "$test_output" ]]; then
        log "✓ PASS: Batch test extraction works"
        ((TESTS_PASSED++))
    else
        error "✗ FAIL: Batch test extraction failed"
        ((TESTS_FAILED++))
    fi
}

# ============================================================================
# Integration Tests
# ============================================================================

test_full_pipeline() {
    log "Integration Test: Full pipeline"

    setup_test_env

    # Run all steps in sequence
    test_extraction
    test_categorization
    test_indexing
    test_search
    test_scoring
    test_deduplication

    cleanup_test_env
}

# ============================================================================
# Performance Tests
# ============================================================================

test_performance() {
    log "Performance Test: Extraction speed"

    setup_test_env

    local start=$(date +%s%3N)
    "$EXTRACTOR" extract "$TEST_SESSION_DIR" > /dev/null 2>&1
    local end=$(date +%s%3N)

    local duration=$((end - start))
    log "  Extraction took ${duration}ms"

    # Should be under 5 seconds for small test
    if [[ $duration -lt 5000 ]]; then
        log "✓ PASS: Extraction performance acceptable"
        ((TESTS_PASSED++))
    else
        error "✗ FAIL: Extraction too slow (${duration}ms)"
        ((TESTS_FAILED++))
    fi

    cleanup_test_env
}

# ============================================================================
# Test Runner
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Extraction Test Suite

Usage: $(basename "$0") <test> [options]

Tests:
  all                Run all tests
  extraction         Test knowledge extraction
  categorization     Test categorization
  indexing           Test indexing
  search             Test search
  scoring            Test quality scoring
  deduplication      Test deduplication
  batch              Test batch processing
  pipeline           Test full pipeline (integration)
  performance        Test performance
  help               Show this help

Examples:
  $(basename "$0") all
  $(basename "$0") extraction
  $(basename "$0") pipeline
EOF
}

run_all_tests() {
    log "Running all tests"
    log "================="

    test_full_pipeline
    test_batch_processing
    test_performance

    log ""
    log "Test Results"
    log "============"
    log "Passed: $TESTS_PASSED"
    log "Failed: $TESTS_FAILED"
    log "Total:  $((TESTS_PASSED + TESTS_FAILED))"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log "All tests passed! ✓"
        exit 0
    else
        error "Some tests failed"
        exit 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    local test="${1:-help}"

    case "$test" in
        all)
            run_all_tests
            ;;
        extraction)
            setup_test_env
            test_extraction
            cleanup_test_env
            ;;
        categorization)
            setup_test_env
            test_extraction
            test_categorization
            cleanup_test_env
            ;;
        indexing)
            setup_test_env
            test_extraction
            test_categorization
            test_indexing
            cleanup_test_env
            ;;
        search)
            setup_test_env
            test_extraction
            test_categorization
            test_indexing
            test_search
            cleanup_test_env
            ;;
        scoring)
            setup_test_env
            test_extraction
            test_categorization
            test_scoring
            cleanup_test_env
            ;;
        deduplication)
            setup_test_env
            test_extraction
            test_categorization
            test_indexing
            test_deduplication
            cleanup_test_env
            ;;
        batch)
            test_batch_processing
            ;;
        pipeline)
            test_full_pipeline
            ;;
        performance)
            test_performance
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown test: $test"
            show_usage
            exit 1
            ;;
    esac

    log ""
    log "Test Results: Passed=$TESTS_PASSED, Failed=$TESTS_FAILED"

    [[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
}

main "$@"
