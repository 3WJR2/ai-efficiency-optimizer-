#!/usr/bin/env bash

# integration-installer.sh
# Install knowledge synthesis integration hooks
# Part of Cross-Session Knowledge Synthesis Integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Installation Functions
# ============================================================================

# Install session startup hook
install_session_hook() {
    echo -e "${BLUE}Installing session startup hook...${NC}"

    local session_manager="${SCRIPT_DIR}/session-manager.sh"

    if [[ ! -f "$session_manager" ]]; then
        echo -e "${RED}✗${NC} Session manager not found: $session_manager"
        return 1
    fi

    # Check if already installed
    if grep -q "session-startup-hook.sh" "$session_manager"; then
        echo -e "${YELLOW}!${NC} Hook already installed"
        return 0
    fi

    # Backup original
    cp "$session_manager" "${session_manager}.backup-$(date +%Y%m%d-%H%M%S)"

    # Add hook to initialize_session function
    local hook_code='
    # Knowledge synthesis hook
    if [[ -f "${SCRIPT_DIR}/session-startup-hook.sh" ]]; then
        source "${SCRIPT_DIR}/session-startup-hook.sh"
        local initial_prompt="${1:-}"
        if [[ -n "$initial_prompt" ]]; then
            on_session_start "$session_dir" "$initial_prompt" || true
        fi
    fi
'

    # Find the end of initialize_session function
    local line_num=$(grep -n "log_info \"Session initialized successfully" "$session_manager" | cut -d: -f1)

    if [[ -n "$line_num" ]]; then
        # Insert hook before the success message
        sed -i.tmp "${line_num}i\\
${hook_code}" "$session_manager" && rm "${session_manager}.tmp"

        echo -e "${GREEN}✓${NC} Session startup hook installed"
    else
        echo -e "${RED}✗${NC} Could not find insertion point"
        return 1
    fi
}

# Set up pipeline daemon
setup_pipeline_daemon() {
    echo -e "${BLUE}Setting up pipeline daemon...${NC}"

    local plist_file="${HOME}/Library/LaunchAgents/com.claude.knowledge-pipeline.plist"
    local pipeline_script="${SCRIPT_DIR}/knowledge-pipeline.sh"

    # Create LaunchAgent plist
    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.knowledge-pipeline</string>
    <key>ProgramArguments</key>
    <array>
        <string>$pipeline_script</string>
        <string>watch</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/.claude/logs/pipeline-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.claude/logs/pipeline-daemon-error.log</string>
</dict>
</plist>
EOF

    echo -e "${GREEN}✓${NC} Pipeline daemon configured"
    echo -e "  To start: launchctl load $plist_file"
    echo -e "  To stop:  launchctl unload $plist_file"
}

# Set up realtime capture daemon
setup_realtime_daemon() {
    echo -e "${BLUE}Setting up realtime capture daemon...${NC}"

    local plist_file="${HOME}/Library/LaunchAgents/com.claude.realtime-capture.plist"
    local capture_script="${SCRIPT_DIR}/realtime-knowledge-capture.sh"

    # Create LaunchAgent plist
    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.realtime-capture</string>
    <key>ProgramArguments</key>
    <array>
        <string>$capture_script</string>
        <string>watch-all</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/.claude/logs/realtime-capture.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.claude/logs/realtime-capture-error.log</string>
</dict>
</plist>
EOF

    echo -e "${GREEN}✓${NC} Realtime capture daemon configured"
    echo -e "  To start: launchctl load $plist_file"
    echo -e "  To stop:  launchctl unload $plist_file"
}

# Create shell aliases
create_aliases() {
    echo -e "${BLUE}Creating shell aliases...${NC}"

    local alias_file="${HOME}/.claude/aliases/knowledge-aliases.sh"
    mkdir -p "$(dirname "$alias_file")"

    cat > "$alias_file" <<'EOF'
# Knowledge Synthesis System Aliases

# Main assistant
alias knowledge='~/.claude/scripts/knowledge-assistant.sh'
alias ka='~/.claude/scripts/knowledge-assistant.sh'

# Quick commands
alias knowledge-search='~/.claude/scripts/knowledge-assistant.sh search'
alias knowledge-solve='~/.claude/scripts/knowledge-assistant.sh solve'
alias knowledge-pipeline='~/.claude/scripts/knowledge-pipeline.sh'
alias knowledge-stats='~/.claude/scripts/knowledge-assistant.sh stats'

# Dashboard
alias knowledge-dashboard='~/.claude/scripts/knowledge-dashboard.sh interactive'
alias kdb='~/.claude/scripts/knowledge-dashboard.sh interactive'

# Pipeline management
alias kp-full='~/.claude/scripts/knowledge-pipeline.sh full'
alias kp-inc='~/.claude/scripts/knowledge-pipeline.sh incremental'
alias kp-status='~/.claude/scripts/knowledge-pipeline.sh status'
EOF

    echo -e "${GREEN}✓${NC} Aliases created: $alias_file"
    echo -e "  Add to your shell: source $alias_file"
}

# Initialize data structures
initialize_data() {
    echo -e "${BLUE}Initializing data structures...${NC}"

    # Initialize config files
    bash "${SCRIPT_DIR}/knowledge-assistant.sh" config show > /dev/null 2>&1 || true

    # Initialize pipeline state
    bash "${SCRIPT_DIR}/knowledge-pipeline.sh" status > /dev/null 2>&1 || true

    echo -e "${GREEN}✓${NC} Data structures initialized"
}

# ============================================================================
# Full Installation
# ============================================================================

install_all() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Knowledge Synthesis Integration Installer  ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    install_session_hook
    echo ""

    setup_pipeline_daemon
    echo ""

    setup_realtime_daemon
    echo ""

    create_aliases
    echo ""

    initialize_data
    echo ""

    echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}           Installation Complete!              ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BLUE}Next Steps:${NC}"
    echo ""
    echo "1. Run initial knowledge extraction:"
    echo "   ${YELLOW}~/.claude/scripts/knowledge-pipeline.sh full${NC}"
    echo ""
    echo "2. (Optional) Start daemons:"
    echo "   ${YELLOW}launchctl load ~/Library/LaunchAgents/com.claude.knowledge-pipeline.plist${NC}"
    echo "   ${YELLOW}launchctl load ~/Library/LaunchAgents/com.claude.realtime-capture.plist${NC}"
    echo ""
    echo "3. Add aliases to your shell:"
    echo "   ${YELLOW}echo 'source ~/.claude/aliases/knowledge-aliases.sh' >> ~/.zshrc${NC}"
    echo "   ${YELLOW}source ~/.zshrc${NC}"
    echo ""
    echo "4. View dashboard:"
    echo "   ${YELLOW}~/.claude/scripts/knowledge-dashboard.sh interactive${NC}"
    echo ""
    echo "5. Try search:"
    echo "   ${YELLOW}~/.claude/scripts/knowledge-assistant.sh search \"your query\"${NC}"
    echo ""
}

# Uninstall
uninstall_all() {
    echo -e "${RED}Uninstalling knowledge synthesis integration...${NC}"
    echo ""

    # Restore session manager backup
    local session_manager="${SCRIPT_DIR}/session-manager.sh"
    local latest_backup=$(ls -t "${session_manager}.backup-"* 2>/dev/null | head -1)

    if [[ -n "$latest_backup" ]]; then
        echo -e "${BLUE}Restoring session manager from backup...${NC}"
        cp "$latest_backup" "$session_manager"
        echo -e "${GREEN}✓${NC} Session manager restored"
    fi

    # Unload daemons
    echo -e "${BLUE}Stopping daemons...${NC}"
    launchctl unload "${HOME}/Library/LaunchAgents/com.claude.knowledge-pipeline.plist" 2>/dev/null || true
    launchctl unload "${HOME}/Library/LaunchAgents/com.claude.realtime-capture.plist" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Daemons stopped"

    # Remove plist files
    rm -f "${HOME}/Library/LaunchAgents/com.claude.knowledge-pipeline.plist"
    rm -f "${HOME}/Library/LaunchAgents/com.claude.realtime-capture.plist"

    echo ""
    echo -e "${GREEN}Uninstall complete${NC}"
    echo -e "${YELLOW}Note: Knowledge data and scripts are preserved${NC}"
}

# ============================================================================
# Status Check
# ============================================================================

check_status() {
    echo ""
    echo -e "${BLUE}Knowledge Synthesis Integration Status${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo ""

    # Check session hook
    local session_manager="${SCRIPT_DIR}/session-manager.sh"
    if grep -q "session-startup-hook.sh" "$session_manager"; then
        echo -e "${GREEN}✓${NC} Session startup hook: Installed"
    else
        echo -e "${RED}✗${NC} Session startup hook: Not installed"
    fi

    # Check daemons
    if launchctl list | grep -q "com.claude.knowledge-pipeline"; then
        echo -e "${GREEN}✓${NC} Pipeline daemon: Running"
    else
        echo -e "${YELLOW}!${NC} Pipeline daemon: Not running"
    fi

    if launchctl list | grep -q "com.claude.realtime-capture"; then
        echo -e "${GREEN}✓${NC} Realtime capture daemon: Running"
    else
        echo -e "${YELLOW}!${NC} Realtime capture daemon: Not running"
    fi

    # Check knowledge base
    local knowledge_base="${HOME}/.claude/knowledge/knowledge-base.jsonl"
    if [[ -f "$knowledge_base" ]] && [[ -s "$knowledge_base" ]]; then
        local kb_size=$(wc -l < "$knowledge_base")
        echo -e "${GREEN}✓${NC} Knowledge base: $kb_size entries"
    else
        echo -e "${YELLOW}!${NC} Knowledge base: Empty (run pipeline)"
    fi

    # Check aliases
    if [[ -f "${HOME}/.claude/aliases/knowledge-aliases.sh" ]]; then
        echo -e "${GREEN}✓${NC} Aliases: Created"
    else
        echo -e "${RED}✗${NC} Aliases: Not created"
    fi

    echo ""
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Integration Installer - Install knowledge synthesis hooks

Usage: $(basename "$0") <command>

Commands:
  install       Install all components
  uninstall     Remove integration (preserves data)
  status        Check installation status
  help          Show this help

Examples:
  $(basename "$0") install
  $(basename "$0") status
  $(basename "$0") uninstall
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"

    case "$command" in
        install)
            install_all
            ;;

        uninstall)
            uninstall_all
            ;;

        status)
            check_status
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
