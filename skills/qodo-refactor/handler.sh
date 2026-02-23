#!/bin/bash

set -e

TARGET="${target:-current codebase}"
FOCUS="${focus:-all}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "  🔧 ${CYAN}Qodo Refactoring Analysis${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

PROMPT="Analyze $TARGET and suggest refactoring improvements"

case "$FOCUS" in
    complexity)
        PROMPT="$PROMPT. Focus on reducing cyclomatic complexity, extracting methods, and simplifying logic."
        ;;
    duplication)
        PROMPT="$PROMPT. Focus on identifying and removing duplicate code (DRY principle)."
        ;;
    patterns)
        PROMPT="$PROMPT. Focus on applying appropriate design patterns (Repository, Factory, Strategy, etc.)."
        ;;
    naming)
        PROMPT="$PROMPT. Focus on improving variable, function, and class names for clarity."
        ;;
    all)
        PROMPT="$PROMPT covering complexity, duplication, design patterns, and naming."
        ;;
esac

echo -e "${YELLOW}Focus: $FOCUS${NC}"
echo -e "${CYAN}Analyzing...${NC}"
echo ""

qodo refactor "$PROMPT" --ci --yes

echo ""
echo -e "${GREEN}✅ Refactoring analysis complete${NC}"
