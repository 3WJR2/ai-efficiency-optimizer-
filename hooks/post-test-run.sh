#!/bin/bash
# post-test-run.sh
# Autonomous Loop Hook: Trigger test generation if coverage < 80%
# Called after test suite execution

set -euo pipefail

# Arguments from hook
TEST_RESULT="${1:-}"  # SUCCESS or FAILURE
COVERAGE_PERCENT="${2:-0}"
COVERAGE_REPORT_PATH="${3:-}"

# Configuration
COVERAGE_THRESHOLD="${BRAHMA_COVERAGE_THRESHOLD:-80}"
TEST_GEN_ENABLED="${BRAHMA_TEST_GEN_ENABLED:-true}"
MIN_INTERVAL_SECONDS="${BRAHMA_TEST_GEN_MIN_INTERVAL:-300}"  # 5 minutes
LAST_TRIGGER_FILE="$HOME/.claude/cache/last-test-gen-trigger"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "📊 Post-test-run hook triggered"
echo "   Test result: $TEST_RESULT"
echo "   Coverage: ${COVERAGE_PERCENT}%"

# Exit if test generation disabled
if [[ "$TEST_GEN_ENABLED" != "true" ]]; then
    echo "ℹ️  Test generation disabled (BRAHMA_TEST_GEN_ENABLED=false)"
    exit 0
fi

# Exit if tests failed (fix tests first before generating more)
if [[ "$TEST_RESULT" == "FAILURE" ]]; then
    echo "⚠️  Tests failed - not generating more tests until failures are fixed"
    exit 0
fi

# Check if coverage meets threshold
if [[ $(echo "$COVERAGE_PERCENT >= $COVERAGE_THRESHOLD" | bc -l) -eq 1 ]]; then
    echo -e "${GREEN}✅ Coverage meets threshold: ${COVERAGE_PERCENT}% >= ${COVERAGE_THRESHOLD}%${NC}"
    exit 0
fi

echo -e "${YELLOW}⚠️  Coverage below threshold: ${COVERAGE_PERCENT}% < ${COVERAGE_THRESHOLD}%${NC}"

# Rate limiting: Don't trigger too frequently
if [[ -f "$LAST_TRIGGER_FILE" ]]; then
    LAST_TRIGGER=$(cat "$LAST_TRIGGER_FILE")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_TRIGGER))

    if [[ $ELAPSED -lt $MIN_INTERVAL_SECONDS ]]; then
        echo "⏱️  Test generation rate limit: Last trigger ${ELAPSED}s ago (min: ${MIN_INTERVAL_SECONDS}s)"
        exit 0
    fi
fi

# Update last trigger time
date +%s > "$LAST_TRIGGER_FILE"

# Calculate coverage gap
COVERAGE_GAP=$(echo "$COVERAGE_THRESHOLD - $COVERAGE_PERCENT" | bc -l)
echo "   Coverage gap: ${COVERAGE_GAP}%"

# Create test generation task
TASK_ID="testgen-$(date +%s)-$(uuidgen | cut -d- -f1)"

echo "🔄 Creating test generation task: $TASK_ID"

# Ensure task queue directory exists
mkdir -p "$HOME/.claude/tasks/queue"

# Create task for brahma-test-generator
cat > "$HOME/.claude/tasks/queue/$TASK_ID.json" <<EOF
{
  "task_id": "$TASK_ID",
  "type": "TEST_GENERATION",
  "title": "Generate tests to reach ${COVERAGE_THRESHOLD}% coverage",
  "description": "Automated test generation triggered by coverage below threshold",
  "base_priority": 70,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dependencies": [],
  "blocks": [],
  "metadata": {
    "trigger": "post-test-run",
    "current_coverage": $COVERAGE_PERCENT,
    "target_coverage": $COVERAGE_THRESHOLD,
    "coverage_gap": $COVERAGE_GAP,
    "coverage_report_path": "$COVERAGE_REPORT_PATH",
    "test_result": "$TEST_RESULT"
  },
  "assigned_agent": "brahma-test-generator",
  "status": "PENDING"
}
EOF

echo -e "${GREEN}✅ Test generation task created: $TASK_ID${NC}"

# Log for metrics
METRICS_DIR="$HOME/.claude/metrics"
mkdir -p "$METRICS_DIR"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$TASK_ID,$COVERAGE_PERCENT,$COVERAGE_THRESHOLD,$COVERAGE_GAP" >> "$METRICS_DIR/test-gen-triggers.log"

# Optionally trigger brahma-orchestrator to process immediately
# (Comment out if you want manual processing)
if command -v claude &> /dev/null; then
    echo "🚀 Triggering brahma-orchestrator to process task..."
    # Run in background to avoid blocking
    nohup claude --agent brahma-orchestrator "Process pending test generation tasks" > /dev/null 2>&1 &
    echo "   Orchestrator triggered in background"
fi

exit 0
