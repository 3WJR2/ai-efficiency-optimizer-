#!/usr/bin/env bash
# drift-detection.sh - Detect when user preferences drift/change significantly
# Part of Adaptive Learning System v1.3 - Phase 3 Advanced Features

set -euo pipefail

DRIFT_DATA="$HOME/.claude/data/drift-detection.json"
USER_PROFILE="$HOME/.claude/data/user-profile.json"
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"

# Initialize drift data if doesn't exist
if [[ ! -f "$DRIFT_DATA" ]]; then
  cat > "$DRIFT_DATA" <<'EOF'
{
  "version": "1.0.0",
  "preference_snapshots": [],
  "drift_events": [],
  "monitoring_window": 20,
  "drift_threshold": 0.30,
  "last_check": null
}
EOF
fi

COMMAND="${1:-check}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$COMMAND" in
  snapshot)
    # Take snapshot of current preferences
    echo "Taking preference snapshot..."

    # Get current preference indicators
    LEARNING_STAGE=$(jq -r '.profile.learning_stage // "initialization"' "$USER_PROFILE" 2>/dev/null || echo "initialization")
    INTERACTION_COUNT=$(jq -r '.profile.interaction_count // 0' "$USER_PROFILE" 2>/dev/null || echo "0")

    # Get top request types
    TOP_REQUESTS=$(jq -c '
      [.interaction_patterns.request_categories |
      to_entries |
      sort_by(-.value.count) |
      .[0:3] |
      map({key: .key, count: .value.count})]
    ' "$INTERACTION_LEARNING" 2>/dev/null || echo "[]")

    # Get communication style scores
    BREVITY=$(jq -r '.interaction_patterns.communication_style.brevity_vs_detail.score // 0.5' "$INTERACTION_LEARNING" 2>/dev/null || echo "0.5")
    TECH_DEPTH=$(jq -r '.interaction_patterns.communication_style.technical_depth.score // 0.5' "$INTERACTION_LEARNING" 2>/dev/null || echo "0.5")

    # Create snapshot
    jq --arg timestamp "$TIMESTAMP" \
       --arg stage "$LEARNING_STAGE" \
       --arg count "$INTERACTION_COUNT" \
       --argjson requests "$TOP_REQUESTS" \
       --arg brevity "$BREVITY" \
       --arg depth "$TECH_DEPTH" \
       '
       .preference_snapshots += [{
         "timestamp": $timestamp,
         "interaction_count": ($count | tonumber),
         "learning_stage": $stage,
         "top_requests": $requests,
         "communication_style": {
           "brevity": ($brevity | tonumber),
           "technical_depth": ($depth | tonumber)
         }
       }] |
       .preference_snapshots = (.preference_snapshots[-10:])
       ' \
       "$DRIFT_DATA" > "${DRIFT_DATA}.tmp" && mv "${DRIFT_DATA}.tmp" "$DRIFT_DATA"

    echo "Snapshot created at $TIMESTAMP"
    ;;

  check)
    # Check for preference drift
    SNAPSHOT_COUNT=$(jq -r '.preference_snapshots | length' "$DRIFT_DATA")

    if [[ $SNAPSHOT_COUNT -lt 2 ]]; then
      echo "insufficient_data (need 2+ snapshots)"
      exit 0
    fi

    # Compare recent window with older baseline
    WINDOW=$(jq -r '.monitoring_window // 20' "$DRIFT_DATA")
    THRESHOLD=$(jq -r '.drift_threshold // 0.30' "$DRIFT_DATA")

    # Get most recent and baseline snapshots
    RECENT=$(jq -r '.preference_snapshots[-1]' "$DRIFT_DATA")
    BASELINE=$(jq -r '.preference_snapshots[0]' "$DRIFT_DATA")

    # Calculate drift score (simple comparison)
    RECENT_BREVITY=$(echo "$RECENT" | jq -r '.communication_style.brevity')
    BASELINE_BREVITY=$(echo "$BASELINE" | jq -r '.communication_style.brevity')

    BREVITY_DIFF=$(echo "scale=2; ($RECENT_BREVITY - $BASELINE_BREVITY) * ($RECENT_BREVITY - $BASELINE_BREVITY)" | bc -l | awk '{printf "%.2f", sqrt($1)}')

    RECENT_DEPTH=$(echo "$RECENT" | jq -r '.communication_style.technical_depth')
    BASELINE_DEPTH=$(echo "$BASELINE" | jq -r '.communication_style.technical_depth')

    DEPTH_DIFF=$(echo "scale=2; ($RECENT_DEPTH - $BASELINE_DEPTH) * ($RECENT_DEPTH - $BASELINE_DEPTH)" | bc -l | awk '{printf "%.2f", sqrt($1)}')

    # Combined drift score
    DRIFT_SCORE=$(echo "scale=2; ($BREVITY_DIFF + $DEPTH_DIFF) / 2" | bc -l)

    # Update last check
    jq --arg timestamp "$TIMESTAMP" \
       '.last_check = $timestamp' \
       "$DRIFT_DATA" > "${DRIFT_DATA}.tmp" && mv "${DRIFT_DATA}.tmp" "$DRIFT_DATA"

    # Check if drift exceeds threshold
    if (( $(echo "$DRIFT_SCORE >= $THRESHOLD" | bc -l) )); then
      DRIFT_ID=$(date +%s%N | md5sum | cut -d' ' -f1 | cut -c1-8)

      # Record drift event
      jq --arg id "$DRIFT_ID" \
         --arg score "$DRIFT_SCORE" \
         --arg timestamp "$TIMESTAMP" \
         '
         .drift_events += [{
           "id": $id,
           "drift_score": ($score | tonumber),
           "timestamp": $timestamp,
           "action_taken": "preference_reset_suggested"
         }] |
         .drift_events = (.drift_events[-20:])
         ' \
         "$DRIFT_DATA" > "${DRIFT_DATA}.tmp" && mv "${DRIFT_DATA}.tmp" "$DRIFT_DATA"

      echo "drift_detected (score: $DRIFT_SCORE, threshold: $THRESHOLD, id: $DRIFT_ID)"
      echo ""
      echo "⚠️  Significant preference drift detected!"
      echo ""
      echo "Your preferences seem to have changed significantly."
      echo "This could be due to:"
      echo "  • Working on a different type of project"
      echo "  • Learning new technologies"
      echo "  • Changed communication preferences"
      echo "  • Career transition"
      echo ""
      echo "Recommendation: Run '/adaptive-intelligence configure' to review settings"
      echo ""
    else
      echo "no_drift (score: $DRIFT_SCORE, threshold: $THRESHOLD)"
    fi
    ;;

  stats)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║             Preference Drift Statistics                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    SNAPSHOT_COUNT=$(jq -r '.preference_snapshots | length' "$DRIFT_DATA")
    DRIFT_COUNT=$(jq -r '.drift_events | length' "$DRIFT_DATA")
    LAST_CHECK=$(jq -r '.last_check // "never"' "$DRIFT_DATA")
    THRESHOLD=$(jq -r '.drift_threshold' "$DRIFT_DATA")

    echo "Preference snapshots: $SNAPSHOT_COUNT"
    echo "Drift events detected: $DRIFT_COUNT"
    echo "Last check: $LAST_CHECK"
    echo "Drift threshold: $THRESHOLD"
    echo ""

    if [[ $SNAPSHOT_COUNT -gt 0 ]]; then
      echo "Snapshot timeline:"
      jq -r '
        .preference_snapshots |
        .[] |
        "  [\(.timestamp | split("T")[0])] Interactions: \(.interaction_count), Stage: \(.learning_stage)"
      ' "$DRIFT_DATA"
      echo ""
    fi

    if [[ $DRIFT_COUNT -gt 0 ]]; then
      echo "Drift events:"
      jq -r '
        .drift_events |
        .[] |
        "  [\(.timestamp | split("T")[0])] Score: \(.drift_score | tostring | .[0:4]), Action: \(.action_taken)"
      ' "$DRIFT_DATA"
      echo ""
    fi
    ;;

  set-threshold)
    # Adjust drift detection threshold
    THRESHOLD="${2:-0.30}"

    jq --arg thresh "$THRESHOLD" \
       '.drift_threshold = ($thresh | tonumber)' \
       "$DRIFT_DATA" > "${DRIFT_DATA}.tmp" && mv "${DRIFT_DATA}.tmp" "$DRIFT_DATA"

    echo "Drift threshold set to: $THRESHOLD"
    echo "(Lower = more sensitive to changes, Higher = less sensitive)"
    ;;

  reset-baseline)
    # Reset baseline (use current preferences as new baseline)
    echo "Resetting baseline to current preferences..."

    # Take new snapshot
    "$0" snapshot

    # Clear old drift events
    jq '.drift_events = []' \
       "$DRIFT_DATA" > "${DRIFT_DATA}.tmp" && mv "${DRIFT_DATA}.tmp" "$DRIFT_DATA"

    echo "Baseline reset complete"
    ;;

  *)
    echo "Usage: $0 {snapshot|check|stats|set-threshold <value>|reset-baseline}"
    exit 1
    ;;
esac

exit 0
