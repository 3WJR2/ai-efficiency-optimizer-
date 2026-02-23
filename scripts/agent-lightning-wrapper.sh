#!/usr/bin/env bash
#
# agent-lightning-wrapper.sh - Integration wrapper for Agent Lightning with Claude's Adaptive Intelligence
#
# Purpose: Bridge Agent Lightning's RL training capabilities with Claude's existing adaptive learning system
# Features:
#   - Event emission for Agent Lightning tracing
#   - Integration with existing caching infrastructure
#   - Outcome tracking for adaptive learning
#   - Multi-agent coordination patterns
#
# Usage:
#   source ~/.claude/scripts/agent-lightning-wrapper.sh
#   agl_init "task_name"
#   agl_emit_prompt "prompt text" "model_name"
#   agl_emit_tool_call "tool_name" '{"arg": "value"}'
#   agl_emit_reward 0.85 "success"
#   agl_finalize
#

set -euo pipefail

# Configuration
AGL_DATA_DIR="${HOME}/.claude/data/agent-lightning"
AGL_STORE_DIR="${AGL_DATA_DIR}/store"
AGL_TRACES_DIR="${AGL_DATA_DIR}/traces"
AGL_CONFIG_FILE="${AGL_DATA_DIR}/config.json"
AGL_METRICS_FILE="${AGL_DATA_DIR}/metrics.json"

# Integration with existing systems
CACHE_METRICS_FILE="${HOME}/.claude/data/cache-metrics.json"
LEARNING_DATA_FILE="${HOME}/.claude/data/learning-data.json"
OUTCOME_TRACKER="${HOME}/.claude/scripts/outcome-tracker.sh"

# Session state
AGL_SESSION_ID=""
AGL_TASK_ID=""
AGL_START_TIME=""
AGL_EVENTS=()

#
# Initialize Agent Lightning wrapper
#
agl_init() {
    local task_name="${1:-default_task}"

    # Create directories
    mkdir -p "$AGL_DATA_DIR" "$AGL_STORE_DIR" "$AGL_TRACES_DIR"

    # Generate session ID
    AGL_SESSION_ID="session_$(date +%s)_$$"
    AGL_TASK_ID="$task_name"
    AGL_START_TIME=$(date +%s)
    AGL_EVENTS=()

    # Initialize config if not exists
    if [[ ! -f "$AGL_CONFIG_FILE" ]]; then
        cat > "$AGL_CONFIG_FILE" <<EOF
{
  "version": "0.3.0",
  "integration": {
    "adaptive_intelligence": true,
    "caching": true,
    "parallel_execution": true,
    "outcome_tracking": true
  },
  "store": {
    "type": "local",
    "path": "$AGL_STORE_DIR"
  },
  "training": {
    "enabled": false,
    "algorithm": "ppo",
    "batch_size": 32,
    "learning_rate": 0.0001
  },
  "tracing": {
    "enabled": true,
    "collect_token_ids": false,
    "collect_logprobs": false,
    "collect_spans": true
  }
}
EOF
    fi

    # Initialize metrics if not exists
    if [[ ! -f "$AGL_METRICS_FILE" ]]; then
        cat > "$AGL_METRICS_FILE" <<EOF
{
  "total_sessions": 0,
  "total_events": 0,
  "total_rewards": 0,
  "average_reward": 0.0,
  "success_rate": 0.0,
  "integration_metrics": {
    "cache_hits_during_rl": 0,
    "adaptive_optimizations_applied": 0,
    "parallel_executions": 0
  },
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    fi

    echo "[AGL] Initialized session: $AGL_SESSION_ID for task: $AGL_TASK_ID"
}

#
# Emit a prompt event (for Agent Lightning tracing)
#
agl_emit_prompt() {
    local prompt="$1"
    local model="${2:-default}"
    local timestamp=$(date +%s%3N)

    local event=$(cat <<EOF
{
  "type": "prompt",
  "session_id": "$AGL_SESSION_ID",
  "task_id": "$AGL_TASK_ID",
  "timestamp": $timestamp,
  "model": "$model",
  "prompt": $(echo "$prompt" | jq -Rs .),
  "metadata": {
    "adaptive_stage": "$(get_adaptive_stage)"
  }
}
EOF
    )

    AGL_EVENTS+=("$event")
    echo "[AGL] Emitted prompt event for model: $model"
}

#
# Emit a tool call event
#
agl_emit_tool_call() {
    local tool_name="$1"
    local tool_args="$2"
    local timestamp=$(date +%s%3N)

    local event=$(cat <<EOF
{
  "type": "tool_call",
  "session_id": "$AGL_SESSION_ID",
  "task_id": "$AGL_TASK_ID",
  "timestamp": $timestamp,
  "tool_name": "$tool_name",
  "tool_args": $tool_args
}
EOF
    )

    AGL_EVENTS+=("$event")
    echo "[AGL] Emitted tool call: $tool_name"
}

#
# Emit a tool result event
#
agl_emit_tool_result() {
    local tool_name="$1"
    local result="$2"
    local success="${3:-true}"
    local timestamp=$(date +%s%3N)

    local event=$(cat <<EOF
{
  "type": "tool_result",
  "session_id": "$AGL_SESSION_ID",
  "task_id": "$AGL_TASK_ID",
  "timestamp": $timestamp,
  "tool_name": "$tool_name",
  "success": $success,
  "result": $(echo "$result" | jq -Rs .)
}
EOF
    )

    AGL_EVENTS+=("$event")
    echo "[AGL] Emitted tool result: $tool_name (success=$success)"
}

#
# Emit a response event
#
agl_emit_response() {
    local response="$1"
    local model="${2:-default}"
    local timestamp=$(date +%s%3N)

    local event=$(cat <<EOF
{
  "type": "response",
  "session_id": "$AGL_SESSION_ID",
  "task_id": "$AGL_TASK_ID",
  "timestamp": $timestamp,
  "model": "$model",
  "response": $(echo "$response" | jq -Rs .)
}
EOF
    )

    AGL_EVENTS+=("$event")
    echo "[AGL] Emitted response event"
}

#
# Emit a reward signal (critical for RL training)
#
agl_emit_reward() {
    local reward="$1"
    local reason="${2:-no_reason}"
    local timestamp=$(date +%s%3N)

    local event=$(cat <<EOF
{
  "type": "reward",
  "session_id": "$AGL_SESSION_ID",
  "task_id": "$AGL_TASK_ID",
  "timestamp": $timestamp,
  "reward": $reward,
  "reason": "$reason",
  "metadata": {
    "adaptive_confidence": $(get_adaptive_confidence)
  }
}
EOF
    )

    AGL_EVENTS+=("$event")

    # Integrate with outcome tracker
    if [[ -x "$OUTCOME_TRACKER" ]]; then
        "$OUTCOME_TRACKER" track "agent_lightning" "rl_reward" "$reward" "$reason"
    fi

    echo "[AGL] Emitted reward: $reward (reason: $reason)"
}

#
# Finalize session and write trace
#
agl_finalize() {
    local end_time=$(date +%s)
    local duration=$((end_time - AGL_START_TIME))

    # Create trace file
    local trace_file="${AGL_TRACES_DIR}/${AGL_SESSION_ID}.json"

    cat > "$trace_file" <<EOF
{
  "session_id": "$AGL_SESSION_ID",
  "task_id": "$AGL_TASK_ID",
  "start_time": $AGL_START_TIME,
  "end_time": $end_time,
  "duration_seconds": $duration,
  "event_count": ${#AGL_EVENTS[@]},
  "events": [
$(printf '%s\n' "${AGL_EVENTS[@]}" | paste -sd, -)
  ],
  "integration_data": {
    "adaptive_intelligence_enabled": true,
    "cache_enabled": true,
    "learning_stage": "$(get_adaptive_stage)"
  }
}
EOF

    # Update metrics
    update_agl_metrics

    echo "[AGL] Finalized session: $AGL_SESSION_ID"
    echo "[AGL] Trace written to: $trace_file"
    echo "[AGL] Duration: ${duration}s, Events: ${#AGL_EVENTS[@]}"
}

#
# Helper: Get current adaptive learning stage
#
get_adaptive_stage() {
    if [[ -f "$LEARNING_DATA_FILE" ]] && command -v jq &>/dev/null; then
        jq -r '.learning_stage // "unknown"' "$LEARNING_DATA_FILE" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

#
# Helper: Get adaptive confidence score
#
get_adaptive_confidence() {
    if [[ -f "$LEARNING_DATA_FILE" ]] && command -v jq &>/dev/null; then
        jq -r '.confidence_score // 0.5' "$LEARNING_DATA_FILE" 2>/dev/null || echo "0.5"
    else
        echo "0.5"
    fi
}

#
# Helper: Update Agent Lightning metrics
#
update_agl_metrics() {
    if [[ ! -f "$AGL_METRICS_FILE" ]] || ! command -v jq &>/dev/null; then
        return
    fi

    local total_sessions=$(jq '.total_sessions // 0' "$AGL_METRICS_FILE")
    local total_events=$(jq '.total_events // 0' "$AGL_METRICS_FILE")

    # Count rewards
    local rewards=()
    for event in "${AGL_EVENTS[@]}"; do
        local event_type=$(echo "$event" | jq -r '.type')
        if [[ "$event_type" == "reward" ]]; then
            local reward=$(echo "$event" | jq -r '.reward')
            rewards+=("$reward")
        fi
    done

    local total_rewards=$((total_sessions + ${#rewards[@]}))
    local avg_reward=0.0
    if [[ ${#rewards[@]} -gt 0 ]]; then
        avg_reward=$(printf '%s\n' "${rewards[@]}" | awk '{sum+=$1} END {print sum/NR}')
    fi

    # Check cache integration
    local cache_hits=0
    if [[ -f "$CACHE_METRICS_FILE" ]]; then
        cache_hits=$(jq '.prompt_cache.hits // 0' "$CACHE_METRICS_FILE")
    fi

    # Update metrics file
    jq --arg sessions "$((total_sessions + 1))" \
       --arg events "$((total_events + ${#AGL_EVENTS[@]}))" \
       --arg rewards "$total_rewards" \
       --arg avg "$avg_reward" \
       --arg cache "$cache_hits" \
       --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.total_sessions = ($sessions | tonumber) |
        .total_events = ($events | tonumber) |
        .total_rewards = ($rewards | tonumber) |
        .average_reward = ($avg | tonumber) |
        .integration_metrics.cache_hits_during_rl = ($cache | tonumber) |
        .last_updated = $updated' \
       "$AGL_METRICS_FILE" > "${AGL_METRICS_FILE}.tmp" && \
       mv "${AGL_METRICS_FILE}.tmp" "$AGL_METRICS_FILE"
}

#
# Start Agent Lightning store (if not running)
#
agl_start_store() {
    local port="${1:-8765}"

    if lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "[AGL] Store already running on port $port"
        return 0
    fi

    echo "[AGL] Starting Lightning Store on port $port..."
    agl store --port "$port" --store-dir "$AGL_STORE_DIR" &

    # Wait for store to be ready
    local max_wait=30
    local waited=0
    while ! lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; do
        sleep 1
        waited=$((waited + 1))
        if [[ $waited -ge $max_wait ]]; then
            echo "[AGL] ERROR: Store failed to start within ${max_wait}s"
            return 1
        fi
    done

    echo "[AGL] Store started successfully on port $port"
}

#
# Stop Agent Lightning store
#
agl_stop_store() {
    local port="${1:-8765}"

    local pid=$(lsof -Pi ":$port" -sTCP:LISTEN -t 2>/dev/null)
    if [[ -n "$pid" ]]; then
        echo "[AGL] Stopping store (PID: $pid)..."
        kill "$pid"
        echo "[AGL] Store stopped"
    else
        echo "[AGL] No store running on port $port"
    fi
}

#
# View Agent Lightning metrics
#
agl_metrics() {
    if [[ ! -f "$AGL_METRICS_FILE" ]]; then
        echo "[AGL] No metrics file found"
        return 1
    fi

    echo "=== Agent Lightning Metrics ==="
    cat "$AGL_METRICS_FILE" | jq .
}

#
# View recent traces
#
agl_traces() {
    local limit="${1:-5}"

    if [[ ! -d "$AGL_TRACES_DIR" ]]; then
        echo "[AGL] No traces directory found"
        return 1
    fi

    echo "=== Recent Agent Lightning Traces (last $limit) ==="
    ls -t "$AGL_TRACES_DIR"/*.json 2>/dev/null | head -n "$limit" | while read -r trace_file; do
        echo ""
        echo "Trace: $(basename "$trace_file")"
        jq -r '"\(.task_id) - Duration: \(.duration_seconds)s - Events: \(.event_count)"' "$trace_file"
    done
}

#
# Export trace for training (converts to HuggingFace dataset format)
#
agl_export_trace() {
    local session_id="$1"
    local output_file="${2:-${AGL_DATA_DIR}/export_${session_id}.json}"

    local trace_file="${AGL_TRACES_DIR}/${session_id}.json"
    if [[ ! -f "$trace_file" ]]; then
        echo "[AGL] ERROR: Trace not found: $session_id"
        return 1
    fi

    echo "[AGL] Exporting trace $session_id to $output_file..."

    # Convert to training format
    jq '{
        task_id: .task_id,
        duration: .duration_seconds,
        prompts: [.events[] | select(.type == "prompt") | .prompt],
        tool_calls: [.events[] | select(.type == "tool_call") | {name: .tool_name, args: .tool_args}],
        rewards: [.events[] | select(.type == "reward") | {value: .reward, reason: .reason}],
        total_reward: ([.events[] | select(.type == "reward") | .reward] | add),
        success: (([.events[] | select(.type == "reward") | .reward] | add) > 0.5)
    }' "$trace_file" > "$output_file"

    echo "[AGL] Export complete: $output_file"
}

#
# Integration check - verify all systems
#
agl_check_integration() {
    echo "=== Agent Lightning Integration Status ==="
    echo ""

    # Check installation
    if command -v agl &>/dev/null; then
        echo "✓ Agent Lightning CLI installed"
        agl --version 2>/dev/null || echo "  Version: 0.3.0+"
    else
        echo "✗ Agent Lightning CLI not found"
    fi

    # Check directories
    [[ -d "$AGL_DATA_DIR" ]] && echo "✓ Data directory exists" || echo "✗ Data directory missing"
    [[ -f "$AGL_CONFIG_FILE" ]] && echo "✓ Config file exists" || echo "✗ Config file missing"
    [[ -f "$AGL_METRICS_FILE" ]] && echo "✓ Metrics file exists" || echo "✗ Metrics file missing"

    # Check adaptive intelligence integration
    [[ -f "$LEARNING_DATA_FILE" ]] && echo "✓ Adaptive Intelligence integrated" || echo "✗ Adaptive Intelligence not found"
    [[ -f "$CACHE_METRICS_FILE" ]] && echo "✓ Cache system integrated" || echo "✗ Cache system not found"
    [[ -x "$OUTCOME_TRACKER" ]] && echo "✓ Outcome tracker integrated" || echo "✗ Outcome tracker not found"

    # Check Python dependencies
    if python3 -c "import agentlightning" 2>/dev/null; then
        echo "✓ Python agentlightning package installed"
    else
        echo "✗ Python agentlightning package not found"
    fi

    echo ""
    echo "=== Summary ==="
    if [[ -f "$AGL_METRICS_FILE" ]]; then
        jq -r '"Sessions: \(.total_sessions) | Events: \(.total_events) | Avg Reward: \(.average_reward)"' "$AGL_METRICS_FILE"
    fi
}

# Export functions
export -f agl_init
export -f agl_emit_prompt
export -f agl_emit_tool_call
export -f agl_emit_tool_result
export -f agl_emit_response
export -f agl_emit_reward
export -f agl_finalize
export -f agl_start_store
export -f agl_stop_store
export -f agl_metrics
export -f agl_traces
export -f agl_export_trace
export -f agl_check_integration

echo "[AGL] Wrapper loaded. Use 'agl_check_integration' to verify setup."
