# Full Autonomy System

The complete autonomy system with all capabilities active in your OpenClaw workspace.

## Location

```
~/.openclaw/workspace/skills/autonomy/
├── SKILL.md              # Skill manifest (loaded by OpenClaw)
├── autonomy              # CLI tool
├── web_ui.py             # Web dashboard
├── watcher.py            # File watcher daemon
├── config.json           # User configuration
├── requirements.txt      # Python dependencies
├── state.json            # Persistent state (auto-created)
├── history.json          # Event history (auto-created)
├── watchers.json         # Watcher configs (auto-created)
├── tasks/                # Task JSON files
├── logs/                 # Activity logs
├── templates/            # Web UI templates
└── assets/               # SVG assets
```

## Capabilities

### 1. Task Management
- JSON-based task tracking with priority and dependency support
- Create, list, start, complete, delete tasks via CLI or web UI
- Priority levels: critical, high, medium, low
- Task dependencies (`depends_on`) for ordered execution
- Proof-of-completion required for task completion (anti-hallucination)

### 2. System Monitoring (VM Integration)
- CPU, memory, disk, and load average monitoring
- Process listing (top CPU/memory consumers)
- Docker container status
- Service status checks via systemctl
- Health alerts for threshold violations

### 3. GitHub Integration
- Open PR listing and CI status checks
- Review-requested PR tracking
- Unread notification counts
- Issue listing with label filtering
- CI failure alerts

### 4. File Watching
- Cross-platform file system monitoring via watchdog
- Configurable watch paths with custom trigger commands
- Debounced event handling
- Persistent watcher configuration in `watchers.json`
- Watcher event logging

### 5. Web Dashboard
- Real-time dashboard at `http://localhost:8767`
- Task management with create/complete actions
- Skills browser with enable/disable toggles and detail modals
- Personality file editor with AI-powered suggestions
- System health with progress ring visualizations
- GitHub stats overview
- Activity history and metrics timeline
- Alert notifications
- Dark theme with auto-refresh

### 6. Webhook Receiver
- HTTP endpoint for external event ingestion
- Auto-task-creation from webhook payloads
- Event recording to activity history
- Integrates with CI/CD, monitoring tools, GitHub webhooks

### 7. Persistent State & History
- Cross-run state tracking (`state.json`)
- Event history with 500-event rolling window
- Activity timeline in web UI
- Metrics: total events, tasks completed, checks run

## How It Works

1. **OpenClaw Cron** triggers `autonomy check` every 30 minutes
2. **CLI checks** for pending tasks, GitHub notifications, CI failures
3. **AI decides** what needs attention based on check results
4. **Tasks created** for issues found (stored in `tasks/`)
5. **Web dashboard** provides real-time visibility
6. **File watchers** trigger actions on source changes
7. **Webhooks** accept events from external services
8. **History tracked** for all events in `history.json`

## OpenClaw Integration

This skill uses OpenClaw's native tools:

- **Sub-agents**: `sessions_spawn` for delegated work
- **Memory**: `memory_search` / `memory_get` for context retrieval
- **Scheduling**: OpenClaw cron for periodic checks
- **Heartbeat**: Respects OpenClaw's native HEARTBEAT.md

## Safety Guards

- ✅ No background daemon — uses OpenClaw cron
- ✅ No HEARTBEAT.md overwrite — respects user's file
- ✅ Tasks start as "pending" (not auto-executed)
- ✅ Proof required for task completion
- ✅ Max concurrent task limits enforced
- ✅ Web UI binds to 127.0.0.1 by default
- ✅ Approval required for destructive actions
- ✅ Full audit trail in logs and history

## Manual Operation

```bash
# Create and manage tasks
autonomy task create "my-task" "Description" [priority]
autonomy task list
autonomy task work "my-task"
autonomy task complete "my-task" "Proof of completion"

# Check for issues
autonomy check --notify

# GitHub status
autonomy gh status

# System health
autonomy vm health

# File watchers
autonomy watcher add ./src "autonomy task create review-src 'Review source changes'"
autonomy watcher list
autonomy watcher start

# Start web dashboard
python3 web_ui.py
# Open http://localhost:8767
```

## Status

- **Version**: 3.1.0
- **Capabilities**: 7 active
- **Platforms**: Linux, macOS, Windows (WSL2)
- **Last Updated**: 2026-03-03
