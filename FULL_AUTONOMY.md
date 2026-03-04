# Full Autonomy System v3.5

The complete autonomy system — task management, AI dispatch, sub-agent orchestration, and system monitoring for OpenClaw.

## How It Works

1. **User creates tasks** via CLI (`autonomy task create`), web dashboard (`localhost:8767`), or natural language parsing.
2. **Tasks are JSON files** in `tasks/` — one file per task with full metadata (priority, tags, subtasks, notes, due dates, etc.).
3. **Sync writes TASKS.md** to `~/.openclaw/workspace/` — the AI reads this every conversation.
4. **Sync injects into HEARTBEAT.md** — the AI's heartbeat loop checks tasks every 30 minutes.
5. **Sync writes AGENTS.md** — permanent instructions that tell the AI EXACTLY how to use the task system.
6. **AI dispatch** sends tasks to sub-agents via `openclaw agent --local` or as cron jobs.
7. **Web dashboard** provides real-time visibility at `http://localhost:8767`.

## Why Tasks Used to Fail

OpenClaw has **NO native task system**. Previously, tasks were JSON files the AI never read. The AI only reads:
- Workspace files (`TASKS.md`, `HEARTBEAT.md`, `AGENTS.md`, `MEMORY.md`, etc.)
- SKILL.md manifests
- HEARTBEAT.md during heartbeat loops

The fix: **sync tasks INTO those files** so the AI can't miss them.

## Location

```
~/.openclaw/workspace/skills/autonomy/
├── SKILL.md              # Skill manifest with full API reference + rules
├── autonomy              # CLI tool (bash)
├── web_ui.py             # Flask dashboard
├── watcher.py            # File watcher daemon
├── config.json           # User configuration
├── requirements.txt      # Python deps
├── templates/index.html  # Dashboard UI
├── tasks/                # Task JSON files
├── logs/                 # Activity logs
├── digests/              # Generated digests
├── ab_tests/             # Personality A/B tests
├── state.json            # Persistent counters
├── history.json          # Event log (rolling 500)
└── watchers.json         # Watcher configs
```

## Files Written to OpenClaw Workspace

| File | What | When |
|------|------|------|
| `~/.openclaw/workspace/TASKS.md` | Full task list with status, priorities, subtasks, notes | Every sync |
| `~/.openclaw/workspace/HEARTBEAT.md` | Task checklist section (between markers) | Every sync |
| `~/.openclaw/workspace/AGENTS.md` | Mandatory instructions for AI (between markers) | Every sync + startup |

## Capabilities

### 1. Task Management (Full Lifecycle)
- Create, list, start, complete, delete, block, defer, cancel
- Priority levels: critical, high, medium, low
- Tags, due dates, time estimates
- Subtasks with toggle completion
- Notes for progress tracking
- Task dependencies (`depends_on`)
- Proof-of-completion required (anti-hallucination)
- Natural language parsing: `"Fix auth bug by Friday #security !high ~60m"`
- 8 pre-built templates

### 2. AI Dispatch (Sub-Agent Execution)
- Send tasks to AI sub-agents via `openclaw agent --local`
- Register one-shot cron jobs via `openclaw cron add`
- Task prompt includes name, description, priority, subtasks, notes
- Auto-sets task to in_progress + ai_dispatched
- Session tracking with unique IDs

### 3. Workspace Sync (THE CRITICAL BRIDGE)
- Writes TASKS.md — AI reads this every conversation
- Injects into HEARTBEAT.md — AI reads this every 30min heartbeat
- Writes AGENTS.md instructions — permanent rules for the AI
- Auto-syncs after every API mutation
- Manual sync via CLI: `autonomy task sync`

### 4. System Monitoring
- CPU, memory, disk, load average
- Top processes by CPU/memory
- Docker container status
- Service status via systemctl
- Health alerts for threshold violations

### 5. GitHub Integration
- Open PRs, review-requested PRs, CI status
- Unread notifications, issues
- CI failure alerts

### 6. File Watching
- Watchdog-based file monitoring
- Custom trigger commands with placeholders
- Debounced events, persistent config

### 7. Web Dashboard
- Real-time at `http://localhost:8767`
- Task CRUD with modal forms
- Quick-add bar with NL parsing
- Task dispatch to AI
- Skill browser with enable/disable
- Personality editor with AI suggestions, A/B testing, version history
- System health with progress rings
- GitHub stats, alerts, activity history
- Dark theme, fully responsive

### 8. Webhook Receiver
- HTTP endpoint for external events
- Auto-task creation from payloads
- CI/CD integration

### 9. Personality Management
- Full CRUD on SOUL.md, IDENTITY.md, USER.md, AGENTS.md, TOOLS.md, MEMORY.md
- AI-powered rewrite suggestions
- A/B testing between personality variants
- Version history with restore and diff

### 10. Skill Management
- Browse installed OpenClaw skills
- Enable/disable skills
- Install from ClawHub registry
- AI-generated skill creation
- Compatibility checking

## OpenClaw Integration

| Feature | How |
|---------|-----|
| `TASKS.md` | Written by autonomy — read every conversation |
| `HEARTBEAT.md` | Injected with task checklist — read every heartbeat |
| `AGENTS.md` | Injected with mandatory instructions — read on session start |
| `openclaw agent --local` | Sub-agent dispatch |
| `openclaw cron add` | Scheduled checks + one-shot dispatch |
| `openclaw status --json` | Dashboard status |
| `sessions_spawn` | Parallel task execution |
| `memory_search` / `memory_get` | Context retrieval |
| Personality files | Full CRUD |
| Skill discovery | Scans workspace/skills/*/SKILL.md |

## Safety

- No background daemon — uses OpenClaw cron
- No HEARTBEAT.md overwrite — uses markers to inject/replace only autonomy section
- No AGENTS.md overwrite — uses markers to inject/replace only autonomy section
- Tasks start as "pending" (not auto-executed)
- Proof required for completion
- Max concurrent task limits enforced
- Web UI binds to 127.0.0.1 by default
- Full audit trail in history.json

## Quick Start

```bash
bash install.sh --enable-cron    # Install + enable 30-min cron check
python3 web_ui.py                # Start dashboard (auto-syncs on startup)
autonomy task create "my-task" "Description here" high
autonomy task sync               # Push to TASKS.md + HEARTBEAT.md + AGENTS.md
```

## Status

- **Version**: 3.5.0
- **Capabilities**: 10 active
- **Platforms**: Linux, macOS, WSL2
- **Dashboard**: http://localhost:8767