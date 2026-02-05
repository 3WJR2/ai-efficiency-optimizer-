#!/usr/bin/env bash
# capture-interaction.sh - Captures interaction data for learning system
# Part of Adaptive Learning System v1.1 - Enhanced with Phase 1 improvements

set -euo pipefail

USER_PROFILE="$HOME/.claude/data/user-profile.json"
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Ensure data files exist
mkdir -p "$HOME/.claude/data"
[[ ! -f "$USER_PROFILE" ]] && echo '{"profile": {"interaction_count": 0}}' > "$USER_PROFILE"
[[ ! -f "$INTERACTION_LEARNING" ]] && echo '{"interaction_patterns": {}}' > "$INTERACTION_LEARNING"

# Get interaction context from environment or parameters
INTERACTION_TYPE="${1:-general}"
SUCCESS_INDICATOR="${2:-unknown}"
COMPLEXITY="${3:-medium}"

# Increment interaction count
CURRENT_COUNT=$(jq -r '.profile.interaction_count // 0' "$USER_PROFILE")
NEW_COUNT=$((CURRENT_COUNT + 1))

# Update interaction count
jq --arg timestamp "$TIMESTAMP" \
   --arg count "$NEW_COUNT" \
   '.profile.interaction_count = ($count | tonumber) |
    .profile.last_updated = $timestamp' \
   "$USER_PROFILE" > "${USER_PROFILE}.tmp" && mv "${USER_PROFILE}.tmp" "$USER_PROFILE"

# Categorize and learn from interaction
case "$INTERACTION_TYPE" in
  code_implementation|system_design|debugging|explanation|research)
    # Increment category counter
    CATEGORY_PATH=".interaction_patterns.request_categories.${INTERACTION_TYPE}.count"
    CURRENT_CATEGORY_COUNT=$(jq -r "${CATEGORY_PATH} // 0" "$INTERACTION_LEARNING")
    NEW_CATEGORY_COUNT=$((CURRENT_CATEGORY_COUNT + 1))

    jq --arg path "$CATEGORY_PATH" \
       --arg count "$NEW_CATEGORY_COUNT" \
       --arg timestamp "$TIMESTAMP" \
       'setpath($path | split("."); ($count | tonumber))' \
       "$INTERACTION_LEARNING" > "${INTERACTION_LEARNING}.tmp" && \
       mv "${INTERACTION_LEARNING}.tmp" "$INTERACTION_LEARNING"
    ;;
esac

# Log learning stage progression
if [[ $NEW_COUNT -eq 5 ]]; then
  jq '.profile.learning_stage = "early_learning"' "$USER_PROFILE" > "${USER_PROFILE}.tmp" && \
     mv "${USER_PROFILE}.tmp" "$USER_PROFILE"
elif [[ $NEW_COUNT -eq 20 ]]; then
  jq '.profile.learning_stage = "pattern_recognition"' "$USER_PROFILE" > "${USER_PROFILE}.tmp" && \
     mv "${USER_PROFILE}.tmp" "$USER_PROFILE"
elif [[ $NEW_COUNT -eq 50 ]]; then
  jq '.profile.learning_stage = "adaptive_optimization"' "$USER_PROFILE" > "${USER_PROFILE}.tmp" && \
     mv "${USER_PROFILE}.tmp" "$USER_PROFILE"
elif [[ $NEW_COUNT -eq 100 ]]; then
  jq '.profile.learning_stage = "personalized_expertise"' "$USER_PROFILE" > "${USER_PROFILE}.tmp" && \
     mv "${USER_PROFILE}.tmp" "$USER_PROFILE"
fi

# Phase 1 Improvements: Collect additional data

# Preserve session context
if command -v "$HOME/.claude/scripts/preserve-session-context.sh" &> /dev/null; then
  "$HOME/.claude/scripts/preserve-session-context.sh" track_topic "$INTERACTION_TYPE" 2>/dev/null || true
fi

# Optionally collect explicit feedback (if not in background mode)
if [[ "${COLLECT_FEEDBACK:-no}" == "yes" ]]; then
  "$HOME/.claude/scripts/collect-feedback.sh" 2>/dev/null || true
fi

# Silent exit - learning happens in background
exit 0
