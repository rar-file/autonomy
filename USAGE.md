# USAGE.md — Autonomy v2

## Quick Reference

### Task Management

```bash
# Create a task
autonomy task create "refactor-auth" "Refactor authentication to use JWT tokens"

# List all tasks
autonomy task list

# Mark as in-progress
autonomy task work "refactor-auth"

# Complete with proof
autonomy task complete "refactor-auth" "Tested: Login works, tokens refresh correctly"

# Delete task
autonomy task delete "refactor-auth"
```

### GitHub Integration

```bash
# Your open PRs
autonomy gh prs

# PRs waiting for your review  
autonomy gh reviews

# CI status
autonomy gh ci-status

# Check all GitHub status
autonomy gh status
```

### System Monitoring

```bash
# Quick health check
autonomy vm health

# Top CPU processes
autonomy vm top_cpu

# Docker containers
autonomy vm docker_ps

# Service status
autonomy vm service_status nginx
```

## OpenClaw Integration Examples

### Example 1: Heartbeat Checks

Add to your HEARTBEAT.md:

```markdown
## Autonomy Checks

- Run `autonomy check` to see if there are pending tasks
- Run `autonomy gh status` for GitHub overview
- Run `autonomy vm health` for system status
```

### Example 2: Cron Scheduling

```bash
# Check every 30 minutes
openclaw cron add --name autonomy-check \
  --schedule "*/30 * * * *" \
  --command "autonomy check --notify"

# Daily GitHub summary
openclaw cron add --name gh-daily \
  --schedule "0 9 * * *" \
  --command "autonomy gh status"
```

### Example 3: AI Uses Native Tools

Instead of custom sub-agents, the AI uses OpenClaw's `sessions_spawn`:

```json
{
  "tool": "sessions_spawn",
  "args": {
    "task": "Research OAuth2 best practices",
    "runtime": "subagent",
    "mode": "run"
  }
}
```

Instead of custom memory, use MEMORY.md:

```bash
# AI stores decision
echo "## Decision: Use JWT with 24h expiry" >> MEMORY.md

# Later, AI searches via memory_search
```

## Directory Structure

```
autonomy-v2/
├── SKILL.md          # Skill manifest
├── USAGE.md          # This file
├── autonomy          # Main CLI
├── tasks/            # Task JSON files
├── logs/             # Activity logs
└── config.json       # User config
```

## Migration from v1

If you were using Autonomy v1:

1. **Backup your tasks**: `cp -r autonomy/tasks autonomy-v2/tasks/`
2. **Stop the old daemon**: `autonomy off` (v1)
3. **Use OpenClaw cron** instead of `autonomy schedule`
4. **Use OpenClaw sessions** instead of `autonomy spawn`
5. **Remove old HEARTBEAT.md** if it was auto-generated

## Safety

- No daemon running in background
- No HEARTBEAT.md overwrite
- Uses OpenClaw native tools
- Manual approval for destructive actions
