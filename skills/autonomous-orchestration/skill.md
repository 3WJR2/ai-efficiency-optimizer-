# Autonomous Orchestration Skill

**Version**: 1.0.0
**Purpose**: Coordinate multiple agents without human intervention for autonomous workflows
**Applies To**: chief-architect, brahma-orchestrator

---

## Overview

The Autonomous Orchestration skill enables agents to coordinate complex multi-agent workflows without human approval, while maintaining high quality through quality gates and circuit breakers.

**Key Capabilities**:
1. Task decomposition into independent sub-tasks
2. Parallel agent spawning with economic viability checks
3. Deadlock detection and resolution
4. Quality gate enforcement
5. Automatic fallback and retry strategies

---

## When to Use

Use Autonomous Orchestration when:
- Task requires 3+ different specialist agents
- Sub-tasks are independent and can run in parallel
- Total estimated time > 20 minutes
- Economic viability (15x cost) is justified
- Quality can be enforced through automated gates

Do NOT use for:
- Simple single-agent tasks
- Tasks requiring human judgment
- Security-sensitive operations (without approval)
- Operations modifying user data

---

## Protocol

### Phase 1: Task Analysis & Decomposition

```markdown
**Think Protocol**: Use "ultrathink" for complex task decomposition

**Steps**:
1. Analyze task specification
2. Identify required capabilities
3. Break into independent sub-tasks
4. Map sub-tasks to specialist agents
5. Build dependency graph
```

**Decomposition Example**:
```python
# Input task: "Add user authentication with tests and deployment"

sub_tasks = [
    {
        "id": "auth-research",
        "type": "RESEARCH",
        "agent": "docs-researcher",
        "query": "JWT authentication best practices 2026",
        "parallel": True,
        "depends_on": []
    },
    {
        "id": "auth-security-scan",
        "type": "SECURITY",
        "agent": "brahma-security-scanner",
        "query": "Scan for auth vulnerabilities in codebase",
        "parallel": True,
        "depends_on": []
    },
    {
        "id": "auth-planning",
        "type": "PLANNING",
        "agent": "implementation-planner",
        "input": "Create JWT auth implementation plan",
        "parallel": False,
        "depends_on": ["auth-research", "auth-security-scan"]
    },
    {
        "id": "auth-implementation",
        "type": "IMPLEMENTATION",
        "agent": "code-implementer",
        "input": "Implement JWT auth from plan",
        "parallel": False,
        "depends_on": ["auth-planning"]
    },
    {
        "id": "auth-testing",
        "type": "TESTING",
        "agent": "brahma-ci-runner",
        "input": "Run auth tests",
        "parallel": False,
        "depends_on": ["auth-implementation"]
    },
    {
        "id": "auth-deployment",
        "type": "DEPLOYMENT",
        "agent": "brahma-deployer",
        "input": "Deploy auth feature",
        "parallel": False,
        "depends_on": ["auth-testing"]
    }
]

# Parallel execution opportunities:
# - auth-research + auth-security-scan (independent)
# - Rest are sequential due to dependencies
```

---

### Phase 2: Economic Viability Check

```markdown
**Think Protocol**: Use "think hard" for cost/benefit analysis

**Formula**:
```
cost = num_parallel_agents × 5x base_token_cost
benefit = time_saved_hours × $100/hour + quality_improvement_value
roi = benefit / cost

if roi >= 10:
    approve = True
elif roi >= 5:
    approve = require_user_confirmation
else:
    approve = False  # Use single-agent fallback
```

**Example Calculation**:
```python
# Parallel execution of 3 agents
num_parallel_agents = 3
base_token_cost = 1000 tokens × $0.015/1K = $0.015
parallel_cost = 3 × 5 × $0.015 = $0.225

# Benefits
sequential_time = 60 minutes = 1 hour
parallel_time = 20 minutes = 0.33 hours
time_saved = 0.67 hours × $100/hour = $67

quality_improvement = 10% better (fewer errors) = $20 value

total_benefit = $67 + $20 = $87
roi = $87 / $0.225 = 387x

# Decision: APPROVE (roi >= 10)
```

---

### Phase 3: Parallel Agent Spawning

```markdown
**Steps**:
1. Identify parallel sub-tasks (no dependencies)
2. For each parallel sub-task:
   - Spawn appropriate specialist agent
   - Provide context and input
   - Set timeout and retry limits
3. Monitor progress concurrently
4. Collect results when all complete
```

**Spawning Pattern** (using Task tool):
```python
# Spawn parallel agents
parallel_tasks = [
    Task(
        subagent_type="docs-researcher",
        prompt="Research JWT authentication best practices...",
        description="Research JWT auth",
        run_in_background=False
    ),
    Task(
        subagent_type="brahma-security-scanner",
        prompt="Scan codebase for auth vulnerabilities...",
        description="Security scan",
        run_in_background=False
    )
]

# Execute in parallel (single message, multiple tool calls)
results = execute_parallel(parallel_tasks)

# Synthesize results
research_pack = results[0]
security_report = results[1]
```

---

### Phase 4: Quality Gate Enforcement

```markdown
**Quality Gates** (mandatory checks before proceeding):

Gate 1: Research Quality (≥ 80)
- If < 80: Retry with refined query (max 2 retries)
- If still < 80: Escalate to human

Gate 2: Plan Quality (≥ 85)
- If < 85: brahma-analyzer identifies issues
- Refine plan automatically (max 2 retries)
- If still < 85: Escalate to human

Gate 3: Test Coverage (≥ 80%)
- If < 80%: brahma-test-generator adds tests
- Re-run coverage check
- If still < 80%: Block deployment, escalate

Gate 4: Security Scan (0 CRITICAL, < 5 HIGH)
- If CRITICAL found: Block immediately, escalate
- If HIGH > 5: brahma-healer attempts auto-fix
- If unfixable: Escalate to human

Gate 5: Performance (no regression > 10%)
- If regression detected: brahma-optimizer analyzes
- Attempt auto-optimization
- If optimization fails: Rollback, escalate
```

**Gate Implementation**:
```python
def enforce_quality_gate(phase, artifact, threshold):
    score = quality_validation(artifact)

    if score >= threshold:
        return "PASS", artifact

    # Auto-improvement attempts
    for attempt in range(3):
        improved_artifact = improve(artifact, feedback=quality_issues)
        score = quality_validation(improved_artifact)

        if score >= threshold:
            return "PASS", improved_artifact

    # Failed to meet threshold
    return "FAIL", artifact
```

---

### Phase 5: Deadlock Detection & Resolution

```markdown
**Deadlock Scenarios**:

Scenario 1: Circular Dependency
- Task A depends on Task B
- Task B depends on Task A
- Resolution: Identify which dependency is optional, break it

Scenario 2: Resource Contention
- Task A locks Resource X, needs Resource Y
- Task B locks Resource Y, needs Resource X
- Resolution: Order lock acquisition consistently

Scenario 3: Agent Unavailability
- All instances of specialist agent busy
- No fallback agent available
- Resolution: Queue task, increase timeout, or escalate

**Detection Algorithm**:
```python
def detect_deadlock():
    # Check for circular dependencies
    for task in pending_tasks:
        cycle = find_dependency_cycle(task)
        if cycle:
            return resolve_cycle(cycle)

    # Check for stuck tasks (no progress in 2 hours)
    for task in active_tasks:
        if task.last_progress_time < now - 2_hours:
            return diagnose_stuck_task(task)

    return None

def resolve_cycle(cycle):
    # Find lowest-priority task in cycle
    weakest_task = min(cycle, key=lambda t: t.priority)

    # Break dependency
    remove_dependency(weakest_task, cycle)

    log_to_knowledge_core(f"Deadlock resolved by breaking {weakest_task.id} dependency")
    return True
```

---

### Phase 6: Failure Handling & Retry

```markdown
**Failure Types & Strategies**:

Type 1: Transient Failure (network, timeout)
- Strategy: Immediate retry (max 3 attempts)
- Backoff: 1s, 2s, 4s

Type 2: Quality Gate Failure
- Strategy: Auto-improvement (max 3 attempts)
- Escalate if threshold not met

Type 3: Agent Crash
- Strategy: Reassign to backup agent
- Fallback to general-purpose if no specialist available

Type 4: Dependency Failure
- Strategy: Check if dependency is optional
- If optional: Continue without it
- If required: Block and escalate

Type 5: Economic Failure (cost > budget)
- Strategy: Switch to cheaper model (Sonnet → Haiku)
- Reduce parallelism (3 agents → 1 agent)
- Simplify task scope
```

**Retry Logic**:
```python
def execute_with_retry(sub_task, max_attempts=3):
    for attempt in range(max_attempts):
        try:
            result = execute_task(sub_task)

            if quality_gate_pass(result):
                return "SUCCESS", result
            else:
                # Auto-improvement
                sub_task = refine_task(sub_task, result.feedback)

        except TransientError as e:
            wait_seconds = 2 ** attempt  # Exponential backoff
            time.sleep(wait_seconds)
            continue

        except AgentCrash as e:
            # Try backup agent
            sub_task.agent = get_backup_agent(sub_task.agent)
            continue

    # Failed after max attempts
    return "FAILURE", None
```

---

## Integration with Existing Agents

### chief-architect Integration
```markdown
When chief-architect receives complex task:

1. Check if task suitable for autonomous orchestration
   - Complexity: HIGH
   - Sub-tasks: >= 3
   - Independence: HIGH
   - Economic viability: PASS

2. If suitable:
   - Use Autonomous Orchestration skill
   - Spawn parallel agents
   - Monitor via brahma-orchestrator

3. If not suitable:
   - Use traditional sequential workflow
   - Manual approval gates
```

### brahma-orchestrator Integration
```markdown
brahma-orchestrator uses this skill for:

1. Task queue management
2. Agent assignment
3. Deadlock detection
4. Quality gate enforcement
5. Metrics collection
```

---

## Autonomous Decision Framework

### Decision Matrix:

| Condition | Action | Human Approval |
|-----------|--------|----------------|
| Quality ≥ 90, Tests pass | Auto-approve | No |
| Quality 80-89, Tests pass | Auto-approve with monitoring | No |
| Quality 70-79, Tests pass | Auto-improve (3 attempts) | No |
| Quality < 70 | Escalate | Yes |
| CRITICAL security issue | Block immediately | Yes |
| Production data modification | Block | Yes |
| Cost > $50 | Request approval | Yes |

---

## Metrics & Monitoring

### Track These Metrics:
- **Autonomous Success Rate**: % tasks completed without human intervention
- **Quality Distribution**: Distribution of quality scores (< 70, 70-79, 80-89, ≥ 90)
- **Economic Efficiency**: Actual cost vs estimated cost
- **Deadlock Frequency**: Deadlocks detected per 100 tasks
- **Average Parallelization Factor**: Average number of parallel agents used

### Alert Conditions:
- Autonomous success rate < 80% → Review quality gates
- Quality distribution skewed low → Review task complexity
- Economic efficiency < 70% → Review cost estimation
- Deadlock frequency > 5% → Review dependency patterns

---

## Example: Complete Autonomous Workflow

```markdown
Task: "Implement user authentication feature"

Step 1: Decomposition
- Sub-task 1: Research JWT auth (docs-researcher) [PARALLEL]
- Sub-task 2: Security scan (brahma-security-scanner) [PARALLEL]
- Sub-task 3: Create plan (implementation-planner) [DEPENDS: 1,2]
- Sub-task 4: Implement (code-implementer) [DEPENDS: 3]
- Sub-task 5: Generate tests (brahma-test-generator) [DEPENDS: 4]
- Sub-task 6: Run tests (brahma-ci-runner) [DEPENDS: 5]
- Sub-task 7: Deploy (brahma-deployer) [DEPENDS: 6]

Step 2: Economic Check
- Parallel agents: 2 (research + security)
- Sequential agents: 5
- Total cost: 2×5x + 5×1x = 15x base cost = $0.30
- Time saved: 50% (40 min → 20 min)
- Benefit: $50
- ROI: 167x ✅

Step 3: Execution
- Spawn docs-researcher + brahma-security-scanner in parallel
- Wait for both to complete (10 minutes)
- Check quality gates: Research 85/100 ✅, Security 0 CRITICAL ✅
- Spawn implementation-planner (5 minutes)
- Check quality gate: Plan 90/100 ✅
- Spawn code-implementer (15 minutes)
- Spawn brahma-test-generator (3 minutes)
- Spawn brahma-ci-runner (2 minutes)
- Check quality gate: Tests pass ✅, Coverage 82% ✅
- Spawn brahma-deployer (5 minutes)
- Monitor deployment health (brahma-monitor)

Step 4: Completion
- Total time: 40 minutes (vs 80 minutes sequential)
- Quality score: 88/100 (HIGH)
- Cost: $0.32 (vs estimated $0.30, 107% efficiency)
- Autonomous: 100% (no human intervention)

Step 5: Learning
- Update pattern-index.json: JWT_AUTH pattern → 95% confidence
- Add to knowledge-core.md as HIGH confidence pattern
- Update orchestrator metrics
```

---

## Safety & Governance

### Circuit Breakers:
1. **Max Parallel Agents**: 5 (to prevent runaway costs)
2. **Max Retry Attempts**: 3 per task
3. **Max Total Cost**: $100 per workflow
4. **Max Duration**: 4 hours per workflow

### Human Escalation Triggers:
- Quality gate failure after 3 auto-improvement attempts
- CRITICAL security vulnerability detected
- Production data modification required
- Cost exceeds budget by > 50%
- Deadlock unresolvable after 3 attempts
- Agent failure rate > 50% for a sub-task

### Audit Trail:
- All autonomous decisions logged to `.claude/audit/autonomous-decisions.log`
- Quality gate results saved
- Economic calculations documented
- Failure reasons recorded

---

## Best Practices

### DO:
✅ Use "ultrathink" for complex task decomposition
✅ Enforce quality gates rigorously
✅ Monitor economic efficiency continuously
✅ Learn from outcomes (update pattern-index.json)
✅ Escalate when uncertain

### DON'T:
❌ Skip economic viability checks
❌ Ignore quality gates to speed up workflow
❌ Spawn unlimited parallel agents
❌ Modify production data without approval
❌ Continue after 3 failed retry attempts

---

**Skill Version**: 1.0.0
**Last Updated**: 2026-01-31
**Status**: Ready for Use
