#!/usr/bin/env bash
# result-aggregator.sh - Intelligent result aggregation for parallel execution
# Part of Phase 1B Parallel Execution Infrastructure

set -euo pipefail

QUEUE_FILE="$HOME/.claude/data/task-queue.json"
CONFIG_FILE="$HOME/.claude/data/parallel-config.json"

# Aggregate results using specified strategy
# Usage: aggregate_results <strategy> [task_ids...]
aggregate_results() {
  local strategy="$1"
  shift
  local task_ids=("$@")

  case "$strategy" in
    concatenate)
      aggregate_concatenate "${task_ids[@]}"
      ;;
    merge)
      aggregate_merge "${task_ids[@]}"
      ;;
    json_merge)
      aggregate_json_merge "${task_ids[@]}"
      ;;
    summary)
      aggregate_summary "${task_ids[@]}"
      ;;
    *)
      echo "Unknown aggregation strategy: $strategy" >&2
      echo "Available: concatenate, merge, json_merge, summary" >&2
      return 1
      ;;
  esac
}

# Strategy 1: Simple concatenation
# Joins all outputs with separator
aggregate_concatenate() {
  local task_ids=("$@")

  echo "=== Aggregated Results (Concatenate) ==="
  echo

  for task_id in "${task_ids[@]}"; do
    local output=$(jq -r --arg id "$task_id" '.tasks[$id].output // ""' "$QUEUE_FILE")
    local status=$(jq -r --arg id "$task_id" '.tasks[$id].status' "$QUEUE_FILE")

    echo "--- $task_id ($status) ---"
    if [[ -n "$output" ]]; then
      echo "$output"
    else
      echo "(no output)"
    fi
    echo
  done
}

# Strategy 2: Intelligent merge
# Deduplicates lines, preserves order, removes empty lines
aggregate_merge() {
  local task_ids=("$@")

  echo "=== Aggregated Results (Intelligent Merge) ==="
  echo

  # Collect all outputs
  local all_outputs=""
  for task_id in "${task_ids[@]}"; do
    local output=$(jq -r --arg id "$task_id" '.tasks[$id].output // ""' "$QUEUE_FILE")
    if [[ -n "$output" ]]; then
      all_outputs="$all_outputs$output"$'\n'
    fi
  done

  # Deduplicate while preserving order
  echo "$all_outputs" | awk '!seen[$0]++' | grep -v '^$' || echo "(no output)"
}

# Strategy 3: JSON merge
# Combines JSON outputs into single object/array
aggregate_json_merge() {
  local task_ids=("$@")

  echo "=== Aggregated Results (JSON Merge) ==="
  echo

  # Collect all JSON outputs
  local json_array="["
  local first=true

  for task_id in "${task_ids[@]}"; do
    local output=$(jq -r --arg id "$task_id" '.tasks[$id].output // ""' "$QUEUE_FILE")

    if [[ -n "$output" ]]; then
      # Try to parse as JSON
      if echo "$output" | jq empty 2>/dev/null; then
        if [[ "$first" == "true" ]]; then
          json_array="$json_array$output"
          first=false
        else
          json_array="$json_array,$output"
        fi
      else
        # Not valid JSON, wrap as string
        local escaped=$(echo "$output" | jq -Rs .)
        if [[ "$first" == "true" ]]; then
          json_array="$json_array{\"task\":\"$task_id\",\"output\":$escaped}"
          first=false
        else
          json_array="$json_array,{\"task\":\"$task_id\",\"output\":$escaped}"
        fi
      fi
    fi
  done

  json_array="$json_array]"

  # Pretty print
  echo "$json_array" | jq .
}

# Strategy 4: Summary
# Provides statistics and summary of results
aggregate_summary() {
  local task_ids=("$@")

  echo "=== Results Summary ==="
  echo

  local total=${#task_ids[@]}
  local completed=0
  local failed=0
  local total_chars=0

  for task_id in "${task_ids[@]}"; do
    local status=$(jq -r --arg id "$task_id" '.tasks[$id].status' "$QUEUE_FILE")
    local output=$(jq -r --arg id "$task_id" '.tasks[$id].output // ""' "$QUEUE_FILE")

    if [[ "$status" == "completed" ]]; then
      completed=$((completed + 1))
    elif [[ "$status" == "failed" ]]; then
      failed=$((failed + 1))
    fi

    total_chars=$((total_chars + ${#output}))
  done

  echo "Total tasks: $total"
  echo "Completed: $completed"
  echo "Failed: $failed"
  echo "Success rate: $(echo "scale=1; $completed * 100 / $total" | bc)%"
  echo "Total output: $total_chars characters"
  echo

  # Show individual task status
  echo "Task Status:"
  for task_id in "${task_ids[@]}"; do
    local status=$(jq -r --arg id "$task_id" '.tasks[$id].status' "$QUEUE_FILE")
    local exit_code=$(jq -r --arg id "$task_id" '.tasks[$id].exit_code // "N/A"' "$QUEUE_FILE")

    printf "  %-20s %s (exit: %s)\n" "$task_id" "$status" "$exit_code"
  done
}

# Get all task results as structured data
get_all_results() {
  local task_ids=("$@")

  python3 << EOF
import json

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})
task_ids = $(printf '%s\n' "${task_ids[@]}" | jq -R . | jq -s .)

results = []
for task_id in task_ids:
    if task_id in tasks:
        task = tasks[task_id]
        results.append({
            "task_id": task_id,
            "status": task['status'],
            "output": task.get('output'),
            "error": task.get('error'),
            "exit_code": task.get('exit_code'),
            "started_at": task.get('started_at'),
            "completed_at": task.get('completed_at')
        })

print(json.dumps(results, indent=2))
EOF
}

# Aggregate by execution level
# Useful for seeing results grouped by dependency level
aggregate_by_level() {
  local plan=$(source /Users/wallonwalusayi/.claude/scripts/dependency-resolver.sh && resolve_dependencies 2>/dev/null)

  echo "=== Results by Execution Level ==="
  echo

  local num_levels=$(echo "$plan" | jq -r '.total_levels')

  for ((i=0; i<num_levels; i++)); do
    local level_tasks=$(echo "$plan" | jq -r --arg level "$i" '.levels[] | select(.level == ($level | tonumber)) | .tasks[]')

    echo "Level $i:"
    while IFS= read -r task_id; do
      [[ -z "$task_id" ]] && continue

      local status=$(jq -r --arg id "$task_id" '.tasks[$id].status' "$QUEUE_FILE")
      local output=$(jq -r --arg id "$task_id" '.tasks[$id].output // "(no output)"' "$QUEUE_FILE")

      echo "  • $task_id [$status]: $output"
    done <<< "$level_tasks"
    echo
  done
}

# Extract specific fields from results
extract_field() {
  local field="$1"
  shift
  local task_ids=("$@")

  for task_id in "${task_ids[@]}"; do
    local value=$(jq -r --arg id "$task_id" --arg field "$field" '.tasks[$id][$field] // ""' "$QUEUE_FILE")
    echo "$task_id: $value"
  done
}

# Check if all tasks succeeded
all_tasks_succeeded() {
  local task_ids=("$@")

  for task_id in "${task_ids[@]}"; do
    local status=$(jq -r --arg id "$task_id" '.tasks[$id].status' "$QUEUE_FILE")

    if [[ "$status" != "completed" ]]; then
      return 1
    fi
  done

  return 0
}

# Get failed tasks
get_failed_tasks() {
  local task_ids=("$@")

  for task_id in "${task_ids[@]}"; do
    local status=$(jq -r --arg id "$task_id" '.tasks[$id].status' "$QUEUE_FILE")

    if [[ "$status" == "failed" ]]; then
      echo "$task_id"
    fi
  done
}

# Aggregate outputs and save to file
save_aggregated_results() {
  local output_file="$1"
  local strategy="$2"
  shift 2
  local task_ids=("$@")

  aggregate_results "$strategy" "${task_ids[@]}" > "$output_file"
  echo "Results saved to: $output_file"
}

# Export functions
export -f aggregate_results
export -f aggregate_concatenate
export -f aggregate_merge
export -f aggregate_json_merge
export -f aggregate_summary
export -f get_all_results
export -f aggregate_by_level
export -f extract_field
export -f all_tasks_succeeded
export -f get_failed_tasks
export -f save_aggregated_results
