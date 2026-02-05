# Self-Healing Skill

**Version**: 1.0.0
**Purpose**: Systematic failure detection, diagnosis, and automatic remediation
**Applies To**: brahma-healer, brahma-monitor, brahma-investigator

---

## Overview

The Self-Healing skill provides systematic patterns for automatically detecting, diagnosing, and fixing system failures without human intervention. It combines pattern matching, trial-and-error learning, and safety mechanisms to achieve 70%+ auto-fix success rate.

**Key Capabilities**:
1. Failure pattern recognition and classification
2. Root cause hypothesis generation
3. Safe fix application with rollback
4. Continuous learning from outcomes
5. Economic viability assessment (fix cost vs downtime cost)

---

## When to Use

Use Self-Healing when:
- System failure detected (error, crash, timeout, performance degradation)
- Known failure pattern identified (confidence ≥ 60%)
- Fix can be applied safely (rollback plan exists)
- Cost of auto-fix < cost of downtime + manual intervention

Do NOT use for:
- Security incidents (require manual investigation)
- User data operations (require approval)
- Unknown failure with no hypotheses
- Failures during blackout windows (business hours)

---

## Protocol

### Phase 1: Failure Detection & Classification

```markdown
**Input**: Alert from monitoring system

**Steps**:
1. **Parse alert context**:
   - Error message and stack trace
   - Affected service/component
   - Timestamp and frequency
   - Recent changes (git commits, deploys)

2. **Classify failure type**:
   - CRASH: Service stopped
   - ERROR: Exception thrown
   - TIMEOUT: Request too slow
   - PERFORMANCE: Degraded response time
   - MEMORY: Out of memory, leak detected
   - DISK: Disk full, I/O errors
   - NETWORK: Connection failures

3. **Classify severity**:
   - CRITICAL: Production down, data loss risk
   - HIGH: Feature broken, user impact
   - MEDIUM: Degraded performance
   - LOW: Minor issue, workaround exists

4. **Check knowledge base**:
   - Search knowledge-core.md for similar failures
   - Check pattern-index.json for confidence scores
   - If match found (confidence ≥ 80%) → Use documented fix
   - If no match → Generate hypotheses
```

**Classification Decision Tree**:
```
Is error message in knowledge-core.md?
├─ Yes (confidence ≥ 80%) → Use documented fix
└─ No → Generate hypotheses
    ├─ Error pattern matches known category?
    │   ├─ Memory pattern → Memory fix
    │   ├─ Timeout pattern → Timeout fix
    │   ├─ Connection pattern → Network fix
    │   └─ Disk pattern → Disk fix
    └─ No pattern match → Generate custom hypotheses
```

---

### Phase 2: Root Cause Hypothesis Generation

```markdown
**Think Protocol**: Use "think harder" for hypothesis generation

**Steps**:
1. **Temporal correlation analysis**:
   - What changed in last 24 hours?
   - Recent code deploys (git log)
   - Recent config changes
   - Recent dependency updates
   - External events (load spikes)

2. **Generate 3-5 hypotheses** (ranked by likelihood):
   - Based on error pattern
   - Based on temporal correlation
   - Based on affected component
   - Based on system state

3. **For each hypothesis, define**:
   - Root cause description
   - Likelihood (0-100%)
   - Fix procedure
   - Validation method
   - Rollback procedure

4. **Rank hypotheses** by:
   - Likelihood × ease_of_fix × reversibility
```

**Hypothesis Template**:
```markdown
## Hypothesis #N: [Root Cause Description]

**Likelihood**: X% (based on Y evidence)
**Ease of Fix**: [EASY | MEDIUM | HARD]
**Reversibility**: [FULLY_REVERSIBLE | MOSTLY_REVERSIBLE | IRREVERSIBLE]

**Evidence**:
- [Evidence point 1]
- [Evidence point 2]

**Fix Procedure**:
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Validation Method**:
- Check that [specific metric] improves
- Verify [specific error] stops
- Monitor for [time period]

**Rollback Procedure**:
1. [Rollback step 1]
2. [Rollback step 2]
```

**Example Hypotheses**:
```markdown
# Alert: API server crashes with "Out of Memory"

## Hypothesis #1: Memory Leak in Background Job
**Likelihood**: 70%
**Evidence**:
- Memory usage growing steadily over 24 hours
- Background job added in yesterday's deploy
- Job processes large datasets without cleanup

**Fix**: Add explicit memory cleanup in background job
**Validation**: Memory usage stable over 24 hours

## Hypothesis #2: Insufficient Memory Allocation
**Likelihood**: 50%
**Evidence**:
- Increased traffic in past week (+30%)
- Memory limit not changed in 6 months
- Other services using more memory

**Fix**: Increase memory limit from 2GB → 4GB
**Validation**: No OOM errors for 24 hours

## Hypothesis #3: Large Request Payload
**Likelihood**: 30%
**Evidence**:
- New feature allows file uploads
- Some users uploading very large files
- Crashes correlate with upload endpoint

**Fix**: Add request size limit, stream large files
**Validation**: Crashes stop, uploads still work
```

---

### Phase 3: Rollback Snapshot Creation

```markdown
**MANDATORY**: Never apply fix without rollback snapshot

**Steps**:
1. **Capture current state**:
   ```bash
   # Git state
   git rev-parse HEAD > rollback-snapshot.txt
   git status --short >> rollback-snapshot.txt

   # Config files
   cp config.yaml config.yaml.rollback
   cp .env .env.rollback

   # Database schema (if applicable)
   pg_dump --schema-only > schema.rollback.sql

   # Service versions
   kubectl get deployments -o yaml > deployments.rollback.yaml
   ```

2. **Create rollback script**:
   ```bash
   #!/bin/bash
   # Rollback script for failure-[ID]
   # Created: [timestamp]

   echo "Rolling back to pre-fix state..."

   # Rollback git
   git checkout [commit-hash]

   # Rollback config
   cp config.yaml.rollback config.yaml

   # Rollback deployment
   kubectl apply -f deployments.rollback.yaml

   # Validate rollback
   ./validate-health.sh
   ```

3. **Test rollback script** (dry-run):
   - Verify all commands are valid
   - Check all files exist
   - Estimate rollback time

4. **Store snapshot**:
   - Save to `.claude/rollback/failure-[ID]/`
   - Set expiration (7 days)
   - Log to audit trail
```

**Rollback Snapshot Checklist**:
- [ ] Git commit hash captured
- [ ] Config files backed up
- [ ] Database schema captured (if applicable)
- [ ] Service versions captured
- [ ] Rollback script created
- [ ] Rollback script tested (dry-run)
- [ ] Expiration date set
- [ ] Audit log updated

---

### Phase 4: Fix Application (with Safety Checks)

```markdown
**Think Protocol**: Use "think hard" for fix execution

**Safety Checks** (all must pass):
1. ✅ Rollback snapshot created and tested
2. ✅ Fix confidence ≥ 60% OR human approval obtained
3. ✅ Fix does not modify user data (unless approved)
4. ✅ Fix is reversible
5. ✅ Not in blackout window (if configured)
6. ✅ Economic viability (fix cost < downtime cost)

**Execution Steps**:

**Option A: Known Fix (confidence ≥ 80%)**
```bash
# 1. Apply fix from knowledge-core.md
./apply-fix.sh --fix-id=[known-fix-id]

# 2. Wait for stabilization (2 minutes)
sleep 120

# 3. Validate fix
./validate-fix.sh

# 4. If valid → Document success
# 5. If invalid → Rollback
```

**Option B: Trial-and-Error Fix (confidence < 80%)**
```bash
# 1. Test fix in staging (if available)
if [ -n "$STAGING_ENV" ]; then
    echo "Testing fix in staging..."
    ssh $STAGING_ENV "./apply-fix.sh"
    if ! validate_staging; then
        echo "Fix failed in staging, aborting"
        exit 1
    fi
fi

# 2. Apply to production
./apply-fix.sh

# 3. Monitor closely (5 minutes)
for i in {1..5}; do
    sleep 60
    if ! validate_health; then
        echo "Health check failed, rolling back"
        ./rollback.sh
        exit 1
    fi
done

# 4. Declare success
echo "Fix validated successfully"
```

**Fix Application Pattern** (pseudocode):
```python
def apply_fix(hypothesis, rollback_snapshot):
    # Pre-flight checks
    assert rollback_snapshot is not None
    assert hypothesis.confidence >= 0.60 or human_approved
    assert hypothesis.reversible == True

    # Test in staging first (if available)
    if has_staging():
        if not test_in_staging(hypothesis):
            return "FAILED_IN_STAGING"

    # Apply to production
    print(f"Applying fix: {hypothesis.description}")
    execute_commands(hypothesis.fix_commands)

    # Wait for stabilization
    wait(seconds=120)

    # Validate
    if validate_fix(hypothesis):
        log_success(hypothesis)
        return "SUCCESS"
    else:
        print("Fix failed validation, rolling back")
        execute_rollback(rollback_snapshot)
        return "FAILED"
```

---

### Phase 5: Fix Validation

```markdown
**Validation Criteria**:

1. **Original error stopped**:
   - No recurrence in logs (5 minute window)
   - Error rate dropped to 0

2. **No new errors introduced**:
   - Error rate within baseline ±20%
   - No new exception types

3. **Performance maintained**:
   - Response time within baseline ±20%
   - CPU/memory usage normal

4. **Business functionality intact**:
   - Critical user journeys working
   - No data corruption
   - No service disruption
```

**Validation Script Template**:
```bash
#!/bin/bash
# validate-fix.sh

echo "Validating fix for failure-${FAILURE_ID}..."

# 1. Check if original error stopped
ORIGINAL_ERROR_COUNT=$(grep -c "${ERROR_PATTERN}" /var/log/app.log)
if [ $ORIGINAL_ERROR_COUNT -gt 0 ]; then
    echo "❌ Original error still occurring ($ORIGINAL_ERROR_COUNT times)"
    exit 1
fi
echo "✅ Original error stopped"

# 2. Check error rate
CURRENT_ERROR_RATE=$(get_error_rate_per_minute)
BASELINE_ERROR_RATE=$(get_baseline_error_rate)
THRESHOLD=$(echo "$BASELINE_ERROR_RATE * 1.2" | bc)

if (( $(echo "$CURRENT_ERROR_RATE > $THRESHOLD" | bc) )); then
    echo "❌ Error rate too high: $CURRENT_ERROR_RATE (threshold: $THRESHOLD)"
    exit 1
fi
echo "✅ Error rate normal"

# 3. Check response time
RESPONSE_TIME_P95=$(get_response_time_p95)
BASELINE_P95=$(get_baseline_response_time_p95)
THRESHOLD=$(echo "$BASELINE_P95 * 1.2" | bc)

if (( $(echo "$RESPONSE_TIME_P95 > $THRESHOLD" | bc) )); then
    echo "❌ Response time degraded: ${RESPONSE_TIME_P95}ms (threshold: ${THRESHOLD}ms)"
    exit 1
fi
echo "✅ Response time normal"

# 4. Check critical endpoints
for endpoint in "${CRITICAL_ENDPOINTS[@]}"; do
    if ! curl -f -s "$endpoint" > /dev/null; then
        echo "❌ Critical endpoint failing: $endpoint"
        exit 1
    fi
done
echo "✅ All critical endpoints healthy"

echo "✅ Fix validated successfully!"
exit 0
```

---

### Phase 6: Learning & Documentation

```markdown
**Steps**:

1. **Document successful fix** in knowledge-core.md:
   ```markdown
   ### Pattern: [Failure Type] - [Brief Description]

   **Context**: [When this occurs]
   **Problem**: [What fails]
   **Solution**: [Fix procedure]
   **Performance**: Success rate X%, MTTR Y minutes
   **Confidence**: Z% (HIGH/MEDIUM/LOW)
   ```

2. **Update pattern-index.json**:
   ```json
   {
     "failure_pattern_name": {
       "total_uses": 5,
       "successes": 4,
       "confidence": 0.80,
       "confidence_level": "HIGH",
       "avg_resolution_time_minutes": 8,
       "last_used": "2026-01-31T12:00:00Z"
     }
   }
   ```

3. **Create runbook** (for on-call engineers):
   - Step-by-step fix procedure
   - Validation checklist
   - Rollback procedure
   - Troubleshooting tips

4. **Update metrics**:
   - Increment fix attempts
   - Record success/failure
   - Track time to resolution
   - Update confidence scores
```

---

## Common Self-Healing Patterns

### Pattern 1: Service Restart

**When to Use**: Service crashed or hung
**Success Rate**: 85%
**Confidence**: HIGH (0.90)

```bash
# Detection
if ! curl -f http://service/health; then
    # Rollback snapshot
    git rev-parse HEAD > rollback.txt

    # Fix: Restart service
    systemctl restart api-server

    # Validate (wait 30 seconds)
    sleep 30
    if curl -f http://service/health; then
        echo "✅ Fix successful"
        log_success "service_restart"
    else
        echo "❌ Fix failed"
        # Service down, escalate immediately
        alert_human "CRITICAL"
    fi
fi
```

---

### Pattern 2: Memory Leak Mitigation

**When to Use**: Memory usage growing, OOM errors
**Success Rate**: 70%
**Confidence**: MEDIUM (0.70)

```bash
# Detection
MEMORY_PERCENT=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
if (( $(echo "$MEMORY_PERCENT > 90" | bc) )); then
    # Hypothesis: Memory leak or insufficient allocation

    # Short-term fix: Restart to free memory
    systemctl restart api-server

    # Long-term: Schedule investigation
    create_task brahma-investigator "Find memory leak source"
fi
```

---

### Pattern 3: Disk Space Cleanup

**When to Use**: Disk full errors
**Success Rate**: 95%
**Confidence**: HIGH (0.95)

```bash
# Detection
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 90 ]; then
    # Rollback: Not needed (cleanup is safe)

    # Fix: Clean old logs and temp files
    find /var/log -name "*.log" -mtime +7 -delete
    find /tmp -mtime +1 -delete
    docker system prune -f --volumes

    # Validate
    DISK_USAGE_AFTER=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ $DISK_USAGE_AFTER -lt 80 ]; then
        echo "✅ Disk space recovered: $DISK_USAGE% → $DISK_USAGE_AFTER%"
    else
        echo "⚠️  Disk still high: $DISK_USAGE_AFTER%"
        alert_human "HIGH"
    fi
fi
```

---

### Pattern 4: Rollback Recent Deployment

**When to Use**: Errors started after recent deploy
**Success Rate**: 90%
**Confidence**: HIGH (0.90)

```bash
# Detection
LAST_DEPLOY=$(get_last_deploy_time)
ERROR_START=$(get_first_error_time)

if [ "$ERROR_START" -gt "$LAST_DEPLOY" ]; then
    # High likelihood: Deploy caused issue

    # Rollback deployment
    kubectl rollout undo deployment/api-server

    # Wait for rollout
    kubectl rollout status deployment/api-server

    # Validate
    sleep 60
    if validate_health; then
        echo "✅ Rollback successful, errors stopped"
        create_task code-implementer "Fix deployed code"
    else
        echo "❌ Rollback didn't help, issue is elsewhere"
        create_task brahma-investigator "Investigate root cause"
    fi
fi
```

---

### Pattern 5: Connection Pool Tuning

**When to Use**: "Connection pool exhausted" errors
**Success Rate**: 80%
**Confidence**: HIGH (0.80)

```bash
# Detection
if grep -q "connection pool exhausted" /var/log/app.log; then
    # Rollback: Save current config
    cp config.yaml config.yaml.rollback

    # Fix: Increase pool size
    sed -i 's/connection_pool_size: 20/connection_pool_size: 50/' config.yaml

    # Restart service
    systemctl restart api-server

    # Validate
    sleep 120
    ERROR_COUNT=$(grep -c "connection pool exhausted" /var/log/app.log)
    if [ $ERROR_COUNT -eq 0 ]; then
        echo "✅ Fix successful"
        create_task code-implementer "Find connection leaks"
    else
        echo "❌ Fix failed, rolling back"
        cp config.yaml.rollback config.yaml
        systemctl restart api-server
    fi
fi
```

---

## Economic Viability Assessment

**Formula**:
```
fix_value = downtime_cost_per_minute × expected_downtime_minutes
fix_cost = manual_intervention_cost + fix_risk_cost

if fix_value > fix_cost × 2:
    apply_fix_automatically()
else:
    require_human_approval()
```

**Example Calculation**:
```
# E-commerce site down
downtime_cost_per_minute = $500 (lost sales)
expected_downtime_minutes = 30 (if not auto-fixed)
fix_value = $500 × 30 = $15,000

# Auto-fix cost
manual_intervention_cost = $200 (engineer time)
fix_risk_cost = $100 (risk of making it worse)
fix_cost = $200 + $100 = $300

# Decision
fix_value ($15,000) > fix_cost ($300) × 2
$15,000 > $600 ✅

# Conclusion: Auto-fix is economically justified
```

---

## Integration with Agents

**brahma-healer** uses this skill for:
- All failure detection and remediation
- Learning from fix outcomes
- Building failure pattern library

**brahma-monitor** uses this skill for:
- Classifying detected anomalies
- Deciding when to trigger brahma-healer

**brahma-investigator** uses this skill for:
- Understanding known failure patterns
- Avoiding duplicate investigations

---

## Best Practices

### DO:
✅ Always create rollback snapshot before fix
✅ Test fixes in staging first (if available)
✅ Monitor closely after fix application
✅ Document successful fixes immediately
✅ Learn from failures (update pattern confidence)
✅ Escalate after 3 failed attempts

### DON'T:
❌ Apply fixes without rollback plan
❌ Skip validation after fix
❌ Modify user data without approval
❌ Apply low-confidence fixes to CRITICAL issues
❌ Continue after 3 failures (escalate instead)
❌ Fix during blackout windows without approval

---

**Skill Version**: 1.0.0
**Last Updated**: 2026-01-31
**Status**: Ready for Use
