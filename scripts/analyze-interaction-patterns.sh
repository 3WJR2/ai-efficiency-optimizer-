#!/usr/bin/env bash
# analyze-interaction-patterns.sh - Analyzes accumulated interactions to extract insights
# Part of Adaptive Learning System v1.0

set -euo pipefail

USER_PROFILE="$HOME/.claude/data/user-profile.json"
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
INSIGHTS_FILE="$HOME/.claude/data/learned-insights.json"

# Check if we have enough data to analyze
INTERACTION_COUNT=$(jq -r '.profile.interaction_count // 0' "$USER_PROFILE" 2>/dev/null || echo "0")

if [[ $INTERACTION_COUNT -lt 3 ]]; then
  echo "Insufficient data for pattern analysis (need 3+ interactions, have $INTERACTION_COUNT)"
  exit 0
fi

# Analyze request type distribution
echo "Analyzing interaction patterns from $INTERACTION_COUNT interactions..."

# Extract top request categories
TOP_CATEGORIES=$(jq -r '
  .interaction_patterns.request_categories |
  to_entries |
  sort_by(-.value.count) |
  .[0:3] |
  map("\(.key): \(.value.count)") |
  join(", ")
' "$INTERACTION_LEARNING" 2>/dev/null || echo "unknown")

# Calculate success patterns
LEARNING_STAGE=$(jq -r '.profile.learning_stage // "initialization"' "$USER_PROFILE")

# Generate insights report
cat > "$INSIGHTS_FILE" <<EOF
{
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "interaction_count": $INTERACTION_COUNT,
  "learning_stage": "$LEARNING_STAGE",
  "insights": {
    "top_request_types": "$TOP_CATEGORIES",
    "confidence_level": $(echo "scale=2; $INTERACTION_COUNT / 100" | bc -l 2>/dev/null || echo "0.1"),
    "recommendations": [
      "Continue building interaction history for better personalization",
      "System is learning your communication patterns",
      "Quality-first approach is active and monitoring"
    ]
  }
}
EOF

echo "Pattern analysis complete. Insights saved to $INSIGHTS_FILE"
exit 0
