#!/usr/bin/env bash
# multi-armed-bandit.sh - Explore/exploit different response strategies
# Part of Adaptive Learning System v1.2 - Phase 2 Improvements

set -euo pipefail

MAB_DATA="$HOME/.claude/data/multi-armed-bandit.json"
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"

# Initialize MAB data if doesn't exist
if [[ ! -f "$MAB_DATA" ]]; then
  cat > "$MAB_DATA" <<'EOF'
{
  "version": "1.0.0",
  "strategies": {
    "verbose_detailed": {
      "description": "Detailed explanations with context",
      "tries": 0,
      "successes": 0,
      "total_reward": 0,
      "avg_reward": 0,
      "confidence_bound": 999
    },
    "concise_direct": {
      "description": "Brief, to-the-point responses",
      "tries": 0,
      "successes": 0,
      "total_reward": 0,
      "avg_reward": 0,
      "confidence_bound": 999
    },
    "code_first": {
      "description": "Code examples before explanation",
      "tries": 0,
      "successes": 0,
      "total_reward": 0,
      "avg_reward": 0,
      "confidence_bound": 999
    },
    "theory_first": {
      "description": "Explanation before code",
      "tries": 0,
      "successes": 0,
      "total_reward": 0,
      "avg_reward": 0,
      "confidence_bound": 999
    },
    "examples_heavy": {
      "description": "Multiple examples and use cases",
      "tries": 0,
      "successes": 0,
      "total_reward": 0,
      "avg_reward": 0,
      "confidence_bound": 999
    },
    "diagrams_visual": {
      "description": "Visual representations and diagrams",
      "tries": 0,
      "successes": 0,
      "total_reward": 0,
      "avg_reward": 0,
      "confidence_bound": 999
    }
  },
  "exploration_rate": 0.1,
  "total_selections": 0,
  "best_strategy": null
}
EOF
fi

COMMAND="${1:-select}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$COMMAND" in
  select)
    # Select strategy using Upper Confidence Bound (UCB1) algorithm
    REQUEST_TYPE="${2:-general}"

    # Get total selections across all strategies
    TOTAL_SELECTIONS=$(jq -r '.total_selections // 0' "$MAB_DATA")

    if [[ $TOTAL_SELECTIONS -lt 6 ]]; then
      # Initial exploration: try each strategy once
      STRATEGY=$(jq -r '.strategies | to_entries | map(select(.value.tries == 0)) | .[0].key // "verbose_detailed"' "$MAB_DATA")
      echo "initial_exploration"
    else
      # Calculate UCB1 scores for each strategy
      EXPLORATION_RATE=$(jq -r '.exploration_rate // 0.1' "$MAB_DATA")

      # Decide: explore or exploit?
      RANDOM_VALUE=$(echo "scale=2; $RANDOM / 32767" | bc -l)

      if (( $(echo "$RANDOM_VALUE < $EXPLORATION_RATE" | bc -l) )); then
        # Explore: pick random strategy
        STRATEGY=$(jq -r '.strategies | keys | .['$(($RANDOM % 6))']' "$MAB_DATA")
        echo "exploration"
      else
        # Exploit: pick best UCB1 score
        STRATEGY=$(jq -r --arg total "$TOTAL_SELECTIONS" '
          .strategies |
          to_entries |
          map({
            key: .key,
            ucb: (
              if .value.tries > 0 then
                .value.avg_reward + (2 * (($total | tonumber | log) / .value.tries) | sqrt)
              else
                999
              end
            )
          }) |
          max_by(.ucb) |
          .key
        ' "$MAB_DATA")
        echo "exploitation"
      fi
    fi

    # Output selected strategy details
    jq -r --arg strategy "$STRATEGY" '
      .strategies[$strategy] |
      {
        strategy: $strategy,
        description: .description,
        tries: .tries,
        avg_reward: .avg_reward,
        mode: "ucb1"
      }
    ' "$MAB_DATA"
    ;;

  record)
    # Record result of strategy
    STRATEGY="${2}"
    REWARD="${3:-0}"  # Feedback score: -1 to 1

    if [[ -z "$STRATEGY" ]]; then
      echo "Error: Strategy name required"
      exit 1
    fi

    # Update strategy statistics
    jq --arg strategy "$STRATEGY" \
       --arg reward "$REWARD" \
       --arg timestamp "$TIMESTAMP" \
       '
       .strategies[$strategy].tries += 1 |
       .strategies[$strategy].total_reward += ($reward | tonumber) |
       .strategies[$strategy].avg_reward = (
         .strategies[$strategy].total_reward / .strategies[$strategy].tries
       ) |
       .strategies[$strategy].last_used = $timestamp |
       .total_selections += 1 |
       (if ($reward | tonumber) > 0 then
         .strategies[$strategy].successes += 1
       else . end)
       ' \
       "$MAB_DATA" > "${MAB_DATA}.tmp" && mv "${MAB_DATA}.tmp" "$MAB_DATA"

    # Update best strategy
    BEST_STRATEGY=$(jq -r '
      .strategies |
      to_entries |
      max_by(.value.avg_reward) |
      .key
    ' "$MAB_DATA")

    jq --arg best "$BEST_STRATEGY" \
       '.best_strategy = $best' \
       "$MAB_DATA" > "${MAB_DATA}.tmp" && mv "${MAB_DATA}.tmp" "$MAB_DATA"

    echo "Strategy '$STRATEGY' updated: reward=$REWARD"
    ;;

  stats)
    # Show statistics for all strategies
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║         Multi-Armed Bandit Strategy Performance                 ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    BEST=$(jq -r '.best_strategy // "none"' "$MAB_DATA")
    TOTAL=$(jq -r '.total_selections' "$MAB_DATA")

    echo "Best Strategy: $BEST"
    echo "Total Selections: $TOTAL"
    echo ""
    echo "Strategy Performance:"
    echo "────────────────────────────────────────────────────────────────"

    jq -r '
      .strategies |
      to_entries |
      sort_by(-.value.avg_reward) |
      .[] |
      "  \(.key | . + (" " * (20 - length))): \(.value.tries) tries, avg reward: \(.value.avg_reward | tostring | .[0:5]), success rate: \(
        if .value.tries > 0 then
          ((.value.successes / .value.tries * 100) | tostring | .[0:5]) + "%"
        else
          "N/A"
        end
      )"
    ' "$MAB_DATA"

    echo ""
    ;;

  best)
    # Return best performing strategy
    BEST=$(jq -r '.best_strategy // "verbose_detailed"' "$MAB_DATA")
    DETAILS=$(jq -r --arg strategy "$BEST" '.strategies[$strategy]' "$MAB_DATA")

    echo "Best strategy: $BEST"
    echo "$DETAILS" | jq .
    ;;

  reset)
    # Reset all statistics (keep structure)
    jq '
      .strategies |= map_values({
        description: .description,
        tries: 0,
        successes: 0,
        total_reward: 0,
        avg_reward: 0,
        confidence_bound: 999
      }) |
      .total_selections = 0 |
      .best_strategy = null
    ' "$MAB_DATA" > "${MAB_DATA}.tmp" && mv "${MAB_DATA}.tmp" "$MAB_DATA"

    echo "Multi-Armed Bandit statistics reset"
    ;;

  *)
    echo "Usage: $0 {select|record <strategy> <reward>|stats|best|reset}"
    exit 1
    ;;
esac

exit 0
