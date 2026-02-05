#!/usr/bin/env bash
# track-error-patterns.sh - Learn from errors and corrections
# Part of Adaptive Learning System v1.2 - Phase 2 Improvements

set -euo pipefail

ERROR_PATTERNS="$HOME/.claude/data/error-patterns.json"

# Initialize error patterns if doesn't exist
if [[ ! -f "$ERROR_PATTERNS" ]]; then
  cat > "$ERROR_PATTERNS" <<'EOF'
{
  "version": "1.0.0",
  "patterns": {},
  "categories": {
    "authentication": [],
    "database": [],
    "api": [],
    "configuration": [],
    "logic": [],
    "performance": [],
    "security": []
  },
  "corrections": [],
  "total_tracked": 0
}
EOF
fi

COMMAND="${1:-track}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$COMMAND" in
  track)
    # Track an error or correction
    ERROR_TYPE="${2:-general}"
    DESCRIPTION="${3:-No description provided}"
    RESOLUTION="${4:-}"

    ERROR_ID=$(echo "$DESCRIPTION" | md5sum | cut -d' ' -f1 | cut -c1-8)

    # Check if this error pattern exists
    if jq -e ".patterns.\"$ERROR_ID\"" "$ERROR_PATTERNS" > /dev/null 2>&1; then
      # Update existing pattern
      jq --arg id "$ERROR_ID" \
         --arg timestamp "$TIMESTAMP" \
         --arg resolution "$RESOLUTION" \
         '
         .patterns[$id].occurrences += 1 |
         .patterns[$id].last_seen = $timestamp |
         (if $resolution != "" then
           .patterns[$id].resolutions += [$resolution] |
           .patterns[$id].resolutions |= unique |
           .patterns[$id].resolved_count += 1
         else . end)
         ' \
         "$ERROR_PATTERNS" > "${ERROR_PATTERNS}.tmp" && mv "${ERROR_PATTERNS}.tmp" "$ERROR_PATTERNS"

      echo "Updated existing error pattern: $ERROR_ID"
    else
      # Create new pattern
      jq --arg id "$ERROR_ID" \
         --arg type "$ERROR_TYPE" \
         --arg desc "$DESCRIPTION" \
         --arg timestamp "$TIMESTAMP" \
         --arg resolution "$RESOLUTION" \
         '
         .patterns[$id] = {
           "type": $type,
           "description": $desc,
           "first_seen": $timestamp,
           "last_seen": $timestamp,
           "occurrences": 1,
           "resolved_count": (if $resolution != "" then 1 else 0 end),
           "resolutions": (if $resolution != "" then [$resolution] else [] end),
           "confidence": 0.5
         } |
         .categories[$type] += [$id] |
         .total_tracked += 1
         ' \
         "$ERROR_PATTERNS" > "${ERROR_PATTERNS}.tmp" && mv "${ERROR_PATTERNS}.tmp" "$ERROR_PATTERNS"

      echo "Tracked new error pattern: $ERROR_ID"
    fi

    # If resolution provided, add to corrections
    if [[ -n "$RESOLUTION" ]]; then
      jq --arg id "$ERROR_ID" \
         --arg desc "$DESCRIPTION" \
         --arg resolution "$RESOLUTION" \
         --arg timestamp "$TIMESTAMP" \
         '
         .corrections += [{
           "pattern_id": $id,
           "description": $desc,
           "resolution": $resolution,
           "timestamp": $timestamp
         }] |
         .corrections = (.corrections[-100:])
         ' \
         "$ERROR_PATTERNS" > "${ERROR_PATTERNS}.tmp" && mv "${ERROR_PATTERNS}.tmp" "$ERROR_PATTERNS"
    fi
    ;;

  correction)
    # Record a user correction (when user fixes Claude's suggestion)
    ORIGINAL="${2:-}"
    CORRECTED="${3:-}"
    CONTEXT="${4:-general}"

    if [[ -z "$ORIGINAL" ]] || [[ -z "$CORRECTED" ]]; then
      echo "Error: Both original and corrected versions required"
      exit 1
    fi

    CORRECTION_ID=$(date +%s%N | md5sum | cut -d' ' -f1 | cut -c1-8)

    jq --arg id "$CORRECTION_ID" \
       --arg original "$ORIGINAL" \
       --arg corrected "$CORRECTED" \
       --arg context "$CONTEXT" \
       --arg timestamp "$TIMESTAMP" \
       '
       .corrections += [{
         "correction_id": $id,
         "original": $original,
         "corrected": $corrected,
         "context": $context,
         "timestamp": $timestamp,
         "type": "user_correction"
       }] |
       .corrections = (.corrections[-100:]) |
       .total_tracked += 1
       ' \
       "$ERROR_PATTERNS" > "${ERROR_PATTERNS}.tmp" && mv "${ERROR_PATTERNS}.tmp" "$ERROR_PATTERNS"

    echo "Recorded user correction: $CORRECTION_ID"
    ;;

  search)
    # Search for similar error patterns
    QUERY="${2:-}"

    if [[ -z "$QUERY" ]]; then
      echo "Error: Search query required"
      exit 1
    fi

    echo ""
    echo "🔍 Searching for patterns matching: $QUERY"
    echo ""

    # Simple grep-based search (could be enhanced with fuzzy matching)
    jq -r --arg query "$QUERY" '
      .patterns |
      to_entries |
      map(select(.value.description | ascii_downcase | contains($query | ascii_downcase))) |
      .[] |
      "Pattern: \(.key)\n" +
      "  Type: \(.value.type)\n" +
      "  Description: \(.value.description)\n" +
      "  Occurrences: \(.value.occurrences)\n" +
      "  Resolutions: \(.value.resolutions | join(", "))\n"
    ' "$ERROR_PATTERNS"
    ;;

  category)
    # Show errors by category
    CATEGORY="${2:-all}"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              Error Patterns by Category                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$CATEGORY" == "all" ]]; then
      for cat in authentication database api configuration logic performance security; do
        COUNT=$(jq -r ".categories.$cat | length" "$ERROR_PATTERNS")
        if [[ $COUNT -gt 0 ]]; then
          echo "$cat: $COUNT patterns"
          jq -r --arg cat "$cat" '
            .categories[$cat][] as $id |
            .patterns[$id] |
            "  • \(.description) (\(.occurrences) times)"
          ' "$ERROR_PATTERNS"
          echo ""
        fi
      done
    else
      COUNT=$(jq -r ".categories.$CATEGORY | length" "$ERROR_PATTERNS")
      echo "$CATEGORY: $COUNT patterns"
      jq -r --arg cat "$CATEGORY" '
        .categories[$cat][] as $id |
        .patterns[$id] |
        "  • \(.description)\n" +
        "    Occurrences: \(.occurrences)\n" +
        "    Resolutions: \(.resolutions | join(", "))\n"
      ' "$ERROR_PATTERNS"
    fi
    ;;

  stats)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              Error Pattern Statistics                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    TOTAL=$(jq -r '.total_tracked // 0' "$ERROR_PATTERNS")
    PATTERN_COUNT=$(jq -r '.patterns | length' "$ERROR_PATTERNS")
    CORRECTION_COUNT=$(jq -r '.corrections | length' "$ERROR_PATTERNS")

    echo "Total patterns tracked: $TOTAL"
    echo "Unique patterns: $PATTERN_COUNT"
    echo "Corrections recorded: $CORRECTION_COUNT"
    echo ""

    echo "Top 5 Most Common Errors:"
    jq -r '
      .patterns |
      to_entries |
      sort_by(-.value.occurrences) |
      .[0:5] |
      .[] |
      "  \(.value.occurrences)x: \(.value.description)"
    ' "$ERROR_PATTERNS"
    echo ""

    echo "Category Distribution:"
    for cat in authentication database api configuration logic performance security; do
      COUNT=$(jq -r ".categories.$cat | length" "$ERROR_PATTERNS")
      [[ $COUNT -gt 0 ]] && echo "  $cat: $COUNT"
    done
    echo ""
    ;;

  *)
    echo "Usage: $0 {track <type> <description> [resolution]|correction <original> <corrected> [context]|search <query>|category [category]|stats}"
    exit 1
    ;;
esac

exit 0
