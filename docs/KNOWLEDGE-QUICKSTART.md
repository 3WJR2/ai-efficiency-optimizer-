# Knowledge Synthesis System - Quick Start Guide

Get up and running with the Knowledge Synthesis System in 5 minutes.

## 1. Installation (2 minutes)

```bash
# Run automated installer
~/.claude/scripts/integration-installer.sh install
```

This will:
- Install session startup hook
- Configure pipeline daemon
- Configure realtime capture daemon
- Create shell aliases
- Initialize data structures

## 2. Initial Knowledge Extraction (3 minutes)

```bash
# Extract knowledge from all existing sessions
~/.claude/scripts/knowledge-pipeline.sh full
```

This processes all sessions in `~/Desktop/multi-claude-sessions/sessions/` and extracts knowledge into `~/.claude/knowledge/knowledge-base.jsonl`.

## 3. Add Aliases (Optional)

```bash
# Add to your shell
echo 'source ~/.claude/aliases/knowledge-aliases.sh' >> ~/.zshrc
source ~/.zshrc

# Now you can use short commands
knowledge search "your query"
ka stats
kdb  # knowledge dashboard
```

## 4. View Your Knowledge

```bash
# Interactive dashboard
~/.claude/scripts/knowledge-dashboard.sh interactive

# Or simple view
~/.claude/scripts/knowledge-dashboard.sh show

# Or stats
~/.claude/scripts/knowledge-assistant.sh stats
```

## 5. Try It Out

### Search for Knowledge

```bash
knowledge-assistant search "authentication"
knowledge-assistant solve "session timeout"
```

### View Top Knowledge

```bash
knowledge-assistant top-knowledge 10
```

### See Knowledge Growth

```bash
knowledge-assistant growth-chart 7
```

## Usage Examples

### Scenario 1: Find Solution to Problem

```bash
$ knowledge-assistant solve "database connection timeout"

Finding solutions for: "database connection timeout"

1. Solution (Confidence: 0.85, Relevance: 92)
   Problem: Database connections timing out after 30 seconds
   Solution: Increase connection_timeout and pool_recycle settings...

2. Solution (Confidence: 0.78, Relevance: 87)
   Problem: Connection pool exhausted
   Solution: Increase pool_size and max_overflow in SQLAlchemy...
```

### Scenario 2: Search Knowledge Base

```bash
$ knowledge-assistant search "redis" 5

Searching for: "redis"

[solution] k_session3_msg12_20260215
  Problem: Need to implement caching layer with Redis
  Confidence: 0.90 | Tags: redis, cache, api

[pattern] k_session5_msg34_20260217
  Problem: Rate limiting with Redis
  Confidence: 0.85 | Tags: redis, rate-limit, api
```

### Scenario 3: View Dashboard

```bash
$ knowledge-dashboard interactive

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃             CLAUDE KNOWLEDGE SYNTHESIS DASHBOARD              ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ Overview                                 Last Update: 10:30 AM  ┃
┃ ────────────────────────────────────────────────────────────── ┃
┃ Total Knowledge:        247 entries     Pipeline Runs: 5       ┃
┃ Avg Confidence:         0.82            Last Run: 2026-02-18   ┃
┃ ────────────────────────────────────────────────────────────── ┃
┃ Knowledge Growth (Last 7 Days)                                 ┃
┃                                                                 ┃
┃  40│                                                     █      ┃
┃    │                                              █            ┃
┃  30│                                      █                    ┃
...

[R]efresh  [S]earch  [G]raph  [T]op  [E]xport  [Q]uit
```

## Automatic Operation

Once installed, the system works automatically:

1. **Session Start**: Relevant past solutions are injected into `.session-context.md`
2. **During Session**: Knowledge moments are captured in real-time
3. **Session End**: Knowledge is extracted and indexed
4. **Next Session**: New knowledge is available for search and injection

## Common Commands

```bash
# Search
knowledge-assistant search "your query"
ka search "your query"

# Find solutions
knowledge-assistant solve "your problem"

# Run pipeline
knowledge-pipeline incremental
kp-inc

# View dashboard
knowledge-dashboard interactive
kdb

# Show stats
knowledge-assistant stats
kp-status

# Export knowledge
knowledge-assistant export backup.json
```

## Troubleshooting

### No Knowledge Found

```bash
# Check if knowledge base exists
ls -lh ~/.claude/knowledge/knowledge-base.jsonl

# If missing, run extraction
knowledge-pipeline full
```

### Hook Not Working

```bash
# Check installation status
integration-installer status

# If not installed, run
integration-installer install
```

### Need Help

```bash
# Show help for any command
knowledge-assistant help
knowledge-pipeline help
knowledge-dashboard help
integration-installer help

# Run tests
test-knowledge-integration.sh
```

## What's Happening Behind the Scenes

When you start a new session with prompt "implement authentication":

1. **Session Manager** creates session directory
2. **Startup Hook** analyzes prompt:
   - Detects technologies: authentication, security
   - Task type: implementation
   - Key terms: implement, authentication
3. **Knowledge Search** finds relevant entries:
   - Search knowledge base for "authentication"
   - Score by: technology match, key terms, confidence, recency
   - Rank by relevance score
4. **Knowledge Injection** formats top 5 results:
   - Creates markdown with solutions, code, confidence
   - Injects into `.session-context.md`
5. **Claude Reads Context** and knows:
   - "You solved this 2 days ago..."
   - "Here's what worked last time..."
   - Time saved: 15-60 minutes

## Next Steps

1. **Run initial extraction** (if not done):
   ```bash
   knowledge-pipeline full
   ```

2. **View your knowledge**:
   ```bash
   knowledge-dashboard interactive
   ```

3. **Test search**:
   ```bash
   knowledge-assistant search "something you've worked on"
   ```

4. **Start new session** and watch for injected knowledge in context

5. **Optional: Enable daemons** for auto-processing:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.claude.knowledge-pipeline.plist
   launchctl load ~/Library/LaunchAgents/com.claude.realtime-capture.plist
   ```

## Performance Expectations

| Metric | Expected Value |
|--------|---------------|
| Extraction time (100 sessions) | 5-10 minutes |
| Search response time | <1 second |
| Session startup overhead | <1 second |
| Knowledge entries per session | 2-5 average |
| Time saved per session | 15-60 minutes (familiar problems) |

## Full Documentation

For comprehensive documentation, see:
- **Full Guide**: `~/.claude/docs/KNOWLEDGE-SYNTHESIS.md`
- **API Reference**: In full guide
- **Advanced Usage**: In full guide

## Support

- **Test Suite**: `test-knowledge-integration.sh`
- **Status Check**: `integration-installer status`
- **Logs**: `~/.claude/logs/knowledge-*.log`

---

**You now have a perfect memory across all Claude sessions!**

Every solution you find is automatically captured, indexed, and made available for future sessions. The system learns from your past successes and helps you avoid repeating work.
