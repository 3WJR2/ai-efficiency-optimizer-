#!/usr/bin/env bash
# rlhf-lite.sh - Reinforcement Learning from Human Feedback (lightweight)
# Part of Adaptive Learning System v1.3 - Phase 3 Advanced Features

set -euo pipefail

RLHF_DATA="$HOME/.claude/data/rlhf-lite.json"
FEEDBACK_LOG="$HOME/.claude/data/feedback-log.jsonl"

# Initialize RLHF data if doesn't exist
if [[ ! -f "$RLHF_DATA" ]]; then
  cat > "$RLHF_DATA" <<'EOF'
{
  "version": "1.0.0",
  "state_action_values": {},
  "policy": {
    "exploration_rate": 0.15,
    "learning_rate": 0.1,
    "discount_factor": 0.95
  },
  "reward_model": {
    "excellent_response": 1.0,
    "good_response": 0.7,
    "acceptable_response": 0.3,
    "poor_response": -0.5,
    "user_correction": -1.0
  },
  "episode_history": [],
  "total_episodes": 0,
  "avg_reward": 0
}
EOF
fi

COMMAND="${1:-update}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

calculate_reward() {
  local feedback_score="$1"
  local user_modified="$2"
  local user_rejected="$3"

  local reward=0

  # Base reward from feedback
  if (( $(echo "$feedback_score >= 0.8" | bc -l) )); then
    reward=1.0  # Excellent
  elif (( $(echo "$feedback_score >= 0.6" | bc -l) )); then
    reward=0.7  # Good
  elif (( $(echo "$feedback_score >= 0.3" | bc -l) )); then
    reward=0.3  # Acceptable
  elif (( $(echo "$feedback_score >= 0" | bc -l) )); then
    reward=-0.5  # Poor
  else
    reward=-1.0  # User correction needed
  fi

  # Penalty for user having to modify
  if [[ "$user_modified" == "true" ]]; then
    reward=$(echo "$reward - 0.2" | bc -l)
  fi

  # Strong penalty for rejection
  if [[ "$user_rejected" == "true" ]]; then
    reward=-1.0
  fi

  echo "$reward"
}

case "$COMMAND" in
  update)
    # Update policy based on recent feedback
    STATE="${2:-general}"
    ACTION="${3:-verbose_detailed}"
    FEEDBACK_SCORE="${4:-0.5}"
    USER_MODIFIED="${5:-false}"
    USER_REJECTED="${6:-false}"

    # Calculate reward
    REWARD=$(calculate_reward "$FEEDBACK_SCORE" "$USER_MODIFIED" "$USER_REJECTED")

    # Get current Q-value
    STATE_ACTION="${STATE}_${ACTION}"
    CURRENT_Q=$(jq -r ".state_action_values.\"$STATE_ACTION\" // 0" "$RLHF_DATA")

    # Q-learning update: Q(s,a) = Q(s,a) + α[R + γ·max(Q(s',a')) - Q(s,a)]
    LEARNING_RATE=$(jq -r '.policy.learning_rate' "$RLHF_DATA")

    # Simplified update (no next state for now)
    NEW_Q=$(echo "$CURRENT_Q + $LEARNING_RATE * ($REWARD - $CURRENT_Q)" | bc -l)

    # Update Q-value
    jq --arg sa "$STATE_ACTION" \
       --arg newq "$NEW_Q" \
       --arg reward "$REWARD" \
       --arg timestamp "$TIMESTAMP" \
       '
       .state_action_values[$sa] = ($newq | tonumber) |
       .episode_history += [{
         "state": $sa,
         "reward": ($reward | tonumber),
         "timestamp": $timestamp
       }] |
       .episode_history = (.episode_history[-100:]) |
       .total_episodes += 1
       ' \
       "$RLHF_DATA" > "${RLHF_DATA}.tmp" && mv "${RLHF_DATA}.tmp" "$RLHF_DATA"

    # Update average reward
    TOTAL_REWARD=$(jq -r '[.episode_history[].reward] | add // 0' "$RLHF_DATA")
    EPISODE_COUNT=$(jq -r '.total_episodes // 1' "$RLHF_DATA")
    AVG_REWARD=$(echo "scale=3; $TOTAL_REWARD / $EPISODE_COUNT" | bc -l)

    jq --arg avg "$AVG_REWARD" \
       '.avg_reward = ($avg | tonumber)' \
       "$RLHF_DATA" > "${RLHF_DATA}.tmp" && mv "${RLHF_DATA}.tmp" "$RLHF_DATA"

    echo "RLHF policy updated: reward=$REWARD, new_Q=$NEW_Q, avg_reward=$AVG_REWARD"
    ;;

  select-action)
    # Select best action for given state using ε-greedy policy
    STATE="${2:-general}"

    EXPLORATION_RATE=$(jq -r '.policy.exploration_rate' "$RLHF_DATA")
    RANDOM_VALUE=$(echo "scale=2; $RANDOM / 32767" | bc -l)

    if (( $(echo "$RANDOM_VALUE < $EXPLORATION_RATE" | bc -l) )); then
      # Explore: random action
      ACTIONS=("verbose_detailed" "concise_direct" "code_first" "theory_first" "examples_heavy" "diagrams_visual")
      SELECTED="${ACTIONS[$((RANDOM % 6))]}"
      echo "$SELECTED (exploration)"
    else
      # Exploit: best known action
      BEST_ACTION=$(jq -r --arg state "$STATE" '
        .state_action_values |
        to_entries |
        map(select(.key | startswith($state + "_"))) |
        max_by(.value) |
        .key |
        sub($state + "_"; "")
      ' "$RLHF_DATA" 2>/dev/null || echo "verbose_detailed")

      echo "$BEST_ACTION (exploitation)"
    fi
    ;;

  get-policy)
    # Get current policy (best action for each state)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                Current RLHF Policy                               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    TOTAL=$(jq -r '.total_episodes // 0' "$RLHF_DATA")
    AVG=$(jq -r '.avg_reward // 0' "$RLHF_DATA")

    echo "Total episodes: $TOTAL"
    echo "Average reward: $AVG"
    echo ""

    echo "Learned Q-Values (State-Action pairs):"
    jq -r '
      .state_action_values |
      to_entries |
      sort_by(-.value) |
      .[] |
      "  \(.key): \(.value | tostring | .[0:6])"
    ' "$RLHF_DATA"
    echo ""
    ;;

  stats)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              RLHF Learning Statistics                            ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    TOTAL=$(jq -r '.total_episodes // 0' "$RLHF_DATA")
    AVG=$(jq -r '.avg_reward // 0' "$RLHF_DATA")
    LEARNING_RATE=$(jq -r '.policy.learning_rate' "$RLHF_DATA")
    EXPLORATION=$(jq -r '.policy.exploration_rate' "$RLHF_DATA")

    echo "Episodes: $TOTAL"
    echo "Average reward: $AVG"
    echo "Learning rate: $LEARNING_RATE"
    echo "Exploration rate: $EXPLORATION"
    echo ""

    if [[ $TOTAL -gt 0 ]]; then
      echo "Recent episode rewards (last 10):"
      jq -r '
        .episode_history[-10:] |
        .[] |
        "  \(.timestamp | split("T")[0]): \(.reward | tostring | .[0:5])"
      ' "$RLHF_DATA"
    fi
    echo ""
    ;;

  tune)
    # Adjust hyperparameters
    PARAM="${2}"
    VALUE="${3}"

    case "$PARAM" in
      exploration|exploration_rate)
        jq --arg val "$VALUE" \
           '.policy.exploration_rate = ($val | tonumber)' \
           "$RLHF_DATA" > "${RLHF_DATA}.tmp" && mv "${RLHF_DATA}.tmp" "$RLHF_DATA"
        echo "Exploration rate set to: $VALUE"
        ;;
      learning|learning_rate)
        jq --arg val "$VALUE" \
           '.policy.learning_rate = ($val | tonumber)' \
           "$RLHF_DATA" > "${RLHF_DATA}.tmp" && mv "${RLHF_DATA}.tmp" "$RLHF_DATA"
        echo "Learning rate set to: $VALUE"
        ;;
      discount|discount_factor)
        jq --arg val "$VALUE" \
           '.policy.discount_factor = ($val | tonumber)' \
           "$RLHF_DATA" > "${RLHF_DATA}.tmp" && mv "${RLHF_DATA}.tmp" "$RLHF_DATA"
        echo "Discount factor set to: $VALUE"
        ;;
      *)
        echo "Unknown parameter: $PARAM"
        echo "Available: exploration_rate, learning_rate, discount_factor"
        exit 1
        ;;
    esac
    ;;

  *)
    echo "Usage: $0 {update <state> <action> <feedback> [modified] [rejected]|select-action <state>|get-policy|stats|tune <param> <value>}"
    exit 1
    ;;
esac

exit 0
