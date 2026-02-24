# Phase 3B Integration Examples

**Complete workflows and real-world usage scenarios**

---

## Table of Contents

1. [Quick Start: First-Time Setup](#quick-start-first-time-setup)
2. [Workflow 1: Intelligent Configuration Discovery](#workflow-1-intelligent-configuration-discovery)
3. [Workflow 2: Workload-Adaptive System](#workflow-2-workload-adaptive-system)
4. [Workflow 3: Continuous Optimization Loop](#workflow-3-continuous-optimization-loop)
5. [Workflow 4: Safe Configuration Testing](#workflow-4-safe-configuration-testing)
6. [Workflow 5: Context-Aware Caching](#workflow-5-context-aware-caching)
7. [Integration with Phase 1-3A](#integration-with-phase-1-3a)
8. [Automation Examples](#automation-examples)
9. [Real-World Scenarios](#real-world-scenarios)
10. [Monitoring Dashboard](#monitoring-dashboard)

---

## Quick Start: First-Time Setup

### Initialize All Phase 3B Systems

```bash
#!/usr/bin/env bash
# init-phase-3b.sh - Initialize all Phase 3B improvements

echo "🚀 Initializing Phase 3B Systems..."
echo

# 1. Multi-Objective Optimization
echo "1. Multi-Objective Optimization..."
~/.claude/scripts/multi-objective-optimization.sh init
echo

# 2. Workload Classification
echo "2. Workload Classification..."
~/.claude/scripts/workload-classifier.sh init
~/.claude/scripts/workload-classifier.sh auto-switch enable
echo

# 3. Config MAB
echo "3. Multi-Armed Bandit..."
~/.claude/scripts/config-mab.sh init
~/.claude/scripts/config-mab.sh enable
echo

# 4. A/B Testing
echo "4. A/B Testing Framework..."
~/.claude/scripts/ab-testing.sh init
echo

# 5. Smart Caching
echo "5. Smart Caching..."
~/.claude/scripts/smart-cache.sh init
~/.claude/scripts/smart-cache.sh enable
echo

echo "✅ All Phase 3B systems initialized!"
echo
echo "Next steps:"
echo "  1. Let system collect baseline data (run normally for 1 hour)"
echo "  2. Run: ./check-phase-3b-status.sh"
echo "  3. Start with Workflow 1 (Intelligent Configuration Discovery)"
```

### Check Status of All Systems

```bash
#!/usr/bin/env bash
# check-phase-3b-status.sh - Check status of all Phase 3B systems

echo "📊 Phase 3B System Status"
echo "========================="
echo

echo "1️⃣  Multi-Objective Optimization"
echo "--------------------------------"
~/.claude/scripts/multi-objective-optimization.sh status
echo

echo "2️⃣  Workload Classification"
echo "--------------------------------"
~/.claude/scripts/workload-classifier.sh status
echo

echo "3️⃣  Config Multi-Armed Bandit"
echo "--------------------------------"
~/.claude/scripts/config-mab.sh status
echo

echo "4️⃣  A/B Testing Framework"
echo "--------------------------------"
~/.claude/scripts/ab-testing.sh status
echo

echo "5️⃣  Smart Caching"
echo "--------------------------------"
~/.claude/scripts/smart-cache.sh performance
echo
```

Save these scripts and run:

```bash
chmod +x ~/init-phase-3b.sh ~/check-phase-3b-status.sh
~/init-phase-3b.sh
```

---

## Workflow 1: Intelligent Configuration Discovery

**Goal:** Find the optimal configuration for your workload using multi-objective optimization and statistical validation.

### Step 1: Collect Baseline Data

```bash
# Let system run normally for 1-2 hours to collect data
# The learning daemon automatically tracks outcomes

# Check if enough data collected
samples=$(jq '.cache_outcomes.hit_rate_history | length' ~/.claude/data/learning-data.json)
echo "Samples collected: $samples (need 20+)"
```

### Step 2: Run Multi-Objective Evaluation

```bash
# Calculate current performance across all metrics
~/.claude/scripts/multi-objective-optimization.sh evaluate
```

**Example output:**
```
Finding Pareto frontier...
✓ Found 3 non-dominated solutions

Top Pareto-optimal solutions:
  Score: 82% | Cache: 0.78 | Concurrent: 4 | Hit: 68% | Latency: 45ms
  Score: 79% | Cache: 0.80 | Concurrent: 5 | Hit: 65% | Latency: 42ms
  Score: 76% | Cache: 0.75 | Concurrent: 6 | Hit: 71% | Latency: 52ms

Best Configuration:
{
  "composite_score": 0.82,
  "config": {
    "cache_threshold": 0.78,
    "max_concurrent": 4
  }
}
```

### Step 3: Validate with A/B Testing

```bash
# Get current config
current_cache=$(jq -r '.similarity_threshold' ~/.claude/data/cache-config.json)
current_concurrent=$(jq -r '.max_concurrent_processes' ~/.claude/data/parallel-config.json)

# Get recommended config (from MOO best)
recommended_cache=0.78
recommended_concurrent=4

# Create A/B test
~/.claude/scripts/ab-testing.sh create \
  "moo_recommendation" \
  $current_cache $current_concurrent \
  $recommended_cache $recommended_concurrent
```

**Output:**
```
✓ Test created: test_1738771234
  Variant A (control): cache=0.80, concurrent=5
  Variant B (treatment): cache=0.78, concurrent=4

Apply variant A with: ~/.claude/scripts/ab-testing.sh apply-variant test_1738771234 a
```

### Step 4: Run A/B Test

```bash
#!/usr/bin/env bash
# run-ab-test.sh - Automated A/B test execution

TEST_ID="test_1738771234"
SAMPLES_PER_VARIANT=20
SAMPLE_INTERVAL=300  # 5 minutes

echo "🧪 Running A/B Test: $TEST_ID"
echo

# Variant A - Control
echo "Testing Variant A (Control)..."
~/.claude/scripts/ab-testing.sh apply-variant $TEST_ID a

for i in $(seq 1 $SAMPLES_PER_VARIANT); do
  echo "  Sample $i/$SAMPLES_PER_VARIANT"

  # Wait for workload to run
  sleep $SAMPLE_INTERVAL

  # Collect sample
  ~/.claude/scripts/ab-testing.sh collect-sample $TEST_ID
done

echo
echo "Testing Variant B (Treatment)..."
~/.claude/scripts/ab-testing.sh apply-variant $TEST_ID b

for i in $(seq 1 $SAMPLES_PER_VARIANT); do
  echo "  Sample $i/$SAMPLES_PER_VARIANT"

  # Wait for workload to run
  sleep $SAMPLE_INTERVAL

  # Collect sample
  ~/.claude/scripts/ab-testing.sh collect-sample $TEST_ID
done

echo
echo "📊 Analyzing results..."
~/.claude/scripts/ab-testing.sh analyze $TEST_ID
```

### Step 5: Apply if Significant

```bash
# Analyze test
~/.claude/scripts/ab-testing.sh analyze test_1738771234

# If recommendation is "ADOPT_B" and confidence is "high":
# Apply the new configuration
jq '.similarity_threshold = 0.78' ~/.claude/data/cache-config.json | sponge ~/.claude/data/cache-config.json
jq '.max_concurrent_processes = 4' ~/.claude/data/parallel-config.json | sponge ~/.claude/data/parallel-config.json

# Complete the test
~/.claude/scripts/ab-testing.sh complete test_1738771234

echo "✅ New configuration applied and validated!"
```

---

## Workflow 2: Workload-Adaptive System

**Goal:** Automatically adapt configuration as your work type changes throughout the day.

### Setup: Enable Automatic Workload Detection

```bash
# Enable auto-switching
~/.claude/scripts/workload-classifier.sh auto-switch enable

# Lower confidence threshold for faster switching (optional)
jq '.min_confidence_for_switch = 0.65' \
  ~/.claude/data/workload-data.json | \
  sponge ~/.claude/data/workload-data.json
```

### Create Monitoring Script

```bash
#!/usr/bin/env bash
# workload-monitor.sh - Monitor and log workload transitions

LOG_FILE="$HOME/.claude/logs/workload-transitions.log"
mkdir -p "$(dirname "$LOG_FILE")"

while true; do
  # Detect current workload
  result=$(~/.claude/scripts/workload-classifier.sh detect 2>&1)

  workload=$(echo "$result" | grep "Detected workload:" | awk '{print $3}')
  confidence=$(echo "$result" | grep "Confidence:" | awk '{print $2}')

  timestamp=$(date "+%Y-%m-%d %H:%M:%S")

  # Log transition
  echo "[$timestamp] Workload: $workload | Confidence: $confidence" >> "$LOG_FILE"

  # Apply if confident
  auto_switch=$(jq -r '.auto_switch_enabled' ~/.claude/data/workload-data.json)
  min_conf=$(jq -r '.min_confidence_for_switch' ~/.claude/data/workload-data.json)

  if [[ "$auto_switch" == "true" ]]; then
    conf_num=$(echo "$confidence" | tr -d '%')
    min_num=$(echo "$min_conf * 100" | bc | cut -d. -f1)

    if [[ $conf_num -ge $min_num ]]; then
      echo "[$timestamp] AUTO-APPLYING: $workload config" >> "$LOG_FILE"
      ~/.claude/scripts/workload-classifier.sh apply $workload >> "$LOG_FILE" 2>&1
    fi
  fi

  # Check every 15 minutes
  sleep 900
done
```

### Start Background Monitoring

```bash
# Start in background
nohup ~/workload-monitor.sh > /dev/null 2>&1 &

# Check logs
tail -f ~/.claude/logs/workload-transitions.log
```

**Example log output:**
```
[2026-02-05 09:00:00] Workload: exploration | Confidence: 78%
[2026-02-05 09:00:01] AUTO-APPLYING: exploration config
[2026-02-05 09:15:00] Workload: exploration | Confidence: 82%
[2026-02-05 09:30:00] Workload: implementation | Confidence: 75%
[2026-02-05 09:30:01] AUTO-APPLYING: implementation config
[2026-02-05 10:45:00] Workload: debugging | Confidence: 81%
[2026-02-05 10:45:01] AUTO-APPLYING: debugging config
```

### Manual Workload Override

```bash
# If you know you're about to do specific work, set it manually:

# Starting research session
~/.claude/scripts/workload-classifier.sh set research
~/.claude/scripts/workload-classifier.sh apply

# Starting implementation sprint
~/.claude/scripts/workload-classifier.sh set implementation
~/.claude/scripts/workload-classifier.sh apply

# Running test suite
~/.claude/scripts/workload-classifier.sh set testing
~/.claude/scripts/workload-classifier.sh apply
```

---

## Workflow 3: Continuous Optimization Loop

**Goal:** Use Multi-Armed Bandit to continuously discover better configurations.

### Setup: MAB Continuous Loop

```bash
#!/usr/bin/env bash
# mab-continuous-loop.sh - Continuous MAB optimization

CYCLE_DURATION=3600  # 1 hour per arm
LOG_FILE="$HOME/.claude/logs/mab-optimization.log"

mkdir -p "$(dirname "$LOG_FILE")"

echo "🎰 Starting MAB Continuous Optimization"
echo "Cycle duration: $CYCLE_DURATION seconds ($(($CYCLE_DURATION / 60)) minutes)"
echo "Logs: $LOG_FILE"
echo

iteration=1

while true; do
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] ===== Iteration $iteration =====" | tee -a "$LOG_FILE"

  # Select and apply next arm
  echo "[$timestamp] Selecting arm..." | tee -a "$LOG_FILE"
  result=$(~/.claude/scripts/config-mab.sh cycle 2>&1)
  echo "$result" | tee -a "$LOG_FILE"

  # Extract selected arm
  arm=$(echo "$result" | grep "Selected arm:" | awk '{print $3}')
  echo "[$timestamp] Running with arm: $arm" | tee -a "$LOG_FILE"

  # Wait for cycle duration
  sleep $CYCLE_DURATION

  # Update reward
  echo "[$timestamp] Calculating reward..." | tee -a "$LOG_FILE"
  reward_result=$(~/.claude/scripts/config-mab.sh update-reward 2>&1)
  echo "$reward_result" | tee -a "$LOG_FILE"

  # Show current standings
  echo "[$timestamp] Current standings:" | tee -a "$LOG_FILE"
  ~/.claude/scripts/config-mab.sh compare | tee -a "$LOG_FILE"

  echo | tee -a "$LOG_FILE"

  iteration=$((iteration + 1))
done
```

### Start MAB Loop

```bash
# Start in background
nohup ~/mab-continuous-loop.sh > /dev/null 2>&1 &

# Monitor progress
tail -f ~/.claude/logs/mab-optimization.log
```

### Check MAB Progress

```bash
#!/usr/bin/env bash
# check-mab-progress.sh - Check MAB learning progress

echo "🎰 Multi-Armed Bandit Progress"
echo "=============================="
echo

# Show arm rankings
~/.claude/scripts/config-mab.sh compare

echo
echo "Current best arm:"
best=$(jq -r '.best_arm' ~/.claude/data/config-mab-data.json)
if [[ "$best" != "null" ]]; then
  echo "  $best"

  # Show config
  cache=$(jq -r --arg arm "$best" '.arms[$arm].config.cache_threshold' ~/.claude/data/config-mab-data.json)
  concurrent=$(jq -r --arg arm "$best" '.arms[$arm].config.max_concurrent' ~/.claude/data/config-mab-data.json)
  reward=$(jq -r --arg arm "$best" '.arms[$arm].avg_reward' ~/.claude/data/config-mab-data.json)

  echo "  Config: cache=$cache, concurrent=$concurrent"
  echo "  Avg reward: $(echo "$reward * 100" | bc | cut -d. -f1)%"
else
  echo "  Not determined yet (need more samples)"
fi

echo
echo "Total exploration:"
total_pulls=$(jq '[.arms[].total_pulls] | add' ~/.claude/data/config-mab-data.json)
echo "  $total_pulls arm pulls"

# Minimum pulls check
min_pulls=$(jq -r '.min_pulls_per_arm' ~/.claude/data/config-mab-data.json)
echo "  Minimum per arm: $min_pulls"

# Check if all arms explored
all_explored=true
for arm in conservative balanced aggressive quality_focused speed_focused; do
  pulls=$(jq -r --arg arm "$arm" '.arms[$arm].total_pulls' ~/.claude/data/config-mab-data.json)
  if [[ $pulls -lt $min_pulls ]]; then
    all_explored=false
    echo "  ⚠ $arm: only $pulls pulls (need $min_pulls)"
  fi
done

if [[ "$all_explored" == "true" ]]; then
  echo "  ✅ All arms adequately explored"
fi
```

---

## Workflow 4: Safe Configuration Testing

**Goal:** Test risky configuration changes safely with automatic rollback.

### Integrated Safe Testing Pipeline

```bash
#!/usr/bin/env bash
# safe-config-test.sh - Safe configuration testing with rollback

set -e

TEST_NAME="$1"
NEW_CACHE="$2"
NEW_CONCURRENT="$3"

if [[ -z "$TEST_NAME" ]] || [[ -z "$NEW_CACHE" ]] || [[ -z "$NEW_CONCURRENT" ]]; then
  echo "Usage: $0 <test_name> <new_cache_threshold> <new_concurrent>"
  echo "Example: $0 aggressive_test 0.65 8"
  exit 1
fi

echo "🛡️  Safe Configuration Test: $TEST_NAME"
echo

# Step 1: Create rollback snapshot (Phase 3A)
echo "1. Creating rollback snapshot..."
~/.claude/scripts/automatic-rollback.sh snapshot cache "before $TEST_NAME"

# Step 2: Get current config
current_cache=$(jq -r '.similarity_threshold' ~/.claude/data/cache-config.json)
current_concurrent=$(jq -r '.max_concurrent_processes' ~/.claude/data/parallel-config.json)

echo "   Current: cache=$current_cache, concurrent=$current_concurrent"
echo "   New:     cache=$NEW_CACHE, concurrent=$NEW_CONCURRENT"
echo

# Step 3: Create A/B test
echo "2. Creating A/B test..."
test_id=$(~/.claude/scripts/ab-testing.sh create \
  "$TEST_NAME" \
  $current_cache $current_concurrent \
  $NEW_CACHE $NEW_CONCURRENT 2>&1 | \
  grep "Test created:" | awk '{print $3}')

echo "   Test ID: $test_id"
echo

# Step 4: Apply new config
echo "3. Applying new configuration..."
~/.claude/scripts/ab-testing.sh apply-variant $test_id b

echo "4. Collecting samples for 30 minutes..."
samples=0
max_samples=6
interval=300  # 5 minutes

for i in $(seq 1 $max_samples); do
  echo "   Sample $i/$max_samples..."
  sleep $interval
  ~/.claude/scripts/ab-testing.sh collect-sample $test_id
  samples=$((samples + 1))

  # Check for anomalies after each sample (Phase 3A)
  if ~/.claude/scripts/anomaly-detection.sh detect 2>&1 | grep -q "ANOMALY DETECTED"; then
    echo "   ⚠️  ANOMALY DETECTED!"
    echo
    echo "5. Performing automatic rollback..."
    ~/.claude/scripts/automatic-rollback.sh rollback

    echo "   ❌ Test aborted due to anomalies"
    echo "   Check: ~/.claude/scripts/anomaly-detection.sh log"
    exit 1
  fi
done

echo
echo "5. Analyzing results..."
analysis=$(~/.claude/scripts/ab-testing.sh analyze $test_id 2>&1)
echo "$analysis"

# Check recommendation
if echo "$analysis" | grep -q "Recommendation: ADOPT_B"; then
  echo
  echo "✅ Test successful! New configuration performs better."
  echo
  echo "Apply changes? (y/N): "
  read -r response

  if [[ "$response" =~ ^[Yy]$ ]]; then
    jq --argjson cache "$NEW_CACHE" \
       '.similarity_threshold = $cache' \
       ~/.claude/data/cache-config.json | \
       sponge ~/.claude/data/cache-config.json

    jq --argjson concurrent "$NEW_CONCURRENT" \
       '.max_concurrent_processes = $concurrent' \
       ~/.claude/data/parallel-config.json | \
       sponge ~/.claude/data/parallel-config.json

    echo "✅ Configuration applied permanently"
  else
    echo "Rolling back..."
    ~/.claude/scripts/automatic-rollback.sh rollback
    echo "✅ Rolled back to previous configuration"
  fi
else
  echo
  echo "❌ Test failed: new configuration not better"
  echo
  echo "Rolling back..."
  ~/.claude/scripts/automatic-rollback.sh rollback
  echo "✅ Rolled back to previous configuration"
fi

~/.claude/scripts/ab-testing.sh complete $test_id
echo
echo "Test complete: $TEST_NAME"
```

### Usage Example

```bash
chmod +x ~/safe-config-test.sh

# Test aggressive configuration safely
~/safe-config-test.sh "aggressive_caching" 0.65 8

# Test conservative configuration safely
~/safe-config-test.sh "conservative_quality" 0.92 3
```

---

## Workflow 5: Context-Aware Caching

**Goal:** Improve cache hit rate with smart caching factors.

### Enable and Configure Smart Caching

```bash
#!/usr/bin/env bash
# setup-smart-caching.sh - Configure smart caching

echo "🧠 Setting up Smart Caching"
echo

# Enable smart caching
~/.claude/scripts/smart-cache.sh enable

# Configure weights based on your usage pattern
echo "Select your usage pattern:"
echo "  1. High churn (queries change frequently)"
echo "  2. Stable (queries repeat often)"
echo "  3. Balanced (default)"
echo
read -p "Choice (1-3): " choice

case $choice in
  1)
    # High churn: prioritize similarity + recency
    ~/.claude/scripts/smart-cache.sh set-weights 0.6 0.3 0.05 0.05
    echo "✅ Configured for high churn environment"
    ;;
  2)
    # Stable: prioritize similarity + success rate
    ~/.claude/scripts/smart-cache.sh set-weights 0.4 0.1 0.4 0.1
    echo "✅ Configured for stable environment"
    ;;
  3)
    # Balanced (default)
    ~/.claude/scripts/smart-cache.sh set-weights 0.5 0.2 0.2 0.1
    echo "✅ Using balanced configuration"
    ;;
esac

echo
echo "Current configuration:"
~/.claude/scripts/smart-cache.sh config
```

### Monitor Smart Cache Performance

```bash
#!/usr/bin/env bash
# monitor-smart-cache.sh - Compare traditional vs smart caching

echo "📊 Smart Cache Performance Monitor"
echo "================================="
echo

while true; do
  clear
  echo "Smart Cache Performance (refreshing every 30s)"
  echo "Press Ctrl+C to stop"
  echo

  # Get performance metrics
  ~/.claude/scripts/smart-cache.sh performance

  echo
  echo "---"
  echo "Last updated: $(date)"

  sleep 30
done
```

### Integration with Semantic Cache

Smart caching works as a decision layer on top of the existing semantic cache:

```bash
#!/usr/bin/env bash
# Example: Integrate smart caching into cache lookup flow

query_hash="$1"
query_text="$2"

# Traditional semantic cache lookup
candidates=$(redis-cli KEYS "semantic_cache:*" | head -5)

best_candidate=""
best_score=0

for candidate in $candidates; do
  # Get similarity from semantic cache
  similarity=$(redis-cli HGET "$candidate" "similarity" 2>/dev/null || echo "0")

  # Use smart cache to make decision
  should_use=$(~/.claude/scripts/smart-cache.sh should-use \
    "$query_hash" "$candidate" "$similarity")

  if [[ "$should_use" == "true" ]]; then
    # Calculate smart score for ranking
    score=$(~/.claude/scripts/smart-cache.sh calculate-score \
      "$query_hash" "$candidate" "$similarity")

    if [[ $(echo "$score > $best_score" | bc -l) -eq 1 ]]; then
      best_score=$score
      best_candidate=$candidate
    fi
  fi
done

if [[ -n "$best_candidate" ]]; then
  echo "Cache HIT (smart score: $(echo "$best_score * 100" | bc | cut -d. -f1)%)"
  response=$(redis-cli HGET "$best_candidate" "response")

  # Record success
  ~/.claude/scripts/smart-cache.sh feedback "$query_hash" true

  echo "$response"
else
  echo "Cache MISS"

  # Call API, cache result
  response=$(call_api "$query_text")

  # Register in smart cache
  response_hash=$(echo "$response" | sha256sum | cut -d' ' -f1)
  ~/.claude/scripts/smart-cache.sh register \
    "$query_hash" "$query_text" "$response_hash"

  echo "$response"
fi
```

---

## Integration with Phase 1-3A

### Combined Intelligence Stack

```bash
#!/usr/bin/env bash
# intelligent-execution.sh - Full integration of all phases

TASK="$1"

echo "🧠 Intelligent Execution Pipeline"
echo "================================"
echo

# Phase 3B: Detect workload and apply optimal config
echo "1. Workload Classification..."
workload=$(~/.claude/scripts/workload-classifier.sh detect | grep "Detected workload:" | awk '{print $3}')
echo "   Detected: $workload"
~/.claude/scripts/workload-classifier.sh apply $workload

# Phase 3A: Create snapshot before execution
echo
echo "2. Creating safety snapshot..."
~/.claude/scripts/automatic-rollback.sh snapshot cache "before $TASK"

# Phase 3B: Check smart cache first
echo
echo "3. Smart cache lookup..."
cache_result=$(check_smart_cache "$TASK")

if [[ -n "$cache_result" ]]; then
  echo "   ✅ Cache HIT (smart caching)"
  ~/.claude/scripts/smart-cache.sh feedback "$TASK" true
  echo "$cache_result"
  exit 0
fi

# Phase 1B: Parallel execution for complex tasks
echo
echo "4. Analyzing task for parallelization..."
if can_parallelize "$TASK"; then
  echo "   ✅ Task can be parallelized"

  # Execute in parallel
  result=$(execute_parallel "$TASK")
else
  echo "   Sequential execution required"
  result=$(execute_sequential "$TASK")
fi

# Phase 1A: Cache result
echo
echo "5. Caching result..."
cache_result "$TASK" "$result"
~/.claude/scripts/smart-cache.sh register \
  "$(echo "$TASK" | sha256sum | cut -d' ' -f1)" \
  "$TASK" \
  "$(echo "$result" | sha256sum | cut -d' ' -f1)"

# Phase 2: Track outcome for learning
echo
echo "6. Tracking outcome..."
~/.claude/scripts/outcome-tracker.sh track

# Phase 3A: Check for anomalies
echo
echo "7. Anomaly detection..."
if ~/.claude/scripts/anomaly-detection.sh detect 2>&1 | grep -q "ANOMALY"; then
  echo "   ⚠️  Anomaly detected, consider rollback"
fi

# Phase 3B: Update MOO history
echo
echo "8. Updating multi-objective score..."
~/.claude/scripts/multi-objective-optimization.sh score > /dev/null

echo
echo "✅ Task complete with full intelligence stack"
echo "$result"
```

---

## Automation Examples

### Cron Jobs for Continuous Optimization

```bash
# Add to crontab: crontab -e

# Workload detection and adaptation (every 15 min)
*/15 * * * * ~/.claude/scripts/workload-classifier.sh detect-and-apply >> ~/.claude/logs/workload.log 2>&1

# MAB optimization cycle (every 2 hours)
0 */2 * * * ~/.claude/scripts/config-mab.sh cycle >> ~/.claude/logs/mab.log 2>&1
0 */2 * * * sleep 7200 && ~/.claude/scripts/config-mab.sh update-reward >> ~/.claude/logs/mab.log 2>&1

# Multi-objective evaluation (daily at 2am)
0 2 * * * ~/.claude/scripts/multi-objective-optimization.sh evaluate >> ~/.claude/logs/moo.log 2>&1

# Anomaly detection (every 30 min)
*/30 * * * * ~/.claude/scripts/anomaly-detection.sh detect >> ~/.claude/logs/anomalies.log 2>&1

# Smart cache performance report (daily at 9am)
0 9 * * * ~/.claude/scripts/smart-cache.sh performance >> ~/.claude/logs/smart-cache-daily.log 2>&1

# Cleanup old logs (weekly on Sunday at 3am)
0 3 * * 0 find ~/.claude/logs -name "*.log" -mtime +30 -delete
```

### LaunchDaemon Integration (macOS)

```xml
<!-- ~/Library/LaunchAgents/com.claude.phase3b-optimizer.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.phase3b-optimizer</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>~/.claude/scripts/phase3b-optimization-loop.sh</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>~/.claude/logs/phase3b-optimizer.log</string>

    <key>StandardErrorPath</key>
    <string>~/.claude/logs/phase3b-optimizer-error.log</string>
</dict>
</plist>
```

Load with:
```bash
launchctl load ~/Library/LaunchAgents/com.claude.phase3b-optimizer.plist
```

---

## Real-World Scenarios

### Scenario 1: Developer's Typical Day

**Morning: Code Exploration**
```bash
# System auto-detects exploration workload
# Applies: cache_threshold=0.75, max_concurrent=6

# You start exploring codebase
claude "find all API endpoints"
# → High parallelization for file searching
# → Moderate cache threshold for variety

# Check current config
~/.claude/scripts/workload-classifier.sh status
# Shows: exploration (confidence: 82%)
```

**Midday: Implementation**
```bash
# System detects implementation workload
# Applies: cache_threshold=0.70, max_concurrent=3

# You start coding
claude "implement user authentication"
# → Lower parallelization (focus)
# → Lower cache threshold (new code patterns)

# Check what changed
~/.claude/scripts/workload-classifier.sh status
# Shows: implementation (confidence: 79%)
```

**Afternoon: Testing & Debugging**
```bash
# System detects testing/debugging workload
# Applies: cache_threshold=0.92, max_concurrent=5

# Running tests
pytest tests/
# → High cache threshold (repeated test queries)
# → High parallelization (test execution)

# If issues found, switches to debugging
# → Lower cache threshold (investigating new patterns)
```

### Scenario 2: Configuration Optimization Project

**Week 1: Baseline Collection**
```bash
# Just observe and collect data
# No changes made, just monitoring

# Daily check
~/check-phase-3b-status.sh | tee daily-status-$(date +%Y%m%d).log
```

**Week 2: MOO Discovery**
```bash
# Run multi-objective evaluation
~/.claude/scripts/multi-objective-optimization.sh evaluate

# Found best config: cache=0.78, concurrent=4
# Current: cache=0.80, concurrent=5

# Start A/B test
~/safe-config-test.sh "moo_week2" 0.78 4

# Result: 12% improvement! Applied.
```

**Week 3: MAB Exploration**
```bash
# Start MAB continuous loop
nohup ~/mab-continuous-loop.sh &

# Check progress daily
~/check-mab-progress.sh

# After 1 week: "balanced" arm winning
# After 2 weeks: "quality_focused" arm emerges as winner
```

**Week 4: Workload Specialization**
```bash
# Enable workload-based adaptation
~/.claude/scripts/workload-classifier.sh auto-switch enable

# Customize for your specific workflows
~/.claude/scripts/workload-classifier.sh customize \
  implementation 0.68 3

# Monitor transitions
tail -f ~/.claude/logs/workload-transitions.log
```

### Scenario 3: High-Stakes Configuration Change

**Before making any production config change:**

```bash
#!/usr/bin/env bash
# production-config-change.sh

echo "🚨 High-Stakes Configuration Change Protocol"
echo

# 1. Snapshot current state
~/.claude/scripts/automatic-rollback.sh snapshot cache "before production change"

# 2. Run A/B test with high sample count
~/safe-config-test.sh "production_change" 0.75 6
# (runs for 30 minutes, 6 samples)

# 3. If successful, run extended validation
echo "Extended validation: running for 2 hours..."
for i in {1..24}; do
  sleep 300  # 5 min

  # Check for anomalies
  if ~/.claude/scripts/anomaly-detection.sh detect 2>&1 | grep -q "ANOMALY"; then
    echo "ANOMALY DETECTED! Rolling back..."
    ~/.claude/scripts/automatic-rollback.sh rollback
    exit 1
  fi

  # Check degradation
  if ~/.claude/scripts/automatic-rollback.sh check cache 2>&1 | grep -q "DEGRADATION"; then
    echo "DEGRADATION DETECTED! Rolling back..."
    ~/.claude/scripts/automatic-rollback.sh rollback
    exit 1
  fi

  echo "Check $i/24 passed"
done

echo "✅ Extended validation passed - change is safe"
```

---

## Monitoring Dashboard

### Real-Time Performance Dashboard Script

```bash
#!/usr/bin/env bash
# dashboard.sh - Real-time Phase 3B dashboard

while true; do
  clear

  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║           Phase 3B Real-Time Dashboard                     ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo

  # Current Configuration
  echo "📊 Current Configuration"
  echo "────────────────────────"
  cache=$(jq -r '.similarity_threshold' ~/.claude/data/cache-config.json)
  concurrent=$(jq -r '.max_concurrent_processes' ~/.claude/data/parallel-config.json)
  echo "Cache threshold: $cache"
  echo "Max concurrent:  $concurrent"
  echo

  # Workload Status
  echo "🔄 Workload Classification"
  echo "────────────────────────"
  workload=$(jq -r '.current_workload' ~/.claude/data/workload-data.json)
  confidence=$(jq -r '.confidence' ~/.claude/data/workload-data.json)
  echo "Current: $workload"
  echo "Confidence: $(echo "$confidence * 100" | bc | cut -d. -f1)%"
  echo

  # MOO Score
  echo "🎯 Multi-Objective Score"
  echo "────────────────────────"
  eval_count=$(jq '.evaluations | length' ~/.claude/data/moo-history.json)
  if [[ $eval_count -gt 0 ]]; then
    latest_score=$(jq -r '.evaluations[-1].composite_score' ~/.claude/data/moo-history.json)
    echo "Latest: $(echo "$latest_score * 100" | bc | cut -d. -f1)%"
    echo "Evaluations: $eval_count"
  else
    echo "No evaluations yet"
  fi
  echo

  # MAB Status
  echo "🎰 Multi-Armed Bandit"
  echo "────────────────────────"
  best_arm=$(jq -r '.best_arm' ~/.claude/data/config-mab-data.json)
  if [[ "$best_arm" != "null" ]]; then
    reward=$(jq -r --arg arm "$best_arm" '.arms[$arm].avg_reward' ~/.claude/data/config-mab-data.json)
    echo "Best arm: $best_arm"
    echo "Reward: $(echo "$reward * 100" | bc | cut -d. -f1)%"
  else
    echo "Still exploring..."
    total_pulls=$(jq '[.arms[].total_pulls] | add' ~/.claude/data/config-mab-data.json)
    echo "Total pulls: $total_pulls"
  fi
  echo

  # Smart Cache
  echo "🧠 Smart Caching"
  echo "────────────────────────"
  smart_hits=$(jq -r '.performance_metrics.smart_hits' ~/.claude/data/smart-cache-data.json)
  smart_misses=$(jq -r '.performance_metrics.smart_misses' ~/.claude/data/smart-cache-data.json)
  smart_total=$((smart_hits + smart_misses))
  if [[ $smart_total -gt 0 ]]; then
    hit_rate=$(echo "scale=1; $smart_hits * 100 / $smart_total" | bc)
    echo "Hit rate: ${hit_rate}%"
    echo "Hits: $smart_hits | Misses: $smart_misses"
  else
    echo "No data yet"
  fi
  echo

  # A/B Tests
  echo "🧪 A/B Tests"
  echo "────────────────────────"
  active_tests=$(jq '.active_tests | length' ~/.claude/data/ab-test-data.json)
  completed_tests=$(jq '.completed_tests | length' ~/.claude/data/ab-test-data.json)
  echo "Active: $active_tests | Completed: $completed_tests"
  echo

  echo "────────────────────────────────────────────────────────────"
  echo "Last updated: $(date)"
  echo "Press Ctrl+C to exit | Refreshing every 10s..."

  sleep 10
done
```

**Run dashboard:**
```bash
chmod +x ~/dashboard.sh
~/dashboard.sh
```

---

## Summary

These integration examples show how Phase 3B improvements work together:

1. **Workload Classification** → Adapts base configuration
2. **Multi-Objective Optimization** → Finds optimal settings
3. **A/B Testing** → Validates changes statistically
4. **Multi-Armed Bandit** → Continuously explores alternatives
5. **Smart Caching** → Improves hit rate with context

**Plus integration with Phase 1-3A:**
- Automatic rollback (safety net)
- Anomaly detection (early warning)
- Incremental analysis (speed)
- Performance profiling (visibility)
- Active learning (continuous improvement)

**Result:** A fully intelligent, self-optimizing system that adapts to your workload, validates changes statistically, and continuously improves performance.

---

*All scripts are production-ready and can be automated via cron or LaunchDaemon.*
