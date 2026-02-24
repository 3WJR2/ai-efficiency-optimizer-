#!/usr/bin/env bash
# autoload.sh - Ensures Adaptive Intelligence System is loaded
# Add this to your shell profile (.zshrc or .bashrc) for automatic loading

# Initialize Adaptive Intelligence on Claude startup
if [[ -f "$HOME/.claude/hooks/on-session-start.sh" ]]; then
    "$HOME/.claude/hooks/on-session-start.sh"
fi

# Display status if requested
if [[ "${1:-}" == "--status" ]]; then
    if command -v claude &> /dev/null && [[ -f "$HOME/.claude/skills/adaptive-intelligence/skill.sh" ]]; then
        "$HOME/.claude/skills/adaptive-intelligence/skill.sh" status
    fi
fi
