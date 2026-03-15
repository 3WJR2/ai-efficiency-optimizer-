#!/usr/bin/env bash
# test-prompt-optimizer.sh - Automated tests for the prompt optimizer
# Run: bash tests/test-prompt-optimizer.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTIMIZER="$SCRIPT_DIR/scripts/prompt-optimizer.sh"
CLASSIFIER="$SCRIPT_DIR/scripts/semantic-classifier.py"
HOOK="$SCRIPT_DIR/hooks/prompt-optimizer-hook.sh"

PASS=0
FAIL=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $test_name (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -q "$needle"; then
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $test_name (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_empty() {
    local test_name="$1"
    local value="$2"
    TOTAL=$((TOTAL + 1))
    if [ -n "$value" ]; then
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $test_name (expected non-empty)"
        FAIL=$((FAIL + 1))
    fi
}

assert_empty() {
    local test_name="$1"
    local value="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$value" ]; then
        echo -e "  ${GREEN}PASS${NC}: $test_name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}: $test_name (expected empty, got '$value')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Prompt Optimizer Test Suite ==="
echo ""

# ─── Syntax check ─────────────────────────────────────────────────
echo "--- Syntax Checks ---"
bash -n "$OPTIMIZER" 2>/dev/null
assert_eq "prompt-optimizer.sh syntax valid" "0" "$?"

bash -n "$HOOK" 2>/dev/null
assert_eq "prompt-optimizer-hook.sh syntax valid" "0" "$?"

python3 -c "import py_compile; py_compile.compile('$CLASSIFIER', doraise=True)" 2>/dev/null
assert_eq "semantic-classifier.py syntax valid" "0" "$?"

# ─── Classification Tests ─────────────────────────────────────────
echo ""
echo "--- Classification Tests (Semantic Classifier) ---"

result=$(python3 "$CLASSIFIER" "Fix the null pointer exception in the login handler" 2>/dev/null)
assert_eq "debugging classification" "debugging" "$result"

result=$(python3 "$CLASSIFIER" "Build a React dashboard with user analytics" 2>/dev/null)
assert_eq "frontend classification" "frontend" "$result"

result=$(python3 "$CLASSIFIER" "How could I optimize my prompts more" 2>/dev/null)
assert_eq "research classification" "research" "$result"

result=$(python3 "$CLASSIFIER" "Write unit tests for the payment module" 2>/dev/null)
assert_eq "testing classification" "testing" "$result"

result=$(python3 "$CLASSIFIER" "Refactor this function to reduce complexity" 2>/dev/null)
assert_eq "refactoring classification" "refactoring" "$result"

result=$(python3 "$CLASSIFIER" "Design a microservice architecture for the e-commerce platform" 2>/dev/null)
assert_eq "system_design classification" "system_design" "$result"

result=$(python3 "$CLASSIFIER" "Set up CI/CD pipeline with GitHub Actions" 2>/dev/null)
assert_eq "devops classification" "devops" "$result"

result=$(python3 "$CLASSIFIER" "Review this pull request for security issues" 2>/dev/null)
assert_eq "code_review classification" "code_review" "$result"

# ─── Classification Tests (grep fallback via prompt-optimizer.sh) ──
echo ""
echo "--- Classification Tests (Integrated) ---"

result=$("$OPTIMIZER" classify "Fix the bug in authentication" 2>/dev/null)
assert_eq "classify debugging via optimizer" "debugging" "$result"

result=$("$OPTIMIZER" classify "Build a REST API for user management" 2>/dev/null)
assert_eq "classify api_integration via optimizer" "api_integration" "$result"

# ─── Generate Tests ───────────────────────────────────────────────
echo ""
echo "--- Generate Tests ---"

output=$("$OPTIMIZER" generate "Implement a user registration endpoint" 2>/dev/null)
assert_contains "generate includes category header" "# Task Category:" "$output"
assert_contains "generate includes complexity" "# Complexity:" "$output"
assert_contains "generate includes task tag" "<task>" "$output"
assert_contains "generate includes instructions tag" "<instructions>" "$output"
assert_contains "generate includes role" "expert" "$output"

output=$("$OPTIMIZER" generate "Fix the crash when users submit empty forms" 2>/dev/null)
assert_contains "debugging prompt includes debugging approach" "<debugging_approach>" "$output"

# ─── Generate with CWD ────────────────────────────────────────────
echo ""
echo "--- Project Context Tests ---"

# Create temp project for testing
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR"
echo '{"name":"test-app","dependencies":{"react":"^18.0","typescript":"^5.0"}}' > "$TMPDIR/package.json"
echo '{}' > "$TMPDIR/tsconfig.json"

output=$("$OPTIMIZER" generate "Add a new component" "$TMPDIR" 2>/dev/null)
assert_contains "detects TypeScript from project" "TypeScript" "$output"

rm -rf "$TMPDIR"

# ─── Git Context Tests ────────────────────────────────────────────
echo ""
echo "--- Git Context Tests ---"

if [ -d "$SCRIPT_DIR/.git" ] || git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    output=$("$OPTIMIZER" detect-git "$SCRIPT_DIR" 2>/dev/null)
    assert_contains "git context detects branch" "Branch:" "$output"
else
    echo "  SKIP: Not a git repo"
fi

# ─── Refine Tests ─────────────────────────────────────────────────
echo ""
echo "--- Refinement Tests ---"

original="You are an expert. <instructions>1. Do thing.</instructions>"
refined=$("$OPTIMIZER" refine "$original" "add tests for the fix" "debugging" 2>/dev/null)
assert_contains "refine adds testing requirement" "<testing_requirement>" "$refined"

refined=$("$OPTIMIZER" refine "$original" "ensure this is secure and safe" "code_implementation" 2>/dev/null)
assert_contains "refine adds security requirement" "<security_requirement>" "$refined"

refined=$("$OPTIMIZER" refine "$original" "make it shorter please" "code_implementation" 2>/dev/null)
# simpler/shorter should try to remove verbose sections (may not have them here)
assert_not_empty "refine returns non-empty for simpler" "$refined"

refined=$("$OPTIMIZER" refine "$original" "also handle pagination" "api_integration" 2>/dev/null)
assert_contains "refine adds custom feedback" "<user_refinement>" "$refined"

# ─── Hook Skip Logic Tests ────────────────────────────────────────
echo ""
echo "--- Hook Skip Logic Tests ---"

# Short prompt should produce no output
output=$(echo '{"prompt":"hello","cwd":"."}' | "$HOOK" 2>/dev/null)
assert_empty "hook skips short prompt" "$output"

# Slash command should produce no output
output=$(echo '{"prompt":"/commit my changes","cwd":"."}' | "$HOOK" 2>/dev/null)
assert_empty "hook skips slash command" "$output"

# Yes/no should skip
output=$(echo '{"prompt":"yes","cwd":"."}' | "$HOOK" 2>/dev/null)
assert_empty "hook skips yes response" "$output"

# Git operations should skip
output=$(echo '{"prompt":"commit these changes to the repo now","cwd":"."}' | "$HOOK" 2>/dev/null)
assert_empty "hook skips git operations" "$output"

# Skip opt-out
output=$(echo '{"prompt":"just do it without any optimization needed","cwd":"."}' | "$HOOK" 2>/dev/null)
assert_empty "hook skips opt-out" "$output"

# Valid prompt should produce output
output=$(echo '{"prompt":"Build a REST API with user authentication and rate limiting","cwd":"."}' | "$HOOK" 2>/dev/null)
assert_contains "hook generates output for valid prompt" "PROMPT OPTIMIZER" "$output"

# ─── Edge Cases ───────────────────────────────────────────────────
echo ""
echo "--- Edge Cases ---"

# Empty request
output=$("$OPTIMIZER" generate "" 2>/dev/null)
assert_contains "handles empty request" "Error" "$output"

# No args to classifier
output=$(python3 "$CLASSIFIER" 2>/dev/null)
assert_eq "classifier with no args returns general" "general" "$output"

# Status command
output=$("$OPTIMIZER" status 2>/dev/null)
assert_contains "status shows features" "Features" "$output"
assert_contains "status shows semantic classifier" "Semantic TF-IDF" "$output"

# ─── Summary ──────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
