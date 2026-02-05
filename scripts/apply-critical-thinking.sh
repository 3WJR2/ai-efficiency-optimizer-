#!/usr/bin/env bash
# apply-critical-thinking.sh - Enforces critical thinking framework
# Part of Adaptive Learning System v1.0

set -euo pipefail

FRAMEWORK_FILE="$HOME/.claude/data/critical-thinking-framework.json"
REQUEST_TYPE="${1:-general}"
COMPLEXITY="${2:-medium}"

# Check if critical thinking framework is enabled
ENABLED=$(jq -r '.framework.enabled // true' "$FRAMEWORK_FILE" 2>/dev/null || echo "true")

if [[ "$ENABLED" != "true" ]]; then
  echo "Critical thinking framework is disabled"
  exit 0
fi

# Get enforcement level
ENFORCEMENT=$(jq -r '.framework.enforcement_level // "mandatory"' "$FRAMEWORK_FILE" 2>/dev/null || echo "mandatory")

# Determine thinking mode based on complexity and request type
THINKING_MODE="standard_thinking"

case "$COMPLEXITY" in
  high|critical)
    THINKING_MODE="deep_thinking"
    ;;
  very_high|architecture)
    THINKING_MODE="critical_thinking"
    ;;
esac

# Check if this request type triggers critical thinking automatically
AUTO_TRIGGERS=$(jq -r '.critical_thinking_triggers.auto_enable_for[]' "$FRAMEWORK_FILE" 2>/dev/null || echo "")

for trigger in $AUTO_TRIGGERS; do
  if echo "$REQUEST_TYPE" | grep -iq "$trigger"; then
    THINKING_MODE="critical_thinking"
    break
  fi
done

# Get thinking protocol for this mode
DURATION_TARGET=$(jq -r ".thinking_modes.${THINKING_MODE}.duration_target // \"1-2min\"" "$FRAMEWORK_FILE" 2>/dev/null)
DEPTH=$(jq -r ".thinking_modes.${THINKING_MODE}.depth // \"moderate\"" "$FRAMEWORK_FILE" 2>/dev/null)

# Output thinking requirements (will be read by Claude)
cat <<EOF
{
  "thinking_mode": "$THINKING_MODE",
  "duration_target": "$DURATION_TARGET",
  "depth": "$DEPTH",
  "enforcement": "$ENFORCEMENT",
  "protocols": $(jq -c '.thinking_protocols' "$FRAMEWORK_FILE" 2>/dev/null || echo '{}')
}
EOF

exit 0
