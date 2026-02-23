#!/usr/bin/env bash
# workflow-optimizer.sh - Analyzes workflows and suggests optimizations
# Identifies parallelization opportunities and bottlenecks

set -euo pipefail

QUEUE_FILE="$HOME/.claude/data/task-queue.json"

# Source dependencies
source "$HOME/.claude/scripts/dependency-resolver.sh" 2>/dev/null || true

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Analyze current workflow and suggest optimizations
analyze_workflow() {
  if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "No workflow to analyze. Add tasks to the queue first."
    return 1
  fi

  echo -e "${BLUE}=== Workflow Optimization Analysis ===${NC}"
  echo

  # Get workflow statistics
  local total_tasks=$(jq '.tasks | length' "$QUEUE_FILE")

  if [[ $total_tasks -eq 0 ]]; then
    echo "No tasks in queue."
    return 0
  fi

  echo "Total tasks: $total_tasks"
  echo

  # Analyze dependency structure
  python3 << 'EOF'
import json
import sys
from collections import defaultdict, deque

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})

# Build dependency graph
graph = defaultdict(list)  # task -> dependencies
reverse_graph = defaultdict(list)  # task -> dependents
in_degree = {}

for task_id, task in tasks.items():
    deps = task.get('depends_on', [])
    graph[task_id] = deps
    in_degree[task_id] = len(deps)
    for dep in deps:
        reverse_graph[dep].append(task_id)

# Calculate metrics
no_deps = [t for t, d in in_degree.items() if d == 0]
high_deps = [(t, d) for t, d in in_degree.items() if d >= 3]
single_deps = [t for t in tasks if len(reverse_graph[t]) == 1]

# Find parallelizable groups
parallelizable = []
for task_id in tasks:
    if in_degree[task_id] == 0:
        parallelizable.append(task_id)

# Calculate longest path (critical path)
def longest_path_length(node, memo={}):
    if node in memo:
        return memo[node]

    if not reverse_graph[node]:
        return 1

    max_length = max(longest_path_length(child, memo) for child in reverse_graph[node])
    memo[node] = max_length + 1
    return memo[node]

critical_length = max(longest_path_length(t) for t in tasks) if tasks else 0

# Calculate potential parallelism
total_levels = 0
current_level = no_deps[:]
visited = set()
levels = []

while current_level:
    levels.append(len(current_level))
    visited.update(current_level)
    next_level = []

    for task in current_level:
        for dependent in reverse_graph[task]:
            if all(dep in visited for dep in graph[dependent]) and dependent not in visited:
                next_level.append(dependent)

    current_level = list(set(next_level))
    total_levels += 1

# Output analysis
print("=== Dependency Analysis ===")
print(f"Tasks with no dependencies: {len(no_deps)}")
print(f"Tasks with 3+ dependencies: {len(high_deps)}")
print(f"Execution levels: {total_levels}")
print(f"Critical path length: {critical_length}")
print(f"Average parallelism: {len(tasks) / total_levels if total_levels > 0 else 0:.1f}")
print(f"Max parallel tasks: {max(levels) if levels else 0}")
print()

# Calculate potential speedup
sequential_time = len(tasks)
parallel_time = total_levels
speedup = sequential_time / parallel_time if parallel_time > 0 else 1

print("=== Performance Potential ===")
print(f"Sequential execution: {sequential_time} time units")
print(f"Parallel execution: {parallel_time} time units")
print(f"Potential speedup: {speedup:.1f}x ({(1 - parallel_time/sequential_time) * 100:.1f}% faster)")
print()

# Identify bottlenecks
print("=== Bottleneck Analysis ===")

bottlenecks = []
for task_id in tasks:
    dependents = len(reverse_graph[task_id])
    if dependents >= 3:
        bottlenecks.append((task_id, dependents))

if bottlenecks:
    print("Critical tasks (3+ dependents):")
    for task, count in sorted(bottlenecks, key=lambda x: x[1], reverse=True):
        print(f"  • {task}: {count} tasks depend on this")
else:
    print("✓ No critical bottlenecks detected")

print()

# Optimization suggestions
print("=== Optimization Suggestions ===")
suggestions = []

# Suggestion 1: Parallelizable tasks
if len(no_deps) > 1:
    suggestions.append(f"✓ {len(no_deps)} tasks can run immediately in parallel")

# Suggestion 2: Over-dependent tasks
if high_deps:
    suggestions.append(f"⚠ {len(high_deps)} tasks have 3+ dependencies - consider reducing")

# Suggestion 3: Single-chain tasks
long_chains = [t for t in tasks if len(reverse_graph[t]) == 1 and len(graph[t]) == 1]
if len(long_chains) > 3:
    suggestions.append(f"💡 {len(long_chains)} tasks in single chains - look for parallelization")

# Suggestion 4: Independent groups
if speedup > 2:
    suggestions.append(f"🚀 High parallelization potential ({speedup:.1f}x speedup possible)")
elif speedup < 1.5:
    suggestions.append(f"⚠ Low parallelization potential - mostly sequential workflow")

if suggestions:
    for i, suggestion in enumerate(suggestions, 1):
        print(f"{i}. {suggestion}")
else:
    print("✓ Workflow is well-optimized")

EOF
}

# Suggest specific optimizations for current workflow
suggest_optimizations() {
  echo -e "${BLUE}=== Specific Optimization Recommendations ===${NC}"
  echo

  python3 << 'EOF'
import json
from collections import defaultdict

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})

# Build graphs
graph = defaultdict(list)
reverse_graph = defaultdict(list)

for task_id, task in tasks.items():
    deps = task.get('depends_on', [])
    graph[task_id] = deps
    for dep in deps:
        reverse_graph[dep].append(task_id)

print("Recommendations:")
print()

# 1. Identify unnecessary dependencies
print("1. Dependency Optimization:")
for task_id, deps in graph.items():
    # Check for transitive dependencies
    direct_deps = set(deps)
    indirect_deps = set()
    for dep in deps:
        indirect_deps.update(graph[dep])

    unnecessary = direct_deps & indirect_deps
    if unnecessary:
        print(f"  • {task_id}: Remove unnecessary dependencies: {', '.join(unnecessary)}")
        print(f"    (already covered by other dependencies)")

print()

# 2. Suggest task grouping
print("2. Task Grouping:")
no_deps = [t for t, d in graph.items() if not d]
if len(no_deps) > 1:
    print(f"  • Group {len(no_deps)} independent tasks for parallel execution:")
    for task in no_deps[:5]:  # Show first 5
        print(f"    - {task}")
    if len(no_deps) > 5:
        print(f"    ... and {len(no_deps) - 5} more")

print()

# 3. Critical path optimization
print("3. Critical Path:")
# Find longest chains
def find_longest_chain(node, visited=set()):
    if node in visited:
        return []
    visited.add(node)

    if not reverse_graph[node]:
        return [node]

    chains = [find_longest_chain(child, visited.copy()) for child in reverse_graph[node]]
    longest = max(chains, key=len) if chains else []
    return [node] + longest

longest = []
for task in tasks:
    chain = find_longest_chain(task)
    if len(chain) > len(longest):
        longest = chain

if len(longest) > 3:
    print(f"  • Longest dependency chain ({len(longest)} tasks):")
    print(f"    {' → '.join(longest[:5])}")
    if len(longest) > 5:
        print(f"    ... → {longest[-1]}")
    print(f"  • Consider if any steps can be parallelized")

print()

# 4. Resource optimization
print("4. Resource Optimization:")
max_parallel = len(no_deps)
print(f"  • Current max parallelism: {max_parallel} tasks")
print(f"  • Recommended concurrent limit: {min(max_parallel, 5)}")
if max_parallel > 5:
    print(f"  • Consider batching into groups of 5 for resource efficiency")

EOF
}

# Visualize workflow efficiency
visualize_efficiency() {
  echo -e "${BLUE}=== Workflow Efficiency Visualization ===${NC}"
  echo

  python3 << 'EOF'
import json
from collections import defaultdict

with open('/Users/wallonwalusayi/.claude/data/task-queue.json') as f:
    data = json.load(f)

tasks = data.get('tasks', {})
graph = {t: tasks[t].get('depends_on', []) for t in tasks}

# Calculate execution levels
in_degree = {t: len(deps) for t, deps in graph.items()}
levels = []
current = [t for t, d in in_degree.items() if d == 0]
visited = set()

while current:
    levels.append(current[:])
    visited.update(current)
    next_level = []

    for task in current:
        for other_task, deps in graph.items():
            if task in deps and other_task not in visited:
                if all(d in visited for d in deps):
                    next_level.append(other_task)

    current = list(set(next_level))

# Visualize
print("Execution Timeline:")
print()
for i, level in enumerate(levels):
    bar_length = len(level) * 2
    bar = '█' * bar_length
    print(f"Level {i}: {bar} ({len(level)} tasks)")
    for task in level:
        print(f"         {task}")
    print()

print(f"Total execution levels: {len(levels)}")
print(f"Efficiency: {len(tasks) / len(levels) if levels else 0:.1f} tasks per level (avg)")

# Calculate utilization
max_parallel = max(len(level) for level in levels) if levels else 0
avg_parallel = len(tasks) / len(levels) if levels else 0
utilization = (avg_parallel / max_parallel * 100) if max_parallel > 0 else 0

print(f"Parallelism utilization: {utilization:.1f}%")

if utilization < 50:
    print("⚠ Low utilization - many sequential bottlenecks")
elif utilization < 80:
    print("✓ Moderate utilization - room for improvement")
else:
    print("🚀 High utilization - well-parallelized workflow")

EOF
}

# Compare sequential vs parallel execution estimates
compare_execution() {
  local avg_task_time="${1:-5}"  # seconds per task

  echo -e "${BLUE}=== Execution Time Comparison ===${NC}"
  echo

  local total_tasks=$(jq '.tasks | length' "$QUEUE_FILE")

  # Sequential time
  local sequential_time=$((total_tasks * avg_task_time))

  # Parallel time (based on levels)
  local plan=$(resolve_dependencies 2>/dev/null || echo '{"total_levels":0}')
  local levels=$(echo "$plan" | jq -r '.total_levels')
  local parallel_time=$((levels * avg_task_time))

  # Calculate savings
  local time_saved=$((sequential_time - parallel_time))
  local percent_saved=$(echo "scale=1; $time_saved * 100 / $sequential_time" | bc)

  echo "Assuming ${avg_task_time}s per task:"
  echo
  echo "Sequential execution: ${sequential_time}s"
  echo "Parallel execution:   ${parallel_time}s"
  echo "Time saved:           ${time_saved}s (${percent_saved}% faster)"
  echo

  # Show per-level breakdown
  echo "Execution breakdown:"
  echo "$plan" | jq -r '.levels[] | "  Level \(.level): \(.parallelism) tasks in parallel"'
}

# Generate optimization report
generate_report() {
  local output_file="${1:-/tmp/workflow-optimization-report.txt}"

  {
    echo "WORKFLOW OPTIMIZATION REPORT"
    echo "Generated: $(date)"
    echo "=" | head -c 60 | tr '\n' '='
    echo
    echo

    analyze_workflow
    echo
    echo

    suggest_optimizations
    echo
    echo

    visualize_efficiency
    echo
    echo

    compare_execution 5

  } > "$output_file"

  echo "Report saved to: $output_file"
  cat "$output_file"
}

# Main command
case "${1:-analyze}" in
  analyze)
    analyze_workflow
    ;;
  suggest)
    suggest_optimizations
    ;;
  visualize)
    visualize_efficiency
    ;;
  compare)
    compare_execution "${2:-5}"
    ;;
  report)
    generate_report "${2:-}"
    ;;
  *)
    echo "Usage: $0 {analyze|suggest|visualize|compare|report} [args]"
    echo
    echo "Commands:"
    echo "  analyze    - Analyze current workflow structure"
    echo "  suggest    - Suggest specific optimizations"
    echo "  visualize  - Show efficiency visualization"
    echo "  compare    - Compare sequential vs parallel execution times"
    echo "  report     - Generate full optimization report"
    exit 1
    ;;
esac
