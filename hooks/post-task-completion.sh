#!/bin/bash
# post-task-completion.sh
# Autonomous Loop Trigger: Continuous Learning
# Updates pattern confidence and knowledge-core.md after task completion

set -euo pipefail

# Arguments from hook
TASK_ID="${1:-}"
AGENT_NAME="${2:-}"
STATUS="${3:-}"  # SUCCESS or FAILURE
DURATION_SECONDS="${4:-0}"
RETRY_COUNT="${5:-0}"

# Configuration
LEARNING_ENABLED="${BRAHMA_LEARNING_ENABLED:-true}"
PATTERN_INDEX="$HOME/.claude/data/pattern-index.json"
KNOWLEDGE_CORE="$HOME/knowledge-core.md"

# Exit if learning disabled
if [[ "$LEARNING_ENABLED" != "true" ]]; then
    exit 0
fi

echo "📊 Learning from task completion: $TASK_ID"

# Read task details
TASK_FILE="$HOME/.claude/tasks/completed/$TASK_ID.json"
if [[ ! -f "$TASK_FILE" ]]; then
    echo "⚠️  Task file not found: $TASK_FILE"
    exit 0
fi

TASK_TYPE=$(jq -r '.type' "$TASK_FILE")
PATTERN_USED=$(jq -r '.metadata.pattern_used // "none"' "$TASK_FILE")

# Update pattern metrics
if [[ "$PATTERN_USED" != "none" ]] && [[ -f "$PATTERN_INDEX" ]]; then
    echo "🔄 Updating pattern confidence for: $PATTERN_USED"

    # Calculate new confidence (Python script for Bayesian update)
    python3 - <<PYTHON_SCRIPT
import json
import sys
from datetime import datetime, timedelta

# Load pattern index
with open('$PATTERN_INDEX', 'r') as f:
    patterns = json.load(f)

pattern_name = '$PATTERN_USED'
status = '$STATUS'

if pattern_name in patterns:
    pattern = patterns[pattern_name]

    # Update usage stats
    pattern['total_uses'] = pattern.get('total_uses', 0) + 1
    pattern['last_used'] = datetime.now().isoformat()

    if status == 'SUCCESS':
        pattern['successes'] = pattern.get('successes', 0) + 1

    # Calculate Bayesian confidence
    base_confidence = pattern['successes'] / pattern['total_uses']

    # Time decay factor
    last_used = datetime.fromisoformat(pattern['last_used'])
    days_since_use = (datetime.now() - last_used).days
    if days_since_use > 180:
        time_decay = 0.5
    elif days_since_use > 90:
        time_decay = 0.75
    else:
        time_decay = 1.0

    # Evidence factor
    total_uses = pattern['total_uses']
    if total_uses < 3:
        evidence_factor = 0.5
    elif total_uses < 5:
        evidence_factor = 0.75
    else:
        evidence_factor = 1.0

    # Final confidence
    confidence = base_confidence * time_decay * evidence_factor
    pattern['confidence'] = round(confidence, 3)

    # Determine confidence level
    if confidence >= 0.80:
        pattern['confidence_level'] = 'HIGH'
    elif confidence >= 0.50:
        pattern['confidence_level'] = 'MEDIUM'
    else:
        pattern['confidence_level'] = 'LOW'

    # Update pattern index
    patterns[pattern_name] = pattern

    # Write updated patterns
    with open('$PATTERN_INDEX', 'w') as f:
        json.dump(patterns, f, indent=2)

    print(f"✅ Pattern '{pattern_name}' updated:")
    print(f"   - Total uses: {pattern['total_uses']}")
    print(f"   - Success rate: {base_confidence:.1%}")
    print(f"   - Confidence: {confidence:.1%} ({pattern['confidence_level']})")

    # If HIGH confidence and not yet in knowledge-core, suggest addition
    if pattern['confidence_level'] == 'HIGH' and not pattern.get('in_knowledge_core', False):
        print(f"💡 Pattern '{pattern_name}' has HIGH confidence - consider adding to knowledge-core.md")
PYTHON_SCRIPT

fi

# Log metrics
METRICS_FILE="$HOME/.claude/metrics/task-completion-metrics.json"
mkdir -p "$(dirname "$METRICS_FILE")"

# Append to metrics (JSONL format)
cat >> "$METRICS_FILE" <<EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","task_id":"$TASK_ID","agent":"$AGENT_NAME","type":"$TASK_TYPE","status":"$STATUS","duration_seconds":$DURATION_SECONDS,"retry_count":$RETRY_COUNT,"pattern_used":"$PATTERN_USED"}
EOF

# Generate daily learning summary (if it's been 24 hours)
LAST_SUMMARY_FILE="$HOME/.claude/cache/last-learning-summary"
if [[ -f "$LAST_SUMMARY_FILE" ]]; then
    LAST_SUMMARY=$(cat "$LAST_SUMMARY_FILE")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_SUMMARY))

    if [[ $ELAPSED -ge 86400 ]]; then  # 24 hours
        echo "📈 Generating daily learning summary..."

        # Count successes/failures today
        TODAY=$(date +%Y-%m-%d)
        SUCCESS_COUNT=$(grep "$TODAY" "$METRICS_FILE" | grep '"status":"SUCCESS"' | wc -l)
        FAILURE_COUNT=$(grep "$TODAY" | grep '"status":"FAILURE"' | wc -l)
        TOTAL_COUNT=$((SUCCESS_COUNT + FAILURE_COUNT))

        if [[ $TOTAL_COUNT -gt 0 ]]; then
            SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))
            echo "   - Tasks completed: $TOTAL_COUNT"
            echo "   - Success rate: $SUCCESS_RATE%"
            echo "   - Failures: $FAILURE_COUNT"
        fi

        date +%s > "$LAST_SUMMARY_FILE"
    fi
else
    date +%s > "$LAST_SUMMARY_FILE"
fi

echo "✅ Learning cycle complete for task: $TASK_ID"

exit 0
