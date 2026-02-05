#!/bin/bash
# post-file-write.sh
# Autonomous Loop Trigger: Continuous Integration
# Triggers brahma-ci-runner on file changes

set -euo pipefail

# Arguments from hook
FILE_PATH="${1:-}"
FILE_TYPE="${2:-}"

# Configuration
CI_ENABLED="${BRAHMA_CI_ENABLED:-true}"
MIN_INTERVAL_SECONDS="${BRAHMA_CI_MIN_INTERVAL:-60}"  # Don't trigger more than once per minute
LAST_TRIGGER_FILE="$HOME/.claude/cache/last-ci-trigger"

# Exit if CI disabled
if [[ "$CI_ENABLED" != "true" ]]; then
    exit 0
fi

# Exit if not a code file
case "$FILE_TYPE" in
    *.md|*.txt|*.json|*.yaml|*.yml|*.toml|*.lock)
        # Skip documentation and config files
        exit 0
        ;;
esac

# Rate limiting: Don't trigger too frequently
if [[ -f "$LAST_TRIGGER_FILE" ]]; then
    LAST_TRIGGER=$(cat "$LAST_TRIGGER_FILE")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_TRIGGER))

    if [[ $ELAPSED -lt $MIN_INTERVAL_SECONDS ]]; then
        echo "⏱️  CI rate limit: Last trigger ${ELAPSED}s ago (min: ${MIN_INTERVAL_SECONDS}s)"
        exit 0
    fi
fi

# Update last trigger time
date +%s > "$LAST_TRIGGER_FILE"

# Trigger brahma-ci-runner
echo "🔄 Triggering CI for file change: $FILE_PATH"

# Create CI task (brahma-orchestrator will pick it up)
TASK_ID="ci-$(date +%s)-$(uuidgen | cut -d- -f1)"

cat > "$HOME/.claude/tasks/queue/$TASK_ID.json" <<EOF
{
  "task_id": "$TASK_ID",
  "type": "TESTING",
  "title": "Run tests for $FILE_PATH",
  "description": "Automated test execution triggered by file change",
  "base_priority": 80,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dependencies": [],
  "blocks": [],
  "metadata": {
    "trigger": "post-file-write",
    "file_path": "$FILE_PATH",
    "file_type": "$FILE_TYPE",
    "scope": "incremental"
  },
  "assigned_agent": "brahma-ci-runner",
  "status": "PENDING"
}
EOF

echo "✅ CI task created: $TASK_ID"

# Log for metrics
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$TASK_ID,$FILE_PATH" >> "$HOME/.claude/metrics/ci-triggers.log"

exit 0
