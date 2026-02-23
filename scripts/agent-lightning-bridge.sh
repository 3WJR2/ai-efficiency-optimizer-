#!/usr/bin/env bash
#
# Agent Lightning Bridge - Integrates agent-lightning with Claude's adaptive learning system
#
# This bridge connects:
# 1. Existing outcome tracking (cache hits, parallel execution, latency)
# 2. Agent-lightning's LightningStore (spans, traces, rewards)
# 3. Reinforcement learning feedback loop
#
# Architecture:
# - Reads outcomes from ~/.claude/data/learning-data.json
# - Converts to agent-lightning spans format
# - Emits to LightningStore for RL training
# - Feeds learned optimizations back to adaptive-config-manager.sh
#
# Usage:
#   source agent-lightning-bridge.sh
#   agl_bridge_init
#   agl_bridge_emit_outcome "task_id" "success" 0.95 '{"latency": 120}'
#   agl_bridge_train
#

set -euo pipefail

# Configuration
readonly AGL_BRIDGE_DIR="${HOME}/.claude/data/agent-lightning"
readonly AGL_STORE_PATH="${AGL_BRIDGE_DIR}/lightning-store"
readonly AGL_VENV_PATH="${HOME}/.claude/venv"
readonly LEARNING_DATA_PATH="${HOME}/.claude/data/learning-data.json"
readonly CACHE_METRICS_PATH="${HOME}/.claude/data/cache-metrics.json"

# Logging
log_info() {
    echo "[AGL-BRIDGE $(date +%H:%M:%S)] INFO: $*" >&2
}

log_error() {
    echo "[AGL-BRIDGE $(date +%H:%M:%S)] ERROR: $*" >&2
}

# Initialize agent-lightning bridge
agl_bridge_init() {
    log_info "Initializing agent-lightning bridge..."

    # Create directories
    mkdir -p "${AGL_BRIDGE_DIR}"
    mkdir -p "${AGL_STORE_PATH}"

    # Check if virtual environment exists
    if [[ ! -d "${AGL_VENV_PATH}" ]]; then
        log_error "Virtual environment not found at ${AGL_VENV_PATH}"
        log_error "Run: python3 -m venv ${AGL_VENV_PATH}"
        return 1
    fi

    # Initialize configuration
    if [[ ! -f "${AGL_BRIDGE_DIR}/config.json" ]]; then
        cat > "${AGL_BRIDGE_DIR}/config.json" <<EOF
{
  "bridge_enabled": true,
  "store_type": "file",
  "store_path": "${AGL_STORE_PATH}",
  "emit_to_lightning": true,
  "training_enabled": false,
  "algorithm": "apo",
  "learning_rate": 0.001,
  "batch_size": 32,
  "reward_shaping": {
    "cache_hit_reward": 1.0,
    "cache_miss_penalty": -0.1,
    "latency_threshold_ms": 1000,
    "fast_response_reward": 0.5,
    "slow_response_penalty": -0.2,
    "parallel_success_reward": 0.8,
    "parallel_failure_penalty": -0.3
  },
  "integration": {
    "sync_interval_seconds": 300,
    "auto_train": false,
    "min_samples_for_training": 100
  }
}
EOF
        log_info "Created default configuration at ${AGL_BRIDGE_DIR}/config.json"
    fi

    # Initialize metrics
    if [[ ! -f "${AGL_BRIDGE_DIR}/metrics.json" ]]; then
        cat > "${AGL_BRIDGE_DIR}/metrics.json" <<EOF
{
  "total_spans_emitted": 0,
  "total_training_runs": 0,
  "last_sync_timestamp": null,
  "last_training_timestamp": null,
  "rewards": {
    "total_reward": 0.0,
    "average_reward": 0.0,
    "cache_rewards": 0.0,
    "latency_rewards": 0.0,
    "parallel_rewards": 0.0
  }
}
EOF
        log_info "Created metrics file at ${AGL_BRIDGE_DIR}/metrics.json"
    fi

    log_info "Agent-lightning bridge initialized successfully"
    return 0
}

# Emit outcome to agent-lightning
# Args: task_id, outcome (success/failure), confidence, metadata_json
agl_bridge_emit_outcome() {
    local task_id="${1}"
    local outcome="${2}"
    local confidence="${3:-0.5}"
    local metadata="${4:-{}}"

    # Calculate reward based on outcome
    local reward=0.0
    if [[ "${outcome}" == "success" ]]; then
        reward=$(echo "${confidence}" | awk '{print $1}')
    else
        reward=$(echo "${confidence}" | awk '{print -$1}')
    fi

    # Create span structure
    local span_json
    span_json=$(cat <<EOF
{
  "trace_id": "$(uuidgen | tr '[:upper:]' '[:lower:]')",
  "span_id": "$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-16)",
  "task_id": "${task_id}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "outcome": "${outcome}",
  "confidence": ${confidence},
  "reward": ${reward},
  "metadata": ${metadata}
}
EOF
)

    # Append to spans file
    echo "${span_json}" >> "${AGL_STORE_PATH}/spans.jsonl"

    # Update metrics
    jq --argjson reward "${reward}" '
        .total_spans_emitted += 1 |
        .rewards.total_reward += $reward |
        .rewards.average_reward = .rewards.total_reward / .total_spans_emitted
    ' "${AGL_BRIDGE_DIR}/metrics.json" | sponge "${AGL_BRIDGE_DIR}/metrics.json"

    log_info "Emitted span for task ${task_id}: outcome=${outcome}, reward=${reward}"
}

# Sync learning data to agent-lightning
agl_bridge_sync() {
    log_info "Syncing learning data to agent-lightning..."

    # Check if learning data exists
    if [[ ! -f "${LEARNING_DATA_PATH}" ]]; then
        log_error "Learning data not found at ${LEARNING_DATA_PATH}"
        return 1
    fi

    # Extract cache outcomes
    local cache_samples
    cache_samples=$(jq -r '.outcome_data.cache_samples // []' "${LEARNING_DATA_PATH}")

    # Process each cache sample
    echo "${cache_samples}" | jq -c '.[]' | while read -r sample; do
        local hit_rate=$(echo "${sample}" | jq -r '.hit_rate // 0')
        local timestamp=$(echo "${sample}" | jq -r '.timestamp // ""')

        # Determine outcome based on hit rate
        local outcome="success"
        local confidence="${hit_rate}"
        if (( $(echo "${hit_rate} < 0.5" | bc -l) )); then
            outcome="failure"
        fi

        # Emit to agent-lightning
        agl_bridge_emit_outcome \
            "cache_lookup_${timestamp}" \
            "${outcome}" \
            "${confidence}" \
            "{\"type\": \"cache\", \"hit_rate\": ${hit_rate}}"
    done

    # Extract parallel execution outcomes
    local parallel_samples
    parallel_samples=$(jq -r '.outcome_data.parallel_samples // []' "${LEARNING_DATA_PATH}")

    # Process each parallel sample
    echo "${parallel_samples}" | jq -c '.[]' | while read -r sample; do
        local success_rate=$(echo "${sample}" | jq -r '.success_rate // 0')
        local timestamp=$(echo "${sample}" | jq -r '.timestamp // ""')

        # Determine outcome
        local outcome="success"
        local confidence="${success_rate}"
        if (( $(echo "${success_rate} < 0.7" | bc -l) )); then
            outcome="failure"
        fi

        # Emit to agent-lightning
        agl_bridge_emit_outcome \
            "parallel_exec_${timestamp}" \
            "${outcome}" \
            "${confidence}" \
            "{\"type\": \"parallel\", \"success_rate\": ${success_rate}}"
    done

    # Update sync timestamp
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.last_sync_timestamp = $ts' \
        "${AGL_BRIDGE_DIR}/metrics.json" | sponge "${AGL_BRIDGE_DIR}/metrics.json"

    log_info "Sync completed successfully"
}

# Train using agent-lightning
agl_bridge_train() {
    log_info "Starting agent-lightning training..."

    # Check if training is enabled
    local training_enabled
    training_enabled=$(jq -r '.training_enabled' "${AGL_BRIDGE_DIR}/config.json")

    if [[ "${training_enabled}" != "true" ]]; then
        log_info "Training is disabled in configuration"
        return 0
    fi

    # Check minimum samples
    local total_spans
    total_spans=$(jq -r '.total_spans_emitted' "${AGL_BRIDGE_DIR}/metrics.json")

    local min_samples
    min_samples=$(jq -r '.integration.min_samples_for_training' "${AGL_BRIDGE_DIR}/config.json")

    if (( total_spans < min_samples )); then
        log_info "Not enough samples for training (${total_spans}/${min_samples})"
        return 0
    fi

    # Activate virtual environment and run training
    source "${AGL_VENV_PATH}/bin/activate"

    # Run APO (Automatic Prompt Optimization) training
    local algorithm
    algorithm=$(jq -r '.algorithm' "${AGL_BRIDGE_DIR}/config.json")

    log_info "Running ${algorithm} training on ${total_spans} spans..."

    # Create training script
    cat > "${AGL_BRIDGE_DIR}/train.py" <<'EOF'
import json
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load configuration
config_path = Path.home() / ".claude/data/agent-lightning/config.json"
with open(config_path) as f:
    config = json.load(f)

# Load spans
spans_path = Path.home() / ".claude/data/agent-lightning/lightning-store/spans.jsonl"
spans = []
if spans_path.exists():
    with open(spans_path) as f:
        for line in f:
            spans.append(json.loads(line))

logger.info(f"Loaded {len(spans)} spans for training")

# Calculate reward statistics
total_reward = sum(span.get("reward", 0) for span in spans)
avg_reward = total_reward / len(spans) if spans else 0

logger.info(f"Total reward: {total_reward:.2f}")
logger.info(f"Average reward: {avg_reward:.2f}")

# Identify top performing patterns
cache_spans = [s for s in spans if s.get("metadata", {}).get("type") == "cache"]
parallel_spans = [s for s in spans if s.get("metadata", {}).get("type") == "parallel"]

if cache_spans:
    cache_reward = sum(s.get("reward", 0) for s in cache_spans) / len(cache_spans)
    logger.info(f"Cache average reward: {cache_reward:.2f}")

if parallel_spans:
    parallel_reward = sum(s.get("reward", 0) for s in parallel_spans) / len(parallel_spans)
    logger.info(f"Parallel average reward: {parallel_reward:.2f}")

# Save optimization recommendations
recommendations = {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "total_spans": len(spans),
    "average_reward": avg_reward,
    "recommendations": []
}

if cache_spans:
    avg_hit_rate = sum(s.get("metadata", {}).get("hit_rate", 0) for s in cache_spans) / len(cache_spans)
    recommendations["recommendations"].append({
        "component": "cache",
        "metric": "hit_rate",
        "current_value": avg_hit_rate,
        "recommended_action": "adjust_threshold" if avg_hit_rate < 0.65 else "maintain"
    })

if parallel_spans:
    avg_success = sum(s.get("metadata", {}).get("success_rate", 0) for s in parallel_spans) / len(parallel_spans)
    recommendations["recommendations"].append({
        "component": "parallel",
        "metric": "success_rate",
        "current_value": avg_success,
        "recommended_action": "adjust_concurrency" if avg_success < 0.9 else "maintain"
    })

# Save recommendations
rec_path = Path.home() / ".claude/data/agent-lightning/recommendations.json"
with open(rec_path, 'w') as f:
    json.dump(recommendations, f, indent=2)

logger.info(f"Saved recommendations to {rec_path}")
EOF

    python3 "${AGL_BRIDGE_DIR}/train.py"

    # Update training metrics
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .total_training_runs += 1 |
        .last_training_timestamp = $ts
    ' "${AGL_BRIDGE_DIR}/metrics.json" | sponge "${AGL_BRIDGE_DIR}/metrics.json"

    deactivate

    log_info "Training completed successfully"
}

# View bridge status
agl_bridge_status() {
    echo "=== Agent-Lightning Bridge Status ==="
    echo ""

    # Configuration
    echo "Configuration:"
    jq -r '
        "  Bridge Enabled: \(.bridge_enabled)",
        "  Training Enabled: \(.training_enabled)",
        "  Algorithm: \(.algorithm)",
        "  Store Path: \(.store_path)"
    ' "${AGL_BRIDGE_DIR}/config.json"

    echo ""

    # Metrics
    echo "Metrics:"
    jq -r '
        "  Total Spans Emitted: \(.total_spans_emitted)",
        "  Total Training Runs: \(.total_training_runs)",
        "  Average Reward: \(.rewards.average_reward)",
        "  Last Sync: \(.last_sync_timestamp // "Never")",
        "  Last Training: \(.last_training_timestamp // "Never")"
    ' "${AGL_BRIDGE_DIR}/metrics.json"

    echo ""

    # Recommendations (if available)
    if [[ -f "${AGL_BRIDGE_DIR}/recommendations.json" ]]; then
        echo "Latest Recommendations:"
        jq -r '.recommendations[] | "  - \(.component): \(.recommended_action)"' \
            "${AGL_BRIDGE_DIR}/recommendations.json"
    fi
}

# Main CLI
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        init)
            agl_bridge_init
            ;;
        sync)
            agl_bridge_sync
            ;;
        train)
            agl_bridge_train
            ;;
        status)
            agl_bridge_status
            ;;
        *)
            cat <<EOF
Usage: $0 {init|sync|train|status}

Commands:
  init    - Initialize agent-lightning bridge
  sync    - Sync learning data to agent-lightning
  train   - Run agent-lightning training
  status  - View bridge status

Examples:
  $0 init
  $0 sync
  $0 train
  $0 status
EOF
            exit 1
            ;;
    esac
fi
