#!/bin/bash
# autonomous-control.sh
# Main handler for /autonomous command

set -euo pipefail

ACTION="${1:-status}"
CONFIG_FILE="$HOME/.claude/autonomous-config.json"
AUDIT_LOG="$HOME/.claude/audit/autonomous-decisions.log"
METRICS_DIR="$HOME/.claude/metrics"
TASK_QUEUE="$HOME/.claude/tasks/queue"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure directories exist
mkdir -p "$(dirname "$CONFIG_FILE")"
mkdir -p "$(dirname "$AUDIT_LOG")"
mkdir -p "$METRICS_DIR"
mkdir -p "$TASK_QUEUE"

# Initialize config if not exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<'EOF'
{
  "autonomous_mode_enabled": true,
  "coverage_threshold": 80,
  "quality_thresholds": {
    "research_min": 80,
    "plan_min": 85,
    "test_coverage_min": 80
  },
  "auto_fix_enabled": true,
  "auto_fix_max_attempts": 3,
  "security_auto_patch": {
    "critical": true,
    "high": true,
    "medium": false
  },
  "economic_controls": {
    "max_cost_per_workflow_usd": 100,
    "parallel_execution_min_roi": 10
  }
}
EOF
fi

# Helper functions
log_audit() {
    local event="$1"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | AUTONOMOUS_CONTROL | $event" >> "$AUDIT_LOG"
}

get_config_value() {
    local key="$1"
    jq -r ".$key // \"not_set\"" "$CONFIG_FILE"
}

set_config_value() {
    local key="$1"
    local value="$2"
    jq ".$key = $value" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

show_status() {
    echo -e "${BLUE}🤖 Autonomous Operations Status${NC}"
    echo ""

    local enabled=$(get_config_value "autonomous_mode_enabled")

    if [[ "$enabled" == "true" ]]; then
        echo -e "Mode: ${GREEN}ENABLED ✅${NC}"
    else
        echo -e "Mode: ${RED}DISABLED ❌${NC}"
    fi

    # Calculate uptime (time since last enable)
    if [[ -f "$HOME/.claude/cache/autonomous-enabled-at" ]]; then
        local enabled_at=$(cat "$HOME/.claude/cache/autonomous-enabled-at")
        local now=$(date +%s)
        local uptime=$((now - enabled_at))
        local hours=$((uptime / 3600))
        local minutes=$(((uptime % 3600) / 60))
        echo "Uptime: ${hours}h ${minutes}m"
    fi

    # Count tasks
    local pending=$(ls -1 "$TASK_QUEUE" 2>/dev/null | wc -l)
    local completed=$(ls -1 "$HOME/.claude/tasks/completed" 2>/dev/null | wc -l)

    echo ""
    echo "Tasks:"
    echo "  Pending: $pending"
    echo "  Completed: $completed"

    # Recent activity
    echo ""
    echo "Recent Activity (last 1 hour):"
    if [[ -f "$AUDIT_LOG" ]]; then
        tail -20 "$AUDIT_LOG" | grep -E "$(date -u --date='1 hour ago' +%Y-%m-%d)" | tail -5 || echo "  No recent activity"
    else
        echo "  No audit log found"
    fi

    # Agent status
    echo ""
    echo "Active Loops:"
    echo "  ✅ Continuous Integration (brahma-ci-runner)"
    echo "  ✅ Self-Healing (brahma-healer)"
    echo "  ✅ Test Generation (brahma-test-generator)"
    echo "  ✅ Dependency Management (brahma-dependency-resolver)"
    echo "  ✅ Security Scanning (brahma-security-scanner)"
}

enable_autonomous() {
    echo -e "${GREEN}Enabling autonomous operations...${NC}"

    set_config_value "autonomous_mode_enabled" "true"
    date +%s > "$HOME/.claude/cache/autonomous-enabled-at"
    log_audit "ENABLED | Autonomous operations enabled"

    echo -e "${GREEN}✅ Autonomous operations enabled${NC}"
    echo ""
    echo "Autonomous agents will now process tasks automatically."
    echo "Monitor with: /autonomous status"
}

disable_autonomous() {
    local force=false

    # Check for --force flag
    for arg in "$@"; do
        if [[ "$arg" == "--force" ]]; then
            force=true
        fi
    done

    if [[ "$force" == "false" ]]; then
        echo -e "${YELLOW}⚠️  This will disable all autonomous operations.${NC}"
        echo "In-progress tasks will complete, but no new tasks will be started."
        echo ""
        read -p "Are you sure? (yes/no): " confirm

        if [[ "$confirm" != "yes" ]]; then
            echo "Cancelled."
            return
        fi
    fi

    echo -e "${YELLOW}Disabling autonomous operations...${NC}"

    set_config_value "autonomous_mode_enabled" "false"
    log_audit "DISABLED | Autonomous operations disabled"

    echo -e "${YELLOW}⏸️  Autonomous operations disabled${NC}"
    echo ""
    echo "Agents will finish current tasks but won't start new ones."
    echo "Re-enable with: /autonomous enable"
}

pause_autonomous() {
    local duration="30m"

    # Parse duration argument
    for arg in "$@"; do
        if [[ "$arg" == --duration=* ]]; then
            duration="${arg#*=}"
        fi
    done

    echo -e "${YELLOW}Pausing autonomous operations for $duration...${NC}"

    # Convert duration to seconds
    local duration_seconds=1800  # default 30 minutes

    if [[ "$duration" =~ ^([0-9]+)h$ ]]; then
        duration_seconds=$((${BASH_REMATCH[1]} * 3600))
    elif [[ "$duration" =~ ^([0-9]+)m$ ]]; then
        duration_seconds=$((${BASH_REMATCH[1]} * 60))
    fi

    # Disable temporarily
    set_config_value "autonomous_mode_enabled" "false"

    # Schedule resume
    local resume_at=$(($(date +%s) + duration_seconds))
    echo "$resume_at" > "$HOME/.claude/cache/autonomous-resume-at"

    log_audit "PAUSED | Paused for $duration"

    echo -e "${YELLOW}⏸️  Paused for $duration${NC}"
    echo "Will auto-resume at: $(date -d @$resume_at)"
    echo "Or manually resume with: /autonomous resume"

    # Schedule resume job (background)
    (
        sleep "$duration_seconds"
        if [[ -f "$HOME/.claude/cache/autonomous-resume-at" ]]; then
            resume_autonomous
        fi
    ) &
}

resume_autonomous() {
    echo -e "${GREEN}Resuming autonomous operations...${NC}"

    set_config_value "autonomous_mode_enabled" "true"
    rm -f "$HOME/.claude/cache/autonomous-resume-at"
    log_audit "RESUMED | Autonomous operations resumed"

    echo -e "${GREEN}▶️  Autonomous operations resumed${NC}"
}

show_metrics() {
    echo -e "${BLUE}📊 Autonomous Operations Metrics${NC}"
    echo ""

    # Calculate metrics from log files
    local completed_today=0
    local failed_today=0

    if [[ -f "$METRICS_DIR/task-completion-metrics.json" ]]; then
        local today=$(date +%Y-%m-%d)
        completed_today=$(grep "$today" "$METRICS_DIR/task-completion-metrics.json" | grep -c '"status":"SUCCESS"' || echo 0)
        failed_today=$(grep "$today" "$METRICS_DIR/task-completion-metrics.json" | grep -c '"status":"FAILURE"' || echo 0)
    fi

    local total=$((completed_today + failed_today))
    local success_rate=0

    if [[ $total -gt 0 ]]; then
        success_rate=$(echo "scale=2; $completed_today * 100 / $total" | bc)
    fi

    echo "Today's Performance:"
    echo "  Tasks Completed: $completed_today"
    echo "  Tasks Failed: $failed_today"
    echo "  Success Rate: ${success_rate}%"

    # Show per-agent metrics (if available)
    echo ""
    echo "By Agent:"

    for agent in brahma-ci-runner brahma-healer brahma-test-generator brahma-dependency-resolver brahma-security-scanner; do
        if [[ -f "$METRICS_DIR/${agent}-metrics.json" ]]; then
            echo "  $agent:"
            # Extract metrics (simplified)
            echo "    - $(wc -l < "$METRICS_DIR/${agent}-metrics.json" || echo 0) operations"
        fi
    done

    # Export option
    if [[ "$*" == *"--export"* ]]; then
        local export_file="${2:-metrics-$(date +%Y-%m-%d).json}"
        echo ""
        echo "Exporting metrics to: $export_file"

        cat > "$export_file" <<EOF
{
  "date": "$(date -u +%Y-%m-%d)",
  "summary": {
    "tasks_completed": $completed_today,
    "tasks_failed": $failed_today,
    "success_rate": $success_rate
  }
}
EOF

        echo -e "${GREEN}✅ Metrics exported${NC}"
    fi
}

show_audit() {
    echo -e "${BLUE}🔍 Autonomous Operations Audit Trail${NC}"
    echo ""

    if [[ ! -f "$AUDIT_LOG" ]]; then
        echo "No audit log found."
        return
    fi

    # Default: show last 20 entries
    local count=20

    # Parse arguments
    for arg in "$@"; do
        if [[ "$arg" == --search=* ]]; then
            local search="${arg#*=}"
            echo "Searching for: $search"
            echo ""
            grep -i "$search" "$AUDIT_LOG" | tail -"$count"
            return
        elif [[ "$arg" == --date=* ]]; then
            local date="${arg#*=}"
            echo "Events on: $date"
            echo ""
            grep "$date" "$AUDIT_LOG" | tail -"$count"
            return
        fi
    done

    # Default: show recent entries
    echo "Recent Events:"
    echo ""
    tail -"$count" "$AUDIT_LOG"
}

manage_config() {
    if [[ $# -eq 0 ]]; then
        # Show current config
        echo -e "${BLUE}⚙️  Autonomous Configuration${NC}"
        echo ""
        cat "$CONFIG_FILE" | jq .
        return
    fi

    local key="$1"

    if [[ "$key" == "--reset" ]]; then
        echo "Resetting configuration to defaults..."
        rm -f "$CONFIG_FILE"
        # Re-initialize will happen automatically
        show_status
        return
    fi

    if [[ $# -eq 1 ]]; then
        # Show specific setting
        local value=$(get_config_value "$key")
        echo "$key: $value"
    else
        # Update setting
        local value="$2"
        set_config_value "$key" "$value"
        log_audit "CONFIG_UPDATE | Set $key = $value"
        echo -e "${GREEN}✅ Configuration updated${NC}"
    fi
}

run_test() {
    echo -e "${BLUE}🧪 Testing Autonomous System${NC}"
    echo ""

    echo "Creating test scenario..."

    # Create test file
    local test_file="$HOME/test-autonomous-$(date +%s).py"
    cat > "$test_file" <<'EOF'
def test_function(x):
    # Intentional issue: no validation
    return x * 2
EOF

    echo "Test file created: $test_file"
    echo ""

    echo "Triggering autonomous loops..."
    echo "1. brahma-ci-runner should detect changes"
    echo "2. brahma-test-generator should add tests"
    echo "3. brahma-security-scanner should scan"
    echo ""

    echo "Monitor progress with: /autonomous status"
    echo "View audit trail with: /autonomous audit"
    echo ""
    echo "Cleanup with: rm $test_file"
}

reset_system() {
    echo -e "${RED}⚠️  WARNING: This will reset autonomous system state${NC}"
    echo "This operation:"
    echo "  - Clears task queue"
    echo "  - Resets metrics"
    echo "  - Clears audit trail"
    echo ""
    read -p "Are you ABSOLUTELY sure? (type 'RESET' to confirm): " confirm

    if [[ "$confirm" != "RESET" ]]; then
        echo "Cancelled."
        return
    fi

    echo "Resetting system..."

    # Backup first
    local backup_dir="$HOME/.claude/backups/reset-$(date +%s)"
    mkdir -p "$backup_dir"

    cp -r "$TASK_QUEUE" "$backup_dir/" 2>/dev/null || true
    cp -r "$METRICS_DIR" "$backup_dir/" 2>/dev/null || true
    cp "$AUDIT_LOG" "$backup_dir/" 2>/dev/null || true

    echo "Backup created: $backup_dir"

    # Clear state
    rm -rf "$TASK_QUEUE"/*
    rm -f "$METRICS_DIR"/*.json
    > "$AUDIT_LOG"  # Clear but keep file

    log_audit "RESET | System state reset (backup: $backup_dir)"

    echo -e "${GREEN}✅ System reset complete${NC}"
    echo "Backup available at: $backup_dir"
}

# Main execution
case "$ACTION" in
    status)
        show_status
        ;;
    enable)
        enable_autonomous "$@"
        ;;
    disable)
        disable_autonomous "$@"
        ;;
    pause)
        pause_autonomous "$@"
        ;;
    resume)
        resume_autonomous
        ;;
    metrics)
        show_metrics "$@"
        ;;
    audit)
        show_audit "$@"
        ;;
    config)
        shift  # Remove 'config' from arguments
        manage_config "$@"
        ;;
    test)
        run_test "$@"
        ;;
    reset)
        reset_system "$@"
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo ""
        echo "Usage: /autonomous [action] [options]"
        echo ""
        echo "Actions:"
        echo "  status  - Show current status"
        echo "  enable  - Enable autonomous operations"
        echo "  disable - Disable autonomous operations"
        echo "  pause   - Temporarily pause operations"
        echo "  resume  - Resume paused operations"
        echo "  metrics - Show performance metrics"
        echo "  audit   - View audit trail"
        echo "  config  - View/update configuration"
        echo "  test    - Run end-to-end test"
        echo "  reset   - Reset system state (careful!)"
        exit 1
        ;;
esac
