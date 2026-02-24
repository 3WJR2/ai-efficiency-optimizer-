# Per-Session Context System Documentation

**Version:** 1.0.0
**Phase:** A - Infrastructure Implementation
**Created:** 2026-02-17

## Overview

The Per-Session Context System is a comprehensive solution for managing and learning from Claude conversation sessions. It provides automatic logging, context generation, insights extraction, and session management capabilities.

## Architecture

```
Per-Session Context System
│
├── Session Manager (session-manager.sh)
│   ├── Initialize session directories
│   ├── Manage active sessions
│   ├── Track session lifecycle
│   └── Generate session metadata
│
├── Conversation Logger (conversation-logger.sh)
│   ├── Log user/assistant messages to JSONL
│   ├── Track token usage
│   ├── Export conversations
│   └── Search message history
│
├── Context Generator (context-generator.sh)
│   ├── Extract topics and patterns
│   ├── Identify user preferences
│   ├── Track commands and solutions
│   └── Generate session context files
│
└── Insights Generator (insights-generator.sh)
    ├── Analyze conversation patterns
    ├── Identify successful interactions
    ├── Calculate quality scores
    └── Generate recommendations
```

## Components

### 1. Session Manager

**Location:** `~/.claude/scripts/session-manager.sh`

**Purpose:** Initialize and manage session directories with proper structure.

**Key Features:**
- Auto-generate unique session IDs
- Create directory structure with all required files
- Track session status (active/closed)
- List and filter sessions
- Display session information

**Usage:**

```bash
# Initialize new session
~/.claude/scripts/session-manager.sh init

# Get active session
~/.claude/scripts/session-manager.sh active

# List active sessions
~/.claude/scripts/session-manager.sh list active 10

# Show session info
~/.claude/scripts/session-manager.sh info <session_dir>

# End session
~/.claude/scripts/session-manager.sh end <session_dir>
```

**Directory Structure Created:**

```
2026-02-17-session-1-3d3a/
├── .session-context.md          # Session context (auto-generated)
├── .session-metadata.json        # Session metadata
├── conversation-log.jsonl        # Message history (JSONL format)
├── token-usage.json              # Token tracking
└── insights.md                   # Session insights (auto-generated)
```

### 2. Conversation Logger

**Location:** `~/.claude/scripts/conversation-logger.sh`

**Purpose:** Log conversation messages to JSONL format and track token usage.

**Key Features:**
- Log user and assistant messages
- Track token counts (input/output)
- Generate conversation summaries
- Export to markdown
- Search message history
- Show recent messages

**Usage:**

```bash
# Log user message
~/.claude/scripts/conversation-logger.sh log-user <session_dir> "message content"

# Log assistant message with token counts
~/.claude/scripts/conversation-logger.sh log-assistant <session_dir> "response" 15 42

# Show conversation summary
~/.claude/scripts/conversation-logger.sh summary <session_dir>

# Show recent messages
~/.claude/scripts/conversation-logger.sh recent <session_dir> 10

# Export to markdown
~/.claude/scripts/conversation-logger.sh export <session_dir> [output_file]

# Search for keyword
~/.claude/scripts/conversation-logger.sh search <session_dir> "keyword"
```

**JSONL Format:**

Each message is stored as a single-line JSON object:

```json
{"timestamp":"2026-02-17T20:47:33Z","role":"user","content":"Hello!","content_length":6,"tokens":{"input":2,"output":0,"total":2},"metadata":{"working_directory":"/path","shell":"zsh"}}
```

### 3. Context Generator

**Location:** `~/.claude/scripts/context-generator.sh`

**Purpose:** Generate session context from conversation logs.

**Key Features:**
- Extract active topics from keywords
- Identify commands and code snippets
- Track errors and solutions
- Detect user preferences
- Auto-regenerate after 5+ new messages

**Usage:**

```bash
# Generate context file
~/.claude/scripts/context-generator.sh generate <session_dir>

# Auto-generate (only if needed)
~/.claude/scripts/context-generator.sh auto <session_dir>

# Show current context
~/.claude/scripts/context-generator.sh show <session_dir>
```

**Generated Context Includes:**
- Session statistics (messages, tokens, exchanges)
- Active topics (keyword extraction)
- Recent commands (code snippets)
- Known issues and solutions
- User preferences observed
- Context for next interaction

**Example Output:**

```markdown
# Session Context: 2026-02-17-session-1-3d3a

**Created:** 2026-02-17T20:47:23Z
**Status:** active

## Session Statistics
- **Total Messages:** 6
- **Total Tokens:** 312 (Input: 125, Output: 187)
- **Conversation Depth:** 3.0 exchanges

## Active Topics
- python
- error
- debug

## Recent Commands
- `print(data[2])`

## User Preferences Observed
- Prefers concise communication
- Code-focused interactions
```

### 4. Insights Generator

**Location:** `~/.claude/scripts/insights-generator.sh`

**Purpose:** Generate insights from conversation patterns and interactions.

**Key Features:**
- Analyze conversation patterns
- Identify successful/failed interactions
- Extract learning moments
- Calculate quality scores
- Generate recommendations

**Usage:**

```bash
# Generate insights file
~/.claude/scripts/insights-generator.sh generate <session_dir>

# Show current insights
~/.claude/scripts/insights-generator.sh show <session_dir>
```

**Generated Insights Include:**
- Overview and quality score (0-100)
- Pattern analysis (style, type, engagement)
- Communication characteristics
- Successful interactions
- Failed interactions (for improvement)
- Learning moments (Q&A sequences)
- Recommendations for next session

**Quality Score Calculation:**
- Base score: 50
- +10 for 5+ exchanges
- +10 for 10+ exchanges
- +5 per successful interaction
- -5 per failed interaction
- +10 for high engagement ratio (>0.8)
- Capped at 100

**Example Output:**

```markdown
# Session Insights: 2026-02-17-session-1-3d3a

**Quality Score: 60/100**

Good interaction with room for improvement in some areas.

## Patterns Detected
- **Communication Style:** concise
- **Interaction Type:** troubleshooting
- **Code Blocks:** 2
- **Error Mentions:** 4

## Recommendations
- User prefers brief, to-the-point responses
- Focus on debugging and error resolution
```

## Integration Workflow

### Starting a New Session

```bash
# 1. Initialize session
SESSION_DIR=$(~/.claude/scripts/session-manager.sh init)
echo "Session: $SESSION_DIR"

# 2. Set as active
~/.claude/scripts/session-manager.sh set-active "$SESSION_DIR"

# 3. Session is ready for use
```

### During Conversation

```bash
# Log each message
~/.claude/scripts/conversation-logger.sh log-user "$SESSION_DIR" "user message"
~/.claude/scripts/conversation-logger.sh log-assistant "$SESSION_DIR" "assistant response" 20 80

# Auto-generate context after 5+ messages
~/.claude/scripts/context-generator.sh auto "$SESSION_DIR"
```

### Ending a Session

```bash
# 1. Generate final insights
~/.claude/scripts/insights-generator.sh generate "$SESSION_DIR"

# 2. End session (updates status and clears active)
~/.claude/scripts/session-manager.sh end "$SESSION_DIR"

# 3. Optional: Export conversation
~/.claude/scripts/conversation-logger.sh export "$SESSION_DIR"
```

## Configuration

### Environment Variables

- `SESSIONS_BASE_DIR`: Base directory for sessions (default: `~/Desktop/multi-claude-sessions/sessions`)
- `DEBUG`: Enable debug output (set to `1`)

### Customization

All scripts support the following customization points:

1. **Session ID Format:** Edit `initialize_session()` in session-manager.sh
2. **Keyword List:** Edit `extract_topics()` in context-generator.sh
3. **Quality Scoring:** Edit `calculate_quality_score()` in insights-generator.sh

## File Formats

### .session-metadata.json

```json
{
  "session_id": "2026-02-17-session-1-3d3a",
  "created_at": "2026-02-17T20:47:23Z",
  "last_activity": "2026-02-17T20:47:33Z",
  "status": "active",
  "working_directory": "/Users/user/project",
  "user": "username",
  "hostname": "localhost",
  "claude_version": "unknown",
  "tags": [],
  "notes": ""
}
```

### token-usage.json

```json
{
  "session_id": "2026-02-17-session-1-3d3a",
  "start_time": "2026-02-17T20:47:23Z",
  "last_update": "2026-02-17T20:47:33Z",
  "total_tokens": {
    "input": 125,
    "output": 187,
    "total": 312
  },
  "message_count": 6,
  "interactions": [
    {
      "timestamp": "2026-02-17T20:47:33Z",
      "input_tokens": 14,
      "output_tokens": 0,
      "total_tokens": 14
    }
  ]
}
```

### conversation-log.jsonl

JSONL format (one JSON object per line):

```jsonl
{"timestamp":"2026-02-17T20:47:33Z","role":"user","content":"Hello!","content_length":6,"tokens":{"input":2,"output":0,"total":2},"metadata":{"working_directory":"/path","shell":"zsh"}}
{"timestamp":"2026-02-17T20:47:35Z","role":"assistant","content":"Hi!","content_length":3,"tokens":{"input":0,"output":1,"total":1},"metadata":{"working_directory":"/path","shell":"zsh"}}
```

## Best Practices

### 1. Session Management

- Initialize new session for each distinct conversation topic
- End sessions when switching contexts
- Use descriptive tags in metadata for organization

### 2. Logging

- Log messages immediately after exchange
- Include accurate token counts when available
- Use estimated tokens (1 token ≈ 4 chars) if exact counts unavailable

### 3. Context Generation

- Let auto-generation handle context updates (every 5 messages)
- Manually generate for important milestones
- Review context before long/complex conversations

### 4. Insights

- Generate insights at session end for best quality
- Review failed interactions for improvement opportunities
- Use quality scores to track conversation effectiveness

## Troubleshooting

### Issue: JSONL parsing errors

**Cause:** Multi-line JSON objects
**Solution:** All scripts now use `jq -s '.[]'` for proper JSONL parsing

### Issue: Associative array errors on macOS

**Cause:** Bash 3.x doesn't support `declare -A`
**Solution:** Use alternative data structures (arrays with grep/sort/uniq)

### Issue: Token counts are inaccurate

**Cause:** Estimation based on character count
**Solution:** Pass actual token counts from API when available

### Issue: Context not generating

**Cause:** Insufficient messages (<2) or unreadable JSONL
**Solution:** Ensure valid JSONL format and at least 2 messages logged

## Performance

- **Session initialization:** <100ms
- **Message logging:** <50ms per message
- **Context generation:** 200-500ms (depends on message count)
- **Insights generation:** 300-800ms (depends on message count)
- **JSONL format:** Efficient for append-only operations

## Future Enhancements (Phase B)

1. **Cross-session learning:** Aggregate insights across multiple sessions
2. **Semantic search:** Vector-based conversation search
3. **Auto-tagging:** Automatic topic classification
4. **Performance metrics:** Track response quality over time
5. **Workflow templates:** Pre-configured session templates
6. **CLI integration:** Direct integration with Claude CLI commands

## Examples

### Complete Session Workflow

```bash
#!/bin/bash

# Start session
SESSION=$(~/.claude/scripts/session-manager.sh init)
echo "Started session: $SESSION"

# Simulate conversation
~/.claude/scripts/conversation-logger.sh log-user "$SESSION" \
  "How do I fix this Python error?"

~/.claude/scripts/conversation-logger.sh log-assistant "$SESSION" \
  "Let me help you debug that. Can you share the error message?" 12 15

~/.claude/scripts/conversation-logger.sh log-user "$SESSION" \
  "IndexError: list index out of range"

~/.claude/scripts/conversation-logger.sh log-assistant "$SESSION" \
  "The error occurs when accessing an invalid index. Check your list bounds." 18 25

~/.claude/scripts/conversation-logger.sh log-user "$SESSION" \
  "Thanks! That fixed it."

~/.claude/scripts/conversation-logger.sh log-assistant "$SESSION" \
  "Glad to help!" 5 5

# Generate artifacts
~/.claude/scripts/context-generator.sh generate "$SESSION"
~/.claude/scripts/insights-generator.sh generate "$SESSION"

# Show results
echo ""
echo "=== Summary ==="
~/.claude/scripts/conversation-logger.sh summary "$SESSION"

echo ""
echo "=== Insights ==="
~/.claude/scripts/insights-generator.sh show "$SESSION" | head -30

# End session
~/.claude/scripts/session-manager.sh end "$SESSION"
echo "Session ended"
```

### Search and Export

```bash
#!/bin/bash

# Find all sessions with Python discussions
for session in ~/Desktop/multi-claude-sessions/sessions/2026-02-*; do
  if ~/.claude/scripts/conversation-logger.sh search "$session" "python" | grep -q "Found"; then
    echo "Python discussion in: $(basename "$session")"

    # Export for review
    ~/.claude/scripts/conversation-logger.sh export "$session" \
      "$session/python-discussion.md"
  fi
done
```

## Testing

All scripts have been tested with:
- Session initialization and directory structure creation
- Message logging (user and assistant)
- Context generation with topic extraction
- Insights generation with quality scoring
- Conversation export to markdown
- Session listing and information display

**Test Session:** `2026-02-17-session-1-3d3a`
**Test Results:** All functions working correctly

## Support

For issues or questions:
1. Check script help: `<script-name>.sh help`
2. Enable debug mode: `DEBUG=1 <script-name>.sh ...`
3. Review generated files for errors
4. Check JSONL format with: `jq -s '.' conversation-log.jsonl`

---

**Status:** ✅ **Phase A Complete - Infrastructure Functional**

All four core components are implemented, tested, and working correctly. Session directories are now fully functional with automatic logging, context generation, and insights extraction.
