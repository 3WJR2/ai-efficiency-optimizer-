#!/usr/bin/env bash

# test-codebase-indexer.sh
# Test suite for Deep Codebase Understanding System
# Part of Deep Codebase Understanding System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="/Users/wallonwalusayi/claude-multi-workspace"

# Dependencies
CODE_EMBEDDER="${SCRIPT_DIR}/code-embedder.sh"
CODEBASE_INDEXER="${SCRIPT_DIR}/codebase-indexer.sh"
CODE_SEARCH="${SCRIPT_DIR}/code-search.sh"
DEPENDENCY_ANALYZER="${SCRIPT_DIR}/dependency-analyzer.sh"
CONTEXT_EXTRACTOR="${SCRIPT_DIR}/context-extractor.sh"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Test Framework
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

test_start() {
    local test_name="$1"
    echo ""
    echo "========================================="
    echo "TEST: $test_name"
    echo "========================================="
    ((TESTS_RUN++))
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    local reason="$1"
    echo -e "${RED}✗ FAIL: $reason${NC}"
    ((TESTS_FAILED++))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        test_fail "$message (expected: $expected, got: $actual)"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    if [[ -n "$value" ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local message="${2:-File should exist: $filepath}"

    if [[ -f "$filepath" ]]; then
        return 0
    else
        test_fail "$message"
        return 1
    fi
}

assert_greater_than() {
    local value="$1"
    local threshold="$2"
    local message="${3:-Value should be greater than threshold}"

    if [[ $value -gt $threshold ]]; then
        return 0
    else
        test_fail "$message (value: $value, threshold: $threshold)"
        return 1
    fi
}

# ============================================================================
# Test Cases
# ============================================================================

# Test 1: Code Embedder - Single File
test_embedder_single_file() {
    test_start "Code Embedder - Single File"

    # Create test file
    local test_file
    test_file=$(mktemp --suffix=.py)
    cat > "$test_file" <<'EOF'
def authenticate(username, password):
    """Authenticate a user"""
    if username and password:
        return True
    return False

class User:
    """User class"""
    def __init__(self, name):
        self.name = name
EOF

    log "Test file: $test_file"

    # Embed the file
    local output
    output=$("$CODE_EMBEDDER" file "$test_file" 2>&1)

    log "Output lines: $(echo "$output" | wc -l)"

    # Verify output
    if assert_not_empty "$output" "Embedder should produce output"; then
        # Check we got JSON lines
        local json_valid=true
        echo "$output" | while read -r line; do
            if ! echo "$line" | jq . >/dev/null 2>&1; then
                json_valid=false
                break
            fi
        done

        if $json_valid; then
            # Check for expected definitions
            local func_count
            local class_count
            func_count=$(echo "$output" | jq -r 'select(.type == "function")' | wc -l | tr -d ' ')
            class_count=$(echo "$output" | jq -r 'select(.type == "class")' | wc -l | tr -d ' ')

            log "Functions found: $func_count"
            log "Classes found: $class_count"

            if [[ $func_count -ge 1 ]] && [[ $class_count -ge 1 ]]; then
                test_pass
            else
                test_fail "Expected at least 1 function and 1 class"
            fi
        else
            test_fail "Output is not valid JSON"
        fi
    fi

    # Cleanup
    rm -f "$test_file"
}

# Test 2: Code Embedder - Directory
test_embedder_directory() {
    test_start "Code Embedder - Directory"

    # Use actual test directory
    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    log "Embedding directory: $TEST_DIR"

    # Embed directory
    local output_file
    output_file=$(mktemp --suffix=.jsonl)

    "$CODE_EMBEDDER" directory "$TEST_DIR" "$output_file" 2>&1 | tee /tmp/embed_log.txt

    log "Output file: $output_file"

    # Verify output file exists and has content
    if assert_file_exists "$output_file" "Output file should exist"; then
        local line_count
        line_count=$(wc -l < "$output_file" | tr -d ' ')

        log "Total definitions: $line_count"

        if assert_greater_than "$line_count" 0 "Should have at least 1 definition"; then
            # Verify JSON validity
            if jq . "$output_file" >/dev/null 2>&1; then
                test_pass
            else
                test_fail "Output file contains invalid JSON"
            fi
        fi
    fi

    # Cleanup
    rm -f "$output_file"
}

# Test 3: Codebase Indexer - Full Index
test_indexer_full() {
    test_start "Codebase Indexer - Full Index"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    log "Indexing: $TEST_DIR"

    # Index the codebase
    "$CODEBASE_INDEXER" index "$TEST_DIR" 2>&1 | tee /tmp/index_log.txt

    # Verify index was created
    local index_path
    index_path=$("$SCRIPT_DIR/codebase-indexer.sh" stats "$TEST_DIR" 2>&1 | grep "Index path" | cut -d: -f2- | xargs)

    log "Checking for index files..."

    # Check metadata exists
    local metadata_file
    metadata_file=$(find "$HOME/.claude/indexes" -name "metadata.json" -path "*$(basename "$TEST_DIR")*" 2>/dev/null | head -1)

    if [[ -z "$metadata_file" ]]; then
        # Try alternative method
        local hash
        hash=$(echo -n "$TEST_DIR" | md5 | cut -c1-16)
        metadata_file="$HOME/.claude/indexes/${hash}/metadata.json"
    fi

    log "Metadata file: $metadata_file"

    if assert_file_exists "$metadata_file" "Metadata file should exist"; then
        # Verify embeddings file
        local embeddings_file="${metadata_file%/*}/embeddings.jsonl"
        log "Embeddings file: $embeddings_file"

        if assert_file_exists "$embeddings_file" "Embeddings file should exist"; then
            # Check stats
            local files_indexed
            files_indexed=$(jq -r '.stats.files_indexed' "$metadata_file")

            log "Files indexed: $files_indexed"

            if assert_greater_than "$files_indexed" 0 "Should index at least 1 file"; then
                test_pass
            fi
        fi
    fi
}

# Test 4: Codebase Indexer - Incremental Update
test_indexer_update() {
    test_start "Codebase Indexer - Incremental Update"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    log "Running incremental update..."

    # Get current file count
    local hash
    hash=$(echo -n "$TEST_DIR" | md5 | cut -c1-16)
    local metadata_file="$HOME/.claude/indexes/${hash}/metadata.json"

    if [[ ! -f "$metadata_file" ]]; then
        test_fail "Index doesn't exist. Run full index test first."
        return
    fi

    local files_before
    files_before=$(jq -r '.stats.files_indexed' "$metadata_file")

    # Run update
    "$CODEBASE_INDEXER" update "$TEST_DIR" 2>&1 | tee /tmp/update_log.txt

    # Verify update completed
    local files_after
    files_after=$(jq -r '.stats.files_indexed' "$metadata_file")

    log "Files before: $files_before, after: $files_after"

    if [[ $files_after -ge $files_before ]]; then
        test_pass
    else
        test_fail "File count decreased after update"
    fi
}

# Test 5: Code Search - Semantic Search
test_search_semantic() {
    test_start "Code Search - Semantic Search"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    # Verify index exists
    local hash
    hash=$(echo -n "$TEST_DIR" | md5 | cut -c1-16)
    local embeddings_file="$HOME/.claude/indexes/${hash}/embeddings.jsonl"

    if [[ ! -f "$embeddings_file" ]]; then
        test_fail "Index doesn't exist. Run indexer test first."
        return
    fi

    log "Searching for: 'function definition'"

    # Perform search
    local results
    results=$("$CODE_SEARCH" search "$TEST_DIR" "function definition" 5 2>&1)

    log "Results: $(echo "$results" | jq length 2>/dev/null || echo 0)"

    # Verify results
    if assert_not_empty "$results" "Search should return results"; then
        # Check JSON validity
        if echo "$results" | jq . >/dev/null 2>&1; then
            # Check we have at least one result with a score
            local has_scores
            has_scores=$(echo "$results" | jq 'map(has("score")) | any')

            if [[ "$has_scores" == "true" ]]; then
                test_pass
            else
                test_fail "Results don't have scores"
            fi
        else
            test_fail "Results are not valid JSON"
        fi
    fi
}

# Test 6: Code Search - Find Function
test_search_function() {
    test_start "Code Search - Find Function"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    # Find any function from index
    local hash
    hash=$(echo -n "$TEST_DIR" | md5 | cut -c1-16)
    local embeddings_file="$HOME/.claude/indexes/${hash}/embeddings.jsonl"

    if [[ ! -f "$embeddings_file" ]]; then
        test_fail "Index doesn't exist. Run indexer test first."
        return
    fi

    # Get a function name from the index
    local func_name
    func_name=$(jq -r 'select(.type == "function") | .name' "$embeddings_file" | head -1)

    if [[ -z "$func_name" ]]; then
        log "No functions in index, skipping test"
        test_pass
        return
    fi

    log "Searching for function: $func_name"

    # Search for the function
    local results
    results=$("$CODE_SEARCH" function "$TEST_DIR" "$func_name" 2>&1)

    log "Results: $(echo "$results" | wc -l)"

    if assert_not_empty "$results" "Should find the function"; then
        test_pass
    fi
}

# Test 7: Dependency Analyzer
test_dependency_analysis() {
    test_start "Dependency Analyzer"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    log "Analyzing dependencies..."

    # Run dependency analysis
    "$DEPENDENCY_ANALYZER" analyze "$TEST_DIR" 2>&1 | tee /tmp/deps_log.txt

    # Verify graph was created
    local hash
    hash=$(echo -n "$TEST_DIR" | md5 | cut -c1-16)
    local graph_file="$HOME/.claude/indexes/${hash}/dependency_graph.json"

    log "Graph file: $graph_file"

    if assert_file_exists "$graph_file" "Dependency graph should exist"; then
        # Verify graph structure
        local has_nodes
        local has_edges
        has_nodes=$(jq 'has("nodes")' "$graph_file")
        has_edges=$(jq 'has("edges")' "$graph_file")

        if [[ "$has_nodes" == "true" ]] && [[ "$has_edges" == "true" ]]; then
            local node_count
            local edge_count
            node_count=$(jq '.nodes | length' "$graph_file")
            edge_count=$(jq '.edges | length' "$graph_file")

            log "Nodes: $node_count, Edges: $edge_count"

            test_pass
        else
            test_fail "Graph missing nodes or edges"
        fi
    fi
}

# Test 8: Context Extractor
test_context_extraction() {
    test_start "Context Extractor"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    # Find a file to extract context from
    local test_file
    test_file=$(find "$TEST_DIR" -name "*.py" -o -name "*.js" -o -name "*.sh" | head -1)

    if [[ -z "$test_file" ]]; then
        log "No suitable files found, skipping test"
        test_pass
        return
    fi

    log "Extracting context for: $test_file"

    # Extract context
    local context
    context=$("$CONTEXT_EXTRACTOR" extract "$TEST_DIR" "$test_file" 2>&1)

    log "Context length: ${#context}"

    if assert_not_empty "$context" "Context should be generated"; then
        # Check for expected sections
        if echo "$context" | grep -q "## Definition" && \
           echo "$context" | grep -q "## Documentation"; then
            test_pass
        else
            test_fail "Context missing expected sections"
        fi
    fi
}

# Test 9: End-to-End Workflow
test_e2e_workflow() {
    test_start "End-to-End Workflow"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    log "Running complete workflow..."

    # 1. Index
    log "Step 1: Indexing..."
    if ! "$CODEBASE_INDEXER" rebuild "$TEST_DIR" 2>&1; then
        test_fail "Indexing failed"
        return
    fi

    # 2. Search
    log "Step 2: Searching..."
    local search_results
    if ! search_results=$("$CODE_SEARCH" search "$TEST_DIR" "function" 3 2>&1); then
        test_fail "Search failed"
        return
    fi

    # 3. Dependency analysis
    log "Step 3: Dependency analysis..."
    if ! "$DEPENDENCY_ANALYZER" analyze "$TEST_DIR" 2>&1; then
        test_fail "Dependency analysis failed"
        return
    fi

    # 4. Get stats
    log "Step 4: Getting stats..."
    if ! "$CODEBASE_INDEXER" stats "$TEST_DIR" 2>&1; then
        test_fail "Stats retrieval failed"
        return
    fi

    test_pass
}

# Test 10: Performance Benchmark
test_performance() {
    test_start "Performance Benchmark"

    if [[ ! -d "$TEST_DIR" ]]; then
        test_fail "Test directory not found: $TEST_DIR"
        return
    fi

    # Count lines of code
    local loc
    loc=$(find "$TEST_DIR" -name "*.py" -o -name "*.js" -o -name "*.sh" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

    log "Total LOC: $loc"

    # Time indexing
    log "Timing full index..."
    local start_time
    local end_time
    start_time=$(date +%s)

    "$CODEBASE_INDEXER" rebuild "$TEST_DIR" >/dev/null 2>&1

    end_time=$(date +%s)
    local index_time=$((end_time - start_time))

    log "Indexing time: ${index_time}s"

    # Calculate speed (LOC per second)
    if [[ $loc -gt 0 ]] && [[ $index_time -gt 0 ]]; then
        local speed=$((loc / index_time))
        log "Indexing speed: $speed LOC/s"

        if [[ $speed -ge 100 ]]; then
            test_pass
        else
            test_fail "Indexing too slow (expected >100 LOC/s, got ${speed} LOC/s)"
        fi
    else
        test_fail "Unable to calculate speed"
    fi
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    log "Starting Deep Codebase Understanding System Tests"
    log "Test directory: $TEST_DIR"
    echo ""

    # Run tests
    test_embedder_single_file
    test_embedder_directory
    test_indexer_full
    test_indexer_update
    test_search_semantic
    test_search_function
    test_dependency_analysis
    test_context_extraction
    test_e2e_workflow
    test_performance

    # Summary
    echo ""
    echo "========================================="
    echo "TEST SUMMARY"
    echo "========================================="
    echo "Total tests:  $TESTS_RUN"
    echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# ============================================================================
# CLI Interface
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [test_name]

Run tests for Deep Codebase Understanding System.

Tests:
    embedder-single         Test code embedder on single file
    embedder-directory      Test code embedder on directory
    indexer-full            Test full indexing
    indexer-update          Test incremental update
    search-semantic         Test semantic search
    search-function         Test function search
    dependency-analysis     Test dependency analyzer
    context-extraction      Test context extractor
    e2e-workflow            Test end-to-end workflow
    performance             Run performance benchmark
    all                     Run all tests (default)

Examples:
    $(basename "$0")                    # Run all tests
    $(basename "$0") search-semantic    # Run specific test

EOF
}

main() {
    local test_name="${1:-all}"

    case "$test_name" in
        embedder-single)
            test_embedder_single_file
            ;;
        embedder-directory)
            test_embedder_directory
            ;;
        indexer-full)
            test_indexer_full
            ;;
        indexer-update)
            test_indexer_update
            ;;
        search-semantic)
            test_search_semantic
            ;;
        search-function)
            test_search_function
            ;;
        dependency-analysis)
            test_dependency_analysis
            ;;
        context-extraction)
            test_context_extraction
            ;;
        e2e-workflow)
            test_e2e_workflow
            ;;
        performance)
            test_performance
            ;;
        all)
            run_all_tests
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown test: $test_name"
            usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
