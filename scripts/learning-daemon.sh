#!/usr/bin/env bash
# learning-daemon.sh - Background daemon for continuous active learning
# Periodically tracks outcomes, analyzes patterns, and adapts configurations

set -euo pipefail

OUTCOME_TRACKER="$HOME/.claude/scripts/outcome-tracker.sh"
PATTERN_ANALYZER="$HOME/.claude/scripts/pattern-analyzer.sh"
CONFIG_MANAGER="$HOME/.claude/scripts/adaptive-config-manager.sh"
LEARNING_CONFIG="$HOME/.claude/data/learning-config.json"
PID_FILE="$HOME/.claude/data/learning-daemon.pid"
LOG_FILE="$HOME/.claude/logs/learning-daemon.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if daemon is already running
is_running() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null 2>&1; then
      return 0
    else
      # Stale PID file
      rm -f "$PID_FILE"
      return 1
    fi
  fi
  return 1
}

# Check if learning is enabled
is_learning_enabled() {
  if [[ ! -f "$LEARNING_CONFIG" ]]; then
    return 1
  fi

  local enabled=$(jq -r '.learning_enabled // false' "$LEARNING_CONFIG")
  [[ "$enabled" == "true" ]]
}

# Main learning loop
learning_loop() {
  log "Learning daemon started (PID: $$)"

  # Get intervals from config
  local outcome_interval=$(jq -r '.analysis_intervals.outcome_tracking_interval_seconds // 300' "$LEARNING_CONFIG")
  local analysis_interval=$(jq -r '.analysis_intervals.pattern_analysis_interval_seconds // 3600' "$LEARNING_CONFIG")
  local adaptation_interval=$(jq -r '.analysis_intervals.config_adaptation_interval_seconds // 7200' "$LEARNING_CONFIG")

  local last_outcome=0
  local last_analysis=0
  local last_adaptation=0

  while true; do
    if ! is_learning_enabled; then
      log "Learning disabled, daemon sleeping..."
      sleep 60
      continue
    fi

    local current_time=$(date +%s)

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
}

# Start daemon
start_daemon() {
  if is_running; then
    echo "Learning daemon is already running (PID: $(cat "$PID_FILE"))"
    return 1
  fi

  if ! is_learning_enabled; then
    echo "Learning is disabled in config. Enable it first:"
    echo "  jq '.learning_enabled = true' $LEARNING_CONFIG | sponge $LEARNING_CONFIG"
    return 1
  fi

  echo "Starting learning daemon..."

  # Start daemon in background
  nohup bash -c "$(declare -f learning_loop log is_learning_enabled); learning_loop" > /dev/null 2>&1 &
  local pid=$!

  echo $pid > "$PID_FILE"
  echo "Learning daemon started (PID: $pid)"
  echo "Logs: $LOG_FILE"
}

# Stop daemon
stop_daemon() {
  if ! is_running; then
    echo "Learning daemon is not running"
    return 1
  fi

  local pid=$(cat "$PID_FILE")
  echo "Stopping learning daemon (PID: $pid)..."

  kill "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"

  echo "Learning daemon stopped"
}

# Restart daemon
restart_daemon() {
  stop_daemon 2>/dev/null || true
  sleep 2
  start_daemon
}

# Show daemon status
show_status() {
  echo "=== Learning Daemon Status ==="
  echo

  if is_running; then
    local pid=$(cat "$PID_FILE")
    echo "Status: RUNNING (PID: $pid)"

    # Show process info
    ps -p "$pid" -o pid,etime,rss 2>/dev/null | tail -n +2 | while read pid etime rss; do
      echo "  Uptime: $etime"
      echo "  Memory: $((rss / 1024))MB"
    done
  else
    echo "Status: STOPPED"
  fi

  echo

  # Show learning config
  if [[ -f "$LEARNING_CONFIG" ]]; then
    local enabled=$(jq -r '.learning_enabled' "$LEARNING_CONFIG")
    local auto_tuning=$(jq -r '.learning_features.auto_tuning' "$LEARNING_CONFIG")

    echo "Configuration:"
    echo "  Learning enabled: $enabled"
    echo "  Auto-tuning enabled: $auto_tuning"
  fi

  echo

  # Show recent log activity
  if [[ -f "$LOG_FILE" ]]; then
    echo "Recent Activity (last 10 lines):"
    tail -n 10 "$LOG_FILE"
  fi
}

# Show daemon logs
show_logs() {
  local lines="${1:-50}"

  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No log file found"
    return 1
  fi

  echo "=== Learning Daemon Logs (last $lines lines) ==="
  tail -n "$lines" "$LOG_FILE"
}

# Follow logs in real-time
follow_logs() {
  if [[ ! -f "$LOG_FILE" ]]; then
    echo "No log file found. Waiting for logs..."
    touch "$LOG_FILE"
  fi

  echo "Following learning daemon logs (Ctrl+C to stop)..."
  tail -f "$LOG_FILE"
}

# Run one learning cycle manually
run_manual_cycle() {
  echo "=== Running Manual Learning Cycle ==="
  echo

  if ! is_learning_enabled; then
    echo "Warning: Learning is disabled in config"
    echo
  fi

  echo "1. Tracking outcomes..."
  "$OUTCOME_TRACKER" track

  echo
  echo "2. Analyzing patterns..."
  "$PATTERN_ANALYZER" analyze

  echo
  echo "3. Calculating optimal configurations..."
  "$PATTERN_ANALYZER" optimal

  echo
  echo "4. Running adaptation cycle..."
  "$CONFIG_MANAGER" run

  echo
  echo "Manual learning cycle complete"
}

# Main command dispatcher
case "${1:-}" in
  start)
    start_daemon
    ;;
  stop)
    stop_daemon
    ;;
  restart)
    restart_daemon
    ;;
  status)
    show_status
    ;;
  logs)
    show_logs "${2:-50}"
    ;;
  follow)
    follow_logs
    ;;
  manual)
    run_manual_cycle
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|follow|manual}"
    echo
    echo "Commands:"
    echo "  start    - Start the learning daemon in background"
    echo "  stop     - Stop the learning daemon"
    echo "  restart  - Restart the learning daemon"
    echo "  status   - Show daemon status and configuration"
    echo "  logs [N] - Show last N lines of log (default: 50)"
    echo "  follow   - Follow logs in real-time"
    echo "  manual   - Run one learning cycle manually (without daemon)"
    exit 1
    ;;
esac
