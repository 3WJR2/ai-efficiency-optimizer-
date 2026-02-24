# Knowledge Graph Quick Start Guide

## 5-Minute Setup

### 1. Create Sample Graph (30 seconds)

```bash
~/.claude/scripts/knowledge-graph-builder.sh sample
```

This creates a sample knowledge graph with 5 nodes and 5 relationships about authentication and APIs.

### 2. Get Your First Recommendations (10 seconds)

```bash
~/.claude/scripts/solution-recommender.sh recommend "implement authentication" 3
```

You'll see 3 relevant solutions ranked by relevance with scores, confidence, and success rates.

### 3. See Your Learning Path (10 seconds)

```bash
~/.claude/scripts/learning-path-tracker.sh visualize "auth"
```

Shows how your authentication knowledge evolved over time.

## Daily Usage

### Starting a New Task

**Interactive mode** (recommended):
```bash
~/.claude/scripts/smart-session-startup.sh interactive
```

Type what you're working on, get instant recommendations.

**Command line**:
```bash
~/.claude/scripts/smart-session-startup.sh quick "build REST API" 5
```

### After Using a Recommendation

**Mark it helpful**:
```bash
~/.claude/scripts/recommendation-feedback.sh track "k_auth_oauth_20260201" success
```

**Mark it not helpful**:
```bash
~/.claude/scripts/recommendation-feedback.sh track "k_auth_oauth_20260201" not_helpful
```

The system learns and improves recommendations over time.

### Check Your Progress

**See expertise levels**:
```bash
~/.claude/scripts/learning-path-tracker.sh expertise "nodejs"
```

**View statistics**:
```bash
~/.claude/scripts/knowledge-graph-builder.sh stats
~/.claude/scripts/recommendation-feedback.sh stats
```

## Common Commands

| What You Want | Command |
|---------------|---------|
| Get recommendations | `solution-recommender.sh recommend "<problem>"` |
| Check current context | `context-ranker.sh summary` |
| See learning path | `learning-path-tracker.sh path "<domain>"` |
| Start smart session | `smart-session-startup.sh interactive` |
| Track feedback | `recommendation-feedback.sh track "<id>" <outcome>` |
| View graph stats | `knowledge-graph-builder.sh stats` |

## Tips

1. **Be specific** in problem descriptions for better recommendations
2. **Provide feedback** on recommendations to improve future results
3. **Check context** before starting - system auto-detects your environment
4. **Visualize paths** to see how your knowledge evolved
5. **Track expertise** to identify areas for growth

## Troubleshooting

**No recommendations?**
```bash
~/.claude/scripts/knowledge-graph-builder.sh sample  # Create test data
```

**Wrong context detected?**
```bash
~/.claude/scripts/context-ranker.sh detect | jq .  # Check detection
```

**Want to reset?**
```bash
rm -rf ~/.claude/knowledge/  # Delete all knowledge data
```

## Next Steps

1. **Build real graph**: Connect to your actual knowledge base
2. **Use daily**: Get recommendations for every new task
3. **Provide feedback**: Mark recommendations helpful/not helpful
4. **Review learning**: Check expertise growth weekly

## Documentation

- **Full Guide**: `~/.claude/docs/KNOWLEDGE-GRAPH.md`
- **Summary**: `~/.claude/docs/KNOWLEDGE-GRAPH-SUMMARY.md`
- **Scripts**: `~/.claude/scripts/knowledge-*.sh`

## Example Session

```bash
# Morning: Start new feature
$ smart-session-startup.sh quick "implement real-time notifications" 3

# You get recommendations:
# 1. WebSocket solution (90% relevant)
# 2. Server-Sent Events (75% relevant)
# 3. Polling approach (60% relevant)

# You use WebSocket solution successfully
$ recommendation-feedback.sh track "k_websocket_20260205" success

# Afternoon: Check your progress
$ learning-path-tracker.sh visualize "realtime"

# See your expertise grew from Novice to Beginner!
```

That's it! Start recommending and learning.

---

**Pro Tip**: Set up aliases in your `.bashrc` or `.zshrc`:

```bash
alias kgrec='~/.claude/scripts/solution-recommender.sh recommend'
alias kgstart='~/.claude/scripts/smart-session-startup.sh interactive'
alias kgfeed='~/.claude/scripts/recommendation-feedback.sh track'
alias kgpath='~/.claude/scripts/learning-path-tracker.sh visualize'
```

Then just use:
```bash
kgrec "implement authentication" 5
kgfeed "k_auth_oauth_20260201" success
kgpath "auth"
```
