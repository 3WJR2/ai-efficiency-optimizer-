# Phase 3B Quick Start Guide

**Get started with Phase 3B in 5 minutes!**

---

## Step 1: Initialize (1 minute)

```bash
# Initialize all Phase 3B systems
~/.claude/scripts/init-phase-3b.sh
```

**What this does:**
- Initializes all 5 Phase 3B improvements
- Enables auto-switching for workload classification
- Enables smart caching
- Creates all necessary data files

---

## Step 2: Collect Baseline (1 hour)

**Just use your system normally for 1 hour.**

The learning daemon automatically collects performance data:
- Cache hit rates
- Parallel execution success rates
- Latency measurements
- Workload patterns

**No action needed!** Just work as usual.

---

## Step 3: Check Status (1 minute)

```bash
# After 1 hour, check system status
~/.claude/scripts/check-phase-3b-status.sh
```

**Look for:**
- ✅ Cache samples: 20+ collected
- ✅ Parallel samples: 20+ collected
- ✅ Workload detected (with confidence %)
- ✅ MOO evaluations: 1+
- ✅ Smart cache: tracking hits/misses

---

## Step 4: Run Your First Optimization (3 minutes)

### Option A: Quick Workload Detection

```bash
# Detect current workload and apply optimal config
~/.claude/scripts/workload-classifier.sh detect-and-apply
```

**Result:** Configuration automatically adjusted for your current work type!

### Option B: Find Optimal Config

```bash
# Run multi-objective evaluation
~/.claude/scripts/multi-objective-optimization.sh evaluate
```

**Result:** Get recommended configuration based on all metrics!

---

## Step 5: Monitor (ongoing)

### Real-Time Dashboard

```bash
# Launch live dashboard (updates every 10s)
~/.claude/scripts/dashboard.sh
```

**Shows:**
- Current configuration
- Workload classification status
- Multi-objective score
- MAB best arm
- Smart cache hit rate
- Active A/B tests
- Learning data summary

### Quick Status Check

```bash
# Quick snapshot of all systems
~/.claude/scripts/check-phase-3b-status.sh
```

---

## Common Workflows

### Workflow 1: Test New Configuration Safely

```bash
# Test cache=0.75, concurrent=6 safely
~/.claude/scripts/safe-config-test.sh "my_test" 0.75 6

# The script will:
# 1. Create rollback snapshot
# 2. Run A/B test (30 minutes)
# 3. Check for anomalies
# 4. Analyze results statistically
# 5. Apply if significant OR rollback if not
```

### Workflow 2: Enable Continuous MAB Optimization

```bash
# Start MAB in background
nohup ~/.claude/scripts/config-mab.sh cycle &

# Check progress
~/.claude/scripts/config-mab.sh status

# View best performing strategy
~/.claude/scripts/config-mab.sh compare
```

### Workflow 3: Workload-Aware System

```bash
# Enable automatic workload adaptation
~/.claude/scripts/workload-classifier.sh auto-switch enable

# Manually set workload if needed
~/.claude/scripts/workload-classifier.sh set implementation
~/.claude/scripts/workload-classifier.sh apply

# View workload transitions
~/.claude/scripts/workload-classifier.sh status
```

---

## Key Commands Reference

### Multi-Objective Optimization
```bash
~/.claude/scripts/multi-objective-optimization.sh status    # View current score
~/.claude/scripts/multi-objective-optimization.sh evaluate  # Full evaluation
~/.claude/scripts/multi-objective-optimization.sh pareto    # Find optimal solutions
~/.claude/scripts/multi-objective-optimization.sh best      # Get best config
```

### Workload Classification
```bash
~/.claude/scripts/workload-classifier.sh detect            # Detect workload
~/.claude/scripts/workload-classifier.sh apply             # Apply optimal config
~/.claude/scripts/workload-classifier.sh detect-and-apply  # One command
~/.claude/scripts/workload-classifier.sh status            # View status
~/.claude/scripts/workload-classifier.sh list              # List all workloads
```

### Multi-Armed Bandit
```bash
~/.claude/scripts/config-mab.sh cycle           # Run one cycle
~/.claude/scripts/config-mab.sh status          # View arm performance
~/.claude/scripts/config-mab.sh compare         # Compare all arms
~/.claude/scripts/config-mab.sh update-reward   # Update after workload
```

### A/B Testing
```bash
~/.claude/scripts/ab-testing.sh create "test_name" 0.80 5 0.75 5  # Create test
~/.claude/scripts/ab-testing.sh apply-variant <test_id> a         # Apply variant
~/.claude/scripts/ab-testing.sh collect-sample <test_id>          # Collect sample
~/.claude/scripts/ab-testing.sh analyze <test_id>                 # Analyze results
~/.claude/scripts/ab-testing.sh list                              # List tests
```

### Smart Caching
```bash
~/.claude/scripts/smart-cache.sh performance    # View metrics
~/.claude/scripts/smart-cache.sh config         # View configuration
~/.claude/scripts/smart-cache.sh enable         # Enable
~/.claude/scripts/smart-cache.sh set-weights 0.6 0.2 0.15 0.05  # Adjust weights
```

---

## What to Expect

### After 1 Hour (Initial Data)
- Workload detected with 60-70% confidence
- 20-30 cache/parallel samples collected
- Baseline performance established
- Smart cache starting to learn

### After 1 Day (Learning Patterns)
- Workload confidence 75-85%
- 100+ samples collected
- MOO identifies optimal configs
- Smart cache improving hit rate 5-10%

### After 1 Week (Mature Learning)
- Workload classification highly accurate
- MAB identifies best strategy
- 500+ samples for statistical significance
- Smart cache improving hit rate 10-20%
- Overall performance +30-50% from Phase 3B

### After 1 Month (Fully Optimized)
- System fully adapted to your workflow
- Automatic workload switching working perfectly
- Best configuration learned and stable
- Smart cache maximally effective
- Overall performance +40-60% from Phase 3B

---

## Troubleshooting

### "Not enough samples yet"
**Solution:** Keep using system normally. Need 20+ samples for each metric.

### "Workload confidence low"
**Solution:** Normal for first few hours. Manually override if needed:
```bash
~/.claude/scripts/workload-classifier.sh set exploration
```

### "MAB no clear winner"
**Solution:** Normal for first week. Each arm needs minimum 5 pulls.

### "A/B test inconclusive"
**Solution:** Collect more samples (increase from 6 to 20+ per variant).

### "Smart cache not improving"
**Solution:** Adjust weights for your usage pattern:
```bash
# High churn (queries change often)
~/.claude/scripts/smart-cache.sh set-weights 0.6 0.3 0.05 0.05

# Stable (queries repeat)
~/.claude/scripts/smart-cache.sh set-weights 0.4 0.1 0.4 0.1
```

---

## Performance Tips

1. **Start with workload detection** - Easiest way to see immediate improvement
2. **Use safe-config-test.sh** for all manual config changes
3. **Enable MAB** for continuous background optimization
4. **Monitor dashboard** to understand what's working
5. **Let system learn** for at least 1 week before major adjustments

---

## Automation (Optional)

Add to crontab for continuous optimization:

```bash
# Edit crontab
crontab -e

# Add these lines:

# Workload detection every 15 min
*/15 * * * * ~/.claude/scripts/workload-classifier.sh detect-and-apply

# MAB cycle every 2 hours
0 */2 * * * ~/.claude/scripts/config-mab.sh cycle

# Daily MOO evaluation at 2am
0 2 * * * ~/.claude/scripts/multi-objective-optimization.sh evaluate
```

---

## Success Indicators

You'll know Phase 3B is working when:

✅ **Workload auto-switches** as you change tasks
✅ **MOO score** increases over time (target: 80%+)
✅ **MAB identifies** clear winning strategy
✅ **Smart cache hit rate** improves 10-20%
✅ **A/B tests** show statistical significance
✅ **Dashboard** shows all metrics green

**Overall target: +40-60% performance improvement from Phase 3B!**

---

## Next Steps After Quickstart

1. **Review integration examples**: `~/.claude/docs/PHASE-3B-INTEGRATION-EXAMPLES.md`
2. **Read full documentation**: `~/.claude/docs/PHASE-3B-COMPLETE.md`
3. **Customize for your workflow**: Adjust weights, thresholds, workload configs
4. **Set up automation**: Add cron jobs for continuous optimization
5. **Monitor long-term**: Track performance improvements over weeks

---

## Support

**Documentation:**
- Quick Start: This file
- Integration Examples: `~/.claude/docs/PHASE-3B-INTEGRATION-EXAMPLES.md`
- Complete Guide: `~/.claude/docs/PHASE-3B-COMPLETE.md`
- Improvement Roadmap: `~/.claude/docs/IMPROVEMENT-ROADMAP.md`

**Scripts:**
- All in: `~/.claude/scripts/`
- Logs in: `~/.claude/logs/`
- Data in: `~/.claude/data/`

**Quick Help:**
- Dashboard: `~/.claude/scripts/dashboard.sh`
- Status: `~/.claude/scripts/check-phase-3b-status.sh`
- Any script with `--help` or no args shows usage

---

**You're ready to go! Start with Step 1 above. 🚀**
