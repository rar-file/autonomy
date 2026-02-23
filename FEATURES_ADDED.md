# Core Missing Features - Implementation Complete

This document describes the four core missing features that have been implemented in the autonomy skill.

## Features Added

### 1. --dry-run Mode for All Actions

All action commands now support `--dry-run` (or `-n`) flag to preview what would happen without making changes.

**Supported actions:**
- `autonomy action stash <repo> --dry-run`
- `autonomy action commit <repo> --dry-run`
- `autonomy action push <repo> --dry-run`
- `autonomy action sync <repo> --dry-run`

**What it shows:**
- Stash: The stash name that would be created
- Commit: Files that would be committed and the suggested message
- Push: Branch and number of unpushed commits
- Sync: Number of commits that would be fast-forwarded

**Example:**
```bash
$ autonomy action commit . --dry-run
[DRY RUN] Would execute: git add -A && git commit -m "Update README.md"
  Files to be committed:
   M README.md
   A new_file.txt
```

---

### 2. Undo System

Track and undo recent actions with `autonomy undo`.

**Supported undo operations:**
| Action | Undo Command | What Happens |
|--------|--------------|--------------|
| commit | `git reset --soft HEAD~1` | Commit undone, changes staged |
| stash | `git stash pop` | Stash restored to working directory |
| sync | N/A (warns user) | Fast-forward cannot be cleanly undone |
| push | N/A (warns user) | Push cannot be undone (remote history) |

**How it works:**
- Last action is tracked in `state/last_action.json`
- Actions record whether they are `undoable`
- Push and other irreversible actions are marked `undoable: false`

**Example:**
```bash
$ autonomy action commit .
Committed in myproject: Update README.md

$ autonomy undo
Undoing: commit
Target: /home/user/myproject
Details: Update README.md

→ Running: git reset --soft HEAD~1
✓ Commit undone. Changes are now staged.
```

**Push undo warning:**
```bash
$ autonomy undo
✗ Cannot undo: push
   Push cannot be undone (commits are now on remote)
   To revert: use 'git revert' or force-push (use with caution)
```

---

### 3. Work Hours / Quiet Mode Configuration

Configure work hours to suppress non-critical alerts outside business hours.

**Configuration:**
```bash
# Set work hours (24-hour format)
autonomy config work-hours 09:00-18:00

# View current setting
autonomy config work-hours

# Show status
autonomy status
# Shows: Work hours: 09:00-18:00 (currently active) or (currently quiet mode)
```

**Behavior:**
- Alerts marked as `critical` are always shown
- Non-critical alerts (low, medium, high severity) are suppressed outside work hours
- Status command shows whether currently in work hours or quiet mode
- Configuration stored in `config.json` as `global_config.work_hours`

**Implementation:**
- `is_within_work_hours()` - checks if current time is within configured hours
- `should_skip_alert(severity)` - determines if alert should be suppressed

---

### 4. Auto-Context Detection on cd

Shell hook that detects when entering project directories and notifies the user.

**Setup:**
```bash
# Automatic setup (adds to .bashrc or .zshrc)
source /root/.openclaw/workspace/skills/autonomy/cd_hook.sh
autonomy_setup_cd_hook

# Or manual setup - add to ~/.bashrc or ~/.zshrc:
export AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
source $AUTONOMY_DIR/cd_hook.sh
PROMPT_COMMAND="autonomy_cd_hook; ${PROMPT_COMMAND}"
```

**Features:**
- Detects when `cd` into a project directory defined in contexts
- Shows notification with context name
- Reminds user to run `autonomy on <context>` to enable monitoring
- Tracks last detected context to avoid spam
- Optional auto-enable via `global_config.auto_enable_context: true`

**Example notification:**
```bash
cd ~/myproject

[autonomy] Entered project context: myproject
[autonomy] Run 'autonomy on myproject' to enable monitoring
```

**Manual check:**
```bash
autonomy_detect_context
# or after sourcing cd_hook.sh:
autonomy_check_context
```

---

## Files Modified/Created

| File | Action | Description |
|------|--------|-------------|
| `actions.sh` | Modified | Added `--dry-run` support and action tracking |
| `autonomy` | Modified | Added `cmd_undo()` and `cmd_config()` functions, work hours helpers |
| `config.json` | Modified | Added `work_hours` and `quiet_mode_enabled` to global_config |
| `cd_hook.sh` | Created | Shell hook for auto-context detection on cd |
| `FEATURES_ADDED.md` | Created | This documentation file |

---

## State Files

The following state files are used by these features:

| File | Purpose |
|------|---------|
| `state/last_action.json` | Tracks the last action for undo system |
| `state/last_auto_context` | Tracks last auto-detected context (cd hook) |

---

## Configuration Schema Update

```json
{
  "global_config": {
    "work_hours": "09:00-18:00",
    "quiet_mode_enabled": true,
    "auto_enable_context": false
  }
}
```

---

## Quick Reference

```bash
# Dry run (preview before doing)
autonomy action commit . --dry-run

# Undo last action
autonomy undo

# Set work hours
autonomy config work-hours 09:00-18:00

# Setup auto-context detection
source /path/to/cd_hook.sh
autonomy_setup_cd_hook
```

---

## Implementation Notes

1. **Dry-run**: Actions check `$DRY_RUN` variable and print `[DRY RUN]` message instead of executing git commands

2. **Undo system**: Each action calls `record_action()` or `mark_not_undoable()`. `cmd_undo()` reads `last_action.json` and executes appropriate git command.

3. **Work hours**: `is_within_work_hours()` converts times to minutes since midnight for easy comparison. Only affects alert display, not background checks.

4. **Auto-context**: `autonomy_cd_hook()` is called via `PROMPT_COMMAND` on every prompt. It compares `$PWD` to stored contexts and shows notification when entering a project directory.
