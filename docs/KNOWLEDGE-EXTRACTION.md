# Knowledge Extraction & Indexing System

## Overview

The Knowledge Extraction system automatically extracts learnings, solutions, patterns, and insights from all conversation logs across sessions, builds a searchable semantic index, and enables knowledge reuse across the multi-session environment.

**Location:** `~/.claude/scripts/knowledge-*.sh`
**Storage:** `~/.claude/knowledge/`

## Architecture

```
┌─────────────────┐
│  Conversation   │
│     Logs        │  (All sessions)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Extractor     │  Parse logs, identify knowledge
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Categorizer    │  Add domains, languages, tags
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Quality Scorer  │  Rate confidence and quality
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Indexer      │  Generate embeddings, build search index
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Knowledge Base  │  Searchable, deduplicated knowledge
└─────────────────┘
```

## Components

### 1. Knowledge Extractor (`knowledge-extractor.sh`)

**Purpose:** Parse conversation logs and extract knowledge entries

**Knowledge Types Detected:**
- **Solution** - Working fixes/implementations with positive feedback
- **Pattern** - Recurring approaches or structures
- **Error** - Error messages with resolutions
- **Decision** - Architectural/design choices with rationale
- **Approach** - Problem-solving methodologies
- **Learning** - Explicit "learned that..." statements
- **Tip** - Best practices or optimizations
- **Caveat** - Warnings or gotchas

**Detection Heuristics:**
```bash
# Solutions
- Keywords: "fixed", "solved", "working", "success"
- User satisfaction: "thanks", "perfect", thumbs up
- Followed by no error messages

# Patterns
- Keywords: "pattern", "approach", "typically", "usually"
- Repeated across multiple sessions

# Errors
- Error messages with subsequent "fixed" or "resolved"
- Stack traces with solutions

# Decisions
- Keywords: "decided to", "chose", "because"
- Followed by rationale
```

**Output Schema:**
```json
{
  "id": "k_session1_msg45_20260218",
  "type": "solution",
  "session_id": "2026-02-17-session-1-df2f",
  "timestamp": "2026-02-17T15:30:00Z",
  "problem": "Focus mode wiping chat history",
  "solution": "Use CSS display property instead of destroying widgets",
  "context": "Textual TUI app with ResizableSessionGrid",
  "code_snippet": "container.display = False",
  "tags": ["textual", "ui", "focus-mode", "widget-state"],
  "confidence": 0.95,
  "success_indicators": ["user_confirmed", "no_errors_after"],
  "related_files": ["resizable_grid.py"],
  "links": []
}
```

**Usage:**
```bash
# Extract from single session
knowledge-extractor.sh extract /path/to/session

# Extract from all sessions
knowledge-extractor.sh extract-all

# Extract since date
knowledge-extractor.sh extract-since 2026-02-01

# Show statistics
knowledge-extractor.sh stats ~/.claude/knowledge/knowledge-base.jsonl
```

### 2. Knowledge Categorizer (`knowledge-categorizer.sh`)

**Purpose:** Enhance knowledge with categories, tags, and metadata

**Categories Added:**

**Domains:**
- frontend, backend, database, devops, security, testing, performance, networking, data-science

**Languages:**
- python, javascript, typescript, shell, go, rust, java, ruby, php, c/c++, sql

**Frameworks:**
- django, flask, fastapi, textual, react, vue, angular, nextjs, express, pytest, jest

**Complexity:**
- simple, moderate, complex

**Reusability:**
- specific, generalizable, pattern

**Usage:**
```bash
# Categorize knowledge file
knowledge-categorizer.sh categorize input.jsonl output.jsonl

# Show statistics
knowledge-categorizer.sh stats categorized.jsonl
```

### 3. Knowledge Indexer (`knowledge-indexer.sh`)

**Purpose:** Build searchable semantic index using TF-IDF embeddings

**Features:**
- TF-IDF embedding generation with caching
- Cosine similarity calculation
- Deduplication (>90% similarity threshold)
- Incremental index updates

**Embedding Strategy:**
- Extract top 50 most frequent terms
- Cache embeddings (MD5 hash key)
- Generate embeddings for problem, solution, and combined context

**Usage:**
```bash
# Index knowledge file
knowledge-indexer.sh index knowledge-base.jsonl

# Update with new entries
knowledge-indexer.sh update new-entries.jsonl

# Deduplicate
knowledge-indexer.sh deduplicate

# Show statistics
knowledge-indexer.sh stats
```

### 4. Knowledge Search (`knowledge-search.sh`)

**Purpose:** Search knowledge base with semantic similarity

**Search Modes:**

1. **Semantic Search** - Find by meaning
```bash
knowledge-search.sh search "authentication timeout bug" 10
```

2. **Problem Search** - Find similar problems solved
```bash
knowledge-search.sh problem "session expires too quickly"
```

3. **Tag Search** - Filter by tags
```bash
knowledge-search.sh tags "python,error,index"
```

4. **Domain Search** - Filter by domain/language
```bash
knowledge-search.sh domain "backend" "python" 10
```

5. **Type Search** - Filter by knowledge type
```bash
knowledge-search.sh type "solution" 10
```

6. **Recent Search** - Find recent knowledge
```bash
knowledge-search.sh recent 7 10  # Last 7 days
```

7. **High-Confidence Search** - Filter by confidence
```bash
knowledge-search.sh confidence 0.8 10
```

8. **Related Knowledge** - Find related entries
```bash
knowledge-search.sh related "k_session1_msg45_20260218"
```

9. **Advanced Search** - Multi-filter search
```bash
knowledge-search.sh advanced "api error" '{"type":"solution","domain":"backend"}'
```

**Output Formats:**
```bash
# Summary (default)
knowledge-search.sh search "query" --format=summary

# Detailed
knowledge-search.sh search "query" --format=detailed

# JSON
knowledge-search.sh search "query" --format=json
```

### 5. Quality Scorer (`knowledge-quality-scorer.sh`)

**Purpose:** Rate knowledge quality and update confidence scores

**Scoring Components:**

1. **Success Indicators (40%)**
   - User confirmed success: +30%
   - No errors after: +25%
   - Tests passed: +25%
   - Positive feedback: +20%

2. **Completeness (20%)**
   - Has problem: +25%
   - Has solution: +30%
   - Has code: +25%
   - Has context: +20%

3. **Reusability (20%)**
   - Generalizable: 1.0
   - Pattern: 0.9
   - Specific solution: 0.6

4. **Recency (10%)**
   - 0-7 days: 1.0
   - 8-30 days: 0.8
   - 31-90 days: 0.6
   - 91+ days: 0.4

5. **Validation (10%)**
   - Applied successfully multiple times: 1.0
   - Applied once: 0.6
   - Unvalidated: 0.3

**Confidence Levels:**
- 0.9-1.0: Very high confidence (proven multiple times)
- 0.7-0.9: High confidence (worked once, good context)
- 0.5-0.7: Medium confidence (partial success or limited context)
- 0.3-0.5: Low confidence (untested or ambiguous)
- 0.0-0.3: Very low confidence (speculative)

**Usage:**
```bash
# Score knowledge file
knowledge-quality-scorer.sh score input.jsonl output.jsonl

# Rescore all entries
knowledge-quality-scorer.sh rescore

# Update with feedback
knowledge-quality-scorer.sh feedback "k_session1_msg45_20260218" success

# Show quality distribution
knowledge-quality-scorer.sh distribution

# Identify entries needing validation
knowledge-quality-scorer.sh needs-validation
```

### 6. Batch Processor (`batch-extract-knowledge.sh`)

**Purpose:** Orchestrate full extraction pipeline and maintenance

**Pipeline Steps:**
1. Extract knowledge from sessions
2. Categorize entries
3. Score quality
4. Build search index
5. Deduplicate

**Commands:**

```bash
# Full extraction pipeline
batch-extract-knowledge.sh extract-all

# Incremental update
batch-extract-knowledge.sh extract-since 2026-02-01

# Rebuild entire index
batch-extract-knowledge.sh rebuild

# Maintenance tasks
batch-extract-knowledge.sh daily    # Extract yesterday
batch-extract-knowledge.sh weekly   # Deduplicate, rescore
batch-extract-knowledge.sh monthly  # Archive low-quality

# Progress and statistics
batch-extract-knowledge.sh progress
batch-extract-knowledge.sh summary

# Test extraction
batch-extract-knowledge.sh test
```

**Recommended Cron Schedule:**
```cron
# Daily extraction at 2 AM
0 2 * * * ~/.claude/scripts/batch-extract-knowledge.sh daily

# Weekly maintenance on Sunday at 3 AM
0 3 * * 0 ~/.claude/scripts/batch-extract-knowledge.sh weekly

# Monthly cleanup on 1st at 4 AM
0 4 1 * * ~/.claude/scripts/batch-extract-knowledge.sh monthly
```

## File Structure

```
~/.claude/knowledge/
├── knowledge-base.jsonl              # Raw extracted knowledge
├── knowledge-base-categorized.jsonl  # With categories/tags
├── knowledge-base-scored.jsonl       # With quality scores
├── knowledge-embeddings.jsonl        # With search embeddings
├── knowledge-deduplicated.jsonl      # After deduplication
├── knowledge-metadata.json           # Index metadata
├── duplicates.csv                    # Duplicate pairs found
└── archive/                          # Low-quality entries
    └── low-quality-202602.jsonl
```

## Usage Examples

### Quick Start

```bash
# 1. Extract knowledge from all sessions
batch-extract-knowledge.sh extract-all

# 2. Search for solutions
knowledge-search.sh search "authentication bug" 10

# 3. Filter by domain
knowledge-search.sh domain "backend" "python"

# 4. Find high-quality solutions
knowledge-search.sh confidence 0.8 10 | jq '.[] | {id, problem, confidence}'
```

### Finding Similar Problems

```bash
# Find solutions to similar problems
knowledge-search.sh problem "session timeout issue"

# Find related knowledge
knowledge-search.sh related "k_session1_msg45_20260218"
```

### Updating with Feedback

```bash
# Mark knowledge as successfully applied
knowledge-quality-scorer.sh feedback "k_session1_msg45_20260218" success

# Rescore after feedback
knowledge-quality-scorer.sh rescore
```

### Maintenance

```bash
# Daily: Extract new sessions
batch-extract-knowledge.sh daily

# Weekly: Clean up duplicates
batch-extract-knowledge.sh weekly

# Monthly: Archive low-quality
batch-extract-knowledge.sh monthly
```

## Expected Performance

| Metric | Target | Notes |
|--------|--------|-------|
| Extraction Speed | ~1000 msg/s | Depends on log size |
| Indexing Speed | ~500 entries/s | With embedding caching |
| Search Speed | <500ms | For 10K entries |
| Deduplication | ~90% reduction | In duplicates |
| Quality Accuracy | 85%+ | For confidence scores |

## Integration

### With Session Manager

The knowledge base can be queried at session startup to provide relevant context:

```bash
# In session startup script
relevant_knowledge=$(knowledge-search.sh search "$user_query" 5 --format=json)

# Include in system prompt
echo "Relevant knowledge from previous sessions:"
echo "$relevant_knowledge" | jq -r '.[] | "- \(.problem): \(.solution)"'
```

### With Adaptive Intelligence

Knowledge extraction feeds into the adaptive intelligence system:

```bash
# Update interaction patterns with extracted knowledge
jq '.knowledge_references += ["'$knowledge_id'"]' \
  ~/.claude/data/interaction-learning.json
```

## Troubleshooting

### Low Extraction Rate

```bash
# Check conversation logs
ls ~/Desktop/multi-claude-sessions/sessions/*/conversation-log.jsonl

# Test extraction on sample
batch-extract-knowledge.sh test

# Verify detection heuristics
grep -A 5 "detect_solution" ~/.claude/scripts/knowledge-extractor.sh
```

### Search Not Finding Results

```bash
# Rebuild index
batch-extract-knowledge.sh rebuild

# Check embeddings
knowledge-indexer.sh stats

# Verify similarity threshold
grep "SIMILARITY_THRESHOLD" ~/.claude/scripts/knowledge-indexer.sh
```

### Low Quality Scores

```bash
# Show quality distribution
knowledge-quality-scorer.sh distribution

# Identify needs validation
knowledge-quality-scorer.sh needs-validation

# Update with success feedback
knowledge-quality-scorer.sh feedback "entry_id" success
```

## Advanced Configuration

### Adjust Similarity Threshold

Edit `knowledge-indexer.sh`:
```bash
SIMILARITY_THRESHOLD=0.85  # Lower = more duplicates merged
```

### Customize Scoring Weights

Edit `knowledge-quality-scorer.sh`:
```bash
WEIGHT_SUCCESS=0.40
WEIGHT_COMPLETENESS=0.20
WEIGHT_REUSABILITY=0.20
WEIGHT_RECENCY=0.10
WEIGHT_VALIDATION=0.10
```

### Add Custom Knowledge Types

Edit `knowledge-extractor.sh`:
```bash
# Add to KNOWLEDGE_TYPES array
KNOWLEDGE_TYPES+=("custom_type")

# Add detection function
detect_custom_type() {
    local content="$1"
    # Your detection logic here
}
```

## Future Enhancements

### Phase 2 (Planned)

1. **Knowledge Graph** - Relationships between entries
2. **Auto-Tagging** - ML-based tag extraction
3. **Session Integration** - Auto-load relevant knowledge at startup
4. **Knowledge Verification** - Automated testing of solutions
5. **Collaborative Knowledge** - Share across team/organization

### Phase 3 (Planned)

1. **LLM-based Embeddings** - Use OpenAI/Claude for better semantic search
2. **Knowledge Recommendations** - Proactive suggestions based on context
3. **Knowledge Evolution** - Track how solutions improve over time
4. **Export/Import** - Share knowledge bases
5. **Web Interface** - Browse and search via web UI

## API Reference

### Extractor API

```bash
knowledge-extractor.sh extract <session_dir>
knowledge-extractor.sh extract-all
knowledge-extractor.sh extract-since <date>
knowledge-extractor.sh stats <file>
```

### Categorizer API

```bash
knowledge-categorizer.sh categorize <input> [output]
knowledge-categorizer.sh stats <file>
```

### Indexer API

```bash
knowledge-indexer.sh index <file>
knowledge-indexer.sh update <new_entries>
knowledge-indexer.sh deduplicate [file] [threshold]
knowledge-indexer.sh stats [file]
```

### Search API

```bash
knowledge-search.sh search <query> [top_k]
knowledge-search.sh problem <description> [top_k]
knowledge-search.sh tags <tag1,tag2> [top_k]
knowledge-search.sh domain <domain> [language] [top_k]
knowledge-search.sh type <type> [top_k]
knowledge-search.sh recent [days] [top_k]
knowledge-search.sh confidence [min] [top_k]
knowledge-search.sh related <id> [top_k]
knowledge-search.sh advanced <query> <filters_json> [top_k]
```

### Scorer API

```bash
knowledge-quality-scorer.sh score <file> [output]
knowledge-quality-scorer.sh rescore [file]
knowledge-quality-scorer.sh feedback <id> <outcome> [file]
knowledge-quality-scorer.sh distribution [file]
knowledge-quality-scorer.sh needs-validation [file]
```

### Batch API

```bash
batch-extract-knowledge.sh extract-all
batch-extract-knowledge.sh extract-since <date>
batch-extract-knowledge.sh rebuild
batch-extract-knowledge.sh daily|weekly|monthly
batch-extract-knowledge.sh progress|summary|test
```

## Best Practices

1. **Run extraction regularly** - Daily cron job for continuous learning
2. **Validate high-confidence entries** - Apply and provide feedback
3. **Review low-quality entries** - Archive or improve metadata
4. **Monitor quality distribution** - Aim for 60%+ high-confidence
5. **Use specific searches** - Combine filters for better results
6. **Update with feedback** - Improve scores over time
7. **Backup knowledge base** - Before rebuild operations
8. **Clean up archives** - Quarterly review of archived entries

## Support

For issues or questions:
- Check logs in `~/.claude/logs/knowledge-extraction.log`
- Run test suite: `test-knowledge-extraction.sh all`
- Review extraction statistics: `batch-extract-knowledge.sh summary`

---

**Version:** 1.0.0
**Last Updated:** 2026-02-18
**Maintained by:** Claude Multi-Session System
