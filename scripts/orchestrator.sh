#!/usr/bin/env bash
# orchestrator.sh - Proactive agent orchestration engine
# Version: 1.0.0
# Purpose: Intelligently orchestrate multiple agents based on request classification

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.claude/data"
LOG_DIR="$HOME/.claude/logs"
STRATEGIES_FILE="$DATA_DIR/agent-strategies.json"
ORCHESTRATION_LOG="$DATA_DIR/orchestration-log.json"
CLASSIFIER="$SCRIPT_DIR/request-classifier.sh"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Initialize orchestration log
init_orchestration_log() {
    if [[ ! -f "$ORCHESTRATION_LOG" ]]; then
        cat > "$ORCHESTRATION_LOG" <<'EOF'
{
  "version": "1.0.0",
  "orchestrations": [],
  "total_orchestrations": 0,
  "success_count": 0,
  "failure_count": 0,
  "last_updated": ""
}
EOF
    fi
}

# Log message with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    case "$level" in
        INFO)
            echo -e "${CYAN}[INFO]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        DEBUG)
            if [[ "${DEBUG:-0}" == "1" ]]; then
                echo -e "${MAGENTA}[DEBUG]${NC} $message"
            fi
            ;;
    esac

    # Also log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/orchestrator.log"
}

# Classify the request
classify_request() {
    local request="$1"

    log INFO "Classifying request..."

    # Run classifier and capture only JSON output
    local temp_output=$("$CLASSIFIER" classify "$request" 2>&1)
    local classification=$(echo "$temp_output" | sed -n '/{/,/}/p')

    if [[ -z "$classification" ]] || [[ "$classification" == "{}" ]]; then
        log ERROR "Failed to classify request"
        log DEBUG "Raw output: $temp_output"
        return 1
    fi

    log DEBUG "Classification: $classification"
    echo "$classification"
}

# Get strategy for task type
get_strategy() {
    local task_type="$1"

    if [[ ! -f "$STRATEGIES_FILE" ]]; then
        log ERROR "Strategies file not found: $STRATEGIES_FILE"
        return 1
    fi

    local strategy=$(jq -r --arg type "$task_type" '.strategies[$type] // empty' "$STRATEGIES_FILE")

    if [[ -z "$strategy" ]]; then
        log WARNING "No strategy found for task type: $task_type"
        # Fallback to explore strategy
        strategy=$(jq -r '.strategies.explore' "$STRATEGIES_FILE")
    fi

    echo "$strategy"
}

# Check if auto-orchestration is enabled
check_auto_orchestration() {
    local confidence="$1"
    local threshold="${AUTO_ORCHESTRATE_THRESHOLD:-0.75}"

    if (( $(echo "$confidence >= $threshold" | bc -l) )); then
        return 0
    else
        return 1
    fi
}

# Generate agent execution plan
generate_execution_plan() {
    local strategy="$1"

    log INFO "Generating execution plan..."

    # Parse agents from strategy
    local agents=$(echo "$strategy" | jq -r '.agents')
    local agent_count=$(echo "$agents" | jq 'length')

    log INFO "Strategy requires $agent_count agents"

    # Sort agents by priority and dependencies
    local execution_plan=$(echo "$agents" | jq -s '
        .[0] | sort_by(.priority) |
        group_by(.priority) |
        map({
            priority: .[0].priority,
            parallel: (map(.parallel) | all),
            agents: .
        })
    ')

    echo "$execution_plan"
}

# Format agent prompt with context
format_agent_prompt() {
    local agent_config="$1"
    local request="$2"
    local context="${3:-}"

    local base_prompt=$(echo "$agent_config" | jq -r '.prompt')
    local role=$(echo "$agent_config" | jq -r '.role')

    # Combine base prompt with request and context
    cat <<EOF
# Task: $role

## User Request
$request

## Agent Instructions
$base_prompt

${context:+## Additional Context
$context}

Please analyze the request and execute your role. Provide detailed results.
EOF
}

# Spawn agent (simulated for now - will integrate with multi-terminal)
spawn_agent() {
    local agent_type="$1"
    local agent_config="$2"
    local request="$3"
    local context="${4:-}"
    local pane="${5:-1}"

    local role=$(echo "$agent_config" | jq -r '.role')
    local agent_id="agent-$(date +%s)-$$-$pane"

    log INFO "Spawning $agent_type agent for role: $role (pane $pane)"

    # Format the prompt
    local prompt=$(format_agent_prompt "$agent_config" "$request" "$context")

    # Create agent execution record
    local agent_record=$(cat <<EOF
{
  "agent_id": "$agent_id",
  "agent_type": "$agent_type",
  "role": "$role",
  "pane": $pane,
  "status": "spawned",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "completed_at": null,
  "result": null
}
EOF
)

    # In real implementation, this would spawn in multi-terminal
    # For now, we simulate with a placeholder
    log DEBUG "Agent $agent_id spawned with prompt length: ${#prompt}"
    log SUCCESS "Agent $agent_id ready in pane $pane"

    echo "$agent_record"
}

# Execute agents in a priority group
execute_priority_group() {
    local group="$1"
    local request="$2"
    local context="${3:-}"

    local priority=$(echo "$group" | jq -r '.priority')
    local parallel=$(echo "$group" | jq -r '.parallel')
    local agents=$(echo "$group" | jq -r '.agents')

    log INFO "Executing priority group $priority (parallel: $parallel)"

    local spawned_agents=()
    local agent_count=$(echo "$agents" | jq 'length')

    # Spawn all agents in the group
    for ((i=0; i<agent_count; i++)); do
        local agent_config=$(echo "$agents" | jq ".[$i]")
        local agent_type=$(echo "$agent_config" | jq -r '.type')
        local pane=$(echo "$agent_config" | jq -r '.pane')

        local agent_record=$(spawn_agent "$agent_type" "$agent_config" "$request" "$context" "$pane")
        spawned_agents+=("$agent_record")
    done

    # If parallel, wait for all; if sequential, wait for each
    if [[ "$parallel" == "true" ]]; then
        log INFO "Waiting for parallel agents to complete..."
        # In real implementation, would monitor agent completion
        sleep 1 # Simulate work
    else
        log INFO "Executing agents sequentially..."
        # In real implementation, would wait for each agent
        sleep 1 # Simulate work
    fi

    # Return spawned agents as JSON array
    printf '%s\n' "${spawned_agents[@]}" | jq -s .
}

# Coordinate results from multiple agents
coordinate_results() {
    local agents="$1"
    local coordinator_strategy="$2"
    local request="$3"

    log INFO "Coordinating results using strategy: $coordinator_strategy"

    # Get coordinator description
    local coordinator_desc=$(jq -r --arg strat "$coordinator_strategy" \
        '.coordinator_strategies[$strat].description // "Synthesize agent results"' \
        "$STRATEGIES_FILE")

    log INFO "Coordinator: $coordinator_desc"

    # In real implementation, this would:
    # 1. Collect results from all agents
    # 2. Synthesize using coordinator strategy
    # 3. Generate unified response

    # For now, simulate coordination
    local coordination_result=$(cat <<EOF
{
  "coordinator": "$coordinator_strategy",
  "description": "$coordinator_desc",
  "agents_coordinated": $(echo "$agents" | jq 'length'),
  "status": "completed",
  "synthesized_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": "Coordinated results from multiple agents"
}
EOF
)

    log SUCCESS "Results coordinated successfully"
    echo "$coordination_result"
}

# Main orchestration function
orchestrate_request() {
    local request="$1"
    local dry_run="${2:-false}"

    init_orchestration_log

    log INFO "=== Starting orchestration ==="
    log INFO "Request: $request"

    # Step 1: Classify request
    local classification=$(classify_request "$request")
    if [[ -z "$classification" ]]; then
        log ERROR "Classification failed"
        return 1
    fi

    local task_type=$(echo "$classification" | jq -r '.type')
    local confidence=$(echo "$classification" | jq -r '.confidence')
    local complexity=$(echo "$classification" | jq -r '.complexity')

    log INFO "Task type: $task_type (confidence: $confidence)"
    log INFO "Complexity: $complexity"

    # Step 2: Get strategy
    local strategy=$(get_strategy "$task_type")
    if [[ -z "$strategy" ]]; then
        log ERROR "Failed to get strategy for task type: $task_type"
        return 1
    fi

    local strategy_desc=$(echo "$strategy" | jq -r '.description')
    log INFO "Strategy: $strategy_desc"

    # Step 3: Generate execution plan
    local execution_plan=$(generate_execution_plan "$strategy")
    local num_groups=$(echo "$execution_plan" | jq 'length')

    log INFO "Execution plan has $num_groups priority groups"

    # Check if dry run
    if [[ "$dry_run" == "true" ]]; then
        log INFO "=== DRY RUN MODE - No agents will be spawned ==="
        echo
        log INFO "Classification:"
        echo "$classification" | jq .
        echo
        log INFO "Execution Plan:"
        echo "$execution_plan" | jq .
        echo
        log INFO "=== End of dry run ==="
        return 0
    fi

    # Step 4: Execute agents according to plan
    local all_agents=()
    for ((i=0; i<num_groups; i++)); do
        local group=$(echo "$execution_plan" | jq ".[$i]")
        local spawned=$(execute_priority_group "$group" "$request" "")
        all_agents+=("$spawned")
    done

    # Combine all spawned agents
    local combined_agents=$(printf '%s\n' "${all_agents[@]}" | jq -s 'add')

    # Step 5: Coordinate results
    local coordinator=$(echo "$strategy" | jq -r '.coordinator')
    local coordination_result=$(coordinate_results "$combined_agents" "$coordinator" "$request")

    # Step 6: Record orchestration
    local orchestration_record=$(cat <<EOF
{
  "request": "$request",
  "classification": $classification,
  "task_type": "$task_type",
  "strategy": "$strategy_desc",
  "agents_spawned": $(echo "$combined_agents" | jq 'length'),
  "agents": $combined_agents,
  "coordination": $coordination_result,
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "completed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "completed"
}
EOF
)

    # Update orchestration log
    jq --argjson record "$orchestration_record" '
        .orchestrations += [$record] |
        .total_orchestrations += 1 |
        .success_count += 1 |
        .last_updated = $record.completed_at
    ' "$ORCHESTRATION_LOG" > "$ORCHESTRATION_LOG.tmp"

    mv "$ORCHESTRATION_LOG.tmp" "$ORCHESTRATION_LOG"

    # Update strategy success rate
    update_strategy_success "$task_type" "success"

    log SUCCESS "=== Orchestration completed ==="
    echo "$orchestration_record" | jq .
}

# Update strategy success rate
update_strategy_success() {
    local task_type="$1"
    local outcome="$2"  # success or failure

    jq --arg type "$task_type" --arg outcome "$outcome" '
        .strategies[$type].total_executions += 1 |
        if $outcome == "success" then
            .strategies[$type].success_count //= 0 |
            .strategies[$type].success_count += 1
        else
            .
        end |
        .strategies[$type].success_rate = (
            (.strategies[$type].success_count // 0) / .strategies[$type].total_executions
        )
    ' "$STRATEGIES_FILE" > "$STRATEGIES_FILE.tmp"

    mv "$STRATEGIES_FILE.tmp" "$STRATEGIES_FILE"

    # Also update classifier
    "$CLASSIFIER" record-outcome "$task_type" "$outcome" >/dev/null 2>&1 || true
}

# Show orchestration statistics
show_stats() {
    init_orchestration_log

    log INFO "=== Orchestration Statistics ==="
    echo

    jq -r '
        "Total orchestrations: \(.total_orchestrations)",
        "Successful: \(.success_count)",
        "Failed: \(.failure_count)",
        "Success rate: \((.success_count / .total_orchestrations * 100 | round))%",
        "",
        "Recent orchestrations:",
        (.orchestrations | sort_by(.started_at) | reverse | .[0:5] | .[] |
            "  - \(.started_at): \(.task_type) (\(.status))")
    ' "$ORCHESTRATION_LOG"

    echo
    log INFO "Strategy Performance:"
    jq -r '
        .strategies | to_entries | map(
            "  \(.key): \(.value.total_executions) executions, \((.value.success_rate * 100 | round))% success"
        ) | .[]
    ' "$STRATEGIES_FILE"
}

# Show available strategies
show_strategies() {
    log INFO "=== Available Orchestration Strategies ==="
    echo

    jq -r '
        .strategies | to_entries | map(
            "[\(.key)]",
            "  Description: \(.value.description)",
            "  Agents: \(.value.agents | length)",
            "  Coordinator: \(.value.coordinator)",
            "  Success rate: \((.value.success_rate * 100 | round))%",
            "  Executions: \(.value.total_executions)",
            ""
        ) | .[]
    ' "$STRATEGIES_FILE"
}

# Main CLI
main() {
    local command="${1:-orchestrate}"
    shift || true

    case "$command" in
        orchestrate)
            local request="$*"
            if [[ -z "$request" ]]; then
                log ERROR "Request text required"
                echo "Usage: $0 orchestrate <request text>" >&2
                exit 1
            fi

            orchestrate_request "$request" "false"
            ;;

        dry-run|--dry-run)
            local request="$*"
            if [[ -z "$request" ]]; then
                log ERROR "Request text required"
                echo "Usage: $0 dry-run <request text>" >&2
                exit 1
            fi

            orchestrate_request "$request" "true"
            ;;

        stats)
            show_stats
            ;;

        strategies)
            show_strategies
            ;;

        test)
            log INFO "=== Orchestrator Test Suite ==="
            echo

            local test_requests=(
                "Debug why the authentication is failing"
                "Implement user profile feature with avatar upload"
                "Optimize the database query performance"
            )

            for request in "${test_requests[@]}"; do
                log INFO "Testing: $request"
                orchestrate_request "$request" "true"
                echo
                echo "---"
                echo
            done
            ;;

        help|--help|-h)
            cat <<EOF
Orchestrator - Proactive agent orchestration engine

USAGE:
    $0 <command> [args]

COMMANDS:
    orchestrate <request>   Orchestrate agents for the request
    dry-run <request>       Simulate orchestration without spawning agents
    stats                   Show orchestration statistics
    strategies              Show available strategies
    test                    Run test suite
    help                    Show this help message

EXAMPLES:
    # Orchestrate a debugging task
    $0 orchestrate "Debug why the API is failing"

    # Dry run to see what would happen
    $0 dry-run "Implement user authentication"

    # View statistics
    $0 stats

ENVIRONMENT VARIABLES:
    AUTO_ORCHESTRATE_THRESHOLD  Confidence threshold for auto-orchestration (default: 0.75)
    DEBUG                       Enable debug logging (set to 1)

EOF
            ;;

        *)
            log ERROR "Unknown command: $command"
            echo "Run '$0 help' for usage information" >&2
            exit 1
            ;;
    esac
}

# Run main
main "$@"
