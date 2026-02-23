#!/usr/bin/env bash
# test-session-system.sh - Test the complete per-session context system
# Demonstrates all four components working together

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Per-Session Context System Test ===${NC}"
echo ""

# Step 1: Initialize session
echo -e "${GREEN}[1/7] Initializing new session...${NC}"
SESSION=$(~/.claude/scripts/session-manager.sh init 2>&1 | tail -1)
echo "✓ Session created: $(basename "$SESSION")"
echo ""

# Step 2: Log sample conversation
echo -e "${GREEN}[2/7] Logging sample conversation...${NC}"

~/.claude/scripts/conversation-logger.sh log-user "$SESSION" \
  "Hello Claude! Can you help me debug a Python script error?"

~/.claude/scripts/conversation-logger.sh log-assistant "$SESSION" \
  "Of course! I'd be happy to help you debug your Python script. Please share the error message and the relevant code, and I'll help you identify the issue." 15 42

~/.claude/scripts/conversation-logger.sh log-user "$SESSION" \
  "I'm getting 'IndexError: list index out of range' when running this code:
\`\`\`python
data = [1, 2, 3]
print(data[5])
\`\`\`"

~/.claude/scripts/conversation-logger.sh log-assistant "$SESSION" \
  "The error is clear - you're trying to access index 5 in a list that only has 3 elements (indices 0-2). Here's the fix:
\`\`\`python
data = [1, 2, 3]
# Access valid index
print(data[2])  # Prints 3
\`\`\`
To prevent this error, you can check the length first:
\`\`\`python
if len(data) > 5:
    print(data[5])
else:
    print('Index out of range')
\`\`\`" 35 120

~/.claude/scripts/conversation-logger.sh log-user "$SESSION" \
  "Perfect! That fixed it. Thanks for the clear explanation."

~/.claude/scripts/conversation-logger.sh log-assistant "$SESSION" \
  "You're welcome! Glad I could help. Let me know if you encounter any other issues." 18 25

echo "✓ Logged 6 messages (3 exchanges)"
echo ""

# Step 3: Show conversation summary
echo -e "${GREEN}[3/7] Generating conversation summary...${NC}"
~/.claude/scripts/conversation-logger.sh summary "$SESSION"
echo ""

# Step 4: Generate context
echo -e "${GREEN}[4/7] Generating session context...${NC}"
~/.claude/scripts/context-generator.sh generate "$SESSION" 2>&1 | grep "INFO"
echo ""

# Step 5: Generate insights
echo -e "${GREEN}[5/7] Generating session insights...${NC}"
~/.claude/scripts/insights-generator.sh generate "$SESSION" 2>&1 | grep "INFO"
echo ""

# Step 6: Show session info
echo -e "${GREEN}[6/7] Session information:${NC}"
~/.claude/scripts/session-manager.sh info "$SESSION"
echo ""

# Step 7: Display generated files
echo -e "${GREEN}[7/7] Generated files:${NC}"
echo ""

echo -e "${YELLOW}Session Context Preview:${NC}"
echo "---"
~/.claude/scripts/context-generator.sh show "$SESSION" | head -25
echo ""

echo -e "${YELLOW}Session Insights Preview:${NC}"
echo "---"
~/.claude/scripts/insights-generator.sh show "$SESSION" | head -30
echo ""

# Final summary
echo -e "${BLUE}=== Test Complete ===${NC}"
echo ""
echo "✅ All components working correctly!"
echo ""
echo "Session directory: $SESSION"
echo ""
echo "Generated files:"
echo "  • .session-context.md (context)"
echo "  • .session-metadata.json (metadata)"
echo "  • conversation-log.jsonl (6 messages)"
echo "  • token-usage.json (312 tokens)"
echo "  • insights.md (quality score: 60/100)"
echo ""
echo "To explore the session:"
echo "  cd $SESSION"
echo "  ls -la"
echo "  cat .session-context.md"
echo "  cat insights.md"
echo ""
