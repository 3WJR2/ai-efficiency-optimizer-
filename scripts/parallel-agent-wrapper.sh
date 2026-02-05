#!/usr/bin/env bash
# parallel-agent-wrapper.sh - Integration layer for running agents in parallel
# Enables existing agents to leverage parallel execution infrastructure

set -euo pipefail

# Source dependencies
source "$HOME/.claude/scripts/task-queue.sh"
source "$HOME/.claude/scripts/parallel-executor.sh"
source "$HOME/.claude/scripts/dependency-resolver.sh"
source "$HOME/.claude/scripts/result-aggregator.sh"

# Run multiple agents in parallel
# Usage: run_agents_parallel <agent1:task1> <agent2:task2> ...
run_agents_parallel() {
  local agent_tasks=("$@")

  if [[ ${#agent_tasks[@]} -eq 0 ]]; then
    echo "Usage: run_agents_parallel <agent1:task1> <agent2:task2> ..." >&2
    return 1
  fi

  echo "Running ${#agent_tasks[@]} agents in parallel..."
  echo

  # Clear queue
  task_queue_clear > /dev/null

  # Add agents to queue
  local task_num=1
  for agent_task in "${agent_tasks[@]}"; do
    local agent_type="${agent_task%%:*}"
    local task_desc="${agent_task#*:}"

    local command="claude_agent \"$agent_type\" \"$task_desc\""
    task_queue_add "agent_${task_num}" "$command"

    echo "Queued: $agent_type - $task_desc"
    task_num=$((task_num + 1))
  done

  echo

  # Execute in parallel
  parallel_execute

  echo
  echo "=== Agent Results ==="
  aggregate_results summary $(seq -f "agent_%g" 1 $((task_num - 1)))
}

# Placeholder for actual agent invocation
# This would call the real agent system
claude_agent() {
  local agent_type="$1"
  local task="$2"

  echo "[$agent_type] Processing: $task"
  sleep 1  # Simulate work
  echo "[$agent_type] Completed: $task"
}

# Explore multiple code areas in parallel
explore_parallel() {
  local patterns=("$@")

  echo "Exploring ${#patterns[@]} code areas in parallel..."

  task_queue_clear > /dev/null

  local task_num=1
  for pattern in "${patterns[@]}"; do
    task_queue_add "explore_$task_num" "echo 'Exploring: $pattern' && sleep 1"
    task_num=$((task_num + 1))
  done

  parallel_execute

  echo
  aggregate_results concatenate $(seq -f "explore_%g" 1 $((task_num - 1)))
}

# Research multiple topics in parallel
research_parallel() {
  local topics=("$@")

  echo "Researching ${#topics[@]} topics in parallel..."

  task_queue_clear > /dev/null

  local task_num=1
  for topic in "${topics[@]}"; do
    task_queue_add "research_$task_num" "echo 'Researching: $topic' && sleep 2"
    task_num=$((task_num + 1))
  done

  parallel_execute

  echo
  aggregate_results merge $(seq -f "research_%g" 1 $((task_num - 1)))
}

# Analyze multiple files in parallel
analyze_parallel() {
  local files=("$@")

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "Usage: analyze_parallel <file1> <file2> ..." >&2
    return 1
  fi

  echo "Analyzing ${#files[@]} files in parallel..."

  task_queue_clear > /dev/null

  local task_num=1
  for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
      task_queue_add "analyze_$task_num" "wc -l '$file' && head -5 '$file'"
      echo "Queued: $file"
      task_num=$((task_num + 1))
    fi
  done

  if [[ $task_num -eq 1 ]]; then
    echo "No valid files to analyze" >&2
    return 1
  fi

  echo

  parallel_execute

  echo
  aggregate_results concatenate $(seq -f "analyze_%g" 1 $((task_num - 1)))
}

# Run multiple code implementations in parallel
implement_parallel() {
  echo "Parallel implementation workflow:"
  echo "  1. Research (parallel)"
  echo "  2. Plan (sequential, depends on research)"
  echo "  3. Implement (parallel, depends on plan)"
  echo "  4. Test (sequential, depends on implement)"
  echo

  task_queue_clear > /dev/null

  # Stage 1: Parallel research
  task_queue_add "research_api" "echo 'Researching API patterns...'"
  task_queue_add "research_db" "echo 'Researching database schema...'"
  task_queue_add "research_ui" "echo 'Researching UI components...'"

  # Stage 2: Planning (depends on all research)
  task_queue_add "plan" "echo 'Creating implementation plan...'" \
    "research_api" "research_db" "research_ui"

  # Stage 3: Parallel implementation (depends on plan)
  task_queue_add "implement_api" "echo 'Implementing API...'" "plan"
  task_queue_add "implement_db" "echo 'Implementing database...'" "plan"
  task_queue_add "implement_ui" "echo 'Implementing UI...'" "plan"

  # Stage 4: Testing (depends on all implementations)
  task_queue_add "test" "echo 'Running integration tests...'" \
    "implement_api" "implement_db" "implement_ui"

  echo "Visualizing workflow:"
  visualize_dependencies

  echo
  echo "Executing workflow..."
  parallel_execute

  echo
  aggregate_by_level
}

# Quick parallel file operations
parallel_grep() {
  local pattern="$1"
  shift
  local files=("$@")

  echo "Searching for '$pattern' in ${#files[@]} files (parallel)..."

  task_queue_clear > /dev/null

  local task_num=1
  for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
      task_queue_add "grep_$task_num" "grep -n '$pattern' '$file' || echo 'No matches'"
      task_num=$((task_num + 1))
    fi
  done

  parallel_execute

  aggregate_results concatenate $(seq -f "grep_%g" 1 $((task_num - 1)))
}

# Batch process with parallel execution
batch_process() {
  local command_template="$1"
  shift
  local items=("$@")

  echo "Batch processing ${#items[@]} items with: $command_template"

  task_queue_clear > /dev/null

  local task_num=1
  for item in "${items[@]}"; do
    local command="${command_template//\{\}/$item}"
    task_queue_add "batch_$task_num" "$command"
    task_num=$((task_num + 1))
  done

  parallel_execute

  aggregate_results summary $(seq -f "batch_%g" 1 $((task_num - 1)))
}

# Show help
show_help() {
  cat << 'EOF'
Parallel Agent Wrapper - Run agents and commands in parallel

USAGE:
  source ~/.claude/scripts/parallel-agent-wrapper.sh
  <command> [arguments...]

COMMANDS:
  run_agents_parallel <agent:task> ...
    Run multiple agents in parallel
    Example: run_agents_parallel "explore:auth" "explore:api" "explore:db"

  explore_parallel <pattern> ...
    Explore multiple code areas in parallel
    Example: explore_parallel "*.js" "*.ts" "*.py"

  research_parallel <topic> ...
    Research multiple topics in parallel
    Example: research_parallel "React" "TypeScript" "Node.js"

  analyze_parallel <file> ...
    Analyze multiple files in parallel
    Example: analyze_parallel src/*.js

  implement_parallel
    Run multi-stage implementation workflow with parallel stages

  parallel_grep <pattern> <files...>
    Search for pattern across multiple files in parallel

  batch_process <command_template> <items...>
    Execute command template for each item in parallel
    Use {} as placeholder for item
    Example: batch_process "echo Processing: {}" item1 item2 item3

EXAMPLES:
  # Explore 3 code areas simultaneously
  explore_parallel "authentication" "database" "api"

  # Research 4 technologies at once
  research_parallel "Redis" "PostgreSQL" "MongoDB" "ElasticSearch"

  # Analyze all scripts
  analyze_parallel ~/.claude/scripts/*.sh

  # Complex workflow with dependencies
  implement_parallel

For more info, see: ~/.claude/docs/PHASE-1B-PARALLEL-EXECUTION.md
EOF
}

# Export functions
export -f run_agents_parallel
export -f explore_parallel
export -f research_parallel
export -f analyze_parallel
export -f implement_parallel
export -f parallel_grep
export -f batch_process
export -f show_help

# Show quick help if sourced
if [[ "${BASH_SOURCE[0]:-}" != "${0}" ]]; then
  echo "✓ Parallel agent wrapper loaded"
  echo "Run 'show_help' for usage information"
fi
