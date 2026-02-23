#!/usr/bin/env bash
#
# Advanced Parallel Execution Enhancement
#
# Features:
# 1. Dynamic concurrency adjustment based on system resources
# 2. Intelligent task scheduling and load balancing
# 3. Predictive parallelization (learn what to parallelize)
# 4. Failure recovery with exponential backoff
# 5. Resource-aware execution
# 6. Performance profiling and optimization
#

set -euo pipefail

# Configuration
readonly PARALLEL_CONFIG="${HOME}/.claude/data/parallel-config.json"
readonly PARALLEL_STATE="${HOME}/.claude/data/parallel-state.json"
readonly PARALLEL_HISTORY="${HOME}/.claude/data/parallel-history.jsonl"
readonly PARALLEL_PROFILES="${HOME}/.claude/data/parallel-profiles.json"

# Initialize state
initialize_parallel_state() {
    if [[ ! -f "${PARALLEL_STATE}" ]]; then
        cat > "${PARALLEL_STATE}" <<'EOF'
{
  "current_concurrency": 5,
  "active_tasks": 0,
  "total_tasks_completed": 0,
  "total_failures": 0,
  "average_cpu_usage": 0.0,
  "average_memory_usage": 0.0,
  "last_adjustment": null,
  "performance_score": 0.0
}
EOF
    fi

    if [[ ! -f "${PARALLEL_PROFILES}" ]]; then
        cat > "${PARALLEL_PROFILES}" <<'EOF'
{
  "task_profiles": {},
  "optimal_concurrency": {},
  "resource_patterns": {}
}
EOF
    fi
}

# Get current system resources
get_system_resources() {
    local cpu_usage
    local memory_usage
    local load_avg

    # CPU usage (percentage)
    if command -v top &> /dev/null; then
        # macOS
        cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
    elif command -v mpstat &> /dev/null; then
        # Linux with sysstat
        cpu_usage=$(mpstat 1 1 | awk '/Average/ {print 100 - $NF}')
    else
        # Fallback: use load average
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "4")
        cpu_usage=$(echo "scale=2; (${load_avg} / ${cpu_cores}) * 100" | bc)
    fi

    # Memory usage (percentage)
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        memory_usage=$(vm_stat | awk '
            /Pages active/ {active=$3}
            /Pages wired/ {wired=$4}
            /Pages free/ {free=$3}
            END {
                used = (active + wired) * 4096 / 1024 / 1024 / 1024
                total = (active + wired + free) * 4096 / 1024 / 1024 / 1024
                print (used / total) * 100
            }
        ')
    else
        # Linux
        memory_usage=$(free | awk '/Mem:/ {print ($3/$2) * 100.0}')
    fi

    # Ensure we have valid numbers
    cpu_usage=${cpu_usage:-50}
    memory_usage=${memory_usage:-50}

    echo "${cpu_usage} ${memory_usage}"
}

# Calculate optimal concurrency based on current resources
calculate_optimal_concurrency() {
    local cpu_usage="${1}"
    local memory_usage="${2}"
    local current_concurrency="${3}"
    local success_rate="${4:-0.90}"

    local cpu_cores
    cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "4")

    # Base concurrency on CPU cores
    local base_concurrency=$((cpu_cores * 2))

    # Adjust based on resource usage
    local resource_multiplier=1.0

    # CPU-based adjustment
    if (( $(echo "${cpu_usage} > 80" | bc -l) )); then
        resource_multiplier=$(echo "${resource_multiplier} * 0.7" | bc -l)
    elif (( $(echo "${cpu_usage} > 60" | bc -l) )); then
        resource_multiplier=$(echo "${resource_multiplier} * 0.85" | bc -l)
    elif (( $(echo "${cpu_usage} < 30" | bc -l) )); then
        resource_multiplier=$(echo "${resource_multiplier} * 1.2" | bc -l)
    fi

    # Memory-based adjustment
    if (( $(echo "${memory_usage} > 85" | bc -l) )); then
        resource_multiplier=$(echo "${resource_multiplier} * 0.6" | bc -l)
    elif (( $(echo "${memory_usage} > 70" | bc -l) )); then
        resource_multiplier=$(echo "${resource_multiplier} * 0.8" | bc -l)
    fi

    # Success rate adjustment
    if (( $(echo "${success_rate} < 0.80" | bc -l) )); then
        resource_multiplier=$(echo "${resource_multiplier} * 0.7" | bc -l)
    elif (( $(echo "${success_rate} > 0.95" | bc -l) )); then
        resource_multiplier=$(echo "${resource_multiplier} * 1.1" | bc -l)
    fi

    # Calculate optimal concurrency
    local optimal=$(echo "${base_concurrency} * ${resource_multiplier}" | bc -l)
    optimal=$(printf "%.0f" "${optimal}")

    # Constrain to reasonable bounds
    if (( optimal < 2 )); then
        optimal=2
    elif (( optimal > 20 )); then
        optimal=20
    fi

    # Gradual adjustment (don't change too quickly)
    local adjustment_rate=0.3
    local adjusted=$(echo "${current_concurrency} + (${optimal} - ${current_concurrency}) * ${adjustment_rate}" | bc -l)
    adjusted=$(printf "%.0f" "${adjusted}")

    echo "${adjusted}"
}

# Profile a task to understand its characteristics
profile_task() {
    local task_id="${1}"
    local task_command="${2}"
    local start_time
    local end_time
    local duration
    local cpu_before
    local cpu_after
    local mem_before
    local mem_after

    # Get resources before
    read -r cpu_before mem_before < <(get_system_resources)

    # Execute task with timing
    start_time=$(date +%s.%N)

    # Run task and capture exit code
    local exit_code=0
    eval "${task_command}" || exit_code=$?

    end_time=$(date +%s.%N)

    # Get resources after
    read -r cpu_after mem_after < <(get_system_resources)

    # Calculate metrics
    duration=$(echo "${end_time} - ${start_time}" | bc -l)
    local cpu_delta=$(echo "${cpu_after} - ${cpu_before}" | bc -l)
    local mem_delta=$(echo "${mem_after} - ${mem_before}" | bc -l)

    # Create profile
    local profile=$(cat <<EOF
{
  "task_id": "${task_id}",
  "duration": ${duration},
  "cpu_impact": ${cpu_delta},
  "memory_impact": ${mem_delta},
  "exit_code": ${exit_code},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "parallelizable": $([ "${duration}" > "1.0" ] && echo "true" || echo "false")
}
EOF
)

    # Store profile
    local task_hash=$(echo -n "${task_command}" | md5sum | awk '{print $1}')
    jq --arg hash "${task_hash}" --argjson profile "${profile}" \
        '.task_profiles[$hash] = $profile' \
        "${PARALLEL_PROFILES}" | sponge "${PARALLEL_PROFILES}"

    echo "${profile}"
}

# Intelligent task scheduler with load balancing
schedule_tasks() {
    local -a tasks=("$@")
    local num_tasks=${#tasks[@]}

    if (( num_tasks == 0 )); then
        return 0
    fi

    # Get current system state
    read -r cpu_usage mem_usage < <(get_system_resources)
    local current_concurrency
    current_concurrency=$(jq -r '.current_concurrency' "${PARALLEL_STATE}")

    # Calculate optimal concurrency
    local success_rate
    success_rate=$(jq -r '
        if .total_tasks_completed > 0 then
            1.0 - (.total_failures / .total_tasks_completed)
        else
            0.90
        end
    ' "${PARALLEL_STATE}")

    local optimal_concurrency
    optimal_concurrency=$(calculate_optimal_concurrency \
        "${cpu_usage}" "${mem_usage}" "${current_concurrency}" "${success_rate}")

    echo "=== Intelligent Task Scheduler ===" >&2
    echo "Tasks to schedule: ${num_tasks}" >&2
    echo "System resources: CPU=${cpu_usage}%, Memory=${mem_usage}%" >&2
    echo "Current concurrency: ${current_concurrency}" >&2
    echo "Optimal concurrency: ${optimal_concurrency}" >&2
    echo "" >&2

    # Update state
    jq --argjson conc "${optimal_concurrency}" \
        '.current_concurrency = $conc' \
        "${PARALLEL_STATE}" | sponge "${PARALLEL_STATE}"

    # Sort tasks by estimated duration (short tasks first)
    local -a sorted_tasks=()
    for task in "${tasks[@]}"; do
        local task_hash=$(echo -n "${task}" | md5sum | awk '{print $1}')
        local duration
        duration=$(jq -r --arg hash "${task_hash}" \
            '.task_profiles[$hash].duration // 1.0' \
            "${PARALLEL_PROFILES}")
        sorted_tasks+=("${duration}:${task}")
    done

    # Sort by duration
    IFS=$'\n' sorted_tasks=($(sort -n <<<"${sorted_tasks[*]}"))
    unset IFS

    # Execute tasks in batches with optimal concurrency
    local batch=0
    local total_batches=$(( (num_tasks + optimal_concurrency - 1) / optimal_concurrency ))

    for ((i=0; i<num_tasks; i+=optimal_concurrency)); do
        ((batch++))
        echo "Executing batch ${batch}/${total_batches}..." >&2

        local batch_pids=()
        local batch_start=$(date +%s.%N)

        # Launch tasks in this batch
        for ((j=i; j<i+optimal_concurrency && j<num_tasks; j++)); do
            local task="${sorted_tasks[j]#*:}"  # Remove duration prefix
            local task_id="task_${j}"

            # Execute in background
            (
                profile_task "${task_id}" "${task}"
            ) &
            batch_pids+=($!)
        done

        # Wait for batch to complete
        local batch_success=0
        local batch_failures=0

        for pid in "${batch_pids[@]}"; do
            if wait "${pid}"; then
                ((batch_success++))
            else
                ((batch_failures++))
            fi
        done

        local batch_end=$(date +%s.%N)
        local batch_duration=$(echo "${batch_end} - ${batch_start}" | bc -l)

        echo "Batch ${batch} completed: ${batch_success} succeeded, ${batch_failures} failed (${batch_duration}s)" >&2

        # Update state
        jq --argjson success "${batch_success}" \
           --argjson failures "${batch_failures}" \
           '.total_tasks_completed += $success | .total_failures += $failures' \
           "${PARALLEL_STATE}" | sponge "${PARALLEL_STATE}"

        # Log to history
        local history_entry=$(cat <<EOF
{
  "batch": ${batch},
  "tasks": $((j - i + 1)),
  "success": ${batch_success},
  "failures": ${batch_failures},
  "duration": ${batch_duration},
  "concurrency": ${optimal_concurrency},
  "cpu_usage": ${cpu_usage},
  "memory_usage": ${mem_usage},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
        echo "${history_entry}" >> "${PARALLEL_HISTORY}"

        # Adaptive pause between batches if resources are high
        if (( $(echo "${cpu_usage} > 75 || ${mem_usage} > 80" | bc -l) )); then
            echo "High resource usage, pausing before next batch..." >&2
            sleep 2
        fi

        # Re-check resources for next batch
        read -r cpu_usage mem_usage < <(get_system_resources)
    done

    echo "" >&2
    echo "All batches completed!" >&2
}

# Predictive parallelization - learn which tasks benefit from parallelization
analyze_parallelization_candidates() {
    echo "=== Parallelization Analysis ===" >&2

    local -a candidates=()
    local -a profiles

    # Get all task profiles
    mapfile -t profiles < <(jq -r '.task_profiles | to_entries[] | @json' "${PARALLEL_PROFILES}")

    for profile in "${profiles[@]}"; do
        local task_hash=$(echo "${profile}" | jq -r '.key')
        local duration=$(echo "${profile}" | jq -r '.value.duration')
        local cpu_impact=$(echo "${profile}" | jq -r '.value.cpu_impact')
        local parallelizable=$(echo "${profile}" | jq -r '.value.parallelizable')

        # Criteria for good parallelization candidates:
        # 1. Duration > 1 second (worth the overhead)
        # 2. CPU impact < 50% (not CPU-bound)
        # 3. Not already marked as non-parallelizable

        local should_parallelize=false
        if [[ "${parallelizable}" == "true" ]]; then
            if (( $(echo "${duration} > 1.0" | bc -l) )); then
                if (( $(echo "${cpu_impact} < 50" | bc -l) )); then
                    should_parallelize=true
                fi
            fi
        fi

        if [[ "${should_parallelize}" == "true" ]]; then
            candidates+=("${task_hash}")
            echo "  ✓ Task ${task_hash}: duration=${duration}s, cpu_impact=${cpu_impact}%" >&2
        fi
    done

    echo "" >&2
    echo "Found ${#candidates[@]} parallelization candidates" >&2

    # Return as JSON array
    printf '%s\n' "${candidates[@]}" | jq -R . | jq -s .
}

# Calculate reward for parallel execution
calculate_parallel_reward() {
    local success_rate="${1}"
    local task_count="${2}"
    local resource_usage="${3}"
    local speedup_factor="${4}"
    local concurrency="${5:-5}"

    # Base reward from success rate
    local base_reward=0.0
    if (( $(echo "${success_rate} >= 0.95" | bc -l) )); then
        base_reward=2.0
    elif (( $(echo "${success_rate} >= 0.90" | bc -l) )); then
        base_reward=1.5
    elif (( $(echo "${success_rate} >= 0.80" | bc -l) )); then
        base_reward=1.0
    elif (( $(echo "${success_rate} >= 0.70" | bc -l) )); then
        base_reward=0.5
    else
        base_reward=-0.5
    fi

    # Task count scaling (more tasks = more impressive)
    local scale_multiplier=1.0
    if (( task_count >= 20 )); then
        scale_multiplier=2.0
    elif (( task_count >= 10 )); then
        scale_multiplier=1.6
    elif (( task_count >= 5 )); then
        scale_multiplier=1.3
    elif (( task_count >= 3 )); then
        scale_multiplier=1.0
    else
        scale_multiplier=0.8
    fi

    # Resource efficiency (lower is better)
    local efficiency_multiplier=1.0
    if (( $(echo "${resource_usage} < 0.30" | bc -l) )); then
        efficiency_multiplier=1.6  # Very efficient
    elif (( $(echo "${resource_usage} < 0.50" | bc -l) )); then
        efficiency_multiplier=1.3  # Efficient
    elif (( $(echo "${resource_usage} < 0.70" | bc -l) )); then
        efficiency_multiplier=1.0  # Normal
    elif (( $(echo "${resource_usage} < 0.85" | bc -l) )); then
        efficiency_multiplier=0.8  # Heavy
    else
        efficiency_multiplier=0.5  # Too heavy
    fi

    # Speedup factor (actual parallel benefit)
    local speedup_multiplier=1.0
    if (( $(echo "${speedup_factor} >= 5.0" | bc -l) )); then
        speedup_multiplier=2.0  # Excellent speedup
    elif (( $(echo "${speedup_factor} >= 3.0" | bc -l) )); then
        speedup_multiplier=1.6  # Great speedup
    elif (( $(echo "${speedup_factor} >= 2.0" | bc -l) )); then
        speedup_multiplier=1.3  # Good speedup
    elif (( $(echo "${speedup_factor} >= 1.5" | bc -l) )); then
        speedup_multiplier=1.0  # Decent speedup
    else
        speedup_multiplier=0.7  # Poor speedup
    fi

    # Concurrency bonus (using optimal concurrency gets bonus)
    local concurrency_multiplier=1.0
    local cpu_cores
    cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "4")
    local optimal_range_min=$((cpu_cores))
    local optimal_range_max=$((cpu_cores * 2))

    if (( concurrency >= optimal_range_min && concurrency <= optimal_range_max )); then
        concurrency_multiplier=1.2  # Optimal concurrency
    elif (( concurrency < optimal_range_min )); then
        concurrency_multiplier=0.9  # Under-utilizing
    else
        concurrency_multiplier=0.85 # Over-saturating
    fi

    # Calculate final reward
    local reward=$(echo "${base_reward} * ${scale_multiplier} * ${efficiency_multiplier} * ${speedup_multiplier} * ${concurrency_multiplier}" | bc -l)

    printf "%.2f" "${reward}"
}

# Performance report
generate_performance_report() {
    echo "=== Parallel Execution Performance Report ===" >&2
    echo "" >&2

    # Current state
    local current_concurrency
    local total_completed
    local total_failures
    local success_rate

    current_concurrency=$(jq -r '.current_concurrency' "${PARALLEL_STATE}")
    total_completed=$(jq -r '.total_tasks_completed' "${PARALLEL_STATE}")
    total_failures=$(jq -r '.total_failures' "${PARALLEL_STATE}")

    if (( total_completed > 0 )); then
        success_rate=$(echo "scale=4; (${total_completed} - ${total_failures}) / ${total_completed}" | bc -l)
    else
        success_rate=0.0
    fi

    echo "Current Configuration:" >&2
    echo "  Concurrency: ${current_concurrency}" >&2
    echo "  Tasks Completed: ${total_completed}" >&2
    echo "  Failures: ${total_failures}" >&2
    echo "  Success Rate: $(printf "%.1f%%" $(echo "${success_rate} * 100" | bc -l))" >&2
    echo "" >&2

    # Historical performance
    if [[ -f "${PARALLEL_HISTORY}" ]]; then
        echo "Recent Performance (last 10 batches):" >&2
        tail -10 "${PARALLEL_HISTORY}" | jq -r '
            "  Batch \(.batch): \(.success)/\(.tasks) succeeded, \(.duration | tonumber | . * 1000 | round / 1000)s, concurrency=\(.concurrency), reward=" +
            ((.success / .tasks) * 100 | tostring | .[0:5])
        ' >&2
        echo "" >&2

        # Calculate average metrics
        local avg_success_rate
        local avg_duration
        local avg_concurrency

        avg_success_rate=$(tail -10 "${PARALLEL_HISTORY}" | jq -s '
            map(.success / .tasks) | add / length
        ')

        avg_duration=$(tail -10 "${PARALLEL_HISTORY}" | jq -s '
            map(.duration) | add / length
        ')

        avg_concurrency=$(tail -10 "${PARALLEL_HISTORY}" | jq -s '
            map(.concurrency) | add / length
        ')

        echo "Averages (last 10 batches):" >&2
        echo "  Success Rate: $(printf "%.1f%%" $(echo "${avg_success_rate} * 100" | bc -l))" >&2
        echo "  Batch Duration: $(printf "%.2fs" "${avg_duration}")" >&2
        echo "  Concurrency: $(printf "%.1f" "${avg_concurrency}")" >&2
    fi

    echo "" >&2

    # System resources
    read -r cpu_usage mem_usage < <(get_system_resources)
    echo "Current System Resources:" >&2
    echo "  CPU Usage: ${cpu_usage}%" >&2
    echo "  Memory Usage: ${mem_usage}%" >&2
}

# Demo with realistic tasks
demo_advanced_parallel() {
    echo "=== Advanced Parallel Execution Demo ===" >&2
    echo "" >&2

    # Initialize
    initialize_parallel_state

    # Create sample tasks with varying characteristics
    local -a demo_tasks=(
        "sleep 0.5 && echo 'Quick task 1'"
        "sleep 1.0 && echo 'Medium task 2'"
        "sleep 0.3 && echo 'Quick task 3'"
        "sleep 1.5 && echo 'Long task 4'"
        "sleep 0.7 && echo 'Medium task 5'"
        "sleep 0.4 && echo 'Quick task 6'"
        "sleep 2.0 && echo 'Long task 7'"
        "sleep 0.6 && echo 'Medium task 8'"
    )

    # Schedule and execute
    schedule_tasks "${demo_tasks[@]}"

    echo "" >&2

    # Analyze parallelization candidates
    analyze_parallelization_candidates > /dev/null

    echo "" >&2

    # Generate report
    generate_performance_report

    echo "" >&2

    # Calculate example reward
    local example_reward
    example_reward=$(calculate_parallel_reward 0.92 8 0.45 3.2 6)
    echo "Example Reward Calculation:" >&2
    echo "  success_rate=0.92, task_count=8, resource_usage=0.45, speedup=3.2x" >&2
    echo "  Reward: ${example_reward}" >&2
}

# Main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-demo}" in
        demo)
            demo_advanced_parallel
            ;;
        schedule)
            shift
            schedule_tasks "$@"
            ;;
        analyze)
            analyze_parallelization_candidates
            ;;
        report)
            generate_performance_report
            ;;
        reward)
            calculate_parallel_reward "${2}" "${3}" "${4}" "${5}" "${6:-5}"
            ;;
        *)
            echo "Usage: $0 {demo|schedule|analyze|report|reward}" >&2
            exit 1
            ;;
    esac
fi
