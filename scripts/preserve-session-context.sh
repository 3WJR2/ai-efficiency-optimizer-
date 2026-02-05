#!/usr/bin/env bash
# preserve-session-context.sh - Preserve context between sessions
# Part of Adaptive Learning System v1.1 - Phase 1 Improvements

set -euo pipefail

SESSION_HISTORY="$HOME/.claude/data/session-history.json"
USER_PROFILE="$HOME/.claude/data/user-profile.json"

# Initialize session history if doesn't exist
if [[ ! -f "$SESSION_HISTORY" ]]; then
  cat > "$SESSION_HISTORY" <<'EOF'
{
  "version": "1.0.0",
  "sessions": [],
  "current_session": null,
  "continuous_topics": [],
  "unresolved_questions": []
}
EOF
fi

COMMAND="${1:-start}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(date +%s)

case "$COMMAND" in
  start)
    # Start new session
    SESSION_DATA=$(cat <<EOF
{
  "session_id": "$SESSION_ID",
  "start_time": "$TIMESTAMP",
  "end_time": null,
  "topics": [],
  "technologies": [],
  "questions_asked": 0,
  "tasks_completed": 0,
  "unresolved_items": []
}
EOF
)

    # Update session history
    jq --argjson session "$SESSION_DATA" \
       '.current_session = $session' \
       "$SESSION_HISTORY" > "${SESSION_HISTORY}.tmp" && mv "${SESSION_HISTORY}.tmp" "$SESSION_HISTORY"

    # Check for continuous topics from previous session
    RECENT_TOPICS=$(jq -r '.continuous_topics[-3:]? | .[]?' "$SESSION_HISTORY" 2>/dev/null || echo "")

    if [[ -n "$RECENT_TOPICS" ]]; then
      echo ""
      echo "📚 Recent topics from previous sessions:"
      echo "$RECENT_TOPICS" | sed 's/^/  • /'
      echo ""
      echo "Continuing these conversations? I remember the context."
      echo ""
    fi
    ;;

  track_topic)
    # Track topic in current session
    TOPIC="${2:-general}"

    jq --arg topic "$TOPIC" \
       '.current_session.topics += [$topic] |
        .current_session.topics |= unique |
        .continuous_topics += [$topic] |
        .continuous_topics |= unique' \
       "$SESSION_HISTORY" > "${SESSION_HISTORY}.tmp" && mv "${SESSION_HISTORY}.tmp" "$SESSION_HISTORY"
    ;;

  track_technology)
    # Track technology used in current session
    TECH="${2:-unknown}"

    jq --arg tech "$TECH" \
       '.current_session.technologies += [$tech] |
        .current_session.technologies |= unique' \
       "$SESSION_HISTORY" > "${SESSION_HISTORY}.tmp" && mv "${SESSION_HISTORY}.tmp" "$SESSION_HISTORY"
    ;;

  track_unresolved)
    # Track something that needs follow-up
    ITEM="${2:-unspecified}"

    jq --arg item "$ITEM" \
       --arg timestamp "$TIMESTAMP" \
       '.current_session.unresolved_items += [{"item": $item, "timestamp": $timestamp}] |
        .unresolved_questions += [{"item": $item, "timestamp": $timestamp}]' \
       "$SESSION_HISTORY" > "${SESSION_HISTORY}.tmp" && mv "${SESSION_HISTORY}.tmp" "$SESSION_HISTORY"
    ;;

  end)
    # End current session
    jq --arg timestamp "$TIMESTAMP" \
       '.current_session.end_time = $timestamp |
        .sessions += [.current_session] |
        .sessions = (.sessions[-20:]) |
        .current_session = null' \
       "$SESSION_HISTORY" > "${SESSION_HISTORY}.tmp" && mv "${SESSION_HISTORY}.tmp" "$SESSION_HISTORY"

    # Generate session summary
    echo ""
    echo "📊 Session Summary:"
    jq -r '.sessions[-1] |
           "  Topics: \(.topics | join(", "))",
           "  Technologies: \(.technologies | join(", "))",
           "  Questions: \(.questions_asked)",
           "  Duration: \(.start_time) to \(.end_time)"' \
           "$SESSION_HISTORY"
    echo ""
    ;;

  summary)
    # Show recent session summary
    echo ""
    echo "📊 Recent Session Context:"
    echo ""

    # Last 3 sessions
    echo "Recent Sessions:"
    jq -r '.sessions[-3:]? | .[] |
           "  [\(.start_time | split("T")[0])] \(.topics | join(", "))"' \
           "$SESSION_HISTORY" 2>/dev/null || echo "  No recent sessions"

    echo ""
    echo "Continuous Topics:"
    jq -r '.continuous_topics[-5:]? | .[]? | "  • \(.)"' "$SESSION_HISTORY" 2>/dev/null || echo "  None"

    echo ""
    echo "Unresolved Items:"
    jq -r '.unresolved_questions[-3:]? | .[]? |
           "  • \(.item) (\(.timestamp | split("T")[0]))"' \
           "$SESSION_HISTORY" 2>/dev/null || echo "  None"
    echo ""
    ;;

  *)
    echo "Usage: $0 {start|end|track_topic|track_technology|track_unresolved|summary}"
    exit 1
    ;;
esac

exit 0
