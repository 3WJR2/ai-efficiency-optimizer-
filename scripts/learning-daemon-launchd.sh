#!/usr/bin/env bash
# learning-daemon-launchd.sh - Learning daemon for launchd (runs in foreground)
# This version is designed to run under launchd and doesn't background itself

set -euo pipefail

OUTCOME_TRACKER="$HOME/.claude/scripts/outcome-tracker.sh"
PATTERN_ANALYZER="$HOME/.claude/scripts/pattern-analyzer.sh"
CONFIG_MANAGER="$HOME/.claude/scripts/adaptive-config-manager.sh"
LEARNING_CONFIG="$HOME/.claude/data/learning-config.json"
LOG_FILE="$HOME/.claude/logs/learning-daemon.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if learning is enabled
is_learning_enabled() {
  if [[ ! -f "$LEARNING_CONFIG" ]]; then
    return 1
  fi

  local enabled=$(jq -r '.learning_enabled // false' "$LEARNING_CONFIG")
  [[ "$enabled" == "true" ]]
}

# Main learning loop (runs in foreground)
log "Learning daemon started (PID: $$) - launchd mode"

# Get intervals from config
outcome_interval=$(jq -r '.analysis_intervals.outcome_tracking_interval_seconds // 300' "$LEARNING_CONFIG")
analysis_interval=$(jq -r '.analysis_intervals.pattern_analysis_interval_seconds // 3600' "$LEARNING_CONFIG")
adaptation_interval=$(jq -r '.analysis_intervals.config_adaptation_interval_seconds // 7200' "$LEARNING_CONFIG")

last_outcome=0
last_analysis=0
last_adaptation=0

# Main loop
while true; do
  if ! is_learning_enabled; then
    log "Learning disabled, daemon sleeping..."
    sleep 60
    continue
  fi

  current_time=$(date +%s)

  # Outcome tracking (every 5 minutes by default)
  if [[ $((current_time - last_outcome)) -ge $outcome_interval ]]; then
    log "Running outcome tracking..."
    "$OUTCOME_TRACKER" track >> "$LOG_FILE" 2>&1 || log "Outcome tracking failed"
    last_outcome=$current_time
  fi

  # Pattern analysis (every 1 hour by default)
  if [[ $((current_time - last_analysis)) -ge $analysis_interval ]]; then
    log "Running pattern analysis..."
    "$PATTERN_ANALYZER" analyze >> "$LOG_FILE" 2>&1 || log "Pattern analysis failed"
    "$PATTERN_ANALYZER" optimal >> "$LOG_FILE" 2>&1 || log "Optimal calculation failed"
    last_analysis=$current_time
  fi

  # Configuration adaptation (every 2 hours by default)
  if [[ $((current_time - last_adaptation)) -ge $adaptation_interval ]]; then
    log "Running configuration adaptation..."
    "$CONFIG_MANAGER" run >> "$LOG_FILE" 2>&1 || log "Config adaptation failed"
    last_adaptation=$current_time
  fi

  # Sleep for 1 minute between checks
  sleep 60
done
