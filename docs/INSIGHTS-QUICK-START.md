# Unified Insights - Quick Start Guide

## 🚀 Getting Started (30 seconds)

### View Insights
```bash
/adaptive-intelligence insights
```

### Export Reports
```bash
/adaptive-intelligence export-insights markdown  # For documentation
/adaptive-intelligence export-insights json      # For automation
```

## 📊 What You'll See

### 1. User Behavior Insights
```
┌─ USER BEHAVIOR INSIGHTS ─────────────────────┐
│ Learning Stage: Pattern Recognition (47 interactions)
│ Technologies: Python (97), Shell (95), JS (8)
│ Communication: High detail, High technical depth
│ Total Requests: 23 categorized
└───────────────────────────────────────────────┘
```
**Tells you**: How you're using Claude, your tech stack, communication preferences

### 2. System Performance Insights
```
┌─ SYSTEM PERFORMANCE INSIGHTS ────────────────┐
│ Cache Hit Rate:  [████████████|████] 65.2% ↑
│ Target: 65.0% | Samples: 47
│ Latency: 45.3ms avg (98.2% reduction)
│ Parallel Executions: 12 runs, 38 tasks
│ Success Rate: 95.0%
│ Learning Cycles: 5 completed
└───────────────────────────────────────────────┘
```
**Tells you**: How efficiently your system is running, performance metrics

### 3. Cross-Domain Insights
```
┌─ CROSS-DOMAIN INSIGHTS ──────────────────────┐
│ • Cache performing well (65.2%) - queries show patterns
│ • Heavy Python focus (97 uses) - optimize for this stack
│ • Parallel usage growing (12 execs) - good adoption
│ • System adapting: 3 recent optimizations applied
└───────────────────────────────────────────────┘
```
**Tells you**: How your usage correlates with performance, opportunities

### 4. Top Recommendations
```
🎯 TOP RECOMMENDATIONS

1. [HIGH] [PERFORMANCE] Raise cache threshold 0.86→0.88 (more selective)
2. [MEDIUM] [OPTIMIZATION] Optimize workflows for Python (75% of activity)
3. [LOW] [LEARNING] Continue diverse interactions (47/100 for optimal)
```
**Tells you**: Concrete actions to improve performance/experience

### 5. Summary Statistics
```
📊 SUMMARY STATISTICS

Trend: IMPROVING | Confidence: HIGH (85%) | Next: 47/100 samples to Optimal
```
**Tells you**: Overall trajectory, confidence level, next milestone

## 🎯 How to Use Recommendations

### HIGH Priority (Do Now)
```bash
# Example: Lower cache threshold
jq '.similarity_threshold = 0.86' ~/.claude/data/cache-config.json \
  > /tmp/cache-config.json && \
  mv /tmp/cache-config.json ~/.claude/data/cache-config.json

# Verify
jq '.similarity_threshold' ~/.claude/data/cache-config.json
```

### MEDIUM Priority (Do This Week)
- Review and optimize workflows
- Enable suggested features
- Adjust configurations

### LOW Priority (Monitor)
- Continue normal usage
- Track progress to milestones
- Review periodically

## 📁 Exported Files

### Location
```bash
ls -lh ~/.claude/data/insights/
```

### Markdown Reports
```bash
# View latest
cat ~/.claude/data/insights/insights_*.md | less

# Copy to project docs
cp ~/.claude/data/insights/insights_20260205_*.md ~/project/docs/
```

### JSON Reports
```bash
# View latest
jq . ~/.claude/data/insights/insights_*.json | less

# Extract specific metrics
jq '.system_performance.cache.recent_hit_rate' \
  ~/.claude/data/insights/insights_*.json

# Get HIGH priority recommendations
jq '.recommendations[] | select(.priority == "HIGH")' \
  ~/.claude/data/insights/insights_*.json
```

## 🔄 Update Frequency

### Daily
- Quick insights check (5 seconds)
- Act on HIGH priority recommendations

### Weekly
- Export markdown report
- Review trend changes
- Apply MEDIUM priority recommendations

### Monthly
- Compare historical reports
- Assess learning stage progression
- Evaluate overall improvements

## 💡 Pro Tips

### 1. Automate Daily Checks
```bash
# Add to ~/.zshrc or ~/.bashrc
alias insights="~/.claude/skills/adaptive-intelligence/skill.sh insights"

# Now just run
insights
```

### 2. Track Improvements
```bash
# Create baseline
/adaptive-intelligence export-insights json
mv ~/.claude/data/insights/insights_*.json \
  ~/.claude/data/insights/baseline.json

# Later, compare
diff \
  ~/.claude/data/insights/baseline.json \
  ~/.claude/data/insights/insights_*.json
```

### 3. Monitor Specific Metrics
```bash
# Watch cache hit rate
watch -n 300 "jq '.cache_outcomes.hit_rate_history[-1]' \
  ~/.claude/data/learning-data.json"
```

### 4. Integration with Scripts
```python
import json

# Load insights
with open(f"{os.environ['HOME']}/.claude/data/insights/insights_latest.json") as f:
    insights = json.load(f)

# Get recommendations
high_priority = [
    r for r in insights.get('recommendations', [])
    if r['priority'] == 'HIGH'
]

# Apply automatically or alert
for rec in high_priority:
    print(f"⚠️  {rec['text']}")
```

## 🐛 Troubleshooting

### "Script not found"
```bash
chmod +x ~/.claude/scripts/unified-insights.sh
```

### "Insufficient data"
```bash
# Check sample count
jq '.cache_outcomes.hit_rate_history | length' \
  ~/.claude/data/learning-data.json

# Need 10+ samples for meaningful insights
```

### "Python not found"
```bash
which python3  # Should show path
brew install python3  # If missing (macOS)
```

### "Permission denied"
```bash
chmod 644 ~/.claude/data/*.json
chmod 755 ~/.claude/scripts/*.sh
```

## 📚 Learn More

- Full documentation: `~/.claude/docs/UNIFIED-INSIGHTS-ENHANCEMENT.md`
- Skill reference: `~/.claude/skills/adaptive-intelligence/skill.md`
- Configuration: `~/.claude/CLAUDE.md`
- Help: `/adaptive-intelligence help`

## 🎉 Quick Wins

After implementing recommendations, you should see:
- ✅ 10-20% improvement in cache hit rate
- ✅ 4x speedup with parallel execution
- ✅ More relevant responses
- ✅ Fewer clarification requests
- ✅ Better alignment with your work style

---

**Remember**: The system learns continuously. The more you use it, the better insights you'll get!

*Last updated: 2026-02-05 | Version: 1.3.0*
