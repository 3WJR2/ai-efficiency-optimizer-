#!/usr/bin/env bash

################################################################################
# demo-integration.sh - Interactive demo of integration layer
# Version: 1.0.0
#
# Demonstrates all features of the orchestrator + indexer integration
################################################################################

set -euo pipefail

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"

# Print header
print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""
}

# Print step
print_step() {
    echo ""
    echo -e "${GREEN}▶${NC} $1"
    echo ""
}

# Print info
print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Print result
print_result() {
    echo -e "${MAGENTA}→${NC} $1"
}

# Pause
pause() {
    echo ""
    read -p "Press Enter to continue..." -r
    echo ""
}

# Main demo
main() {
    clear

    print_header "Orchestrator + Indexer Integration Demo"

    echo "This demo will walk you through all features of the integration layer."
    echo ""
    echo "Features demonstrated:"
    echo "  1. Unified CLI"
    echo "  2. Code indexing and search"
    echo "  3. Context preloading"
    echo "  4. Orchestration enhancement"
    echo "  5. Performance optimization"
    echo "  6. Auto-indexing"
    echo ""

    pause

    # Demo 1: System Status
    print_header "Demo 1: System Status"

    print_step "Checking system status..."
    bash "${SCRIPTS_DIR}/claude-assistant.sh" status

    print_info "This shows the current state of all components"
    pause

    # Demo 2: Indexing
    print_header "Demo 2: Code Indexing"

    print_step "Indexing current directory..."
    print_info "Command: claude-assistant index ."
    bash "${SCRIPTS_DIR}/claude-assistant.sh" index .

    print_step "Checking index status..."
    bash "${SCRIPTS_DIR}/claude-assistant.sh" index-status

    pause

    # Demo 3: Search
    print_header "Demo 3: Code Search"

    print_step "Searching for 'test'..."
    print_info "Command: claude-assistant search 'test'"

    # Try search (may not find anything if no index)
    bash "${SCRIPTS_DIR}/claude-assistant.sh" --dry-run search "test"

    print_result "In real usage, this would search indexed code"
    pause

    # Demo 4: Context Preloading
    print_header "Demo 4: Context Preloading"

    print_step "Preloading context for 'Fix authentication bug'..."
    print_info "Command: context-preloader.sh preload 'Fix authentication bug'"

    bash "${SCRIPTS_DIR}/context-preloader.sh" preload "Fix authentication bug" | head -30
    echo "..."

    print_step "Checking cache statistics..."
    bash "${SCRIPTS_DIR}/context-preloader.sh" stats

    pause

    # Demo 5: Orchestration Enhancement
    print_header "Demo 5: Orchestration Enhancement"

    print_step "Detecting codebase structure..."
    print_info "Command: orchestration-enhancer.sh detect-structure"

    bash "${SCRIPTS_DIR}/orchestration-enhancer.sh" detect-structure

    print_step "Suggesting agents for 'Debug login timeout'..."
    print_info "Command: orchestration-enhancer.sh suggest-agents"

    bash "${SCRIPTS_DIR}/orchestration-enhancer.sh" suggest-agents "Debug login timeout"

    pause

    # Demo 6: Performance Optimization
    print_header "Demo 6: Performance Optimization"

    print_step "Viewing performance statistics..."
    bash "${SCRIPTS_DIR}/performance-optimizer.sh" stats

    print_step "Running quick benchmark (3 iterations)..."
    print_info "This tests search and context loading performance"

    bash "${SCRIPTS_DIR}/performance-optimizer.sh" benchmark 3

    pause

    # Demo 7: Auto-Indexing
    print_header "Demo 7: Auto-Indexing"

    print_step "Checking auto-indexer status..."
    bash "${SCRIPTS_DIR}/auto-index-manager.sh" status

    print_info "Auto-indexer watches directories and updates indexes automatically"
    print_info ""
    print_info "To use auto-indexing:"
    print_info "  1. auto-index-manager.sh add-watch /path/to/project"
    print_info "  2. auto-index-manager.sh start"
    print_info ""
    print_info "Changes are then indexed automatically every 30 seconds"

    pause

    # Demo 8: Complete Workflow
    print_header "Demo 8: Complete Workflow"

    print_step "Running complete assistance workflow..."
    print_info "Command: claude-assistant assist 'Fix authentication issue'"
    print_info ""
    print_info "This combines:"
    print_info "  1. Search codebase"
    print_info "  2. Preload context"
    print_info "  3. Orchestrate agents"
    print_info ""
    print_info "Let's simulate with dry-run..."

    bash "${SCRIPTS_DIR}/claude-assistant.sh" --dry-run assist "Fix authentication issue"

    pause

    # Demo 9: Multi-Terminal Integration
    print_header "Demo 9: Multi-Terminal Integration"

    print_info "The integration includes Python bindings for the multi-terminal app"
    print_info ""
    print_info "Installation:"
    print_info "  multi-terminal-integration.sh install ~/claude-multi-terminal"
    print_info ""
    print_info "Keyboard shortcuts:"
    print_info "  Ctrl+O  - Orchestrate agents"
    print_info "  Ctrl+S  - Show status"
    print_info "  Ctrl+A  - Agent access patterns"
    print_info ""
    print_info "See: KEYBOARD_SHORTCUTS.md for details"

    pause

    # Final Summary
    print_header "Demo Complete!"

    echo "You've seen all major features of the integration layer:"
    echo ""
    echo -e "${GREEN}✓${NC} Unified CLI for all operations"
    echo -e "${GREEN}✓${NC} Fast code search and indexing"
    echo -e "${GREEN}✓${NC} Intelligent context preloading"
    echo -e "${GREEN}✓${NC} Enhanced orchestration with codebase awareness"
    echo -e "${GREEN}✓${NC} Performance optimization and caching"
    echo -e "${GREEN}✓${NC} Automatic index updates"
    echo -e "${GREEN}✓${NC} Multi-terminal app integration"
    echo ""
    echo "Next steps:"
    echo "  1. Index your projects: claude-assistant index /path/to/project"
    echo "  2. Try searching: claude-assistant search 'query'"
    echo "  3. Use complete workflow: claude-assistant assist 'request'"
    echo "  4. Enable auto-indexing: auto-index-manager.sh start"
    echo ""
    echo "Documentation:"
    echo "  - Full guide: ~/.claude/docs/INTEGRATION.md"
    echo "  - Quick ref: ~/.claude/docs/INTEGRATION-QUICKREF.md"
    echo ""
    echo "Get help:"
    echo "  claude-assistant --help"
    echo ""
    echo -e "${CYAN}Happy coding! 🚀${NC}"
    echo ""
}

# Run main
main "$@"
