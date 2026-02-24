# Pattern Import/Export Guide

**Feature**: Transfer learned patterns across machines
**Created**: 2026-02-03
**Status**: ✅ Production Ready

---

## Overview

The Pattern Import/Export system allows you to:
- **Export** learned patterns from one machine to a portable file
- **Import** those patterns on another machine
- **Share** learning across multiple systems
- **Bootstrap** new machines with existing knowledge
- **Backup** learned patterns for recovery

This dramatically reduces the time needed to reach optimal performance on new systems.

---

## Quick Start

### Export Patterns

```bash
# Export to default location
~/.claude/scripts/pattern-import-export.sh export

# Export to specific file
~/.claude/scripts/pattern-import-export.sh export ~/my-patterns.json
```

### Import Patterns

```bash
# Compare first (recommended)
~/.claude/scripts/pattern-import-export.sh compare ~/patterns.json

# Import with conservative merge (default)
~/.claude/scripts/pattern-import-export.sh import ~/patterns.json

# Import with aggressive merge (overwrite local)
~/.claude/scripts/pattern-import-export.sh import ~/patterns.json aggressive
```

### Apply to Live Configs

```bash
# Apply imported patterns to cache-config.json and parallel-config.json
~/.claude/scripts/pattern-import-export.sh apply
```

---

## Export

### What Gets Exported

The export file contains:

1. **Learned Patterns**
   - Optimal cache threshold (if learned)
   - Optimal concurrent processes (if learned)
   - Best performing strategies

2. **Learning Summary**
   - Total learning cycles
   - Cache samples collected
   - Parallel samples collected
   - Average hit rate
   - Average success rate

3. **Adjustment History**
   - Cache threshold adjustments made
   - Concurrent limit adjustments made
   - Reasons for each adjustment

4. **Current Configurations**
   - Active cache threshold
   - Active concurrent limit

5. **Metadata**
   - Export timestamp
   - Source system info (hostname, user, OS)
   - Version

### Export Command

```bash
~/.claude/scripts/pattern-import-export.sh export [output_file]
```

**Parameters:**
- `output_file` (optional): Path to save export file
  - Default: `~/claude-patterns-YYYYMMDD-HHMMSS.json`

**Example:**

```bash
# Export with default filename
~/.claude/scripts/pattern-import-export.sh export

# Export to specific file
~/.claude/scripts/pattern-import-export.sh export ~/Desktop/patterns.json

# Export to shared location
~/.claude/scripts/pattern-import-export.sh export /mnt/shared/team-patterns.json
```

**Output:**

```
=== Exporting Learned Patterns ===

✓ Export successful

Export details:
  File: /tmp/patterns.json
  Size: 4.0K

Summary:
  Learning cycles: 42
  Cache samples: 150
  Parallel samples: 98
  Optimal cache threshold: 0.78
  Optimal concurrent: 4

Share this file to transfer learning to another machine
```

---

## Import

### Import Strategies

Three merge strategies available:

#### 1. Conservative (Recommended)

Only imports patterns that are better than current local patterns.

**When to use:**
- You have some local learning already
- You want to preserve good local patterns
- You're unsure about imported quality

**Logic:**
- Imports learned patterns only if:
  - Local doesn't have any learned pattern yet, OR
  - Imported pattern has more samples than local
- Appends adjustment history (doesn't replace)
- Safe default choice

#### 2. Aggressive

Imports everything, overwrites local patterns.

**When to use:**
- You trust the imported patterns
- Imported source has more learning
- You want to adopt best practices from another machine

**Logic:**
- Replaces all learned patterns with imported ones
- Replaces adjustment history
- More forceful adoption

#### 3. Replace

Complete replacement of local learning data (destructive).

**When to use:**
- Fresh start on new machine
- Current local learning is corrupted
- You want exact copy of source system

**Logic:**
- Backs up current data first
- Replaces entire learning data file
- Resets local collection counters
- Most aggressive option

### Import Command

```bash
~/.claude/scripts/pattern-import-export.sh import <file> [strategy]
```

**Parameters:**
- `file` (required): Path to import file
- `strategy` (optional): Merge strategy
  - `conservative` (default)
  - `aggressive`
  - `replace`

**Examples:**

```bash
# Conservative merge (default)
~/.claude/scripts/pattern-import-export.sh import ~/patterns.json

# Aggressive merge
~/.claude/scripts/pattern-import-export.sh import ~/patterns.json aggressive

# Complete replacement
~/.claude/scripts/pattern-import-export.sh import ~/patterns.json replace
```

**Output (Conservative):**

```
=== Importing Learned Patterns ===

Import file details:
  Exported: 2026-02-03T10:30:00Z
  Source: macbook-pro
  Learning cycles: 42
  Cache samples: 150
  Parallel samples: 98

Merge strategy: Conservative (only import if better)

✓ Imported cache threshold: 0.78
  Reason: More samples (150 > 22)
✓ Imported concurrent limit: 4
  Reason: More samples (98 > 21)
✓ Merged adjustment history

Import complete: 3 changes applied
```

---

## Compare

Before importing, you can compare local vs imported patterns.

### Compare Command

```bash
~/.claude/scripts/pattern-import-export.sh compare <file>
```

**Example:**

```bash
~/.claude/scripts/pattern-import-export.sh compare ~/patterns.json
```

**Output:**

```
=== Pattern Comparison ===

Local vs Imported:

Cache Threshold:
  Local:    not learned (from 22 samples)
  Imported: 0.78 (from 150 samples)
  ⚠ Different values

Concurrent Processes:
  Local:    not learned (from 21 samples)
  Imported: 4 (from 98 samples)
  ⚠ Different values

Learning Experience:
  Local:    0 cycles
  Imported: 42 cycles
```

This helps you decide:
- Whether to import
- Which merge strategy to use
- What will change if you import

---

## Apply

After importing, apply the patterns to your live configurations.

### Apply Command

```bash
~/.claude/scripts/pattern-import-export.sh apply
```

**What it does:**
- Reads learned patterns from `learning-data.json`
- Updates `cache-config.json` with optimal cache threshold
- Updates `parallel-config.json` with optimal concurrent limit

**Example:**

```bash
~/.claude/scripts/pattern-import-export.sh apply
```

**Output:**

```
=== Applying Imported Patterns to Live Configs ===

✓ Applied cache threshold: 0.78
✓ Applied concurrent limit: 4

Applied 2 configuration changes
Restart the learning daemon to use new configs
```

**Restart daemon:**

```bash
launchctl unload ~/Library/LaunchAgents/com.claude.learning-daemon.plist
launchctl load ~/Library/LaunchAgents/com.claude.learning-daemon.plist
```

---

## Use Cases

### Use Case 1: New Machine Setup

You have a well-tuned machine and want to set up a new one.

**On source machine:**

```bash
# Export patterns
~/.claude/scripts/pattern-import-export.sh export ~/patterns.json

# Transfer file to new machine (USB, cloud, etc.)
```

**On new machine:**

```bash
# Import with replace (fresh start)
~/.claude/scripts/pattern-import-export.sh import ~/patterns.json replace

# Apply to live configs
~/.claude/scripts/pattern-import-export.sh apply

# Restart daemon
launchctl unload ~/Library/LaunchAgents/com.claude.learning-daemon.plist
launchctl load ~/Library/LaunchAgents/com.claude.learning-daemon.plist
```

**Result**: New machine starts with optimal configs immediately!

---

### Use Case 2: Team Knowledge Sharing

Multiple team members want to share best practices.

**Team member 1:**

```bash
# Export after extensive tuning
~/.claude/scripts/pattern-import-export.sh export /mnt/shared/team-patterns.json
```

**Team member 2:**

```bash
# Compare first
~/.claude/scripts/pattern-import-export.sh compare /mnt/shared/team-patterns.json

# Import conservatively (keep good local patterns)
~/.claude/scripts/pattern-import-export.sh import /mnt/shared/team-patterns.json conservative

# Apply
~/.claude/scripts/pattern-import-export.sh apply
```

**Result**: Team converges on best practices!

---

### Use Case 3: Backup & Recovery

Regular backups of learned patterns.

**Backup script:**

```bash
#!/usr/bin/env bash
# Daily pattern backup

BACKUP_DIR="$HOME/.claude/backups"
mkdir -p "$BACKUP_DIR"

# Export with timestamp
~/.claude/scripts/pattern-import-export.sh export \
  "$BACKUP_DIR/patterns-$(date +%Y%m%d).json"

# Keep only last 30 days
find "$BACKUP_DIR" -name "patterns-*.json" -mtime +30 -delete
```

**Recovery:**

```bash
# List backups
ls -lt ~/.claude/backups/

# Restore from backup
~/.claude/scripts/pattern-import-export.sh import \
  ~/.claude/backups/patterns-20260203.json aggressive
```

---

### Use Case 4: A/B Testing

Test different learned patterns to see which performs better.

```bash
# Backup current state
~/.claude/scripts/pattern-import-export.sh export ~/patterns-current.json

# Import alternative patterns
~/.claude/scripts/pattern-import-export.sh import ~/patterns-alternative.json aggressive
~/.claude/scripts/pattern-import-export.sh apply

# Run for a week, monitor performance

# If worse, restore original
~/.claude/scripts/pattern-import-export.sh import ~/patterns-current.json replace
~/.claude/scripts/pattern-import-export.sh apply
```

---

## File Format

### Export File Structure

```json
{
  "version": "1.0.0",
  "exported_at": "2026-02-03T10:30:00Z",
  "source_system": {
    "hostname": "macbook-pro",
    "user": "username",
    "os": "darwin"
  },
  "learned_patterns": {
    "optimal_cache_threshold": 0.78,
    "optimal_concurrent_processes": 4,
    "best_performing_strategies": []
  },
  "cache_outcomes": {
    "samples": 150,
    "avg_hit_rate": 0.68,
    "threshold_adjustments": [
      {
        "timestamp": "2026-02-03T08:00:00Z",
        "parameter": "similarity_threshold",
        "old_value": "0.80",
        "new_value": "0.78",
        "reason": "Hit rate 45% below target 65%"
      }
    ]
  },
  "parallel_outcomes": {
    "samples": 98,
    "avg_success_rate": 92.5,
    "concurrent_adjustments": [
      {
        "timestamp": "2026-02-03T09:00:00Z",
        "parameter": "max_concurrent_processes",
        "old_value": "5",
        "new_value": "4",
        "reason": "Success rate 78% below target 90%"
      }
    ]
  },
  "total_learning_cycles": 42,
  "current_configs": {
    "cache_threshold": 0.78,
    "max_concurrent": 4
  }
}
```

---

## Best Practices

### When Exporting

1. **Export regularly** - Create backups of good patterns
2. **Export before major changes** - Save baseline before experiments
3. **Export successful tuning** - Capture good configurations
4. **Name files descriptively** - Use context in filename

### When Importing

1. **Always compare first** - Use `compare` command before importing
2. **Start conservative** - Use conservative merge by default
3. **Backup before replace** - The script does this automatically
4. **Apply after import** - Don't forget to apply to live configs
5. **Restart daemon** - Changes take effect after restart

### When Sharing

1. **Document context** - Note what workload the patterns are for
2. **Include metadata** - Export includes source system info
3. **Version control** - Keep patterns in git if sharing with team
4. **Review before applying** - Not all patterns work for all workloads

---

## Troubleshooting

### Import File Not Found

```
✗ Import file not found: ~/patterns.json
```

**Solution**: Check file path, use absolute path

### Invalid Import File

```
✗ Invalid import file
  Invalid JSON format
```

**Solution**: File is corrupted or not a valid export file

### No Patterns to Apply

```
No patterns to apply
```

**Solution**: Imported file has no learned patterns yet (need more samples)

### Daemon Not Picking Up Changes

**Solution**: Restart the daemon

```bash
launchctl unload ~/Library/LaunchAgents/com.claude.learning-daemon.plist
launchctl load ~/Library/LaunchAgents/com.claude.learning-daemon.plist
```

---

## Security & Privacy

### What's Included in Export

✅ **Included**:
- Learned optimal configurations
- Performance statistics (aggregated)
- Adjustment history (decisions made)
- System metadata (hostname, user, OS)

❌ **NOT Included**:
- Actual cache content
- Query text or responses
- Code or file contents
- Sensitive data
- Personal information

### Safe to Share

Export files are safe to share because they only contain:
- Configuration values (numbers)
- Performance metrics (aggregated statistics)
- Adjustment decisions (optimization choices)

No actual data or content is included.

---

## Advanced

### Automated Cross-Machine Sync

Set up automatic pattern sharing across machines:

```bash
#!/usr/bin/env bash
# sync-patterns.sh - Run via cron

SHARED_DIR="/mnt/shared/claude-patterns"
MACHINE_ID=$(hostname)

# Export local patterns
~/.claude/scripts/pattern-import-export.sh export \
  "$SHARED_DIR/$MACHINE_ID-patterns.json"

# Import from other machines (conservative merge)
for pattern_file in "$SHARED_DIR"/*-patterns.json; do
  if [[ "$pattern_file" != *"$MACHINE_ID"* ]]; then
    ~/.claude/scripts/pattern-import-export.sh import \
      "$pattern_file" conservative >/dev/null 2>&1
  fi
done

# Apply merged patterns
~/.claude/scripts/pattern-import-export.sh apply >/dev/null 2>&1
```

Add to crontab:

```bash
# Sync patterns daily at 2am
0 2 * * * /path/to/sync-patterns.sh
```

---

## Summary

The Pattern Import/Export system enables:

✅ **Knowledge Transfer** - Move learning between machines
✅ **Fast Bootstrap** - New machines start optimal
✅ **Team Collaboration** - Share best practices
✅ **Backup & Recovery** - Protect learned patterns
✅ **Experimentation** - Safe A/B testing

**Commands:**
- `export` - Create portable pattern file
- `import` - Merge patterns from file
- `compare` - Preview before importing
- `apply` - Activate imported patterns

**Result**: Much faster path to optimal performance on new systems!

---

*Last updated: 2026-02-03*
*Version: 1.0.0*
