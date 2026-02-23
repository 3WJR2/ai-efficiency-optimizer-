---
name: autonomous
description: Control autonomous agent operations - enable, disable, monitor, and configure
argument-hint: action (status|enable|disable|pause|resume|metrics|audit|config|test|reset)
disable-model-invocation: true
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
Recent Activity (last 1 hour):
  12:45 - brahma-ci-runner: Tests passed (23/23)
  12:30 - brahma-healer: Auto-fixed memory leak
```

---

### /autonomous enable

Enable autonomous operations (all agents).

```bash
# Enable all autonomous operations
/autonomous enable

# Enable specific agent
/autonomous enable --agent brahma-ci-runner
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
```

**Effect**:
- Sets `autonomous_mode_enabled: false` in config
- Pauses all autonomous agents (they finish current task)
- Stops accepting new tasks
- Logs disable event to audit trail

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
```

---

### /autonomous audit

View audit trail of autonomous decisions.

```bash
# Show recent audit events
/autonomous audit

# Show audit for specific date
/autonomous audit --date 2026-01-31

# Search audit log
/autonomous audit --search "CRITICAL"
```

---

### /autonomous config

View or update autonomous configuration.

```bash
# Show current config
/autonomous config

# Update setting
/autonomous config coverage_threshold 85

# Reset to defaults
/autonomous config --reset
```

---

## Use Cases

### Maintenance Window

```bash
# Pause autonomous operations for 2 hours
/autonomous pause --duration 2h

# Perform maintenance
# ... (deploy, upgrade, etc.)

# Resume (or will auto-resume after 2h)
/autonomous resume
```

---

### Debug Issues

```bash
# Check what's happening
/autonomous status

# View recent audit trail
/autonomous audit --since 1h

# Check specific agent
/autonomous metrics --agent brahma-healer
```

---

### Emergency Shutdown

```bash
# Something went wrong, stop everything
/autonomous disable --force

# Investigate
/autonomous audit --search "ERROR"

# Fix issue, then resume
/autonomous enable
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

**Executing command...**

Please invoke the autonomous control system with: `$ARGUMENTS`

This will manage autonomous agent operations including status monitoring, enabling/disabling agents, viewing metrics, and accessing audit trails.
