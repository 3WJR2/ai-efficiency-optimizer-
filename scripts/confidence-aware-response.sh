#!/usr/bin/env bash
# confidence-aware-response.sh - Adjust response tone based on learning confidence
# Part of Adaptive Learning System v1.1 - Phase 1 Improvements

set -euo pipefail

INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
USER_PROFILE="$HOME/.claude/data/user-profile.json"

REQUEST_TYPE="${1:-general}"
CONTEXT="${2:-}"

# Get learning stage and confidence
if [[ -f "$USER_PROFILE" ]]; then
  LEARNING_STAGE=$(jq -r '.profile.learning_stage // "initialization"' "$USER_PROFILE")
  INTERACTION_COUNT=$(jq -r '.profile.interaction_count // 0' "$USER_PROFILE")
else
  LEARNING_STAGE="initialization"
  INTERACTION_COUNT=0
fi

# Calculate confidence based on learning stage and interaction count
calculate_confidence() {
  local stage="$1"
  local count="$2"

  case "$stage" in
    initialization)
      if [[ $count -lt 3 ]]; then
        echo "very_low"
      else
        echo "low"
      fi
      ;;
    early_learning)
      if [[ $count -lt 10 ]]; then
        echo "low"
      else
        echo "medium_low"
      fi
      ;;
    pattern_recognition)
      echo "medium"
      ;;
    adaptive_optimization)
      echo "medium_high"
      ;;
    personalized_expertise)
      echo "high"
      ;;
    *)
      echo "low"
      ;;
  esac
}

CONFIDENCE=$(calculate_confidence "$LEARNING_STAGE" "$INTERACTION_COUNT")

# Get request-specific confidence if available
if [[ -f "$INTERACTION_LEARNING" ]] && [[ "$REQUEST_TYPE" != "general" ]]; then
  REQUEST_COUNT=$(jq -r ".interaction_patterns.request_categories.${REQUEST_TYPE}.count // 0" "$INTERACTION_LEARNING" 2>/dev/null || echo "0")
  REQUEST_SUCCESS=$(jq -r ".interaction_patterns.request_categories.${REQUEST_TYPE}.success_rate // 0" "$INTERACTION_LEARNING" 2>/dev/null || echo "0")

  # Adjust confidence based on request-specific data
  if [[ $REQUEST_COUNT -lt 3 ]]; then
    CONFIDENCE="low"
  elif [[ $REQUEST_COUNT -ge 10 ]] && (( $(echo "$REQUEST_SUCCESS > 0.7" | bc -l) )); then
    # Boost confidence if we have good success rate
    case "$CONFIDENCE" in
      low) CONFIDENCE="medium_low" ;;
      medium_low) CONFIDENCE="medium" ;;
      medium) CONFIDENCE="medium_high" ;;
    esac
  fi
fi

# Generate appropriate response framing based on confidence
generate_framing() {
  local confidence="$1"
  local request_type="$2"

  case "$confidence" in
    very_low)
      cat <<EOF
{
  "tone": "exploratory",
  "prefix": "I'm still learning your preferences. Let me offer a few approaches:",
  "suffix": "Which approach resonates most with you? Your feedback helps me learn.",
  "certainty": "tentative",
  "alternatives": true,
  "request_feedback": true
}
EOF
      ;;
    low)
      cat <<EOF
{
  "tone": "collaborative",
  "prefix": "Based on early patterns, here's my recommendation:",
  "suffix": "Does this match your expectations? I'm still calibrating to your style.",
  "certainty": "moderate",
  "alternatives": true,
  "request_feedback": true
}
EOF
      ;;
    medium_low)
      cat <<EOF
{
  "tone": "balanced",
  "prefix": "I've noticed you tend to prefer X. Here's my approach:",
  "suffix": "Let me know if you'd like me to adjust this approach.",
  "certainty": "moderate",
  "alternatives": false,
  "request_feedback": true
}
EOF
      ;;
    medium)
      cat <<EOF
{
  "tone": "confident",
  "prefix": "Based on your past preferences for $request_type:",
  "suffix": "This aligns with the approaches that have worked well for you before.",
  "certainty": "confident",
  "alternatives": false,
  "request_feedback": false
}
EOF
      ;;
    medium_high)
      cat <<EOF
{
  "tone": "assured",
  "prefix": "I know you prefer [specific approach] for this type of task:",
  "suffix": "This matches the patterns I've learned from our interactions.",
  "certainty": "high",
  "alternatives": false,
  "request_feedback": false
}
EOF
      ;;
    high)
      cat <<EOF
{
  "tone": "personalized",
  "prefix": "Here's the approach tailored to your preferences:",
  "suffix": "If this doesn't match your current needs, let me know - preferences can evolve!",
  "certainty": "very_high",
  "alternatives": false,
  "request_feedback": false
}
EOF
      ;;
    *)
      cat <<EOF
{
  "tone": "neutral",
  "prefix": "Here's my recommendation:",
  "suffix": "",
  "certainty": "moderate",
  "alternatives": false,
  "request_feedback": false
}
EOF
      ;;
  esac
}

# Output framing guidance
FRAMING=$(generate_framing "$CONFIDENCE" "$REQUEST_TYPE")

# Also output metadata for Claude's context
cat <<EOF
{
  "confidence_analysis": {
    "learning_stage": "$LEARNING_STAGE",
    "interaction_count": $INTERACTION_COUNT,
    "confidence_level": "$CONFIDENCE",
    "request_type": "$REQUEST_TYPE",
    "framing": $FRAMING
  },
  "guidance": {
    "should_offer_alternatives": $(echo "$FRAMING" | jq -r '.alternatives'),
    "should_request_feedback": $(echo "$FRAMING" | jq -r '.request_feedback'),
    "tone": "$(echo "$FRAMING" | jq -r '.tone')",
    "certainty": "$(echo "$FRAMING" | jq -r '.certainty')"
  }
}
EOF

exit 0
