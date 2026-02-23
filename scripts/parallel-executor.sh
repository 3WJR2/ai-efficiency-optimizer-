#!/usr/bin/env bash
# parallel-executor.sh - Main parallel execution engine
# Part of Phase 1B Parallel Execution Infrastructure

set -euo pipefail

CONFIG_FILE="$HOME/.claude/data/parallel-config.json"
METRICS_FILE="$HOME/.claude/data/parallel-metrics.json"

# Source dependencies
source "$HOME/.claude/scripts/task-queue.sh"

# Initialize configuration
init_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "1.0.0",
  "max_concurrent_processes": 5,
  "process_timeout_seconds": 300,
  "retry_attempts": 3,
  "retry_delay_seconds": 2,
  "enable_resource_limits": true,
  "max_memory_mb_per_process": 500,
  "enable_metrics_tracking": true,
  "aggregation_strategy": "concatenate"
}
EOF
  fi
}

# Initialize metrics
init_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then
    cat > "$METRICS_FILE" << 'EOF'
{
  "version": "1.0.0",
  "total_executions": 0,
  "total_parallel_tasks": 0,
  "avg_execution_time_ms": 0,
  "avg_parallelism": 0,
  "total_time_saved_ms": 0,
  "success_rate": 100.0,
  "last_updated": ""
}
EOF
  fi
}

# Execute single task
execute_task() {
  local task_id="$1"
  local command="$2"
  local timeout=$(jq -r '.process_timeout_seconds' "$CONFIG_FILE")

  # Mark as running
  task_queue_update "$task_id" "running"

  # Execute with timeout
  local output_file=$(mktemp)
  local error_file=$(mktemp)
  local exit_code=0

  (
    eval "$command" > "$output_file" 2> "$error_file"
  ) &
  local pid=$!

  # Wait with timeout
  local elapsed=0
  while kill -0 $pid 2>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
      kill -9 $pid 2>/dev/null || true
      echo "Timeout after ${timeout}s" > "$error_file"
      exit_code=124
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [[ $exit_code -eq 0 ]]; then
    wait $pid
    exit_code=$?
  fi

  # Read outputs
  local output=$(cat "$output_file" 2>/dev/null || echo "")
  local error=$(cat "$error_file" 2>/dev/null || echo "")

  # Update task
  if [[ $exit_code -eq 0 ]]; then
    task_queue_update "$task_id" "completed" "$exit_code" "$output" ""
  else
    task_queue_update "$task_id" "failed" "$exit_code" "" "$error"
  fi

  # Cleanup
  rm -f "$output_file" "$error_file"

  return $exit_code
}

# Execute tasks in parallel
parallel_execute() {
  local start_time=$(python3 -c "import time; print(int(time.time() * 1000))")

  # Get max concurrent from config
  local max_concurrent=$(jq -r '.max_concurrent_processes' "$CONFIG_FILE")

  local total_tasks=0
  local completed_tasks=0
  local failed_tasks=0

  echo "Starting parallel execution (max concurrent: $max_concurrent)..."

  # Main execution loop
  while true; do
    # Get ready tasks
    local ready_tasks=($(task_queue_get_ready))

    if [[ ${#ready_tasks[@]} -eq 0 ]]; then
      # Check if any tasks are still running
      local running_count=$(jq '[.tasks | to_entries | map(select(.value.status == "running"))] | length' "$HOME/.claude/data/task-queue.json")

      if [[ $running_count -eq 0 ]]; then
        # No ready tasks and nothing running - we're done
        break
      else
        # Wait for running tasks
        sleep 1
        continue
      fi
    fi

    # Count currently running tasks
    local running_count=$(jq '[.tasks | to_entries | map(select(.value.status == "running"))] | length' "$HOME/.claude/data/task-queue.json")

    # Spawn tasks up to max concurrent
    for task_id in "${ready_tasks[@]}"; do
      if [[ $running_count -ge $max_concurrent ]]; then
        break
      fi

      # Get task command
      local command=$(jq -r --arg id "$task_id" '.tasks[$id].command' "$HOME/.claude/data/task-queue.json")

      echo "Spawning task: $task_id"

      # Execute in background
      execute_task "$task_id" "$command" &

      running_count=$((running_count + 1))
      total_tasks=$((total_tasks + 1))
    done

    # Brief sleep to avoid busy waiting
    sleep 0.5
  done

  # Wait for all background jobs
  wait

  # Calculate statistics
  local end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
  local total_time=$((end_time - start_time))

  completed_tasks=$(jq '[.tasks | to_entries | map(select(.value.status == "completed"))] | length' "$HOME/.claude/data/task-queue.json")
  failed_tasks=$(jq '[.tasks | to_entries | map(select(.value.status == "failed"))] | length' "$HOME/.claude/data/task-queue.json")

  echo ""
  echo "Execution complete:"
  echo "  Total tasks: $total_tasks"
  echo "  Completed: $completed_tasks"
  echo "  Failed: $failed_tasks"
  echo "  Total time: ${total_time}ms"

  # Update metrics
  update_metrics "$total_tasks" "$completed_tasks" "$failed_tasks" "$total_time"

  # Track outcome for active learning (async, non-blocking)
  if [[ -f "$HOME/.claude/scripts/outcome-tracker.sh" ]]; then
    "$HOME/.claude/scripts/outcome-tracker.sh" track-parallel >/dev/null 2>&1 &
  fi
}

# Update performance metrics
update_metrics() {
  local total_tasks=$1
  local completed=$2
  local failed=$3
  local execution_time=$4

  local success_rate=$(echo "scale=2; $completed * 100 / $total_tasks" | bc)
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --argjson tasks "$total_tasks" \
     --argjson completed "$completed" \
     --argjson time "$execution_time" \
     --argjson success "$success_rate" \
     --arg ts "$now" '
    .total_executions += 1 |
    .total_parallel_tasks += $tasks |
    .avg_execution_time_ms = (
      (.avg_execution_time_ms * (.total_executions - 1) + $time) / .total_executions
    ) |
    .success_rate = (
      (.success_rate * (.total_executions - 1) + $success) / .total_executions
    ) |
    .last_updated = $ts
  ' "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
}

# Simple interface: run commands in parallel
# Usage: parallel_run "cmd1" "cmd2" "cmd3" ...
parallel_run() {
  local commands=("$@")

  # Clear queue
  task_queue_clear > /dev/null

  # Add all commands to queue
  local task_num=1
  for cmd in "${commands[@]}"; do
    task_queue_add "task_$task_num" "$cmd"
    task_num=$((task_num + 1))
  done

  # Execute
  parallel_execute

  # Print results
  echo ""
  echo "Results:"
  for ((i=1; i<task_num; i++)); do
    local result=$(task_queue_get_result "task_$i")
    echo "Task $i: $result"
  done
}

# Show parallel execution metrics
show_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then
    echo "No metrics available"
    return 0
  fi

  jq -r '
    "=== Parallel Execution Metrics ===",
    "",
    "Total executions: \(.total_executions)",
    "Total parallel tasks: \(.total_parallel_tasks)",
    "Avg execution time: \(.avg_execution_time_ms)ms",
    "Success rate: \(.success_rate)%",
    "",
    "Last updated: \(.last_updated)"
  ' "$METRICS_FILE"
}

# Initialize
init_config
init_metrics

# Export functions
export -f parallel_execute
export -f parallel_run
export -f show_metrics
export -f execute_task
