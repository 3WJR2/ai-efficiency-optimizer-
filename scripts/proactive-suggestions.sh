#!/usr/bin/env bash
# proactive-suggestions.sh - Anticipate user needs before stated
# Part of Adaptive Learning System v1.3 - Phase 3 Advanced Features

set -euo pipefail

PROACTIVE_DATA="$HOME/.claude/data/proactive-suggestions.json"
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
PROJECT_CONTEXTS="$HOME/.claude/data/project-contexts.json"

# Initialize proactive data if doesn't exist
if [[ ! -f "$PROACTIVE_DATA" ]]; then
  cat > "$PROACTIVE_DATA" <<'EOF'
{
  "version": "1.0.0",
  "suggestion_patterns": {
    "after_code_implementation": [
      {
        "trigger": "code_written",
        "suggestion": "Run tests to verify implementation",
        "confidence_threshold": 0.75,
        "frequency": 0
      },
      {
        "trigger": "code_written",
        "suggestion": "Add documentation for new functions",
        "confidence_threshold": 0.70,
        "frequency": 0
      },
      {
        "trigger": "code_written",
        "suggestion": "Check for error handling",
        "confidence_threshold": 0.75,
        "frequency": 0
      }
    ],
    "after_feature_complete": [
      {
        "trigger": "feature_done",
        "suggestion": "Create git commit with descriptive message",
        "confidence_threshold": 0.80,
        "frequency": 0
      },
      {
        "trigger": "feature_done",
        "suggestion": "Update CHANGELOG or documentation",
        "confidence_threshold": 0.70,
        "frequency": 0
      }
    ],
    "authentication_code": [
      {
        "trigger": "auth_detected",
        "suggestion": "Review security best practices (password hashing, JWT validation)",
        "confidence_threshold": 0.85,
        "frequency": 0
      },
      {
        "trigger": "auth_detected",
        "suggestion": "Add rate limiting to prevent brute force attacks",
        "confidence_threshold": 0.80,
        "frequency": 0
      }
    ],
    "database_operations": [
      {
        "trigger": "db_query_detected",
        "suggestion": "Consider adding database indexes for performance",
        "confidence_threshold": 0.75,
        "frequency": 0
      },
      {
        "trigger": "db_query_detected",
        "suggestion": "Add error handling for database connection failures",
        "confidence_threshold": 0.80,
        "frequency": 0
      }
    ],
    "api_endpoint": [
      {
        "trigger": "api_created",
        "suggestion": "Add input validation and sanitization",
        "confidence_threshold": 0.85,
        "frequency": 0
      },
      {
        "trigger": "api_created",
        "suggestion": "Document API endpoint in OpenAPI/Swagger",
        "confidence_threshold": 0.70,
        "frequency": 0
      },
      {
        "trigger": "api_created",
        "suggestion": "Add rate limiting and authentication",
        "confidence_threshold": 0.80,
        "frequency": 0
      }
    ]
  },
  "user_acceptance_rate": {},
  "total_suggestions_made": 0,
  "total_suggestions_accepted": 0
}
EOF
fi

COMMAND="${1:-suggest}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$COMMAND" in
  suggest)
    # Generate proactive suggestions based on context
    CONTEXT="${2:-general}"
    CURRENT_TASK="${3:-}"

    echo ""
    echo "💡 Proactive Suggestions:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Get suggestions for context
    SUGGESTIONS=$(jq -r --arg context "$CONTEXT" '
      .suggestion_patterns[$context] // [] |
      sort_by(-.confidence_threshold) |
      .[] |
      select(.confidence_threshold >= 0.70) |
      "\(.suggestion)"
    ' "$PROACTIVE_DATA")

    if [[ -n "$SUGGESTIONS" ]]; then
      echo "$SUGGESTIONS" | while IFS= read -r suggestion; do
        echo "  ✓ $suggestion"
      done
      echo ""

      # Increment suggestion count
      jq '.total_suggestions_made += 1' \
         "$PROACTIVE_DATA" > "${PROACTIVE_DATA}.tmp" && mv "${PROACTIVE_DATA}.tmp" "$PROACTIVE_DATA"
    else
      echo "  No proactive suggestions for context: $CONTEXT"
      echo ""
    fi
    ;;

  record-acceptance)
    # Record whether user accepted suggestion
    SUGGESTION_ID="${2}"
    ACCEPTED="${3:-false}"

    if [[ "$ACCEPTED" == "true" ]]; then
      jq '.total_suggestions_accepted += 1' \
         "$PROACTIVE_DATA" > "${PROACTIVE_DATA}.tmp" && mv "${PROACTIVE_DATA}.tmp" "$PROACTIVE_DATA"
    fi

    # Update acceptance rate
    TOTAL=$(jq -r '.total_suggestions_made // 1' "$PROACTIVE_DATA")
    ACCEPTED_COUNT=$(jq -r '.total_suggestions_accepted // 0' "$PROACTIVE_DATA")
    RATE=$(echo "scale=2; $ACCEPTED_COUNT / $TOTAL" | bc -l)

    jq --arg rate "$RATE" \
       '.user_acceptance_rate.overall = ($rate | tonumber)' \
       "$PROACTIVE_DATA" > "${PROACTIVE_DATA}.tmp" && mv "${PROACTIVE_DATA}.tmp" "$PROACTIVE_DATA"

    echo "Suggestion acceptance recorded: $ACCEPTED"
    ;;

  analyze-context)
    # Analyze current context to determine what suggestions to make
    FILE_CONTENT="${2:-}"

    # Detect patterns in content
    DETECTED_CONTEXTS=()

    if echo "$FILE_CONTENT" | grep -qi "def.*login\|def.*authenticate\|password\|jwt\|token"; then
      DETECTED_CONTEXTS+=("authentication_code")
    fi

    if echo "$FILE_CONTENT" | grep -qi "select.*from\|insert.*into\|update.*set\|delete.*from\|\.query\|\.execute"; then
      DETECTED_CONTEXTS+=("database_operations")
    fi

    if echo "$FILE_CONTENT" | grep -qi "@app\.route\|@api\|app\.get\|app\.post\|FastAPI\|express\."; then
      DETECTED_CONTEXTS+=("api_endpoint")
    fi

    if echo "$FILE_CONTENT" | grep -qi "def.*test_\|class.*Test\|@pytest\|describe("; then
      DETECTED_CONTEXTS+=("after_code_implementation")
    fi

    # Return detected contexts
    printf '%s\n' "${DETECTED_CONTEXTS[@]}" | jq -R . | jq -s '.'
    ;;

  stats)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           Proactive Suggestion Statistics                        ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    TOTAL=$(jq -r '.total_suggestions_made // 0' "$PROACTIVE_DATA")
    ACCEPTED=$(jq -r '.total_suggestions_accepted // 0' "$PROACTIVE_DATA")

    if [[ $TOTAL -gt 0 ]]; then
      RATE=$(echo "scale=1; $ACCEPTED * 100 / $TOTAL" | bc -l)
    else
      RATE=0
    fi

    echo "Total suggestions made: $TOTAL"
    echo "Total accepted: $ACCEPTED"
    echo "Acceptance rate: ${RATE}%"
    echo ""

    echo "Suggestion Categories:"
    jq -r '
      .suggestion_patterns |
      to_entries |
      .[] |
      "  \(.key): \(.value | length) patterns"
    ' "$PROACTIVE_DATA"
    echo ""
    ;;

  add-pattern)
    # Add custom suggestion pattern
    CONTEXT="${2}"
    TRIGGER="${3}"
    SUGGESTION="${4}"
    CONFIDENCE="${5:-0.75}"

    if [[ -z "$CONTEXT" ]] || [[ -z "$TRIGGER" ]] || [[ -z "$SUGGESTION" ]]; then
      echo "Error: context, trigger, and suggestion required"
      exit 1
    fi

    jq --arg context "$CONTEXT" \
       --arg trigger "$TRIGGER" \
       --arg suggestion "$SUGGESTION" \
       --arg confidence "$CONFIDENCE" \
       '
       .suggestion_patterns[$context] += [{
         "trigger": $trigger,
         "suggestion": $suggestion,
         "confidence_threshold": ($confidence | tonumber),
         "frequency": 0
       }]
       ' \
       "$PROACTIVE_DATA" > "${PROACTIVE_DATA}.tmp" && mv "${PROACTIVE_DATA}.tmp" "$PROACTIVE_DATA"

    echo "Custom suggestion pattern added to context: $CONTEXT"
    ;;

  *)
    echo "Usage: $0 {suggest <context>|record-acceptance <id> <true|false>|analyze-context <content>|stats|add-pattern <context> <trigger> <suggestion> [confidence]}"
    exit 1
    ;;
esac

exit 0
