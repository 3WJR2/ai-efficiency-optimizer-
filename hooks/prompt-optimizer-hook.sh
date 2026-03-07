#!/usr/bin/env bash
# prompt-optimizer-hook.sh - UserPromptSubmit hook
# Automatically generates an optimized prompt and injects it as additionalContext
# so Claude sees it and presents it to the user for review before proceeding.

# Read hook input from stdin
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")

# Bail if we couldn't parse the prompt
if [ -z "$PROMPT" ]; then
    exit 0
fi

# Skip conditions:
# 1. Empty or very short prompts (< 6 words = conversational/quick questions)
WORD_COUNT=$(echo "$PROMPT" | wc -w | tr -d ' ')
if [ "$WORD_COUNT" -lt 6 ]; then
    exit 0
fi

# 2. Skip for slash commands
case "$PROMPT" in
    /*) exit 0 ;;
esac

# 3. Skip if user explicitly opts out
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
case "$PROMPT_LOWER" in
    *"skip prompt"*|*"just do it"*|*"no optimi"*) exit 0 ;;
esac

# 4. Skip for simple yes/no/continue/ok responses
case "$PROMPT_LOWER" in
    yes|no|ok|okay|sure|continue|accept|skip|cancel|thanks|"thank you"|y|n) exit 0 ;;
esac

# 5. Skip for follow-up edits
case "$PROMPT_LOWER" in
    also\ *|and\ *|but\ *|wait\ *|actually\ *|"never mind"*|"nevermind"*|change\ *|"update that"*|instead\ *) exit 0 ;;
esac

# Run the prompt optimizer
OPTIMIZER="$HOME/.claude/scripts/prompt-optimizer.sh"
if [ ! -x "$OPTIMIZER" ]; then
    exit 0
fi

OPTIMIZED=$("$OPTIMIZER" generate "$PROMPT" 2>/dev/null) || exit 0

if [ -z "$OPTIMIZED" ]; then
    exit 0
fi

# Extract metadata lines and prompt body
CATEGORY=$(echo "$OPTIMIZED" | grep '^# Task Category:' | sed 's/# Task Category: //')
TECH=$(echo "$OPTIMIZED" | grep '^# Detected Tech:' | sed 's/# Detected Tech: //')
COMPLEXITY=$(echo "$OPTIMIZED" | grep '^# Complexity:' | sed 's/# Complexity: //')
INTENT=$(echo "$OPTIMIZED" | grep '^# Intent:' | sed 's/# Intent: //')
PROMPT_BODY=$(echo "$OPTIMIZED" | sed '1,/^---$/d')

# Output plain text to stdout - Claude Code injects this as additionalContext
cat <<HOOKEOF
PROMPT OPTIMIZER (Auto-Generated)

The Prompt Optimizer has analyzed the user's request and generated an optimized prompt based on Anthropic's prompting best practices.

Classification: ${CATEGORY} | Tech: ${TECH:-none detected} | Complexity: ${COMPLEXITY} | Intent: ${INTENT}

--- OPTIMIZED PROMPT ---
${PROMPT_BODY}
--- END OPTIMIZED PROMPT ---

IMPORTANT: Present the optimized prompt above to the user BEFORE starting work on their task. Show the classification and the prompt content clearly. Ask the user to:
1. Accept - proceed using the optimized prompt as guidance
2. Edit - tell you what to change in the prompt
3. Skip - ignore the optimization and use their original request as-is

Wait for the user's choice before proceeding.
HOOKEOF

exit 0
