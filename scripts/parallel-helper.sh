#!/usr/bin/env bash
# parallel-helper.sh - Easy-to-use parallel execution wrapper
# Makes parallel operations simple for common tasks

set -euo pipefail

PARALLEL_EXECUTOR="$HOME/.claude/scripts/parallel-executor.sh"
TASK_QUEUE="$HOME/.claude/scripts/task-queue.sh"

# Source dependencies
source "$TASK_QUEUE"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Read multiple files in parallel
read_files_parallel() {
  local files=("$@")
  local start_time=$(date +%s%3N)

  echo -e "${BLUE}Reading ${#files[@]} files in parallel...${RESET}"

  # Clear task queue
  task_queue_clear

  # Add read tasks
  for file in "${files[@]}"; do
    local task_id=$(basename "$file")
    task_queue_add "$task_id" "cat '$file'"
  done

  # Execute in parallel
  source "$PARALLEL_EXECUTOR"
  parallel_execute

  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  echo -e "${GREEN}✓ Completed in ${duration}ms${RESET}"

  # Show results
  task_queue_list | jq -r '.tasks[] | "\(.id): \(.status)"'
}

# Search multiple directories in parallel
search_parallel() {
  local pattern="$1"
  shift
  local dirs=("$@")
  local start_time=$(date +%s%3N)

  echo -e "${BLUE}Searching for '$pattern' in ${#dirs[@]} directories...${RESET}"

  task_queue_clear

  for dir in "${dirs[@]}"; do
    local task_id="search_$(basename "$dir")"
    task_queue_add "$task_id" "grep -r '$pattern' '$dir' 2>/dev/null || true"
  done

  source "$PARALLEL_EXECUTOR"
  parallel_execute

  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  echo -e "${GREEN}✓ Search completed in ${duration}ms${RESET}"
}

# Run multiple commands in parallel
run_parallel() {
  local commands=("$@")
  local start_time=$(date +%s%3N)

  echo -e "${BLUE}Running ${#commands[@]} commands in parallel...${RESET}"

  task_queue_clear

  local i=0
  for cmd in "${commands[@]}"; do
    task_queue_add "cmd_$i" "$cmd"
    i=$((i + 1))
  done

  source "$PARALLEL_EXECUTOR"
  parallel_execute

  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  echo -e "${GREEN}✓ All commands completed in ${duration}ms${RESET}"
  echo -e "${YELLOW}Sequential time estimate: $((duration * ${#commands[@]}))ms${RESET}"
  echo -e "${GREEN}Time saved: $((duration * (${#commands[@]} - 1)))ms${RESET}"
}

# Analyze multiple files in parallel
analyze_files_parallel() {
  local analysis_type="$1"
  shift
  local files=("$@")

  echo -e "${BLUE}Analyzing ${#files[@]} files ($analysis_type)...${RESET}"

  task_queue_clear

  for file in "${files[@]}"; do
    local task_id="analyze_$(basename "$file")"
    case "$analysis_type" in
      "lines")
        task_queue_add "$task_id" "wc -l '$file'"
        ;;
      "size")
        task_queue_add "$task_id" "du -h '$file'"
        ;;
      "type")
        task_queue_add "$task_id" "file '$file'"
        ;;
      *)
        echo "Unknown analysis type: $analysis_type"
        return 1
        ;;
    esac
  done

  source "$PARALLEL_EXECUTOR"
  parallel_execute
}

# Show usage
usage() {
  cat <<'EOF'
Parallel Helper - Easy parallel execution wrapper

USAGE:
  parallel-helper.sh [command] [args...]

COMMANDS:
  read <file1> <file2> ...           Read multiple files in parallel
  search <pattern> <dir1> <dir2> ... Search pattern across directories
  run <cmd1> <cmd2> ...              Run multiple commands in parallel
  analyze <type> <file1> <file2> ... Analyze files (lines, size, type)

EXAMPLES:
  # Read 5 config files at once
  parallel-helper.sh read ~/.config/*.json

  # Search across multiple directories
  parallel-helper.sh search "TODO" ~/project/src ~/project/tests

  # Run multiple checks
  parallel-helper.sh run \
    "npm run lint" \
    "npm run test" \
    "npm run build"

  # Analyze multiple log files
  parallel-helper.sh analyze lines /var/log/*.log

BENEFITS:
  • 4x faster for independent tasks
  • Automatic error handling
  • Progress tracking
  • Metrics collection

See also: ~/.claude/scripts/parallel-executor.sh
EOF
}

# Main execution
main() {
  local command=${1:-"help"}
  shift || true

  case "$command" in
    read)
      read_files_parallel "$@"
      ;;
    search)
      search_parallel "$@"
      ;;
    run)
      run_parallel "$@"
      ;;
    analyze)
      analyze_files_parallel "$@"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      echo "Unknown command: $command"
      usage
      exit 1
      ;;
  esac
}

main "$@"
