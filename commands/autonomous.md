---
name: autonomous
description: Control autonomous agent operations - enable, disable, monitor, and configure
argument-hint: action (status|enable|disable|pause|resume|metrics|audit|config|test|reset)
---

# /autonomous Command

**Purpose**: Control autonomous agent operations
**Usage**: `/autonomous [action] [options]`
**Autonomy Control**: Enable, disable, or monitor autonomous operations

---

## Actions

### /autonomous status

Display current autonomous operations status.

```bash
# Show overall status
/autonomous status

# Show specific agent status
/autonomous status --agent brahma-ci-runner

# Show metrics summary
/autonomous status --metrics
```

**Output**:
```
🤖 Autonomous Operations Status

Mode: ENABLED ✅
Uptime: 12 hours 34 minutes
Tasks Completed: 45 (42 success, 3 failed)
Autonomy Rate: 93.3%

Active Loops:
✅ Continuous Integration (brahma-ci-runner)
✅ Self-Healing (brahma-healer) - 2 fixes today
✅ Test Generation (brahma-test-generator) - 85% coverage
✅ Dependency Management (brahma-dependency-resolver) - 0 CRITICAL CVEs
✅ Security Scanning (brahma-security-scanner) - Last scan 15 min ago

Pending Tasks: 3
  - testgen-1738329600-abc (PENDING)
  - depcheck-1738329700-def (PENDING)
  - security-scan-1738329800-ghi (IN_PROGRESS)

Recent Activity (last 1 hour):
  12:45 - brahma-ci-runner: Tests passed (23/23)
  12:30 - brahma-healer: Auto-fixed memory leak
  12:15 - brahma-test-generator: Generated 5 tests
  12:00 - brahma-security-scanner: Scan complete (0 CRITICAL)
```

---

### /autonomous enable

Enable autonomous operations (all agents).

```bash
# Enable all autonomous operations
/autonomous enable

# Enable specific agent
/autonomous enable --agent brahma-ci-runner

# Enable specific loop
/autonomous enable --loop continuous-testing
```

**Effect**:
- Sets `autonomous_mode_enabled: true` in config
- Resumes all paused autonomous agents
- Starts processing queued tasks
- Logs enable event to audit trail

---

### /autonomous disable

Disable autonomous operations (requires confirmation).

```bash
# Disable all autonomous operations
/autonomous disable

# Disable with immediate effect (skip confirmation)
/autonomous disable --force

# Disable specific agent
/autonomous disable --agent brahma-healer

# Disable specific loop
/autonomous disable --loop self-healing
```

**Effect**:
- Sets `autonomous_mode_enabled: false` in config
- Pauses all autonomous agents (they finish current task)
- Stops accepting new tasks
- Logs disable event to audit trail

**Safety**:
- Asks for confirmation unless --force flag used
- Waits for in-progress tasks to complete (or timeout after 5 min)
- Does not kill running tasks abruptly

---

### /autonomous pause

Temporarily pause autonomous operations (quick resume).

```bash
# Pause for 30 minutes (default)
/autonomous pause

# Pause for specific duration
/autonomous pause --duration 1h
/autonomous pause --duration 24h

# Pause specific agent
/autonomous pause --agent brahma-test-generator --duration 2h
```

**Effect**:
- Temporarily disables autonomous operations
- Auto-resumes after duration expires
- Useful for maintenance windows

---

### /autonomous resume

Resume paused autonomous operations.

```bash
# Resume all operations
/autonomous resume

# Resume specific agent
/autonomous resume --agent brahma-ci-runner
```

**Effect**:
- Re-enables autonomous operations
- Processes queued tasks
- Logs resume event

---

### /autonomous metrics

Display detailed metrics and performance data.

```bash
# Show all metrics
/autonomous metrics

# Show metrics for specific agent
/autonomous metrics --agent brahma-healer

# Show metrics for time period
/autonomous metrics --since 24h
/autonomous metrics --since "2026-01-30"

# Export metrics to JSON
/autonomous metrics --export metrics-2026-01-31.json
```

**Output**:
```json
{
  "period": "last_24_hours",
  "summary": {
    "tasks_completed": 128,
    "tasks_failed": 8,
    "success_rate": 0.9375,
    "avg_completion_time_minutes": 12.5,
    "autonomy_rate": 0.94,
    "human_interventions": 8,
    "total_cost_usd": 15.67
  },
  "by_agent": {
    "brahma-ci-runner": {
      "tasks": 45,
      "success_rate": 0.98,
      "avg_time_minutes": 3.2
    },
    "brahma-healer": {
      "tasks": 12,
      "success_rate": 0.75,
      "avg_time_minutes": 8.5
    },
    "brahma-test-generator": {
      "tasks": 8,
      "success_rate": 1.0,
      "avg_time_minutes": 25.3
    }
  },
  "quality_gates": {
    "research_quality_avg": 87,
    "plan_quality_avg": 89,
    "test_coverage_avg": 83
  }
}
```

---

### /autonomous audit

View audit trail of autonomous decisions.

```bash
# Show recent audit events
/autonomous audit

# Show audit for specific date
/autonomous audit --date 2026-01-31

# Show audit for specific agent
/autonomous audit --agent brahma-security-scanner

# Search audit log
/autonomous audit --search "CRITICAL"

# Export audit log
/autonomous audit --export audit-2026-01.json
```

**Output**:
```
🔍 Autonomous Operations Audit Trail

Date: 2026-01-31

12:45:23 | brahma-ci-runner | TEST_EXECUTION | SUCCESS
  - Trigger: post-file-write hook
  - File: src/api/users.py
  - Tests: 23/23 passed
  - Coverage: 85%
  - Duration: 2m 15s

12:30:15 | brahma-healer | AUTO_FIX | SUCCESS
  - Issue: Memory leak in background job
  - Severity: HIGH
  - Fix: Increased memory limit 2GB → 4GB
  - Validation: Memory stable for 30 minutes
  - Duration: 8m 30s

12:15:42 | brahma-test-generator | TEST_GENERATION | SUCCESS
  - Trigger: Coverage < 80% (was 75%)
  - Generated: 5 tests
  - Coverage after: 85%
  - All tests pass: Yes
  - Duration: 12m 20s

12:00:00 | brahma-security-scanner | SECURITY_SCAN | INFO
  - Type: Daily SAST scan
  - Findings: 0 CRITICAL, 2 HIGH, 5 MEDIUM
  - Auto-fixed: 2 HIGH (SQL injection, XSS)
  - Duration: 8m 45s
```

---

### /autonomous config

View or update autonomous configuration.

```bash
# Show current config
/autonomous config

# Show specific setting
/autonomous config autonomous_mode_enabled

# Update setting
/autonomous config coverage_threshold 85

# Reset to defaults
/autonomous config --reset

# Import config from file
/autonomous config --import config.json
```

**Configurable Settings**:
```json
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
  },
  "notification_channels": [
    "slack",
    "email"
  ]
}
```

---

### /autonomous test

Run end-to-end test of autonomous system.

```bash
# Test all loops
/autonomous test

# Test specific loop
/autonomous test --loop continuous-testing

# Test with simulated failure
/autonomous test --simulate-failure
```

**Test Workflow**:
```
1. Create test file with intentional issues
2. Trigger autonomous loops
3. Verify each agent responds correctly:
   - brahma-ci-runner detects failure
   - brahma-healer attempts auto-fix
   - brahma-test-generator adds tests if needed
   - brahma-security-scanner finds security issues
4. Validate complete workflow
5. Cleanup test artifacts
6. Report results
```

---

### /autonomous reset

Reset autonomous system state (careful!).

```bash
# Reset all state (requires confirmation)
/autonomous reset

# Reset specific component
/autonomous reset --component task-queue
/autonomous reset --component metrics

# Reset with backup
/autonomous reset --backup
```

**Resets**:
- Task queue (clears pending tasks)
- Metrics (clears collected metrics)
- Pattern index (resets confidence scores)
- Audit trail (clears logs)

**Warning**: This is destructive. Use only when system is in bad state.

---

## Implementation

**Command File**: `.claude/commands/autonomous.md`
**Handler Script**: `.claude/scripts/autonomous-control.sh`
**Config File**: `~/.claude/autonomous-config.json`

### autonomous-control.sh

```bash
#!/bin/bash
# Main handler for /autonomous command

ACTION="${1:-status}"
CONFIG_FILE="$HOME/.claude/autonomous-config.json"
AUDIT_LOG="$HOME/.claude/audit/autonomous-decisions.log"

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
        echo "Usage: /autonomous [status|enable|disable|pause|resume|metrics|audit|config|test|reset]"
        exit 1
        ;;
esac
```

---

## Use Cases

### Use Case 1: Maintenance Window

```bash
# Pause autonomous operations for 2 hours
/autonomous pause --duration 2h

# Perform maintenance
# ... (deploy, upgrade, etc.)

# Resume (or will auto-resume after 2h)
/autonomous resume
```

---

### Use Case 2: Debug Issues

```bash
# Check what's happening
/autonomous status

# View recent audit trail
/autonomous audit --since 1h

# Check specific agent
/autonomous metrics --agent brahma-healer

# Disable problematic agent temporarily
/autonomous disable --agent brahma-healer
```

---

### Use Case 3: Performance Monitoring

```bash
# Daily metrics check
/autonomous metrics --since 24h

# Export for analysis
/autonomous metrics --export daily-metrics.json

# Check autonomy rate
/autonomous status --metrics
# Target: 95%+ autonomy
```

---

### Use Case 4: Emergency Shutdown

```bash
# Something went wrong, stop everything
/autonomous disable --force

# Investigate
/autonomous audit --search "ERROR"

# Fix issue, then resume
/autonomous enable
```

---

## Integration with Agents

All autonomous agents check config before executing:

```python
def should_run_autonomously():
    """Check if autonomous mode is enabled"""
    config = load_config("~/.claude/autonomous-config.json")
    return config.get("autonomous_mode_enabled", False)

# In agent:
if not should_run_autonomously():
    print("Autonomous mode disabled, waiting for manual trigger")
    return
```

---

## Notifications

Configure notifications for important events:

```json
{
  "notifications": {
    "autonomous_disabled": {
      "channels": ["slack", "email"],
      "message": "🚨 Autonomous mode disabled"
    },
    "critical_vulnerability": {
      "channels": ["slack", "pagerduty"],
      "message": "🚨 CRITICAL vulnerability detected"
    },
    "auto_fix_failed": {
      "channels": ["slack"],
      "message": "⚠️ Auto-fix failed after 3 attempts"
    }
  }
}
```

---

## Best Practices

**DO**:
✅ Check `/autonomous status` daily
✅ Review `/autonomous metrics` weekly
✅ Use `/autonomous pause` for maintenance
✅ Export metrics for long-term tracking
✅ Keep audit logs for compliance

**DON'T**:
❌ Disable without checking current tasks
❌ Reset without backup
❌ Ignore failed autonomous operations
❌ Run without monitoring initially
❌ Disable security scanning

---

**Command Version**: 1.0.0
**Last Updated**: 2026-01-31
**Status**: Ready for Implementation
