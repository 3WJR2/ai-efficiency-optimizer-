#!/usr/bin/env bash
# AI Efficiency Optimizer Skill
# Quick access to integrated optimization system

set -euo pipefail

OPTIMIZER="$HOME/.claude/scripts/ai-efficiency-optimizer.sh"

if [[ -x "$OPTIMIZER" ]]; then
  "$OPTIMIZER" "$@"
else
  echo "AI Efficiency Optimizer not found or not executable"
  exit 1
fi
