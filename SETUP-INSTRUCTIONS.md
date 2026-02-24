# Adaptive Intelligence - Automatic Startup Configuration

## How It Works

The Adaptive Intelligence System is **automatically active** because Claude Code loads `~/.claude/CLAUDE.md` on every startup. This file is already configured and ready.

## Verification

Check that it's working:

```bash
# Method 1: Check via Claude command
/adaptive-intelligence status

# Method 2: Check files exist
ls -la ~/.claude/CLAUDE.md
ls -la ~/.claude/data/user-profile.json

# Method 3: Check current session
cat ~/.claude/data/user-profile.json | jq -r '.profile.learning_stage'
```

## Ensuring Startup Hook Runs (Optional Enhancement)

For additional robustness, you can add a startup hook to your shell:

### For Zsh (macOS default)

Add this line to `~/.zshrc`:
```bash
[[ -f ~/.claude/autoload.sh ]] && source ~/.claude/autoload.sh
```

Apply changes:
```bash
echo '[[ -f ~/.claude/autoload.sh ]] && source ~/.claude/autoload.sh' >> ~/.zshrc
source ~/.zshrc
```

### For Bash

Add this line to `~/.bashrc`:
```bash
[[ -f ~/.claude/autoload.sh ]] && source ~/.claude/autoload.sh
```

Apply changes:
```bash
echo '[[ -f ~/.claude/autoload.sh ]] && source ~/.claude/autoload.sh' >> ~/.bashrc
source ~/.bashrc
```

## What Gets Loaded Automatically

1. **~/.claude/CLAUDE.md** - Main configuration (loaded by Claude Code automatically)
2. **~/.claude/data/*.json** - Learning data (created on first use if missing)
3. **Hooks** - `on-session-start.sh` ensures data files exist
4. **Scripts** - Learning scripts ready in `~/.claude/scripts/`
5. **Skill** - `/adaptive-intelligence` command available

## Testing the Setup

### Test 1: Verify CLAUDE.md is loaded
```bash
cat ~/.claude/CLAUDE.md | head -5
```
Should show: "Claude Enhanced Configuration - Adaptive Intelligence System"

### Test 2: Run status check
```bash
/adaptive-intelligence status
```
Should display learning stage and configuration.

### Test 3: Check data files
```bash
ls -lh ~/.claude/data/
```
Should show:
- `user-profile.json`
- `interaction-learning.json`
- `critical-thinking-framework.json`

### Test 4: Verify scripts are executable
```bash
ls -l ~/.claude/scripts/*.sh
```
All should have `x` permission (executable).

## Troubleshooting

### System Not Active

**Problem**: `/adaptive-intelligence status` returns error

**Solutions**:
```bash
# 1. Verify CLAUDE.md exists
cat ~/.claude/CLAUDE.md

# 2. Run initialization manually
~/.claude/hooks/on-session-start.sh

# 3. Check data directory
ls -la ~/.claude/data/

# 4. Verify skill exists
ls -la ~/.claude/skills/adaptive-intelligence/
```

### Data Files Missing

**Problem**: `user-profile.json` or other files not found

**Solution**: Run initialization:
```bash
~/.claude/hooks/on-session-start.sh
```

This creates all necessary files if missing.

### Scripts Not Executable

**Problem**: Permission denied errors

**Solution**: Set permissions:
```bash
chmod +x ~/.claude/scripts/*.sh
chmod +x ~/.claude/skills/adaptive-intelligence/skill.sh
chmod +x ~/.claude/hooks/*.sh
```

### Changes Not Taking Effect

**Problem**: Modifications to config not showing

**Solution**:
```bash
# 1. Restart Claude session
# 2. Verify file was saved
cat ~/.claude/CLAUDE.md

# 3. Check for syntax errors
jq . ~/.claude/data/user-profile.json
```

## File Locations Reference

### Configuration
- `~/.claude/CLAUDE.md` - **Main config** (auto-loaded by Claude)
- `~/.claude/CLAUDE-ADAPTIVE.md` - Detailed documentation
- `~/.claude/QUICK-REFERENCE.md` - Quick command reference

### Data (Learning Storage)
- `~/.claude/data/user-profile.json` - Your profile and progress
- `~/.claude/data/interaction-learning.json` - Learned patterns
- `~/.claude/data/critical-thinking-framework.json` - Quality protocols

### Scripts (Background Automation)
- `~/.claude/scripts/capture-interaction.sh` - Captures interactions
- `~/.claude/scripts/analyze-interaction-patterns.sh` - Generates insights
- `~/.claude/scripts/apply-critical-thinking.sh` - Enforces thinking

### Hooks (Automatic Triggers)
- `~/.claude/hooks/on-session-start.sh` - Runs on Claude startup
- (Future: `on-session-end.sh` for session cleanup)

### Skill (User Interface)
- `~/.claude/skills/adaptive-intelligence/skill.md` - Documentation
- `~/.claude/skills/adaptive-intelligence/skill.sh` - Command interface

### Support (Optional)
- `~/.claude/autoload.sh` - Shell integration for startup
- `~/.claude/SETUP-INSTRUCTIONS.md` - This file

## Default Behavior (No Setup Required)

**The system is already active!** Here's why:

1. **Claude Code automatically loads** `~/.claude/CLAUDE.md` on startup
2. **Data files are created** automatically on first use
3. **Scripts run in background** as needed
4. **No manual configuration** required

## Optional Enhancements

### Shell Integration (Recommended)

Add to `~/.zshrc` or `~/.bashrc`:
```bash
# Adaptive Intelligence System
[[ -f ~/.claude/autoload.sh ]] && source ~/.claude/autoload.sh
```

**Benefits**:
- Ensures data files exist before Claude starts
- Provides `--status` flag: `~/.claude/autoload.sh --status`
- Runs initialization on shell startup

### Startup Message (Optional)

To see a message when Claude starts:

Add to `~/.claude/CLAUDE.md` at the top:
```markdown
<!-- Adaptive Intelligence System v1.0 - Active and Learning -->
```

### Periodic Analysis (Advanced)

Set up cron job for weekly insights:
```bash
# Add to crontab: crontab -e
0 9 * * 1 ~/.claude/scripts/analyze-interaction-patterns.sh
```

Runs every Monday at 9 AM to generate insights.

## Verification Checklist

Before considering setup complete, verify:

- [ ] `~/.claude/CLAUDE.md` exists
- [ ] `~/.claude/data/` directory exists
- [ ] `user-profile.json`, `interaction-learning.json`, `critical-thinking-framework.json` exist
- [ ] `/adaptive-intelligence status` works
- [ ] All scripts in `~/.claude/scripts/` are executable (`chmod +x`)
- [ ] Skill scripts in `~/.claude/skills/adaptive-intelligence/` are executable
- [ ] Learning stage shows "initialization" or higher

Quick check all:
```bash
bash -c '
echo "Checking Adaptive Intelligence System setup..."
[[ -f ~/.claude/CLAUDE.md ]] && echo "✅ CLAUDE.md exists" || echo "❌ CLAUDE.md missing"
[[ -d ~/.claude/data ]] && echo "✅ data directory exists" || echo "❌ data directory missing"
[[ -f ~/.claude/data/user-profile.json ]] && echo "✅ user-profile.json exists" || echo "❌ user-profile.json missing"
[[ -f ~/.claude/data/interaction-learning.json ]] && echo "✅ interaction-learning.json exists" || echo "❌ interaction-learning.json missing"
[[ -f ~/.claude/data/critical-thinking-framework.json ]] && echo "✅ critical-thinking-framework.json exists" || echo "❌ critical-thinking-framework.json missing"
[[ -x ~/.claude/scripts/capture-interaction.sh ]] && echo "✅ capture-interaction.sh executable" || echo "❌ capture-interaction.sh not executable"
[[ -x ~/.claude/skills/adaptive-intelligence/skill.sh ]] && echo "✅ skill.sh executable" || echo "❌ skill.sh not executable"
echo ""
echo "Current learning stage:"
jq -r ".profile.learning_stage" ~/.claude/data/user-profile.json 2>/dev/null || echo "Error reading profile"
'
```

## Summary

**You don't need to do anything!** The system is already configured to:

1. ✅ Load automatically when Claude starts (via `CLAUDE.md`)
2. ✅ Initialize data files on first use
3. ✅ Run learning scripts in background
4. ✅ Provide `/adaptive-intelligence` commands

**Optional enhancements** (shell integration) provide additional robustness but are not required.

**Test it**: Just start using Claude normally and check `/adaptive-intelligence status` to verify it's working.
