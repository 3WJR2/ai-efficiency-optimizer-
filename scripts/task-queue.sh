#!/usr/bin/env bash
# task-queue.sh - Task queue management for parallel execution
# Part of Phase 1B Parallel Execution Infrastructure

set -euo pipefail

QUEUE_FILE="$HOME/.claude/data/task-queue.json"
LOCK_FILE="$HOME/.claude/data/task-queue.lock"

# Initialize queue file if not exists
init_queue() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    cat > "$QUEUE_FILE" << 'EOF'
{
  "version": "1.0.0",
  "tasks": {},
  "metadata": {
    "created_at": "",
    "last_updated": ""
  }
}
EOF
    # Set timestamps
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg ts "$now" '.metadata.created_at = $ts | .metadata.last_updated = $ts' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
    mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
  fi
}

# Acquire lock for queue operations
acquire_lock() {
  local timeout=10
  local elapsed=0

  while [[ -f "$LOCK_FILE" ]] && [[ $elapsed -lt $timeout ]]; do
    sleep 0.1
    elapsed=$((elapsed + 1))
  done

  if [[ -f "$LOCK_FILE" ]]; then
    echo "Failed to acquire lock after ${timeout}s" >&2
    return 1
  fi

  echo $$ > "$LOCK_FILE"
}

# Release lock
release_lock() {
  rm -f "$LOCK_FILE"
}

# Add task to queue
# Usage: task_queue_add <task_id> <command> [depends_on...]
task_queue_add() {
  local task_id="$1"
  local command="$2"
  shift 2
  local depends_on=("$@")

  acquire_lock || return 1

  # Build dependencies array
  local deps_json="[]"
  if [[ ${#depends_on[@]} -gt 0 ]]; then
    deps_json=$(printf '%s\n' "${depends_on[@]}" | jq -R . | jq -s .)
  fi

  # Add task
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg id "$task_id" \
     --arg cmd "$command" \
     --argjson deps "$deps_json" \
     --arg ts "$now" '
    .tasks[$id] = {
      "task_id": $id,
      "command": $cmd,
      "depends_on": $deps,
      "status": "pending",
      "created_at": $ts,
      "started_at": null,
      "completed_at": null,
      "exit_code": null,
      "output": null,
      "error": null
    } |
    .metadata.last_updated = $ts
  ' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"

  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
  release_lock

  echo "Task $task_id added to queue"
}

# Get task status
# Usage: task_queue_status <task_id>
task_queue_status() {
  local task_id="$1"

  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "Task queue not initialized" >&2
    return 1
  fi

  jq -r --arg id "$task_id" '
    .tasks[$id] // empty |
    "Task: \(.task_id)",
    "Status: \(.status)",
    "Command: \(.command)",
    "Dependencies: \(.depends_on | join(", ") // "none")",
    "Created: \(.created_at)",
    "Started: \(.started_at // "not started")",
    "Completed: \(.completed_at // "not completed")",
    "Exit code: \(.exit_code // "N/A")"
  ' "$QUEUE_FILE"
}

# Get tasks ready to execute (no dependencies or all deps completed)
# Usage: task_queue_get_ready
task_queue_get_ready() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    return 0
  fi

  # Get completed tasks
  local completed_tasks=$(jq -r '.tasks | to_entries | map(select(.value.status == "completed")) | map(.key)' "$QUEUE_FILE")

  jq -r --argjson completed "$completed_tasks" '
    .tasks | to_entries |
    map(select(.value.status == "pending")) |
    map(select(
      (.value.depends_on | length) == 0 or
      (.value.depends_on | all(. as $dep | $completed | index($dep) != null))
    )) |
    map(.value.task_id) |
    .[]
  ' "$QUEUE_FILE"
}

# Update task status
# Usage: task_queue_update <task_id> <status> [exit_code] [output] [error]
task_queue_update() {
  local task_id="$1"
  local status="$2"
  local exit_code="${3:-null}"
  local output="${4:-null}"
  local error="${5:-null}"

  acquire_lock || return 1

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local time_field=""

  case "$status" in
    running)
      time_field="started_at"
      ;;
    completed|failed)
      time_field="completed_at"
      ;;
  esac

  jq --arg id "$task_id" \
     --arg status "$status" \
     --arg exit_code "$exit_code" \
     --arg output "$output" \
     --arg error "$error" \
     --arg ts "$now" \
     --arg time_field "$time_field" '
    if .tasks[$id] then
      .tasks[$id].status = $status |
      if $exit_code != "null" then .tasks[$id].exit_code = ($exit_code | tonumber) else . end |
      if $output != "null" then .tasks[$id].output = $output else . end |
      if $error != "null" then .tasks[$id].error = $error else . end |
      if $time_field != "" then .tasks[$id][$time_field] = $ts else . end |
      .metadata.last_updated = $ts
    else
      .
    end
  ' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"

  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
  release_lock
}

# List all tasks
# Usage: task_queue_list [status]
task_queue_list() {
  local filter_status="${1:-all}"

  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "No tasks in queue"
    return 0
  fi

  if [[ "$filter_status" == "all" ]]; then
    jq -r '.tasks | to_entries | map([.value.task_id, .value.status, .value.command]) | .[] | @tsv' "$QUEUE_FILE" | column -t -s $'\t'
  else
    jq -r --arg status "$filter_status" '.tasks | to_entries | map(select(.value.status == $status)) | map([.value.task_id, .value.status, .value.command]) | .[] | @tsv' "$QUEUE_FILE" | column -t -s $'\t'
  fi
}

# Get task result
# Usage: task_queue_get_result <task_id>
task_queue_get_result() {
  local task_id="$1"

  jq -r --arg id "$task_id" '.tasks[$id] | .output // .error // "No output"' "$QUEUE_FILE"
}

# Clear completed tasks
# Usage: task_queue_clear_completed
task_queue_clear_completed() {
  acquire_lock || return 1

  local count=$(jq '[.tasks | to_entries | map(select(.value.status == "completed" or .value.status == "failed"))] | length' "$QUEUE_FILE")

  jq '.tasks |= with_entries(select(.value.status != "completed" and .value.status != "failed"))' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"

  release_lock
  echo "Cleared $count completed/failed tasks"
}

# Clear all tasks
# Usage: task_queue_clear
task_queue_clear() {
  acquire_lock || return 1

  cat > "$QUEUE_FILE" << 'EOF'
{
  "version": "1.0.0",
  "tasks": {},
  "metadata": {
    "created_at": "",
    "last_updated": ""
  }
}
EOF

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg ts "$now" '.metadata.created_at = $ts | .metadata.last_updated = $ts' "$QUEUE_FILE" > "$QUEUE_FILE.tmp"
  mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"

  release_lock
  echo "Queue cleared"
}

# Get queue statistics
# Usage: task_queue_stats
task_queue_stats() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "Queue not initialized"
    return 0
  fi

  jq -r '
    .tasks | to_entries |
    {
      "total": length,
      "pending": map(select(.value.status == "pending")) | length,
      "running": map(select(.value.status == "running")) | length,
      "completed": map(select(.value.status == "completed")) | length,
      "failed": map(select(.value.status == "failed")) | length
    } |
    "Total tasks: \(.total)",
    "Pending: \(.pending)",
    "Running: \(.running)",
    "Completed: \(.completed)",
    "Failed: \(.failed)"
  ' "$QUEUE_FILE"
}

# Validate no circular dependencies
# Usage: task_queue_validate
task_queue_validate() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "Queue not initialized"
    return 0
  fi

  # Use Python for cycle detection (more reliable than bash)
  python3 << 'EOF'
import json
import sys

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})

# Build adjacency list
graph = {}
for task_id, task in tasks.items():
    graph[task_id] = task.get('depends_on', [])

# DFS cycle detection
def has_cycle(node, visited, rec_stack):
    visited.add(node)
    rec_stack.add(node)

    for neighbor in graph.get(node, []):
        if neighbor not in visited:
            if has_cycle(neighbor, visited, rec_stack):
                return True
        elif neighbor in rec_stack:
            return True

    rec_stack.remove(node)
    return False

visited = set()
for node in graph:
    if node not in visited:
        if has_cycle(node, visited, set()):
            print(f"Circular dependency detected involving: {node}")
            sys.exit(1)

print("No circular dependencies detected")
sys.exit(0)
EOF
}

# Initialize queue on source
init_queue

# Export functions
export -f task_queue_add
export -f task_queue_status
export -f task_queue_get_ready
export -f task_queue_update
export -f task_queue_list
export -f task_queue_get_result
export -f task_queue_clear_completed
export -f task_queue_clear
export -f task_queue_stats
export -f task_queue_validate
