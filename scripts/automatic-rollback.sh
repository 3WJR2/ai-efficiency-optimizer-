#!/usr/bin/env bash
# automatic-rollback.sh - Automatic rollback of bad adaptations
# Detects performance degradation and reverts to previous config

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"
ROLLBACK_DATA="$HOME/.claude/data/rollback-data.json"
BLACKLIST_FILE="$HOME/.claude/data/config-blacklist.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize rollback data
initialize_rollback_data() {
  if [[ ! -f "$ROLLBACK_DATA" ]]; then
    cat > "$ROLLBACK_DATA" <<'EOF'
{
  "version": "1.0.0",
  "snapshots": [],
  "rollback_history": [],
  "degradation_threshold": 0.10
}
EOF
  fi

  if [[ ! -f "$BLACKLIST_FILE" ]]; then
    cat > "$BLACKLIST_FILE" <<'EOF'
{
  "version": "1.0.0",
  "blacklisted_configs": [],
  "auto_blacklist_enabled": true
}
EOF
  fi
}

# Create snapshot before adaptation
create_snapshot() {
  local snapshot_type="$1"  # "cache" or "parallel"
  local reason="$2"

  echo -e "${BLUE}Creating snapshot before adaptation...${NC}"

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local snapshot_id="snapshot_$(date +%s)"

  # Get current config values
  local cache_threshold=$(jq -r '.similarity_threshold' "$CACHE_CONFIG" 2>/dev/null || echo "0")
  local max_concurrent=$(jq -r '.max_concurrent_processes' "$PARALLEL_CONFIG" 2>/dev/null || echo "0")

  # Get current performance metrics
  local cache_hit_rate=0
  local cache_latency=0
  local parallel_success_rate=0

  if [[ -f "$LEARNING_DATA" ]]; then
    if [[ $(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA") -gt 0 ]]; then
      cache_hit_rate=$(jq -r '[.cache_outcomes.hit_rate_history[-5:][].hit_rate] | add / length' "$LEARNING_DATA" 2>/dev/null || echo "0")
      cache_latency=$(jq -r '[.cache_outcomes.latency_history[-5:][].avg_latency_ms] | add / length' "$LEARNING_DATA" 2>/dev/null || echo "0")
    fi
    if [[ $(jq '.parallel_outcomes.success_rate_history | length' "$LEARNING_DATA") -gt 0 ]]; then
      parallel_success_rate=$(jq -r '[.parallel_outcomes.success_rate_history[-5:][].success_rate] | add / length' "$LEARNING_DATA" 2>/dev/null || echo "0")
    fi
  fi

  # Create snapshot
  local snapshot=$(jq -n \
    --arg id "$snapshot_id" \
    --arg ts "$now" \
    --arg type "$snapshot_type" \
    --arg reason "$reason" \
    --argjson cache_threshold "$cache_threshold" \
    --argjson max_concurrent "$max_concurrent" \
    --argjson cache_hit_rate "$cache_hit_rate" \
    --argjson cache_latency "$cache_latency" \
    --argjson parallel_success "$parallel_success_rate" \
    '{
      snapshot_id: $id,
      timestamp: $ts,
      type: $type,
      reason: $reason,
      config: {
        cache_threshold: $cache_threshold,
        max_concurrent: $max_concurrent
      },
      performance: {
        cache_hit_rate: $cache_hit_rate,
        cache_latency_ms: $cache_latency,
        parallel_success_rate: $parallel_success
      }
    }')

  # Add snapshot to history (keep last 10)
  jq --argjson snapshot "$snapshot" \
     '.snapshots += [$snapshot] | .snapshots = .snapshots[-10:]' \
     "$ROLLBACK_DATA" > "$ROLLBACK_DATA.tmp"
  mv "$ROLLBACK_DATA.tmp" "$ROLLBACK_DATA"

  echo -e "${GREEN}✓ Snapshot created: $snapshot_id${NC}"
  echo "  Type: $snapshot_type"
  echo "  Cache threshold: $cache_threshold"
  echo "  Max concurrent: $max_concurrent"
  echo "  Cache hit rate: $(echo "$cache_hit_rate * 100" | bc | cut -d. -f1)%"
  echo "  Parallel success: $(echo "$parallel_success_rate" | cut -d. -f1)%"
}

# Check for performance degradation
check_degradation() {
  local snapshot_type="$1"

  echo -e "${BLUE}Checking for performance degradation...${NC}"

  local threshold=$(jq -r '.degradation_threshold' "$ROLLBACK_DATA")
  local snapshot_count=$(jq '.snapshots | length' "$ROLLBACK_DATA")

  if [[ $snapshot_count -lt 2 ]]; then
    echo "Not enough snapshots for comparison (need 2+, have $snapshot_count)"
    return 1
  fi

  # Get last two snapshots
  local prev_snapshot=$(jq '.snapshots[-2]' "$ROLLBACK_DATA")
  local curr_snapshot=$(jq '.snapshots[-1]' "$ROLLBACK_DATA")

  if [[ "$snapshot_type" == "cache" ]]; then
    local prev_hit_rate=$(echo "$prev_snapshot" | jq -r '.performance.cache_hit_rate')
    local curr_hit_rate=$(echo "$curr_snapshot" | jq -r '.performance.cache_hit_rate')
    local prev_latency=$(echo "$prev_snapshot" | jq -r '.performance.cache_latency_ms')
    local curr_latency=$(echo "$curr_snapshot" | jq -r '.performance.cache_latency_ms')

    # Check if hit rate dropped significantly
    if [[ $(echo "$prev_hit_rate > 0" | bc -l) -eq 1 ]]; then
      local hit_rate_change=$(echo "($prev_hit_rate - $curr_hit_rate) / $prev_hit_rate" | bc -l)
      if [[ $(echo "$hit_rate_change > $threshold" | bc -l) -eq 1 ]]; then
        echo -e "${RED}✗ DEGRADATION DETECTED!${NC}"
        echo "  Hit rate dropped: $(echo "$prev_hit_rate * 100" | bc | cut -d. -f1)% → $(echo "$curr_hit_rate * 100" | bc | cut -d. -f1)%"
        echo "  Change: -$(echo "$hit_rate_change * 100" | bc | cut -d. -f1)% (threshold: $(echo "$threshold * 100" | bc | cut -d. -f1)%)"
        return 0
      fi
    fi

    # Check if latency increased significantly
    if [[ $(echo "$prev_latency > 0" | bc -l) -eq 1 ]]; then
      local latency_change=$(echo "($curr_latency - $prev_latency) / $prev_latency" | bc -l)
      if [[ $(echo "$latency_change > $threshold" | bc -l) -eq 1 ]]; then
        echo -e "${RED}✗ DEGRADATION DETECTED!${NC}"
        echo "  Latency increased: ${prev_latency}ms → ${curr_latency}ms"
        echo "  Change: +$(echo "$latency_change * 100" | bc | cut -d. -f1)% (threshold: $(echo "$threshold * 100" | bc | cut -d. -f1)%)"
        return 0
      fi
    fi

  elif [[ "$snapshot_type" == "parallel" ]]; then
    local prev_success=$(echo "$prev_snapshot" | jq -r '.performance.parallel_success_rate')
    local curr_success=$(echo "$curr_snapshot" | jq -r '.performance.parallel_success_rate')

    if [[ $(echo "$prev_success > 0" | bc -l) -eq 1 ]]; then
      local success_change=$(echo "($prev_success - $curr_success) / $prev_success" | bc -l)
      if [[ $(echo "$success_change > $threshold" | bc -l) -eq 1 ]]; then
        echo -e "${RED}✗ DEGRADATION DETECTED!${NC}"
        echo "  Success rate dropped: ${prev_success}% → ${curr_success}%"
        echo "  Change: -$(echo "$success_change * 100" | bc | cut -d. -f1)% (threshold: $(echo "$threshold * 100" | bc | cut -d. -f1)%)"
        return 0
      fi
    fi
  fi

  echo -e "${GREEN}✓ No degradation detected${NC}"
  return 1
}

# Perform rollback
perform_rollback() {
  local snapshot_id="${1:-}"

  echo -e "${RED}=== PERFORMING AUTOMATIC ROLLBACK ===${NC}"
  echo

  # Get snapshot to rollback to
  local snapshot
  if [[ -n "$snapshot_id" ]]; then
    snapshot=$(jq --arg id "$snapshot_id" '.snapshots[] | select(.snapshot_id == $id)' "$ROLLBACK_DATA")
  else
    # Use second-to-last snapshot (before current)
    snapshot=$(jq '.snapshots[-2]' "$ROLLBACK_DATA")
  fi

  if [[ -z "$snapshot" ]] || [[ "$snapshot" == "null" ]]; then
    echo -e "${RED}✗ No snapshot found to rollback to${NC}"
    return 1
  fi

  local rollback_cache_threshold=$(echo "$snapshot" | jq -r '.config.cache_threshold')
  local rollback_max_concurrent=$(echo "$snapshot" | jq -r '.config.max_concurrent')
  local rollback_ts=$(echo "$snapshot" | jq -r '.timestamp')

  echo "Rolling back to snapshot from: $rollback_ts"
  echo "  Cache threshold: $rollback_cache_threshold"
  echo "  Max concurrent: $rollback_max_concurrent"
  echo

  # Get current config (to blacklist)
  local current_cache_threshold=$(jq -r '.similarity_threshold' "$CACHE_CONFIG")
  local current_max_concurrent=$(jq -r '.max_concurrent_processes' "$PARALLEL_CONFIG")

  # Apply rollback
  jq --argjson threshold "$rollback_cache_threshold" \
     '.similarity_threshold = $threshold' \
     "$CACHE_CONFIG" > "$CACHE_CONFIG.tmp"
  mv "$CACHE_CONFIG.tmp" "$CACHE_CONFIG"

  jq --argjson concurrent "$rollback_max_concurrent" \
     '.max_concurrent_processes = $concurrent' \
     "$PARALLEL_CONFIG" > "$PARALLEL_CONFIG.tmp"
  mv "$PARALLEL_CONFIG.tmp" "$PARALLEL_CONFIG"

  echo -e "${GREEN}✓ Configuration rolled back${NC}"

  # Blacklist failed config
  blacklist_config "$current_cache_threshold" "$current_max_concurrent" "Performance degradation"

  # Record rollback
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg ts "$now" \
     --argjson from_cache "$current_cache_threshold" \
     --argjson from_concurrent "$current_max_concurrent" \
     --argjson to_cache "$rollback_cache_threshold" \
     --argjson to_concurrent "$rollback_max_concurrent" \
     '.rollback_history += [{
       timestamp: $ts,
       from: {cache_threshold: $from_cache, max_concurrent: $from_concurrent},
       to: {cache_threshold: $to_cache, max_concurrent: $to_concurrent},
       reason: "automatic_degradation_detection"
     }]' "$ROLLBACK_DATA" > "$ROLLBACK_DATA.tmp"
  mv "$ROLLBACK_DATA.tmp" "$ROLLBACK_DATA"

  echo
  echo -e "${YELLOW}⚠ Restart the learning daemon to use rolled-back config${NC}"
}

# Blacklist a configuration
blacklist_config() {
  local cache_threshold="$1"
  local max_concurrent="$2"
  local reason="$3"

  local auto_blacklist=$(jq -r '.auto_blacklist_enabled' "$BLACKLIST_FILE")
  if [[ "$auto_blacklist" != "true" ]]; then
    echo "Auto-blacklist disabled, skipping"
    return 0
  fi

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg ts "$now" \
     --argjson cache "$cache_threshold" \
     --argjson concurrent "$max_concurrent" \
     --arg reason "$reason" \
     '.blacklisted_configs += [{
       timestamp: $ts,
       cache_threshold: $cache,
       max_concurrent: $concurrent,
       reason: $reason
     }]' "$BLACKLIST_FILE" > "$BLACKLIST_FILE.tmp"
  mv "$BLACKLIST_FILE.tmp" "$BLACKLIST_FILE"

  echo -e "${YELLOW}⚠ Configuration blacklisted${NC}"
  echo "  Cache threshold: $cache_threshold"
  echo "  Max concurrent: $max_concurrent"
  echo "  Reason: $reason"
}

# Check if a config is blacklisted
is_blacklisted() {
  local cache_threshold="$1"
  local max_concurrent="$2"

  local count=$(jq --argjson cache "$cache_threshold" \
                    --argjson concurrent "$max_concurrent" \
                    '[.blacklisted_configs[] | select(.cache_threshold == $cache and .max_concurrent == $concurrent)] | length' \
                    "$BLACKLIST_FILE")

  [[ $count -gt 0 ]]
}

# Show rollback history
show_history() {
  echo -e "${BLUE}=== Rollback History ===${NC}"
  echo

  local count=$(jq '.rollback_history | length' "$ROLLBACK_DATA")
  if [[ $count -eq 0 ]]; then
    echo "No rollbacks performed yet"
    return 0
  fi

  jq -r '.rollback_history | reverse | .[] |
    "\(.timestamp):",
    "  From: cache=\(.from.cache_threshold), concurrent=\(.from.max_concurrent)",
    "  To:   cache=\(.to.cache_threshold), concurrent=\(.to.max_concurrent)",
    "  Reason: \(.reason)",
    ""' "$ROLLBACK_DATA"
}

# Show blacklisted configs
show_blacklist() {
  echo -e "${BLUE}=== Blacklisted Configurations ===${NC}"
  echo

  local count=$(jq '.blacklisted_configs | length' "$BLACKLIST_FILE")
  if [[ $count -eq 0 ]]; then
    echo "No blacklisted configurations"
    return 0
  fi

  jq -r '.blacklisted_configs | .[] |
    "Cache: \(.cache_threshold), Concurrent: \(.max_concurrent)",
    "  Blacklisted: \(.timestamp)",
    "  Reason: \(.reason)",
    ""' "$BLACKLIST_FILE"
}

# Clear blacklist
clear_blacklist() {
  jq '.blacklisted_configs = []' "$BLACKLIST_FILE" > "$BLACKLIST_FILE.tmp"
  mv "$BLACKLIST_FILE.tmp" "$BLACKLIST_FILE"
  echo -e "${GREEN}✓ Blacklist cleared${NC}"
}

# Main command dispatcher
case "${1:-}" in
  init)
    initialize_rollback_data
    echo -e "${GREEN}✓ Rollback system initialized${NC}"
    ;;
  snapshot)
    initialize_rollback_data
    create_snapshot "${2:-cache}" "${3:-manual snapshot}"
    ;;
  check)
    initialize_rollback_data
    if check_degradation "${2:-cache}"; then
      echo
      echo -e "${RED}Consider rolling back with: $0 rollback${NC}"
    fi
    ;;
  rollback)
    initialize_rollback_data
    perform_rollback "${2:-}"
    ;;
  history)
    initialize_rollback_data
    show_history
    ;;
  blacklist)
    initialize_rollback_data
    show_blacklist
    ;;
  clear-blacklist)
    initialize_rollback_data
    clear_blacklist
    ;;
  auto-check)
    # Called by adaptive-config-manager after adaptation
    initialize_rollback_data
    create_snapshot "${2:-cache}" "pre-adaptation snapshot"
    sleep 2
    if check_degradation "${2:-cache}"; then
      perform_rollback
      exit 1  # Signal failure
    fi
    ;;
  *)
    echo "Usage: $0 {init|snapshot|check|rollback|history|blacklist|clear-blacklist|auto-check}"
    echo
    echo "Commands:"
    echo "  init              - Initialize rollback system"
    echo "  snapshot <type> [reason] - Create snapshot (type: cache|parallel)"
    echo "  check <type>      - Check for degradation"
    echo "  rollback [id]     - Rollback to previous config"
    echo "  history           - Show rollback history"
    echo "  blacklist         - Show blacklisted configs"
    echo "  clear-blacklist   - Clear blacklist"
    echo "  auto-check <type> - Automatic check after adaptation"
    exit 1
    ;;
esac
