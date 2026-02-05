#!/usr/bin/env bash
# workload-classifier.sh - Classify workload types and apply optimal configs
# Different workloads need different optimizations

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
WORKLOAD_DATA="$HOME/.claude/data/workload-data.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize workload data
initialize_workload_data() {
  if [[ ! -f "$WORKLOAD_DATA" ]]; then
    cat > "$WORKLOAD_DATA" <<'EOF'
{
  "version": "1.0.0",
  "workload_types": {
    "exploration": {
      "description": "Code exploration, file searching, understanding codebase",
      "optimal_cache_threshold": 0.75,
      "optimal_max_concurrent": 6,
      "characteristics": ["glob", "grep", "read", "search", "find", "explore"]
    },
    "research": {
      "description": "Documentation research, web fetching, learning",
      "optimal_cache_threshold": 0.88,
      "optimal_max_concurrent": 4,
      "characteristics": ["webfetch", "websearch", "docs", "research", "documentation"]
    },
    "implementation": {
      "description": "Writing code, editing files, creating features",
      "optimal_cache_threshold": 0.70,
      "optimal_max_concurrent": 3,
      "characteristics": ["write", "edit", "implement", "create", "modify", "refactor"]
    },
    "testing": {
      "description": "Running tests, validation, verification",
      "optimal_cache_threshold": 0.92,
      "optimal_max_concurrent": 5,
      "characteristics": ["test", "verify", "validate", "check", "assert"]
    },
    "debugging": {
      "description": "Investigating issues, analyzing errors",
      "optimal_cache_threshold": 0.65,
      "optimal_max_concurrent": 4,
      "characteristics": ["debug", "error", "issue", "bug", "investigate", "analyze"]
    }
  },
  "detection_history": [],
  "current_workload": "unknown",
  "confidence": 0.0,
  "auto_switch_enabled": true,
  "min_confidence_for_switch": 0.75
}
EOF
  fi
}

# Detect current workload type based on recent activity
detect_workload() {
  echo -e "${BLUE}Detecting current workload type...${NC}"

  if [[ ! -f "$LEARNING_DATA" ]]; then
    echo "No learning data available"
    return 1
  fi

  # Analyze recent cache and parallel outcomes for patterns
  local recent_samples=$(python3 <<'PYEOF'
import json
import sys
from collections import Counter

with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
    data = json.load(f)

with open('/Users/wallonwalusayi/.claude/data/workload-data.json') as f:
    workload_data = json.load(f)

# Get recent cache/parallel history (last 20 samples)
cache_history = data.get('cache_outcomes', {}).get('hit_rate_history', [])[-20:]
parallel_history = data.get('parallel_outcomes', {}).get('success_rate_history', [])[-20:]

# Look for patterns in queries (if tracked)
# For now, use heuristics based on performance patterns

workload_scores = {}

# Exploration: high parallel, moderate cache
if len(parallel_history) > 5:
    avg_parallel = sum(s.get('success_rate', 0) for s in parallel_history) / len(parallel_history)
    if avg_parallel > 85:
        workload_scores['exploration'] = 0.6

# Research: high cache hit rate expected
if len(cache_history) > 5:
    avg_hit_rate = sum(s.get('hit_rate', 0) for s in cache_history) / len(cache_history)
    if avg_hit_rate > 0.7:
        workload_scores['research'] = 0.5

# Implementation: lower cache hit (new code), moderate parallel
if len(cache_history) > 5:
    avg_hit_rate = sum(s.get('hit_rate', 0) for s in cache_history) / len(cache_history)
    if avg_hit_rate < 0.5:
        workload_scores['implementation'] = 0.7

# Testing: very high cache hit (repeated tests), high parallel
if len(cache_history) > 5 and len(parallel_history) > 5:
    avg_hit_rate = sum(s.get('hit_rate', 0) for s in cache_history) / len(cache_history)
    avg_parallel = sum(s.get('success_rate', 0) for s in parallel_history) / len(parallel_history)
    if avg_hit_rate > 0.8 and avg_parallel > 90:
        workload_scores['testing'] = 0.8

# Debugging: variable patterns, lower cache hit
if len(cache_history) > 5:
    # Calculate variance in hit rates
    hit_rates = [s.get('hit_rate', 0) for s in cache_history]
    mean = sum(hit_rates) / len(hit_rates)
    variance = sum((x - mean) ** 2 for x in hit_rates) / len(hit_rates)
    if variance > 0.05:  # High variance
        workload_scores['debugging'] = 0.6

# Default to exploration if no clear signal
if not workload_scores:
    workload_scores['exploration'] = 0.4

# Get highest scoring workload
detected = max(workload_scores.items(), key=lambda x: x[1])

print(json.dumps({
    'workload': detected[0],
    'confidence': detected[1],
    'all_scores': workload_scores
}))
PYEOF
)

  local workload=$(echo "$recent_samples" | jq -r '.workload')
  local confidence=$(echo "$recent_samples" | jq -r '.confidence')

  # Update workload data
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg ts "$now" \
     --arg workload "$workload" \
     --argjson confidence "$confidence" \
     --argjson scores "$recent_samples" \
     '.current_workload = $workload |
      .confidence = $confidence |
      .detection_history += [{
        timestamp: $ts,
        detected_workload: $workload,
        confidence: $confidence,
        scores: $scores.all_scores
      }] |
      .detection_history = .detection_history[-50:]' \
     "$WORKLOAD_DATA" > "$WORKLOAD_DATA.tmp"
  mv "$WORKLOAD_DATA.tmp" "$WORKLOAD_DATA"

  echo -e "${GREEN}✓ Detected workload: $workload${NC}"
  echo "  Confidence: $(echo "$confidence * 100" | bc | cut -d. -f1)%"

  # Show workload characteristics
  local description=$(jq -r --arg wl "$workload" '.workload_types[$wl].description' "$WORKLOAD_DATA")
  echo "  Description: $description"

  # Show optimal configs for this workload
  local opt_cache=$(jq -r --arg wl "$workload" '.workload_types[$wl].optimal_cache_threshold' "$WORKLOAD_DATA")
  local opt_concurrent=$(jq -r --arg wl "$workload" '.workload_types[$wl].optimal_max_concurrent' "$WORKLOAD_DATA")
  echo "  Optimal cache threshold: $opt_cache"
  echo "  Optimal max concurrent: $opt_concurrent"

  # Check if we should auto-switch
  local auto_switch=$(jq -r '.auto_switch_enabled' "$WORKLOAD_DATA")
  local min_confidence=$(jq -r '.min_confidence_for_switch' "$WORKLOAD_DATA")

  if [[ "$auto_switch" == "true" ]] && [[ $(echo "$confidence >= $min_confidence" | bc -l) -eq 1 ]]; then
    echo
    echo -e "${YELLOW}Auto-switch enabled and confidence threshold met${NC}"
    echo "Run: $0 apply to apply optimal configuration"
  fi

  echo "$workload"
}

# Apply optimal configuration for detected workload
apply_workload_config() {
  local workload="${1:-}"

  if [[ -z "$workload" ]]; then
    workload=$(jq -r '.current_workload' "$WORKLOAD_DATA")
  fi

  if [[ "$workload" == "unknown" ]] || [[ "$workload" == "null" ]]; then
    echo -e "${RED}No workload detected yet${NC}"
    echo "Run: $0 detect first"
    return 1
  fi

  echo -e "${BLUE}Applying optimal configuration for: $workload${NC}"

  # Get optimal configs
  local opt_cache=$(jq -r --arg wl "$workload" '.workload_types[$wl].optimal_cache_threshold' "$WORKLOAD_DATA")
  local opt_concurrent=$(jq -r --arg wl "$workload" '.workload_types[$wl].optimal_max_concurrent' "$WORKLOAD_DATA")

  if [[ "$opt_cache" == "null" ]] || [[ "$opt_concurrent" == "null" ]]; then
    echo -e "${RED}Unknown workload type: $workload${NC}"
    return 1
  fi

  # Get current configs
  local curr_cache=$(jq -r '.similarity_threshold' "$CACHE_CONFIG")
  local curr_concurrent=$(jq -r '.max_concurrent_processes' "$PARALLEL_CONFIG")

  echo
  echo "Changes:"
  echo "  Cache threshold: $curr_cache → $opt_cache"
  echo "  Max concurrent: $curr_concurrent → $opt_concurrent"
  echo

  # Apply changes
  jq --argjson threshold "$opt_cache" \
     '.similarity_threshold = $threshold' \
     "$CACHE_CONFIG" > "$CACHE_CONFIG.tmp"
  mv "$CACHE_CONFIG.tmp" "$CACHE_CONFIG"

  jq --argjson concurrent "$opt_concurrent" \
     '.max_concurrent_processes = $concurrent' \
     "$PARALLEL_CONFIG" > "$PARALLEL_CONFIG.tmp"
  mv "$PARALLEL_CONFIG.tmp" "$PARALLEL_CONFIG"

  echo -e "${GREEN}✓ Configuration applied${NC}"
  echo
  echo -e "${YELLOW}⚠ Restart systems to use new config:${NC}"
  echo "  - Cache: Already active (config read on each operation)"
  echo "  - Parallel: Active on next parallel execution"
  echo "  - Learning daemon: Restart if running"
}

# Manual workload override
set_workload() {
  local workload="$1"

  echo -e "${BLUE}Manually setting workload to: $workload${NC}"

  # Validate workload type
  local exists=$(jq -r --arg wl "$workload" '.workload_types | has($wl)' "$WORKLOAD_DATA")
  if [[ "$exists" != "true" ]]; then
    echo -e "${RED}Unknown workload type: $workload${NC}"
    echo "Available types:"
    jq -r '.workload_types | keys[]' "$WORKLOAD_DATA"
    return 1
  fi

  # Update current workload
  jq --arg wl "$workload" \
     '.current_workload = $wl | .confidence = 1.0' \
     "$WORKLOAD_DATA" > "$WORKLOAD_DATA.tmp"
  mv "$WORKLOAD_DATA.tmp" "$WORKLOAD_DATA"

  echo -e "${GREEN}✓ Workload set${NC}"
  echo
  echo "Apply configuration with: $0 apply"
}

# Customize workload configurations
customize_workload() {
  local workload="$1"
  local cache_threshold="$2"
  local max_concurrent="$3"

  echo -e "${BLUE}Customizing $workload configuration...${NC}"

  # Validate workload exists
  local exists=$(jq -r --arg wl "$workload" '.workload_types | has($wl)' "$WORKLOAD_DATA")
  if [[ "$exists" != "true" ]]; then
    echo -e "${RED}Unknown workload type: $workload${NC}"
    return 1
  fi

  # Update configuration
  jq --arg wl "$workload" \
     --argjson cache "$cache_threshold" \
     --argjson concurrent "$max_concurrent" \
     '.workload_types[$wl].optimal_cache_threshold = $cache |
      .workload_types[$wl].optimal_max_concurrent = $concurrent' \
     "$WORKLOAD_DATA" > "$WORKLOAD_DATA.tmp"
  mv "$WORKLOAD_DATA.tmp" "$WORKLOAD_DATA"

  echo -e "${GREEN}✓ Configuration customized${NC}"
  echo "  Workload: $workload"
  echo "  Cache threshold: $cache_threshold"
  echo "  Max concurrent: $max_concurrent"
}

# Show status
show_status() {
  echo -e "${BLUE}=== Workload Classification Status ===${NC}"
  echo

  local current=$(jq -r '.current_workload' "$WORKLOAD_DATA")
  local confidence=$(jq -r '.confidence' "$WORKLOAD_DATA")
  local auto_switch=$(jq -r '.auto_switch_enabled' "$WORKLOAD_DATA")

  echo "Current Workload: $current"
  echo "Confidence: $(echo "$confidence * 100" | bc | cut -d. -f1)%"
  echo "Auto-switch: $auto_switch"
  echo

  if [[ "$current" != "unknown" ]] && [[ "$current" != "null" ]]; then
    echo "Current Workload Details:"
    jq -r --arg wl "$current" \
       '.workload_types[$wl] |
        "  Description: \(.description)\n" +
        "  Optimal cache threshold: \(.optimal_cache_threshold)\n" +
        "  Optimal max concurrent: \(.optimal_max_concurrent)"' \
       "$WORKLOAD_DATA"
    echo
  fi

  echo "Available Workload Types:"
  jq -r '.workload_types | to_entries[] |
    "  \(.key): \(.value.description)"' \
    "$WORKLOAD_DATA"
  echo

  local detection_count=$(jq '.detection_history | length' "$WORKLOAD_DATA")
  if [[ $detection_count -gt 0 ]]; then
    echo "Recent Detections:"
    jq -r '.detection_history[-5:] | reverse | .[] |
      "  \(.timestamp): \(.detected_workload) (\(.confidence | . * 100 | floor)%)"' \
      "$WORKLOAD_DATA"
  fi
}

# List all workload types
list_workloads() {
  echo -e "${BLUE}=== Available Workload Types ===${NC}"
  echo

  jq -r '.workload_types | to_entries[] |
    "\(.key):\n" +
    "  Description: \(.value.description)\n" +
    "  Cache threshold: \(.value.optimal_cache_threshold)\n" +
    "  Max concurrent: \(.value.optimal_max_concurrent)\n" +
    "  Keywords: \(.value.characteristics | join(", "))\n"' \
    "$WORKLOAD_DATA"
}

# Toggle auto-switch
toggle_auto_switch() {
  local enabled="$1"

  jq --argjson enabled "$enabled" \
     '.auto_switch_enabled = $enabled' \
     "$WORKLOAD_DATA" > "$WORKLOAD_DATA.tmp"
  mv "$WORKLOAD_DATA.tmp" "$WORKLOAD_DATA"

  if [[ "$enabled" == "true" ]]; then
    echo -e "${GREEN}✓ Auto-switch enabled${NC}"
  else
    echo -e "${YELLOW}Auto-switch disabled${NC}"
  fi
}

# Main command dispatcher
case "${1:-}" in
  init)
    initialize_workload_data
    echo -e "${GREEN}✓ Workload classification initialized${NC}"
    ;;
  detect)
    initialize_workload_data
    detect_workload
    ;;
  apply)
    initialize_workload_data
    apply_workload_config "${2:-}"
    ;;
  set)
    initialize_workload_data
    set_workload "$2"
    ;;
  customize)
    initialize_workload_data
    customize_workload "$2" "$3" "$4"
    ;;
  status)
    initialize_workload_data
    show_status
    ;;
  list)
    initialize_workload_data
    list_workloads
    ;;
  auto-switch)
    initialize_workload_data
    if [[ "$2" == "enable" ]]; then
      toggle_auto_switch true
    elif [[ "$2" == "disable" ]]; then
      toggle_auto_switch false
    else
      echo "Usage: $0 auto-switch {enable|disable}"
      exit 1
    fi
    ;;
  detect-and-apply)
    # Full cycle: detect then apply if confident
    initialize_workload_data
    workload=$(detect_workload)
    echo
    confidence=$(jq -r '.confidence' "$WORKLOAD_DATA")
    min_conf=$(jq -r '.min_confidence_for_switch' "$WORKLOAD_DATA")
    if [[ $(echo "$confidence >= $min_conf" | bc -l) -eq 1 ]]; then
      apply_workload_config "$workload"
    else
      echo -e "${YELLOW}Confidence too low for auto-switch (need $(echo "$min_conf * 100" | bc | cut -d. -f1)%)${NC}"
    fi
    ;;
  *)
    echo "Usage: $0 {init|detect|apply|set|customize|status|list|auto-switch|detect-and-apply}"
    echo
    echo "Commands:"
    echo "  init                        - Initialize workload classification"
    echo "  detect                      - Detect current workload type"
    echo "  apply [workload]            - Apply optimal config for workload"
    echo "  set <workload>              - Manually set current workload"
    echo "  customize <wl> <cache> <cc> - Customize workload config"
    echo "  status                      - Show current status"
    echo "  list                        - List all workload types"
    echo "  auto-switch {enable|disable} - Toggle automatic switching"
    echo "  detect-and-apply            - Detect and apply if confident"
    exit 1
    ;;
esac
