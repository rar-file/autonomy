---
name: autonomy-v2
description: >-
  Lightweight task management for OpenClaw agents. 
  Uses native OpenClaw tools for sub-agents, memory, and scheduling.
  Keeps VM diagnostics, file watching, and GitHub integration.
version: 3.0.0
user-invocable: true
metadata:
  openclaw:
    skillKey: autonomy-v2
    emoji: "🤖"
    homepage: https://github.com/rar-file/autonomy
    os:
      - linux
      - macos
    requires:
      bins:
        - bash
        - jq
        - python3
        - git
        - gh
        - flask  # for web UI
---

# Autonomy v2 — OpenClaw-Native Task Management

**Version:** 3.0.0  
**Type:** Task Management + System Capabilities  
**Philosophy:** Use OpenClaw's native tools, add what's missing

## What's Different from v1

| v1 (Old) | v2 (This) |
|----------|-----------|
| Custom sub-agent spawning | Uses `sessions_spawn` |
| Custom memory system | Uses `memory_search` / `memory_get` |
| Overwrites HEARTBEAT.md | Uses OpenClaw cron for scheduling |
| Bash daemon (5 min loop) | OpenClaw native cron |
| Token tracking | Uses OpenClaw status |
| ~23k lines of bash | ~2k lines, focused |

## What It Does

### 1. Task Management
Simple JSON-based task tracking that OpenClaw agents can read/write:

```bash
autonomy task create "fix-auth" "Fix authentication bug in login flow"
autonomy task list                    # Show all tasks
autonomy task work "fix-auth"         # Mark as in-progress
autonomy task complete "fix-auth" "Tested: login works with OAuth"
```

### 2. System Capabilities (VM Integration)
Direct system access for diagnostics and monitoring:

```bash
autonomy vm process_list              # List processes
autonomy vm top_cpu                   # CPU hogs
autonomy vm docker_ps                 # Container status
autonomy vm service_status nginx      # Check service
```

### 3. GitHub Integration
GitHub checks and PR management:

```bash
autonomy gh prs                       # Your open PRs
autonomy gh reviews                   # PRs waiting for your review
autonomy gh ci-status                 # CI status on default branch
autonomy gh issues --label bug        # Issues labeled 'bug'
```

### 4. Web Dashboard
Real-time web UI showing tasks, token usage from OpenClaw, and system health:

```bash
python3 web_ui.py              # Start dashboard
# Open http://localhost:8767
```

Features:
- Live task list with status
- Token usage from OpenClaw sessions
- System health (CPU, memory, disk, load)
- Auto-refresh every 30 seconds
- Dark theme with SVG assets

### 5. File Watching
Monitor files and trigger OpenClaw actions:

```bash
autonomy watcher add ./src "autonomy task create 'review-changes'"
```

## OpenClaw Integration

### Native Sub-Agents
Instead of bash sub-processes, use OpenClaw's `sessions_spawn`:

```json
{
  "tool": "sessions_spawn",
  "args": {
    "task": "Research OAuth2 flows",
    "runtime": "subagent",
    "mode": "run"
  }
}
```

### Native Memory
Store context in MEMORY.md, retrieve via semantic search:

```bash
# AI stores decision
echo "## Decision: Chose JWT over session tokens" >> MEMORY.md

# AI retrieves via memory_search
```

### Native Scheduling
Use OpenClaw cron instead of bash daemon:

```bash
openclaw cron add --name autonomy-check \
  --schedule "*/30 * * * *" \
  --command "autonomy check --notify"
```

## Quick Start

```bash
# Install
ln -s ~/.openclaw/workspace/skills/autonomy-v2/autonomy ~/bin/autonomy 2>/dev/null || true

# Create a task
autonomy task create "refactor-auth" "Refactor auth to use JWT"

# Check system
autonomy vm health

# Check GitHub
autonomy gh prs
```

## Safety Guards

- **No HEARTBEAT.md overwrite** — respects user's file
- **No daemon** — uses OpenClaw cron
- **No custom memory** — uses OpenClaw semantic search
- **Approval required** for: external APIs, messages, git push, deletions

## Configuration

Edit `config.json`:

```json
{
  "limits": {
    "max_concurrent_tasks": 5,
    "daily_task_budget": 20
  },
  "github": {
    "default_repo": null,
    "notify_on_ci_fail": true
  }
}
```

## License
MIT
