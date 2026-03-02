# Autonomy v2 🤖

**OpenClaw-Native Task Management**

A lightweight, OpenClaw-native approach to agentic task management. Uses OpenClaw's built-in tools instead of reimplementing them.

## 🎯 Philosophy

**v1 (Old):** Reimplement everything in bash  
**v2 (This):** Use OpenClaw's native tools, add missing capabilities

## ✨ What's Different

| Feature | v1 | v2 |
|---------|-----|-----|
| Sub-agents | Custom bash spawning | `sessions_spawn` tool |
| Memory | Custom JSON system | `memory_search` / `memory_get` |
| Scheduling | Bash daemon (5 min) | OpenClaw cron |
| Heartbeat | Overwrites HEARTBEAT.md | Respects user's file |
| Token tracking | Custom counting | OpenClaw status |
| Lines of code | ~23,000 | ~2,000 |
| Complexity | High | Low |

## 🌐 Web Dashboard

Custom web UI with real-time data:

```bash
# Start the dashboard
python3 web_ui.py

# Open http://localhost:8767
```

**Features:**
- 📋 Live task list
- 📊 Token usage (from OpenClaw)
- 💻 System health monitoring
- 🎨 Dark theme with custom SVG assets
- 🔄 Auto-refresh every 30s

## 🚀 Quick Start

```bash
# Link to PATH
ln -s ~/.openclaw/workspace/skills/autonomy-v2/autonomy ~/bin/autonomy

# Create your first task
autonomy task create "learn-v2" "Understand the new autonomy system"

# Check GitHub
autonomy gh prs

# Monitor system
autonomy vm health
```

## 📋 Commands

### Task Management
```bash
autonomy task create "name" "description"   # Create task
autonomy task list                           # List all tasks
autonomy task work "name"                    # Mark in-progress
autonomy task complete "name" "proof"        # Mark complete
autonomy task delete "name"                  # Delete task
```

### GitHub
```bash
autonomy gh prs         # Your open PRs
autonomy gh reviews     # PRs waiting for review
autonomy gh ci-status   # CI status
autonomy gh status      # Quick overview
```

### System
```bash
autonomy vm health          # System health
autonomy vm process_list    # List processes
autonomy vm docker_ps       # Docker containers
autonomy vm service_status  # Check service
```

## 🔧 OpenClaw Integration

### Cron Scheduling (Not Daemon)

```bash
# Instead of a bash daemon, use OpenClaw cron:
openclaw cron add --name autonomy-check \
  --schedule "*/30 * * * *" \
  --command "autonomy check --notify"
```

### Native Sub-Agents

```json
{
  "tool": "sessions_spawn",
  "args": {
    "task": "Research topic",
    "runtime": "subagent"
  }
}
```

### Native Memory

```bash
# Store in MEMORY.md
echo "## Decision: Chose X" >> ~/.openclaw/workspace/MEMORY.md

# Retrieve via memory_search (semantic)
```

## 🛡️ Safety

- ✅ No background daemon
- ✅ No HEARTBEAT.md overwrite
- ✅ Uses OpenClaw's native scheduling
- ✅ Uses OpenClaw's memory system
- ✅ Uses OpenClaw's sub-agent spawning

## 📁 Structure

```
autonomy-v2/
├── SKILL.md       # Skill manifest for ClawHub
├── USAGE.md       # User documentation
├── README.md      # This file
├── autonomy       # Main CLI (bash)
├── tasks/         # Task JSON storage
├── logs/          # Activity logs
└── config.json    # User configuration
```

## 🔄 Migration from v1

1. Stop v1: `autonomy off`
2. Backup tasks: `cp autonomy/tasks/* autonomy-v2/tasks/`
3. Remove v1's HEARTBEAT.md (if auto-generated)
4. Use OpenClaw cron instead of `autonomy schedule`
5. Use `sessions_spawn` instead of `autonomy spawn`

## 📄 License

MIT
