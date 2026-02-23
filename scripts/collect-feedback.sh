#!/usr/bin/env bash
# collect-feedback.sh - Collect explicit user feedback on responses
# Part of Adaptive Learning System v1.1 - Phase 1 Improvements

set -euo pipefail

INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
USER_PROFILE="$HOME/.claude/data/user-profile.json"
FEEDBACK_LOG="$HOME/.claude/data/feedback-log.jsonl"

# Feedback options
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Quick Feedback (helps Claude learn your preferences):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Was this response helpful?"
echo "  [1] 👍 Yes, exactly what I needed"
echo "  [2] 👌 Yes, but needed minor adjustments"
echo "  [3] 🤔 Partially - missed some aspects"
echo "  [4] 👎 No, not what I needed"
echo "  [5] ⏭️  Skip feedback"
echo ""
read -p "Enter choice (1-5): " FEEDBACK_CHOICE

# Parse feedback
case "$FEEDBACK_CHOICE" in
  1)
    FEEDBACK_SCORE=1.0
    FEEDBACK_LABEL="excellent"
    echo "✅ Thanks! I'll remember this approach works well for you."
    ;;
  2)
    FEEDBACK_SCORE=0.7
    FEEDBACK_LABEL="good"
    echo "✅ Got it. I'll fine-tune this approach."
    ;;
  3)
    FEEDBACK_SCORE=0.3
    FEEDBACK_LABEL="partial"
    echo "📝 Noted. What was missing? (This helps me learn)"
    read -p "Optional comment: " FEEDBACK_COMMENT
    ;;
  4)
    FEEDBACK_SCORE=-0.5
    FEEDBACK_LABEL="poor"
    echo "📝 I'll adjust my approach. What would have been better?"
    read -p "Optional comment: " FEEDBACK_COMMENT
    ;;
  5|*)
    FEEDBACK_SCORE=0
    FEEDBACK_LABEL="skipped"
    echo "⏭️  Feedback skipped"
    exit 0
    ;;
esac

# Record feedback
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
INTERACTION_ID=$(date +%s)

# Append to feedback log (JSONL format for easy analysis)
echo "{\"timestamp\":\"$TIMESTAMP\",\"interaction_id\":\"$INTERACTION_ID\",\"score\":$FEEDBACK_SCORE,\"label\":\"$FEEDBACK_LABEL\",\"comment\":\"${FEEDBACK_COMMENT:-}\"}" >> "$FEEDBACK_LOG"

# Update quality metrics in user profile
if [[ -f "$USER_PROFILE" ]]; then
  CURRENT_SATISFACTION=$(jq -r '.profile.quality_metrics.satisfaction_signals // 0' "$USER_PROFILE")
  CURRENT_SUCCESS=$(jq -r '.profile.quality_metrics.success_rate // 0' "$USER_PROFILE")
  INTERACTION_COUNT=$(jq -r '.profile.interaction_count // 1' "$USER_PROFILE")

  # Calculate new metrics
  NEW_SATISFACTION=$(echo "$CURRENT_SATISFACTION + $FEEDBACK_SCORE" | bc -l)
  SUCCESS_RATE=$(echo "scale=2; ($CURRENT_SUCCESS * ($INTERACTION_COUNT - 1) + (($FEEDBACK_SCORE + 1) / 2)) / $INTERACTION_COUNT" | bc -l)

  # Update profile
  jq --arg satisfaction "$NEW_SATISFACTION" \
     --arg success_rate "$SUCCESS_RATE" \
     --arg timestamp "$TIMESTAMP" \
     '.profile.quality_metrics.satisfaction_signals = ($satisfaction | tonumber) |
      .profile.quality_metrics.success_rate = ($success_rate | tonumber) |
      .profile.last_updated = $timestamp' \
     "$USER_PROFILE" > "${USER_PROFILE}.tmp" && mv "${USER_PROFILE}.tmp" "$USER_PROFILE"
fi

# Update interaction learning confidence based on feedback
if [[ -f "$INTERACTION_LEARNING" ]] && [[ "$FEEDBACK_SCORE" != "0" ]]; then
  # Positive feedback increases confidence, negative decreases
  CONFIDENCE_ADJUSTMENT=$(echo "$FEEDBACK_SCORE * 0.05" | bc -l)

  jq --arg adjustment "$CONFIDENCE_ADJUSTMENT" \
     '.learning_system.last_feedback = now |
      .learning_system.total_feedback_count = (.learning_system.total_feedback_count // 0) + 1' \
     "$INTERACTION_LEARNING" > "${INTERACTION_LEARNING}.tmp" && mv "${INTERACTION_LEARNING}.tmp" "$INTERACTION_LEARNING"
fi

echo ""
echo "💾 Feedback recorded. Thank you for helping me learn!"
echo ""

exit 0
