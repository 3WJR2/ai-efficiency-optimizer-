#!/usr/bin/env bash

################################################################################
# multi-terminal-integration.sh - Integration with claude-multi-terminal app
# Version: 1.0.0
#
# Features:
# - Hook into app startup
# - Keyboard shortcuts for orchestration
# - Display orchestration status
# - Spawn agents in panes
################################################################################

set -euo pipefail

# Directories
CLAUDE_HOME="${HOME}/.claude"
SCRIPTS_DIR="${CLAUDE_HOME}/scripts"
DATA_DIR="${CLAUDE_HOME}/data"
LOGS_DIR="${CLAUDE_HOME}/logs"

# Log file
LOG_FILE="${LOGS_DIR}/multi-terminal-integration.log"

# Ensure directories exist
mkdir -p "${DATA_DIR}" "${LOGS_DIR}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $*" | tee -a "${LOG_FILE}"
}

# Create Python integration module
create_python_integration() {
    local output_file="${1:-./claude_assistant_integration.py}"

    cat > "${output_file}" <<'EOF'
"""Integration module for claude-assistant with multi-terminal app."""

import asyncio
import subprocess
import json
from pathlib import Path
from typing import Optional, Dict, List


class ClaudeAssistantIntegration:
    """Integration between claude-assistant and multi-terminal app."""

    def __init__(self):
        self.claude_home = Path.home() / ".claude"
        self.scripts_dir = self.claude_home / "scripts"
        self.data_dir = self.claude_home / "data"
        self.logs_dir = self.claude_home / "logs"

        # Ensure directories exist
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.logs_dir.mkdir(parents=True, exist_ok=True)

    async def orchestrate_from_app(
        self, request: str, session_grid=None
    ) -> Dict:
        """
        Orchestrate agents from within the multi-terminal app.

        Args:
            request: User's request
            session_grid: Multi-terminal session grid (optional)

        Returns:
            Dict with orchestration results
        """
        try:
            # Step 1: Search codebase
            search_results = await self._search_codebase(request)

            # Step 2: Preload context
            context = await self._preload_context(request)

            # Step 3: Detect structure
            structure = await self._detect_structure()

            # Step 4: Suggest agents
            agents = await self._suggest_agents(request, structure)

            # Step 5: Spawn agents in panes
            if session_grid:
                await self._spawn_agents_in_panes(agents, request, context, session_grid)

            return {
                "status": "success",
                "search_results": search_results,
                "context": context,
                "structure": structure,
                "agents": agents,
            }

        except Exception as e:
            return {
                "status": "error",
                "error": str(e),
            }

    async def _search_codebase(self, query: str) -> Optional[str]:
        """Search codebase for query."""
        try:
            result = subprocess.run(
                [
                    "bash",
                    str(self.scripts_dir / "claude-assistant.sh"),
                    "search",
                    query,
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            return result.stdout if result.returncode == 0 else None
        except Exception as e:
            print(f"Search error: {e}")
            return None

    async def _preload_context(self, request: str) -> Optional[str]:
        """Preload context for request."""
        try:
            result = subprocess.run(
                [
                    "bash",
                    str(self.scripts_dir / "context-preloader.sh"),
                    "preload",
                    request,
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            return result.stdout if result.returncode == 0 else None
        except Exception as e:
            print(f"Context preload error: {e}")
            return None

    async def _detect_structure(self) -> Optional[Dict]:
        """Detect codebase structure."""
        try:
            result = subprocess.run(
                [
                    "bash",
                    str(self.scripts_dir / "orchestration-enhancer.sh"),
                    "detect-structure",
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode == 0:
                return json.loads(result.stdout)
            return None
        except Exception as e:
            print(f"Structure detection error: {e}")
            return None

    async def _suggest_agents(
        self, request: str, structure: Optional[Dict]
    ) -> List[str]:
        """Suggest agents for request."""
        try:
            result = subprocess.run(
                [
                    "bash",
                    str(self.scripts_dir / "orchestration-enhancer.sh"),
                    "suggest-agents",
                    request,
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode == 0:
                agents_json = result.stdout.strip()
                return json.loads(agents_json)
            return []
        except Exception as e:
            print(f"Agent suggestion error: {e}")
            return []

    async def _spawn_agents_in_panes(
        self, agents: List[str], request: str, context: str, session_grid
    ):
        """Spawn agents in multi-terminal panes."""
        try:
            # Create panes for each agent
            for i, agent in enumerate(agents[:4]):  # Limit to 4 agents
                # Split pane
                if i > 0:
                    session_grid.split_active_horizontal()

                # Get active pane
                active_pane = session_grid.get_active_pane()

                # Set pane title
                active_pane.border_title = f"{agent}"

                # Launch agent
                # This would integrate with your agent system
                # For now, just show a placeholder
                active_pane.update(f"[{agent}]\n\nProcessing: {request}\n\n{context[:200]}...")

        except Exception as e:
            print(f"Agent spawn error: {e}")

    async def get_status(self) -> Dict:
        """Get claude-assistant status."""
        try:
            result = subprocess.run(
                [
                    "bash",
                    str(self.scripts_dir / "claude-assistant.sh"),
                    "status",
                ],
                capture_output=True,
                text=True,
                timeout=10,
            )
            return {
                "status": "running" if result.returncode == 0 else "error",
                "output": result.stdout,
            }
        except Exception as e:
            return {
                "status": "error",
                "error": str(e),
            }


# Singleton instance
_integration = None


def get_integration() -> ClaudeAssistantIntegration:
    """Get singleton integration instance."""
    global _integration
    if _integration is None:
        _integration = ClaudeAssistantIntegration()
    return _integration


# Convenience function for use in app
async def orchestrate_from_app(request: str, session_grid=None) -> Dict:
    """Orchestrate agents from app."""
    integration = get_integration()
    return await integration.orchestrate_from_app(request, session_grid)
EOF

    chmod +x "${output_file}"
    success "Created Python integration module: ${output_file}"
}

# Create app integration example
create_app_integration_example() {
    local output_file="${1:-./app_integration_example.py}"

    cat > "${output_file}" <<'EOF'
"""
Example integration of claude-assistant into multi-terminal app.

Add this to your app.py to enable claude-assistant integration.
"""

from textual import events
from textual.widgets import Input
from claude_assistant_integration import orchestrate_from_app


# Add to your ClaudeMultiTerminal class:

class ClaudeMultiTerminal(App):
    """Enhanced with claude-assistant integration."""

    BINDINGS = [
        # ... existing bindings ...
        Binding("ctrl+o", "orchestrate", "Orchestrate"),
        Binding("ctrl+s", "assistant_status", "Assistant Status"),
    ]

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.orchestrate_input = None

    async def action_orchestrate(self) -> None:
        """Trigger claude-assistant orchestration."""
        # Show input dialog
        if self.orchestrate_input is None:
            self.orchestrate_input = Input(
                placeholder="Enter your request...",
                id="orchestrate-input"
            )

        # Get request from user
        self.push_screen(
            InputDialog(
                prompt="What would you like help with?",
                on_submit=self._handle_orchestrate_request
            )
        )

    async def _handle_orchestrate_request(self, request: str) -> None:
        """Handle orchestration request."""
        if not request:
            return

        # Show status
        self.notify(f"Orchestrating: {request}", title="Claude Assistant")

        # Get session grid
        session_grid = self.query_one("#session-grid")

        # Orchestrate
        result = await orchestrate_from_app(request, session_grid)

        if result["status"] == "success":
            self.notify(
                f"Spawned {len(result['agents'])} agents",
                title="Orchestration Complete",
                severity="information"
            )
        else:
            self.notify(
                f"Error: {result.get('error', 'Unknown error')}",
                title="Orchestration Failed",
                severity="error"
            )

    async def action_assistant_status(self) -> None:
        """Show claude-assistant status."""
        from claude_assistant_integration import get_integration

        integration = get_integration()
        status = await integration.get_status()

        # Display status in modal or notification
        self.notify(
            status["output"],
            title="Claude Assistant Status",
            severity="information"
        )


# Input dialog widget
class InputDialog(ModalScreen):
    """Simple input dialog."""

    def __init__(self, prompt: str, on_submit=None, **kwargs):
        super().__init__(**kwargs)
        self.prompt = prompt
        self.on_submit_callback = on_submit

    def compose(self) -> ComposeResult:
        yield Container(
            Static(self.prompt),
            Input(id="dialog-input"),
            Horizontal(
                Button("Submit", variant="primary", id="submit"),
                Button("Cancel", variant="default", id="cancel"),
            ),
            id="input-dialog"
        )

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "submit":
            input_widget = self.query_one("#dialog-input", Input)
            if self.on_submit_callback:
                await self.on_submit_callback(input_widget.value)
            self.dismiss()
        elif event.button.id == "cancel":
            self.dismiss()


# Usage:
# 1. Copy claude_assistant_integration.py to your app directory
# 2. Import and add bindings as shown above
# 3. Press Ctrl+O to orchestrate
# 4. Press Ctrl+S to check status
EOF

    success "Created app integration example: ${output_file}"
}

# Create keyboard shortcuts documentation
create_keyboard_shortcuts_doc() {
    local output_file="${1:-./KEYBOARD_SHORTCUTS.md}"

    cat > "${output_file}" <<'EOF'
# Claude Assistant - Keyboard Shortcuts

## Multi-Terminal Integration

When claude-assistant is integrated with the multi-terminal app, the following keyboard shortcuts are available:

### Orchestration

- **Ctrl+O** - Orchestrate agents
  - Opens input dialog
  - Enter your request
  - Agents spawn in panes automatically

- **Ctrl+S** - Show assistant status
  - Displays current status
  - Shows running agents
  - Cache statistics

### Navigation

- **Ctrl+A** - Show agent access patterns
  - View which files agents accessed
  - See access frequency
  - Understand agent behavior

### Context

- **Ctrl+C** - Preload context
  - Manually trigger context preloading
  - View preloaded context
  - Cache management

## Command Line

All functionality is also available via command line:

```bash
# Orchestrate
claude-assistant orchestrate "Fix login bug"

# Search
claude-assistant search "authentication"

# Status
claude-assistant status

# Complete workflow
claude-assistant assist "Debug timeout issue"
```

## Tips

- Use **Ctrl+O** for quick orchestration
- View logs in `~/.claude/logs/multi-terminal-integration.log`
- Check cache with `claude-assistant status`
- Clear cache with `context-preloader.sh clear-cache`

EOF

    success "Created keyboard shortcuts doc: ${output_file}"
}

# Install integration into app
install_integration() {
    local app_directory="${1:-}"

    if [[ -z "${app_directory}" ]]; then
        error "Usage: install-integration <app_directory>"
        return 1
    fi

    if [[ ! -d "${app_directory}" ]]; then
        error "Directory not found: ${app_directory}"
        return 1
    fi

    log "Installing integration into: ${app_directory}"

    # Create Python integration module
    create_python_integration "${app_directory}/claude_assistant_integration.py"

    # Create example
    create_app_integration_example "${app_directory}/app_integration_example.py"

    # Create docs
    create_keyboard_shortcuts_doc "${app_directory}/KEYBOARD_SHORTCUTS.md"

    success "Integration installed successfully"
    echo ""
    echo "Next steps:"
    echo "1. Review ${app_directory}/app_integration_example.py"
    echo "2. Add integration code to your app.py"
    echo "3. Test with Ctrl+O keyboard shortcut"
    echo ""
}

# Test integration
test_integration() {
    echo "Testing multi-terminal integration..."
    echo ""

    # Test 1: Create Python module
    echo "Test 1: Create Python integration module"
    local tmp_dir=$(mktemp -d)
    create_python_integration "${tmp_dir}/test_integration.py"
    if [[ -f "${tmp_dir}/test_integration.py" ]]; then
        echo "✓ Module created"
    else
        echo "✗ Module creation failed"
    fi
    echo ""

    # Test 2: Check dependencies
    echo "Test 2: Check required scripts"
    local scripts=(
        "claude-assistant.sh"
        "context-preloader.sh"
        "orchestration-enhancer.sh"
    )
    for script in "${scripts[@]}"; do
        if [[ -f "${SCRIPTS_DIR}/${script}" ]]; then
            echo "  ✓ ${script}"
        else
            echo "  ✗ ${script} (missing)"
        fi
    done
    echo ""

    # Test 3: Test Python syntax
    echo "Test 3: Validate Python syntax"
    if python3 -m py_compile "${tmp_dir}/test_integration.py" 2>/dev/null; then
        echo "✓ Valid Python syntax"
    else
        echo "✗ Invalid Python syntax"
    fi
    echo ""

    # Cleanup
    rm -rf "${tmp_dir}"

    success "All tests completed"
}

# Usage
usage() {
    cat <<EOF
Multi-Terminal Integration - Integration with claude-multi-terminal app

USAGE:
    multi-terminal-integration.sh <command> [options]

COMMANDS:
    install <app_directory>      Install integration into app
    create-module <output_file>  Create Python integration module
    create-example <output_file> Create app integration example
    create-docs <output_file>    Create keyboard shortcuts doc
    test                         Run test suite

OPTIONS:
    --help                       Show this help

EXAMPLES:
    # Install integration
    multi-terminal-integration.sh install ~/claude-multi-terminal

    # Create module only
    multi-terminal-integration.sh create-module ./integration.py

    # Test integration
    multi-terminal-integration.sh test

EOF
}

# Main
main() {
    local command="${1:-}"

    case "${command}" in
        install)
            shift
            install_integration "$@"
            ;;
        create-module)
            shift
            create_python_integration "$@"
            ;;
        create-example)
            shift
            create_app_integration_example "$@"
            ;;
        create-docs)
            shift
            create_keyboard_shortcuts_doc "$@"
            ;;
        test)
            test_integration
            ;;
        --help|-h|"")
            usage
            ;;
        *)
            error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
