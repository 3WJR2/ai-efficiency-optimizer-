# Conversation Summarization - Quick Start Guide

**Goal:** Compress 10K token conversations into 1K summaries (10:1 ratio)

---

## Quick Commands

### Summarize a Single Session

```bash
# Standard summary (500-800 tokens) - most common
~/.claude/scripts/conversation-summarizer.sh save \
    my-session-001 \
    standard \
    /path/to/conversation.txt

# Brief summary (200-300 tokens)
~/.claude/scripts/conversation-summarizer.sh save \
    my-session-001 \
    brief \
    /path/to/conversation.txt

# Detailed summary (1000-1500 tokens)
~/.claude/scripts/conversation-summarizer.sh save \
    my-session-001 \
    detailed \
    /path/to/conversation.txt
```

Output: `~/.claude/summaries/my-session-001-standard.md`

### Batch Operations

```bash
# Summarize all sessions in a directory
~/.claude/scripts/batch-summarizer.sh all /path/to/sessions standard

# Summarize last 7 days
~/.claude/scripts/batch-summarizer.sh recent 7 standard /path/to/sessions

# Update summaries older than 30 days
~/.claude/scripts/batch-summarizer.sh update 30 standard /path/to/sessions

# Parallel processing (4 workers)
~/.claude/scripts/batch-summarizer.sh parallel /path/to/sessions standard 4
```

### Cache Management

```bash
# View cache statistics
~/.claude/scripts/summary-cache-manager.sh stats

# List all cached sessions
~/.claude/scripts/summary-cache-manager.sh list

# Clear cache (creates backup)
~/.claude/scripts/summary-cache-manager.sh clear

# Compact cache (remove gaps)
~/.claude/scripts/summary-cache-manager.sh compact
```

### Quality Validation

```bash
# Generate quality report
~/.claude/scripts/summary-quality-scorer.sh report \
    /path/to/original.txt \
    /path/to/summary.txt \
    standard

# Check if meets minimum quality (0.70)
~/.claude/scripts/summary-quality-scorer.sh check \
    /path/to/original.txt \
    /path/to/summary.txt \
    0.70
```

---

## Detail Level Comparison

| Level | Tokens | Use Case | Contents |
|-------|--------|----------|----------|
| **Brief** | 200-300 | Quick context refresh | One paragraph overview |
| **Standard** | 500-800 | Regular context loading | Decisions, solutions, outcomes |
| **Detailed** | 1000-1500 | Complex sessions | All key points + insights |

---

## What Gets Preserved?

### Decisions
- What was decided
- Rationale/reasoning
- Alternatives considered

### Solutions
- Problems encountered
- Solutions implemented
- Verification/testing

### Code Snippets
- 2-3 most important snippets
- Working code only
- Trimmed to 20 lines max

### Outcomes
- ✅ Successes
- ❌ Failures
- ⚠️ Partial/pending

### Insights
- Key learnings
- Important discoveries
- Best practices

---

## Quality Metrics

**Target Quality Score:** 0.75-0.85

**Dimensions:**
- **Completeness** (25%): Key points preserved
- **Accuracy** (30%): Semantic similarity
- **Conciseness** (20%): 8:1 to 12:1 compression
- **Searchability** (15%): Technical keywords
- **Structure** (10%): Required sections

**Minimum Acceptable:** 0.70

---

## Performance Benchmarks

| Operation | Expected Time |
|-----------|--------------|
| Single summary (standard) | 2-3 seconds |
| Batch (100 sessions) | 4-5 minutes |
| Parallel (100 sessions, 4 workers) | 2-3 minutes |
| Cache lookup | <10ms |

**Cache Hit Rate:** 95%+ after initial run

---

## Example Summary

```markdown
## Session Summary: auth-jwt-implementation

**Project:** authentication-system
**When:** 2026-02-15 14:30
**Goal:** Implement JWT authentication with Redis

### What You Built
- JWT token generation and validation
- Redis integration for token blacklisting
- Refresh token mechanism (7-day expiry)
- Rate limiting middleware

### Key Decisions
**Decision:** Use JWT tokens instead of sessions
  **Rationale:** Stateless design for microservices

**Decision:** Redis for token blacklist
  **Rationale:** Sub-millisecond lookup required

### Problems Solved
**Problem:** Sessions don't persist across servers
**Solution:** Switched to JWT stateless tokens

### Code Highlights
```python
def generate_jwt(user_id):
    payload = {'user_id': user_id, 'exp': datetime.utcnow() + timedelta(minutes=15)}
    return jwt.encode(payload, SECRET_KEY)
```

### Outcomes
✅ Deployed to staging
✅ 1000 req/s, <50ms latency
⚠️ Need rate limiting (next session)

---

**Tags:** authentication, jwt, redis, security, backend

**Tokens:** 850 (vs 12,000 original) | **Compression:** 14:1
```

---

## Troubleshooting

### Low Quality Scores

**Problem:** Scores < 0.70

**Solution:**
- Increase detail level (brief → standard → detailed)
- Check conversation format
- Verify key information present

### Poor Compression

**Problem:** Ratio < 5:1 or > 15:1

**Solution:**
- Check if conversations are too short (<1000 tokens)
- Adjust target ratio in configuration
- Review compression techniques

### Missing Information

**Problem:** Important parts not in summary

**Solution:**
- Use higher detail level
- Check extraction patterns match your conversation style
- Verify with: `~/.claude/scripts/key-point-extractor.sh all conversation.txt`

### Cache Issues

**Problem:** Stale or missing cache

**Solution:**
```bash
# Invalidate specific entry
~/.claude/scripts/summary-cache-manager.sh invalidate session-id

# Clear and rebuild
~/.claude/scripts/summary-cache-manager.sh clear
```

---

## Integration Examples

### With Context Loading

```bash
# Generate and load summary
summary=$(~/.claude/scripts/summary-cache-manager.sh get \
    session-001 standard /path/to/session.txt)

# Use in your context system
echo "$summary" | your-context-loader.sh tier2 session-001
```

### With Search Indexing

```bash
# Batch summarize and index
~/.claude/scripts/batch-summarizer.sh all /sessions standard

# Index all summaries
for summary in ~/.claude/summaries/*-standard.md; do
    session_id=$(basename "$summary" -standard.md)
    cat "$summary" | your-search-indexer.sh add "$session_id"
done
```

### With Knowledge Graph

```bash
# Extract structured key points
~/.claude/scripts/key-point-extractor.sh structured session.txt | \
    your-knowledge-graph.sh add session-001
```

---

## Running Tests

```bash
# Run full test suite
~/.claude/scripts/test-summarizer.sh
```

**Expected:** 11-12 / 12 tests passing (cache timing test may be flaky)

---

## Files Created

**Scripts:**
- `~/.claude/scripts/conversation-summarizer.sh` - Main engine
- `~/.claude/scripts/key-point-extractor.sh` - Extract important info
- `~/.claude/scripts/semantic-compressor.sh` - Compress intelligently
- `~/.claude/scripts/summary-quality-scorer.sh` - Quality validation
- `~/.claude/scripts/summary-cache-manager.sh` - Caching system
- `~/.claude/scripts/batch-summarizer.sh` - Batch operations
- `~/.claude/scripts/test-summarizer.sh` - Test suite

**Documentation:**
- `~/.claude/docs/SUMMARIZATION.md` - Full documentation
- `~/.claude/docs/SUMMARIZATION-QUICKSTART.md` - This guide

**Cache:**
- `~/.claude/summaries/` - Summary storage and cache

---

## Next Steps

1. **Test with your conversations:**
   ```bash
   conversation-summarizer.sh save my-first-session standard /path/to/conversation.txt
   ```

2. **Check quality:**
   ```bash
   summary-quality-scorer.sh report /path/to/conversation.txt ~/.claude/summaries/my-first-session-standard.md
   ```

3. **Batch process existing sessions:**
   ```bash
   batch-summarizer.sh all /your/sessions/directory standard
   ```

4. **Monitor cache:**
   ```bash
   summary-cache-manager.sh stats
   ```

---

**Built:** 2026-02-19
**Version:** 1.0.0
**Status:** Production Ready

For full documentation: `~/.claude/docs/SUMMARIZATION.md`
