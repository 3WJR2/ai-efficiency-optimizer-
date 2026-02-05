#!/usr/bin/env bash
# test-parallel.sh - Test parallel execution system
# Demonstrates performance improvement over sequential execution

set -euo pipefail

echo "=== Parallel Execution Test ==="
echo

# Source parallel executor
source "$HOME/.claude/scripts/parallel-executor.sh"

echo "Test 1: Simple parallel execution (4 independent tasks)"
echo "Each task sleeps for 2 seconds"
echo

# Sequential baseline
echo "Running sequentially..."
seq_start=$(python3 -c "import time; print(int(time.time() * 1000))")

sleep 2 && echo "Task 1 done"
sleep 2 && echo "Task 2 done"
sleep 2 && echo "Task 3 done"
sleep 2 && echo "Task 4 done"

seq_end=$(python3 -c "import time; print(int(time.time() * 1000))")
seq_time=$((seq_end - seq_start))

echo "Sequential time: ${seq_time}ms"
echo

# Parallel execution
echo "Running in parallel..."
par_start=$(python3 -c "import time; print(int(time.time() * 1000))")

parallel_run \
  "sleep 2 && echo 'Task 1 done'" \
  "sleep 2 && echo 'Task 2 done'" \
  "sleep 2 && echo 'Task 3 done'" \
  "sleep 2 && echo 'Task 4 done'"

par_end=$(python3 -c "import time; print(int(time.time() * 1000))")
par_time=$((par_end - par_start))

echo "Parallel time: ${par_time}ms"
echo

# Calculate improvement
improvement=$(echo "scale=1; ($seq_time - $par_time) * 100 / $seq_time" | bc)

echo "=== Results ==="
echo "Sequential: ${seq_time}ms"
echo "Parallel: ${par_time}ms"
echo "Improvement: ${improvement}%"
echo

# Test 2: With dependencies
echo "Test 2: Tasks with dependencies"
echo

task_queue_clear > /dev/null

# Add tasks with dependencies
task_queue_add "task_a" "echo 'Task A starting' && sleep 1 && echo 'Task A done'"
task_queue_add "task_b" "echo 'Task B starting' && sleep 1 && echo 'Task B done'"
task_queue_add "task_c" "echo 'Task C starting (waits for A)' && sleep 1 && echo 'Task C done'" "task_a"
task_queue_add "task_d" "echo 'Task D starting (waits for A,B)' && sleep 1 && echo 'Task D done'" "task_a" "task_b"

echo "Dependency graph:"
echo "  A (no deps) ─┬─→ C (deps: A)"
echo "  B (no deps) ─┘"
echo "               └─→ D (deps: A, B)"
echo

echo "Expected execution:"
echo "  Level 0: A, B (parallel)"
echo "  Level 1: C (after A)"
echo "  Level 2: D (after A, B)"
echo

# Validate no circular dependencies
task_queue_validate

# Execute
dep_start=$(python3 -c "import time; print(int(time.time() * 1000))")
parallel_execute
dep_end=$(python3 -c "import time; print(int(time.time() * 1000))")
dep_time=$((dep_end - dep_start))

echo "Execution time with dependencies: ${dep_time}ms"
echo "Expected: ~3s (3 levels, each ~1s)"
echo

# Show metrics
echo "=== Performance Metrics ==="
show_metrics
