# Claude Multi-Terminal App - Implementation Plan

## Overview
Build a Python-based terminal UI application for running multiple Claude Code CLI sessions simultaneously in a split-pane interface.

## Technology Stack
- **UI Framework**: Textual (best performance, modern features, 120 FPS)
- **Process Management**: ptyprocess + asyncio
- **Output Display**: RichLog widgets (auto-handles ANSI codes)
- **Platform**: macOS (darwin), extendable to Linux

## Architecture

### Component Structure
```
ClaudeMultiTerminalApp (Main App)
├── SessionManager (PTY lifecycle management)
│   └── PTYHandler (per-session PTY wrapper)
├── SessionGrid (Layout container)
│   └── SessionPane widgets (one per Claude session)
├── HeaderBar (Status indicators)
└── StatusBar (Keybindings, broadcast indicator)
```

### File Structure
```
claude-multi-terminal/
├── claude_multi_terminal/
│   ├── __main__.py              # Entry point
│   ├── app.py                   # Main app class
│   ├── config.py                # Configuration constants
│   ├── core/
│   │   ├── pty_handler.py       # PTY wrapper (asyncio.to_thread)
│   │   ├── session_manager.py   # Session lifecycle
│   │   └── clipboard.py         # Copy/paste (pbcopy/pbpaste)
│   ├── widgets/
│   │   ├── session_pane.py      # Individual terminal pane
│   │   ├── session_grid.py      # Grid layout manager
│   │   ├── header_bar.py        # Top status bar
│   │   ├── status_bar.py        # Bottom keybindings
│   │   └── rename_dialog.py     # Modal for renaming
│   └── persistence/
│       ├── session_state.py     # Data structures
│       └── storage.py           # Save/load JSON
├── styles.css                   # Textual CSS
├── pyproject.toml              # Dependencies
└── tests/
```

## Core Implementation Details

### 1. PTY Handler (pty_handler.py)
**Critical**: Uses `asyncio.to_thread` to avoid blocking event loop during PTY I/O.

```python
class PTYHandler:
    - spawn(): Create PTY process with ptyprocess.PtyProcess.spawn()
    - start_reading(callback): Async task reading PTY output
    - _read_loop(): Continuously read via asyncio.to_thread(_read_chunk)
    - write(data): Write to PTY (also via asyncio.to_thread)
    - resize(rows, cols): Update PTY dimensions
    - terminate(): Graceful shutdown (SIGTERM → SIGKILL)
```

**Why asyncio.to_thread**: NEVER use os.fork() with active asyncio event loop (causes EBADF errors).

### 2. Session Manager (session_manager.py)
Manages multiple Claude CLI instances.

```python
class SessionManager:
    sessions: Dict[str, SessionInfo]  # UUID → session metadata

    - create_session(name, cwd, args): Spawn new Claude CLI
    - terminate_session(session_id): Clean shutdown
    - _get_session_env(): Configure TERM=xterm-256color, COLORTERM=truecolor
```

Each session has:
- UUID identifier
- User-friendly name
- PTYHandler instance
- Working directory
- Creation timestamp

### 3. Session Pane Widget (session_pane.py)
Individual terminal pane displaying one Claude session.

```python
class SessionPane(Vertical):
    Composition:
    - Label (session name header)
    - RichLog (terminal output, auto-handles ANSI)
    - Input (command input field)

    - on_mount(): Start PTY reading, wire up callback
    - _handle_output(text): Write PTY output to RichLog
    - on_input_submitted(): Send command to PTY (+ newline)
    - get_output_text(): Extract plain text for copying
```

**Key**: RichLog automatically interprets ANSI escape codes, no manual parsing needed.

### 4. Session Grid Layout (session_grid.py)
Dynamic grid layout adapting to session count.

```python
class SessionGrid(Grid):
    Layout Rules:
    - 1 session: 1x1 (full screen)
    - 2 sessions: 2x1 (side-by-side)
    - 3-4 sessions: 2x2 (grid)
    - 5+ sessions: 2 columns, dynamic rows

    - add_session(session_id): Mount new SessionPane
    - remove_session(session_id): Remove pane, adjust layout
    - watch_pane_count(): Update CSS grid dimensions
```

Uses CSS Grid with fractional units (`fr`) for responsive sizing.

### 5. Main App (app.py)
Orchestrates all components and implements actions.

```python
class ClaudeMultiTerminalApp(App):
    Key Bindings:
    - Ctrl+N: New session
    - Ctrl+W: Close session
    - Ctrl+S: Save sessions
    - Ctrl+L: Load sessions
    - Ctrl+R: Rename session
    - Ctrl+B: Toggle broadcast mode
    - Ctrl+C: Copy output
    - Ctrl+V: Paste input
    - Tab/Shift+Tab: Navigate panes
    - Ctrl+Q: Quit

    State:
    - session_manager: SessionManager instance
    - broadcast_mode: bool (send input to all sessions)
    - clipboard_buffer: str (internal clipboard)
```

## Feature Implementations

### Session Persistence
**Data Format**: JSON file at `~/.claude_multi_terminal/workspace_state.json`

```python
@dataclass
class SessionState:
    session_id: str
    name: str
    working_directory: str
    created_at: float

@dataclass
class WorkspaceState:
    version: str = "1.0"
    sessions: List[SessionState]
    active_session_id: Optional[str]
```

**Save on**: Manual (Ctrl+S), automatic on quit
**Restore**: Recreate sessions with same names and working directories

### Session Naming
- Default names: "Session 1", "Session 2", etc.
- Modal dialog for renaming (Ctrl+R)
- Reactive property updates UI automatically
- Names persisted in workspace state

### Copy/Paste
**System Clipboard Integration** (macOS):
- Copy: `pbcopy` via subprocess
- Paste: `pbpaste` via subprocess
- Fallback: Internal clipboard buffer

**Actions**:
- Ctrl+C: Copy all output from focused session
- Ctrl+V: Paste into focused session's input field

### Command Broadcasting
**Broadcast Mode** (Ctrl+B toggle):
- When enabled: Input sent to ALL sessions simultaneously
- Visual indicator: Status bar highlights in warning color
- Per-session error handling (one failure doesn't stop others)

## Key Technical Decisions

1. **Textual over urwid/blessed**: 120 FPS vs 20 FPS, better performance, modern API, active development

2. **ptyprocess over pexpect**: Lower-level control, better for custom async integration

3. **asyncio.to_thread for PTY I/O**: Avoids blocking event loop, prevents fork+asyncio conflicts

4. **RichLog for output**: Automatic ANSI handling, no manual escape code parsing

5. **JSON for persistence**: Human-readable, easy debugging, standard library support

6. **CSS Grid for layout**: Responsive, flexible, declarative sizing with `fr` units

## Critical Implementation Order

1. **pty_handler.py** - Foundation for all PTY operations
2. **session_manager.py** - Session lifecycle management
3. **session_pane.py** - UI widget connecting PTY ↔ display
4. **app.py** - Wire everything together, key bindings
5. **persistence/** - Save/restore functionality
6. **clipboard.py** - Copy/paste between sessions
7. **Dialogs and polish** - Rename dialog, status bars, CSS

## Dependencies
```toml
[project]
dependencies = [
    "textual>=0.47.0",
    "rich>=13.7.0",
    "ptyprocess>=0.7.0",
]
```

## Installation
```bash
mkdir claude-multi-terminal && cd claude-multi-terminal
python3 -m venv venv
source venv/bin/activate
pip install textual rich ptyprocess

# After implementation:
pip install -e .
claude-multi  # Run the app
```

## Verification Plan

### Unit Tests
- `test_pty_handler.py`: PTY spawn, read, write, terminate
- `test_session_manager.py`: Create/terminate sessions
- `test_storage.py`: Save/load workspace state

### Integration Tests (Manual)
1. **Basic Flow**:
   - Launch app → 2 default sessions appear
   - Type command → output streams to RichLog
   - Tab between sessions → focus changes
   - Ctrl+W → session closes

2. **Persistence**:
   - Create 3 sessions, name them
   - Ctrl+S to save
   - Quit and restart
   - Ctrl+L to load → sessions restored with names

3. **Copy/Paste**:
   - Run `ls -la` in session 1
   - Ctrl+C to copy output
   - Switch to session 2 (Tab)
   - Ctrl+V → output appears in input field

4. **Broadcast**:
   - Ctrl+B to enable (status bar shows [BROADCAST MODE])
   - Type `pwd` → command executes in all sessions
   - Ctrl+B to disable

5. **Edge Cases**:
   - Close session while command running
   - Resize terminal window
   - Invalid Claude CLI path (should show error)

### Performance Checks
- PTY latency < 50ms
- UI maintains 60 FPS
- Memory stable with 4 active sessions

## Configuration
All settings in `config.py`:
- `CLAUDE_PATH`: `/opt/homebrew/bin/claude`
- `STORAGE_DIR`: `~/.claude_multi_terminal`
- `DEFAULT_SESSION_COUNT`: 2
- `MAX_SESSIONS`: 6
- `PTY_ROWS/COLS`: 24/80
- Key bindings (customizable)

## Error Handling
1. Claude CLI not found → Show error, exit
2. PTY process dies → Display error in pane, offer restart
3. Corrupted save file → Backup and start fresh
4. Clipboard unavailable → Use internal buffer only
5. Terminal too small → Show warning notification

## Future Enhancements (v2)
- Resizable split ratios
- Session tabs (in addition to splits)
- Command history per session
- Log export to file
- Custom themes
- Session templates
- Collaborative session sharing

## Timeline Estimate
- **Week 1**: Core (PTY, SessionManager, basic UI)
- **Week 2**: Features (persistence, copy/paste, broadcast)
- **Week 3**: Testing, polish, documentation

**MVP: ~2-3 weeks**
