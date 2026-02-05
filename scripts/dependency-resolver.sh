#!/usr/bin/env bash
# dependency-resolver.sh - Advanced dependency resolution for parallel execution
# Part of Phase 1B Parallel Execution Infrastructure

set -euo pipefail

QUEUE_FILE="$HOME/.claude/data/task-queue.json"

# Resolve dependencies and create execution plan
# Returns execution levels (groups of tasks that can run in parallel)
resolve_dependencies() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "Task queue not found" >&2
    return 1
  fi

  # Use Python for sophisticated graph algorithms
  python3 << 'EOF'
import json
import sys
from collections import defaultdict, deque

# Load task queue
with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})

# Build dependency graph
graph = {}  # task -> dependencies
reverse_graph = defaultdict(list)  # task -> dependents

for task_id, task in tasks.items():
    if task['status'] == 'pending':
        deps = task.get('depends_on', [])
        graph[task_id] = deps
        for dep in deps:
            reverse_graph[dep].append(task_id)

# Detect circular dependencies
def detect_cycles():
    visited = set()
    rec_stack = set()

    def has_cycle(node, path):
        if node in rec_stack:
            cycle = path[path.index(node):] + [node]
            return cycle
        if node in visited:
            return None

        visited.add(node)
        rec_stack.add(node)

        for neighbor in graph.get(node, []):
            cycle = has_cycle(neighbor, path + [node])
            if cycle:
                return cycle

        rec_stack.remove(node)
        return None

    for node in graph:
        if node not in visited:
            cycle = has_cycle(node, [])
            if cycle:
                return cycle
    return None

# Check for cycles
cycle = detect_cycles()
if cycle:
    print(f"ERROR: Circular dependency detected: {' -> '.join(cycle)}", file=sys.stderr)
    sys.exit(1)

# Calculate execution levels using topological sort
def calculate_levels():
    # Count dependencies for each task
    in_degree = {task: len(deps) for task, deps in graph.items()}

    # Initialize with tasks that have no dependencies
    levels = []
    current_level = [task for task, degree in in_degree.items() if degree == 0]

    processed = set()

    while current_level:
        levels.append(sorted(current_level))  # Sort for deterministic output
        processed.update(current_level)

        # Find next level
        next_level = []
        for task in current_level:
            for dependent in reverse_graph.get(task, []):
                # Decrement in-degree
                in_degree[dependent] -= 1

                # If all dependencies satisfied, add to next level
                if in_degree[dependent] == 0 and dependent not in processed:
                    next_level.append(dependent)

        current_level = next_level

    return levels

# Calculate execution levels
levels = calculate_levels()

# Output as JSON
output = {
    "total_levels": len(levels),
    "total_tasks": sum(len(level) for level in levels),
    "max_parallelism": max(len(level) for level in levels) if levels else 0,
    "levels": [
        {
            "level": i,
            "tasks": level,
            "parallelism": len(level)
        }
        for i, level in enumerate(levels)
    ]
}

print(json.dumps(output, indent=2))
EOF
}

# Get tasks ready for execution at current level
# Usage: get_ready_tasks <completed_tasks_json>
get_ready_tasks() {
  local completed_tasks="${1:-[]}"

  python3 << EOF
import json
import sys

# Load task queue
with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})
completed = set(json.loads('$completed_tasks'))

# Find tasks ready to execute
ready = []
for task_id, task in tasks.items():
    if task['status'] != 'pending':
        continue

    deps = task.get('depends_on', [])

    # Check if all dependencies are completed
    if all(dep in completed for dep in deps):
        ready.append(task_id)

# Output as JSON array
print(json.dumps(ready))
EOF
}

# Visualize dependency graph (ASCII art)
visualize_dependencies() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "Task queue not found" >&2
    return 1
  fi

  echo "Dependency Graph:"
  echo

  python3 << 'EOF'
import json

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})

# Group by dependency level
no_deps = []
has_deps = []

for task_id, task in tasks.items():
    if task['status'] != 'pending':
        continue

    deps = task.get('depends_on', [])
    if not deps:
        no_deps.append(task_id)
    else:
        has_deps.append((task_id, deps))

# Print tasks with no dependencies
if no_deps:
    print("Level 0 (No dependencies - run first):")
    for task in no_deps:
        print(f"  • {task}")
    print()

# Print tasks with dependencies
if has_deps:
    print("Tasks with dependencies:")
    for task, deps in has_deps:
        deps_str = ", ".join(deps)
        print(f"  • {task} ← depends on: {deps_str}")
    print()

# Print execution plan
print("Execution Plan:")
EOF

  # Get and display levels
  local plan=$(resolve_dependencies 2>/dev/null || echo '{"levels":[]}')

  echo "$plan" | jq -r '
    .levels[] |
    "  Level \(.level): \(.tasks | join(", ")) (\(.parallelism) parallel)"
  '
}

# Validate all dependencies exist
validate_dependencies() {
  python3 << 'EOF'
import json
import sys

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})
task_ids = set(tasks.keys())

errors = []

for task_id, task in tasks.items():
    deps = task.get('depends_on', [])
    for dep in deps:
        if dep not in task_ids:
            errors.append(f"Task '{task_id}' depends on non-existent task '{dep}'")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)
else:
    print("All dependencies are valid")
    sys.exit(0)
EOF
}

# Calculate critical path (longest dependency chain)
calculate_critical_path() {
  python3 << 'EOF'
import json
from collections import defaultdict, deque

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})

# Build dependency graph
graph = defaultdict(list)
for task_id, task in tasks.items():
    if task['status'] == 'pending':
        for dep in task.get('depends_on', []):
            graph[dep].append(task_id)

# Calculate longest path using dynamic programming
def longest_path(node, memo={}):
    if node in memo:
        return memo[node]

    if not graph[node]:
        return 1

    max_length = max(longest_path(child, memo) for child in graph[node])
    memo[node] = max_length + 1
    return memo[node]

# Find critical path
max_path = 0
critical_tasks = []

for task_id in tasks:
    if tasks[task_id]['status'] == 'pending':
        path_length = longest_path(task_id)
        if path_length > max_path:
            max_path = path_length
            critical_tasks = [task_id]

print(f"Critical path length: {max_path}")
print(f"Tasks on critical path: {', '.join(critical_tasks)}")
EOF
}

# Estimate execution time based on dependencies
estimate_execution_time() {
  local avg_task_time="${1:-5}"  # seconds

  local plan=$(resolve_dependencies 2>/dev/null || echo '{"total_levels":0}')
  local levels=$(echo "$plan" | jq -r '.total_levels')

  local estimated_time=$((levels * avg_task_time))

  echo "Estimated execution time: ${estimated_time}s (assuming ${avg_task_time}s per task)"
  echo "Number of execution levels: $levels"
}

# Export functions
export -f resolve_dependencies
export -f get_ready_tasks
export -f visualize_dependencies
export -f validate_dependencies
export -f calculate_critical_path
export -f estimate_execution_time
