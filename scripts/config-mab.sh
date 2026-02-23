#!/usr/bin/env bash
# config-mab.sh - Multi-Armed Bandit for configuration optimization
# Continuously A/B tests different cache/parallel configurations
# Part of Phase 3B - High Impact Improvements

set -euo pipefail

MAB_DATA="$HOME/.claude/data/config-mab-data.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"
LEARNING_DATA="$HOME/.claude/data/learning-data.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize MAB data
initialize_mab() {
  if [[ ! -f "$MAB_DATA" ]]; then
    cat > "$MAB_DATA" <<'EOF'
{
  "version": "1.0.0",
  "algorithm": "thompson_sampling",
  "arms": {
    "conservative": {
      "description": "Conservative: High cache threshold, low concurrency",
      "config": {"cache_threshold": 0.88, "max_concurrent": 3},
      "successes": 1,
      "failures": 1,
      "total_pulls": 0,
      "avg_reward": 0.0,
      "last_pulled": null
    },
    "balanced": {
      "description": "Balanced: Medium settings",
      "config": {"cache_threshold": 0.80, "max_concurrent": 5},
      "successes": 1,
      "failures": 1,
      "total_pulls": 0,
      "avg_reward": 0.0,
      "last_pulled": null
    },
    "aggressive": {
      "description": "Aggressive: Low cache threshold, high concurrency",
      "config": {"cache_threshold": 0.70, "max_concurrent": 7},
      "successes": 1,
      "failures": 1,
      "total_pulls": 0,
      "avg_reward": 0.0,
      "last_pulled": null
    },
    "quality_focused": {
      "description": "Quality: High threshold, moderate concurrency",
      "config": {"cache_threshold": 0.92, "max_concurrent": 4},
      "successes": 1,
      "failures": 1,
      "total_pulls": 0,
      "avg_reward": 0.0,
      "last_pulled": null
    },
    "speed_focused": {
      "description": "Speed: Low threshold, high concurrency",
      "config": {"cache_threshold": 0.65, "max_concurrent": 8},
      "successes": 1,
      "failures": 1,
      "total_pulls": 0,
      "avg_reward": 0.0,
      "last_pulled": null
    }
  },
  "current_arm": null,
  "exploration_rate": 0.1,
  "min_pulls_per_arm": 5,
  "evaluation_window": 10,
  "reward_history": [],
  "best_arm": null,
  "enabled": true
}
EOF
  fi
}

# Select arm using Thompson Sampling
select_arm_thompson() {
  echo -e "${BLUE}Selecting arm using Thompson Sampling...${NC}"

  local selected=$(python3 <<'PYEOF'
import json
import random

with open('/Users/wallonwalusayi/.claude/data/config-mab-data.json') as f:
    data = json.load(f)

arms = data['arms']
min_pulls = data['min_pulls_per_arm']

# Ensure minimum exploration
needs_exploration = [name for name, arm in arms.items() if arm['total_pulls'] < min_pulls]

if needs_exploration:
    selected = random.choice(needs_exploration)
    print(json.dumps({'arm': selected, 'method': 'forced_exploration'}))
else:
    # Thompson Sampling
    samples = {}
    for name, arm in arms.items():
        sample = random.betavariate(arm['successes'], arm['failures'])
        samples[name] = sample
    selected = max(samples.items(), key=lambda x: x[1])
    print(json.dumps({'arm': selected[0], 'method': 'thompson_sampling', 'sample_value': selected[1]}))
PYEOF
)

  local arm=$(echo "$selected" | jq -r '.arm')
  echo -e "${GREEN}✓ Selected arm: $arm${NC}"

  # Update current arm
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg arm "$arm" --arg ts "$now" '.current_arm = $arm | .arms[$arm].last_pulled = $ts' "$MAB_DATA" > "$MAB_DATA.tmp"
  mv "$MAB_DATA.tmp" "$MAB_DATA"

  echo "$arm"
}

# Apply arm configuration
apply_arm_config() {
  local arm="${1:-$(jq -r '.current_arm' "$MAB_DATA")}"

  if [[ "$arm" == "null" ]] || [[ -z "$arm" ]]; then
    echo -e "${RED}No arm selected${NC}"
    return 1
  fi

  echo -e "${BLUE}Applying configuration for arm: $arm${NC}"

  local cache_threshold=$(jq -r --arg arm "$arm" '.arms[$arm].config.cache_threshold' "$MAB_DATA")
  local max_concurrent=$(jq -r --arg arm "$arm" '.arms[$arm].config.max_concurrent' "$MAB_DATA")

  jq --argjson threshold "$cache_threshold" '.similarity_threshold = $threshold' "$CACHE_CONFIG" > "$CACHE_CONFIG.tmp"
  mv "$CACHE_CONFIG.tmp" "$CACHE_CONFIG"

  jq --argjson concurrent "$max_concurrent" '.max_concurrent_processes = $concurrent' "$PARALLEL_CONFIG" > "$PARALLEL_CONFIG.tmp"
  mv "$PARALLEL_CONFIG.tmp" "$PARALLEL_CONFIG"

  jq --arg arm "$arm" '.arms[$arm].total_pulls += 1' "$MAB_DATA" > "$MAB_DATA.tmp"
  mv "$MAB_DATA.tmp" "$MAB_DATA"

  echo -e "${GREEN}✓ Configuration applied${NC}"
  echo "  Cache threshold: $cache_threshold"
  echo "  Max concurrent: $max_concurrent"
}

# Update reward
update_reward() {
  local arm="${1:-$(jq -r '.current_arm' "$MAB_DATA")}"

  if [[ "$arm" == "null" ]] || [[ -z "$arm" ]]; then
    echo -e "${RED}No arm to update${NC}"
    return 1
  fi

  echo -e "${BLUE}Updating reward for arm: $arm${NC}"

  [[ ! -f "$LEARNING_DATA" ]] && { echo "No learning data"; return 1; }

  local reward=$(python3 <<'PYEOF'
import json

with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
    data = json.load(f)

cache_history = data.get('cache_outcomes', {}).get('hit_rate_history', [])[-5:]
success_history = data.get('parallel_outcomes', {}).get('success_rate_history', [])[-5:]

if not cache_history or not success_history:
    print(0.5)
    exit(0)

avg_hit_rate = sum(s.get('hit_rate', 0) for s in cache_history) / len(cache_history)
avg_success = sum(s.get('success_rate', 0) for s in success_history) / len(success_history) / 100.0

reward = (0.5 * avg_hit_rate) + (0.5 * avg_success)
print(reward)
PYEOF
)

  echo "  Reward: $reward"

  local is_success=$(python3 -c "print('true' if $reward >= 0.5 else 'false')")

  if [[ "$is_success" == "true" ]]; then
    jq --arg arm "$arm" --argjson reward "$reward" \
       '.arms[$arm].successes += 1 | .arms[$arm].avg_reward = ((.arms[$arm].avg_reward * (.arms[$arm].total_pulls - 1) + $reward) / .arms[$arm].total_pulls)' \
       "$MAB_DATA" > "$MAB_DATA.tmp"
    echo -e "${GREEN}✓ Success${NC}"
  else
    jq --arg arm "$arm" --argjson reward "$reward" \
       '.arms[$arm].failures += 1 | .arms[$arm].avg_reward = ((.arms[$arm].avg_reward * (.arms[$arm].total_pulls - 1) + $reward) / .arms[$arm].total_pulls)' \
       "$MAB_DATA" > "$MAB_DATA.tmp"
    echo -e "${YELLOW}Failure${NC}"
  fi
  mv "$MAB_DATA.tmp" "$MAB_DATA"

  # Update best arm
  local best=$(python3 <<'PYEOF'
import json

with open('/Users/wallonwalusayi/.claude/data/config-mab-data.json') as f:
    data = json.load(f)

arms = data['arms']
eligible = {n: a for n, a in arms.items() if a['total_pulls'] >= data['min_pulls_per_arm']}

if eligible:
    best = max(eligible.items(), key=lambda x: x[1]['avg_reward'])
    print(best[0])
else:
    print('null')
PYEOF
)

  if [[ "$best" != "null" ]]; then
    jq --arg arm "$best" '.best_arm = $arm' "$MAB_DATA" > "$MAB_DATA.tmp"
    mv "$MAB_DATA.tmp" "$MAB_DATA"
  fi
}

# Run cycle
run_cycle() {
  echo -e "${BLUE}=== Running Config MAB Cycle ===${NC}"
  echo

  local enabled=$(jq -r '.enabled' "$MAB_DATA")
  [[ "$enabled" != "true" ]] && { echo "MAB disabled"; return 1; }

  local arm=$(select_arm_thompson)
  echo
  apply_arm_config "$arm"
  echo
  echo -e "${YELLOW}Run workload, then: $0 update-reward${NC}"
}

# Show status
show_status() {
  echo -e "${BLUE}=== Config MAB Status ===${NC}"
  echo

  local enabled=$(jq -r '.enabled' "$MAB_DATA")
  local current=$(jq -r '.current_arm' "$MAB_DATA")
  local best=$(jq -r '.best_arm' "$MAB_DATA")

  echo "Enabled: $enabled"
  echo "Current arm: $current"
  echo "Best arm: $best"
  echo

  jq -r '.arms | to_entries | sort_by(-.value.avg_reward) | .[] | "  \(.key):\n    Reward: \(.value.avg_reward | . * 100 | floor)%\n    Pulls: \(.value.total_pulls)\n"' "$MAB_DATA"
}

# Main
case "${1:-}" in
  init) initialize_mab && echo -e "${GREEN}✓ Config MAB initialized${NC}" ;;
  select) initialize_mab && select_arm_thompson ;;
  apply) initialize_mab && apply_arm_config "${2:-}" ;;
  update-reward) initialize_mab && update_reward "${2:-}" ;;
  cycle) initialize_mab && run_cycle ;;
  status) initialize_mab && show_status ;;
  enable) initialize_mab && jq '.enabled = true' "$MAB_DATA" > "$MAB_DATA.tmp" && mv "$MAB_DATA.tmp" "$MAB_DATA" && echo -e "${GREEN}✓ Enabled${NC}" ;;
  disable) initialize_mab && jq '.enabled = false' "$MAB_DATA" > "$MAB_DATA.tmp" && mv "$MAB_DATA.tmp" "$MAB_DATA" && echo -e "${YELLOW}Disabled${NC}" ;;
  *)
    echo "Usage: $0 {init|select|apply|update-reward|cycle|status|enable|disable}"
    exit 1
    ;;
esac
