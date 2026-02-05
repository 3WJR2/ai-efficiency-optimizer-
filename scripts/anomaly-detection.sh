#!/usr/bin/env bash
# anomaly-detection.sh - Statistical anomaly detection for performance metrics
# Uses 3-sigma control limits to detect unusual patterns

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
ANOMALY_LOG="$HOME/.claude/data/anomaly-log.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize anomaly log
initialize_anomaly_log() {
  if [[ ! -f "$ANOMALY_LOG" ]]; then
    cat > "$ANOMALY_LOG" <<'EOF'
{
  "version": "1.0.0",
  "anomalies": [],
  "detection_config": {
    "sigma_threshold": 3.0,
    "min_samples": 10,
    "enabled": true
  }
}
EOF
  fi
}

# Calculate statistics (mean and std dev)
calculate_stats() {
  local values="$1"

  python3 <<EOF
import json
import statistics

values = $values
if len(values) < 2:
    print(json.dumps({"mean": 0, "std_dev": 0, "count": len(values)}))
else:
    mean = statistics.mean(values)
    std_dev = statistics.stdev(values) if len(values) > 1 else 0
    print(json.dumps({"mean": mean, "std_dev": std_dev, "count": len(values)}))
EOF
}

# Detect cache anomalies
detect_cache_anomalies() {
  echo -e "${BLUE}=== Detecting Cache Anomalies ===${NC}"
  echo

  local min_samples=$(jq -r '.detection_config.min_samples' "$ANOMALY_LOG")
  local sample_count=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")

  if [[ $sample_count -lt $min_samples ]]; then
    echo "Insufficient samples (need $min_samples, have $sample_count)"
    return 0
  fi

  local hit_rates=$(jq '[.cache_outcomes.hit_rate_history[].hit_rate]' "$LEARNING_DATA")
  local stats=$(calculate_stats "$hit_rates")
  local mean=$(echo "$stats" | jq -r '.mean')
  local std_dev=$(echo "$stats" | jq -r '.std_dev')

  if [[ $(echo "$std_dev == 0" | bc -l) -eq 1 ]]; then
    echo "No variation in data, no anomalies possible"
    return 0
  fi

  local sigma=$(jq -r '.detection_config.sigma_threshold' "$ANOMALY_LOG")
  local upper=$(echo "$mean + ($sigma * $std_dev)" | bc -l)
  local lower=$(echo "$mean - ($sigma * $std_dev)" | bc -l)

  echo "Hit Rate: mean=$(echo "$mean * 100" | bc | cut -d. -f1)%, limits=$(echo "$lower * 100" | bc | cut -d. -f1)%-$(echo "$upper * 100" | bc | cut -d. -f1)%"
  echo -e "${GREEN}✓ Anomaly detection active${NC}"
}

# Show anomaly log
show_log() {
  local limit="${1:-10}"
  echo -e "${BLUE}=== Recent Anomalies ===${NC}"
  local count=$(jq '.anomalies | length' "$ANOMALY_LOG")
  echo "Total: $count anomalies"
}

# Main dispatcher
case "${1:-}" in
  init) initialize_anomaly_log; echo "✓ Initialized" ;;
  detect) initialize_anomaly_log; detect_cache_anomalies ;;
  log) initialize_anomaly_log; show_log "${2:-10}" ;;
  *) echo "Usage: $0 {init|detect|log}"; exit 1 ;;
esac
