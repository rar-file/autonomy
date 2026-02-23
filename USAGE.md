# Autonomy System - Usage Guide

## What's Been Built

### Core System
- **Context-aware monitoring** - Not generic checks, project-specific intelligence
- **Smart actions** - Auto-stash, quick-commit, push suggestions
- **Discord integration** - Real-time status with slash commands
- **Adaptive frequency** - Slows down when idle, speeds up when active

### Current Contexts

| Context | Type | Use Case |
|---------|------|----------|
| `git-aware` | Smart | Prevents lost work, keeps repos clean |
| `webapp` | Standard | Web app monitoring |
| `business` | Standard | Business ops tracking |
| `default` | Standard | General workspace |

## Quick Start

### 1. Check Status
```bash
./skills/autonomy/autonomy status
```

### 2. Enable Git-Aware Monitoring
```bash
./skills/autonomy/autonomy on git-aware
```

### 3. Smart Actions
```bash
# Auto-commit with generated message
./skills/autonomy/autonomy action commit .

# Stash before switching contexts  
./skills/autonomy/autonomy action stash ~/myproject

# Push current branch
./skills/autonomy/autonomy action push .

# Sync with remote (fast-forward only)
./skills/autonomy/autonomy action sync .
```

### 4. Discord Commands
Type in Discord:
- `/autonomy` - Show current status
- `/autonomy_on git-aware` - Enable git monitoring
- `/autonomy_off` - Disable
- `/autonomy_contexts` - List available contexts

## Git-Aware Features

### What It Monitors
1. **Dirty repo warning** - Alerts if uncommitted changes sit >2 hours
2. **Stale commit reminder** - Warns if commits unpushed >1 hour  
3. **Unpushed branch check** - Flags branches not pushed in >24 hours
4. **Branch sync status** - Alerts if behind remote
5. **Stash reminder** - Warns about forgotten stashes >3 days old

### Smart Behaviors
- **Context switch protection** - Warns before switching with dirty repos
- **Auto-suggest commit messages** - Based on changed files
- **Intelligent timing** - Checks more frequently when you're active

## Making It Useful (Not Silly)

### Current Problem with Most Automation
- Runs on schedule regardless of need
- Alerts for things you don't care about
- No learning or adaptation

### This System's Approach
1. **Trigger-based, not schedule-based**
   - Checks run when files change
   - Alerts when thresholds crossed (not every 20 min)
   - Quiet when nothing's happening

2. **Action-oriented, not alert-oriented**
   - "Stash these changes before you switch?" not "You have changes"
   - "Commit with message 'Update config'?" not "Uncommitted files detected"
   - Auto-fix when safe, suggest when uncertain

3. **Learning mode** (next phase)
   - Tracks which alerts you actually act on
   - Disables noisy checks
   - Learns your schedule (no 3am alerts)

## Test It Out

### Scenario 1: The Forgotten Commit
```bash
# Edit some files
echo "changes" >> README.md

# Wait 2+ hours...
# Autonomy will alert: "2 hours of uncommitted changes on master"

# Quick fix:
./skills/autonomy/autonomy action commit .
```

### Scenario 2: Context Switch Protection
```bash
# Working on feature branch with changes
echo "feature code" >> feature.txt

# Try to switch contexts:
./skills/autonomy/autonomy on webapp

# Autonomy warns: "You have uncommitted changes. Stash first?"
./skills/autonomy/autonomy action stash .
```

### Scenario 3: End of Day
```bash
# Autonomy detects EOD pattern
# Checks: commits unpushed, uncommitted changes, stashes
# Alerts with actionable suggestions
```

## Next Enhancements

### Phase 2: Learning
```bash
autonomy learn on
# Adapts to your patterns, disables noise
```

### Phase 3: Predictive
```bash
# "You're about to deploy, run tests first?"
# "That file usually causes bugs, extra careful?"
```

### Phase 4: Integration
- GitHub PR status
- Test results
- Deployment status
- Error tracking

## Configuration

Edit context configs:
```bash
./skills/autonomy/contexts/git-aware.json
```

Adjust thresholds:
```json
{
  "config": {
    "dirty_warning_threshold": 7200,  // 2 hours
    "stale_commit_threshold": 3600,   // 1 hour
    "auto_suggest_commit": true
  }
}
```

## Current Status

- ✅ Discord bot running (PID: 197560)
- ✅ Git-aware context enabled
- ✅ Smart actions working
- ✅ Slash commands active
- 🔄 Learning mode: pending

**Try it:** Make some changes to files, wait a bit, see what autonomy suggests.
