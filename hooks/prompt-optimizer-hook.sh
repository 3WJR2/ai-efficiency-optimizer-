#!/usr/bin/env bash
# prompt-optimizer-hook.sh v3.1 - UserPromptSubmit hook
# Automatically generates an optimized prompt with project-aware context,
# codebase pattern sniffing, git-aware context, semantic classification,
# few-shot examples, edit learning, task decomposition, ambiguity detection,
# tailored output formats, and iterative refinement. Injects result as additionalContext.

# Error logging
LOG_FILE="$HOME/.claude/logs/prompt-optimizer.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

hook_log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] HOOK: $1" >> "$LOG_FILE" 2>/dev/null
}

# Read hook input from stdin
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$PROMPT" ]; then
    hook_log "SKIP: Failed to parse prompt from hook input (jq missing or invalid JSON)"
    exit 0
fi
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

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

# 6. Skip for git/commit/PR operations
case "$PROMPT_LOWER" in
    *commit*|*push*|*"pull request"*|*"create pr"*|*"merge"*|*"git "*) exit 0 ;;
esac

# 7. Skip for prompt refinement requests (these are handled in-conversation)
case "$PROMPT_LOWER" in
    *"make it simpler"*|*"more detail"*|*"focus on"*|*"add test"*|*"too verbose"*|*"refine"*) exit 0 ;;
esac

# Run the prompt optimizer with CWD for project-aware context
OPTIMIZER="$HOME/.claude/scripts/prompt-optimizer.sh"
if [ ! -x "$OPTIMIZER" ]; then
    hook_log "ERROR: Optimizer not found or not executable at $OPTIMIZER"
    hook_log "FALLBACK: Proceeding without prompt optimization"
    exit 0
fi

OPTIMIZED=$("$OPTIMIZER" generate "$PROMPT" "$CWD" 2>"$LOG_FILE.stderr")
OPT_EXIT=$?
if [ $OPT_EXIT -ne 0 ]; then
    hook_log "ERROR: Optimizer exited with code $OPT_EXIT"
    if [ -s "$LOG_FILE.stderr" ]; then
        hook_log "STDERR: $(cat "$LOG_FILE.stderr")"
    fi
    hook_log "FALLBACK: Proceeding without prompt optimization"
    rm -f "$LOG_FILE.stderr" 2>/dev/null
    exit 0
fi
rm -f "$LOG_FILE.stderr" 2>/dev/null

if [ -z "$OPTIMIZED" ]; then
    hook_log "WARN: Optimizer returned empty output for prompt: ${PROMPT:0:80}..."
    exit 0
fi

# Extract metadata lines and prompt body
CATEGORY=$(echo "$OPTIMIZED" | grep '^# Task Category:' | sed 's/# Task Category: //')
TECH=$(echo "$OPTIMIZED" | grep '^# Detected Tech:' | sed 's/# Detected Tech: //')
PROJECT_CTX=$(echo "$OPTIMIZED" | grep '^# Project Context:' | sed 's/# Project Context: //')
COMPLEXITY=$(echo "$OPTIMIZED" | grep '^# Complexity:' | sed 's/# Complexity: //')
INTENT=$(echo "$OPTIMIZED" | grep '^# Intent:' | sed 's/# Intent: //')
PROMPT_BODY=$(echo "$OPTIMIZED" | sed '1,/^---$/d')

hook_log "OK: Generated prompt for category=$CATEGORY complexity=$COMPLEXITY"

# Build output
cat <<HOOKEOF
PROMPT OPTIMIZER v3.0 (Auto-Generated)

The Prompt Optimizer has analyzed the user's request and generated an optimized prompt based on Anthropic's prompting best practices.

Classification: ${CATEGORY} | Tech: ${TECH:-none detected} | Complexity: ${COMPLEXITY} | Intent: ${INTENT}
Project: ${PROJECT_CTX:-none detected}

--- OPTIMIZED PROMPT ---
${PROMPT_BODY}
--- END OPTIMIZED PROMPT ---

IMPORTANT: Present the optimized prompt above to the user BEFORE starting work on their task. Show the classification metadata and the prompt content clearly. Ask the user to:
1. Accept - proceed using the optimized prompt as guidance
2. Edit - tell you what to change in the prompt (the optimizer supports iterative refinement)
3. Skip - ignore the optimization and use their original request as-is

If the user requests edits, you can refine the prompt iteratively. Common refinements:
- "make it simpler" / "shorter" - removes verbose sections
- "more detail" / "be thorough" - adds extra validation guidance
- "focus on X" / "prioritize X" - adds priority emphasis
- "add tests" - adds testing requirements
- "security focus" - adds security review requirements

Wait for the user's choice before proceeding.
HOOKEOF

exit 0
