# Python & Shell Workflow Optimizations

**Optimized for your 96% Python/Shell usage pattern**

## 🚀 Quick Start (30 seconds)

### Activate Now
```bash
source ~/.zshrc
```

### Test It
```bash
# Quick Python
pq "print('Hello from optimized Python!')"

# Quick Shell
sq "echo 'Hello from optimized Shell!'"

# Python environment check
py-check
```

## 📦 What You Got

### 1. Quick Commands (Ultra-Fast)

#### Python Quick (pq)
```bash
# Inline code
pq "print(sum(range(100)))"
pq "import sys; print(sys.version)"

# Run script
pq myscript.py arg1 arg2
```

#### Shell Quick (sq)
```bash
# Inline command
sq "ls -la | grep '.py'"

# Run script
sq myscript.sh
```

### 2. Python Shortcuts

```bash
# Development
py              # python3
py-venv         # Create & activate virtualenv
py-install      # Install requirements.txt
py-freeze       # Save current packages

# Testing & Quality
py-test         # Run pytest
py-lint         # Run flake8
py-format       # Run black formatter
py-type         # Run mypy type checker

# Debugging
py-debug        # PDB debugger
py-profile      # Performance profiling
py-trace        # Execution tracing

# Environment
py-check        # Full environment report
py-deps         # Analyze dependencies
py-path         # Show Python path
```

### 3. Shell Shortcuts

```bash
# File Operations
ll              # Long list with details
la              # List all including hidden
ff <name>       # Find file by name
tree            # Show directory tree

# Search
gg <pattern>    # Grep recursively
hh <pattern>    # Search command history

# System
cpu             # CPU usage
mem             # Memory usage
disk            # Disk space
ports           # Open ports

# Script Quality
sh-check        # Lint shell scripts
sh-format       # Format shell scripts
sh-profile      # Profile script performance
```

### 4. Integrated Workflows

```bash
# Create new project
project-init myproject

# Run all tests (Python + Shell)
run-all-tests

# Lint everything
lint-all

# Format everything
format-all
```

## 💡 Real-World Examples

### Example 1: Quick Data Analysis

```bash
# Before (slow)
python3 -c "
import csv
with open('data.csv') as f:
    reader = csv.reader(f)
    rows = list(reader)
    print(f'Total rows: {len(rows)}')
"

# After (fast)
pq "
import csv
with open('data.csv') as f:
    print(f'Total rows: {len(list(csv.reader(f)))}')
"
```

### Example 2: Quick Script Testing

```bash
# Before
python3 test_module.py
python3 -m pytest tests/
flake8 .
black .

# After (one command)
run-all-tests && lint-all && format-all
```

### Example 3: Environment Setup

```bash
# Before
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# After
py-venv && py-install
```

### Example 4: Quick Prototyping

```bash
# Use template
cp ~/.claude/templates/python-script.py my-script.py

# Edit and run
vim my-script.py
pq my-script.py
```

### Example 5: Hybrid Python+Shell Script

```bash
# Copy hybrid template
cp ~/.claude/templates/hybrid-script.sh process-data.sh

# Edit for your needs
# Shell handles orchestration, Python handles processing
bash process-data.sh
```

## 🎯 Common Tasks Made Easy

### Task 1: Start New Python Project

```bash
# Create structure
project-init data-analyzer

# Navigate
cd data-analyzer

# Setup environment
py-venv
py-install

# Start coding
code src/
```

### Task 2: Quick Script Development

```bash
# 1. Create from template
cp ~/.claude/templates/python-script.py analyze.py

# 2. Edit
vim analyze.py

# 3. Test
pq analyze.py

# 4. Format & lint
py-format analyze.py
py-lint analyze.py

# 5. Done!
```

### Task 3: Debug Issues

```bash
# Check environment
py-check

# Profile slow script
py-profile slow-script.py

# Debug with PDB
py-debug buggy-script.py

# Trace execution
py-trace complex-script.py
```

### Task 4: System Administration

```bash
# Check system
cpu && mem && disk

# Find processes
psg python

# Check ports
ports

# Kill process on port
kill-port 8080
```

## 📋 Cheat Sheet

### Daily Use
```bash
pq "code"          # Quick Python
py-check           # Environment check
py-test            # Run tests
ll                 # List files
gg "pattern"       # Search code
```

### Before Commit
```bash
lint-all           # Lint everything
format-all         # Format everything
run-all-tests      # Run all tests
```

### New Project
```bash
project-init name  # Create structure
py-venv            # Setup virtualenv
py-install         # Install deps
```

### Debugging
```bash
py-debug script.py # Python debugger
py-profile script  # Performance
sh-check .         # Shell linting
```

## 🔧 Customization

### Add Your Own Aliases

Edit `~/.claude/aliases/python-shell.sh`:
```bash
# Add custom aliases
alias my-test='pytest -v --cov'
alias my-deploy='./scripts/deploy.sh'
```

### Modify Templates

Edit templates in `~/.claude/templates/`:
- `python-script.py` - Python template
- `shell-script.sh` - Shell template
- `hybrid-script.sh` - Python+Shell hybrid

### Quick Commands

Add more to `~/.claude/bin/`:
```bash
# Example: Quick JSON formatter
cat > ~/.claude/bin/jq-pretty << 'EOF'
#!/usr/bin/env bash
jq . "$@"
EOF
chmod +x ~/.claude/bin/jq-pretty
```

## 📊 Performance Benefits

### Before Optimization
```bash
# 5 separate commands
python3 script1.py      # 2s
python3 script2.py      # 2s
python3 -m pytest       # 3s
flake8 .                # 1s
black .                 # 1s
Total: 9 seconds
```

### After Optimization
```bash
# 1 command
run-all-tests && lint-all && format-all
Total: 9 seconds but automated!

# Plus: Shorter commands = faster typing
pq vs python3 = 6 characters saved per use
py-test vs python3 -m pytest = 11 characters saved
```

### Time Savings (Daily)
- 50+ command invocations/day
- Avg 8 characters saved per command
- **~400 characters/day saved = 2 minutes/day**
- Over a year: **12 hours saved!**

## 🛠️ Recommended Tools Installation

### Python Tools
```bash
pip install black flake8 mypy pytest ipython
```

### Shell Tools (macOS)
```bash
brew install shellcheck shfmt bats-core
```

### Shell Tools (Linux)
```bash
# Ubuntu/Debian
apt install shellcheck

# Or use snap
snap install shfmt
```

## 🐛 Troubleshooting

### "Command not found"
```bash
# Reload shell config
source ~/.zshrc

# Or check PATH
echo $PATH | grep claude

# Manual add if needed
export PATH="$HOME/.claude/bin:$PATH"
```

### "Alias not working"
```bash
# Check if loaded
type py

# Reload aliases
source ~/.claude/aliases/python-shell.sh
```

### "Python version issues"
```bash
# Check Python
py-which

# Use specific version
alias py='python3.11'  # Or your version
```

## 📈 Track Your Usage

After a week, check insights:
```bash
/adaptive-intelligence insights
```

You'll see:
- Python/Shell usage patterns
- Most-used commands
- Time saved vs baseline
- Optimization opportunities

## 🎓 Advanced Tips

### 1. Chain Commands
```bash
py-venv && py-install && py-test
```

### 2. Use with Parallel Execution
```bash
~/.claude/scripts/parallel-helper.sh run \
  "py-test tests/unit/" \
  "py-test tests/integration/" \
  "py-lint"
```

### 3. Create Project-Specific Aliases
```bash
# In your project directory
echo "alias deploy='py-test && ./deploy.sh'" >> .project-aliases
source .project-aliases
```

### 4. Integrate with Git Hooks
```bash
# .git/hooks/pre-commit
#!/bin/bash
lint-all && format-all && run-all-tests
```

## 📚 Resources

- **Aliases**: `~/.claude/aliases/python-shell.sh`
- **Templates**: `~/.claude/templates/`
- **Quick Commands**: `~/.claude/bin/`
- **Optimizer**: `~/.claude/scripts/python-shell-optimizer.sh`

## 🔄 Uninstall (if needed)

```bash
~/.claude/scripts/python-shell-optimizer.sh uninstall
```

---

**Your workflows are now optimized for 96% Python/Shell efficiency!** 🎉

*Last updated: 2026-02-05 | Version: 1.3.0*
