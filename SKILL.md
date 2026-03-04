---
name: clawtonomy
description: "Full task management, AI dispatch, and system toolkit for OpenClaw agents. JSON tasks with sync to TASKS.md + HEARTBEAT.md, sub-agent dispatch, NL parsing, GitHub integration, VM health, file watching, personality editor, skill manager, and Flask web dashboard."
metadata:
  version: "3.5.0"
  user-invocable: true
  openclaw:
    skillKey: clawtonomy
    emoji: "🤖"
    homepage: https://github.com/rar-file/autonomy
    os:
      - linux
      - darwin
    requires:
      bins:
        - bash
        - jq
        - python3
        - git
        - gh
---

# ClawTonomy v3.5 — Task Management, AI Dispatch & System Toolkit

> **READ THIS ENTIRE DOCUMENT. If the user mentions tasks, clawtonomy, dashboard, system health, GitHub, or anything in this manifest — USE THIS SKILL. Do not ignore it. Do not say you can't do it. Do not invent your own task tracking. USE THIS.**

**Version:** 3.5.0
**Dashboard:** `http://localhost:8767`
**Task Files:** `tasks/` directory (one JSON file per task)
**Sync Targets:** `~/.openclaw/workspace/TASKS.md` + `~/.openclaw/workspace/HEARTBEAT.md`

---

## ⛔ MANDATORY RULES — NO EXCEPTIONS

1. **NEVER create your own task tracking.** This skill IS the task system. Use it.
2. **NEVER store tasks in memory, notes, or conversation.** Tasks go in `tasks/` as JSON via CLI or API.
3. **"Create a task"** → run `clawtonomy task create <name> <description> [priority]` or POST `/api/task/create`.
4. **"What are my tasks"** → run `clawtonomy task list` or GET `/api/tasks`.
5. **When you finish work** → run `clawtonomy task complete <name> "<proof>"`. Proof is MANDATORY. Describe what you actually did.
6. **Before starting work** → run `clawtonomy task work <name>` to set status to in_progress.
7. **After ANY task change** → run `clawtonomy task sync` or POST `/api/tasks/sync`. If you skip this, changes won't appear in TASKS.md or HEARTBEAT.md. The user will not see your work. DO NOT SKIP THIS.
8. **Start of every conversation** → check TASKS.md for active tasks. Acknowledge them. Ask if the user wants to work on any.
9. **During heartbeat** → read the ClawTonomy Tasks section of HEARTBEAT.md. Report status. Warn about overdue tasks.
10. **Complex work** → break into subtasks via POST `/api/tasks/<id>/subtask` with `{"name": "step description"}`.
11. **Parallel work** → dispatch to sub-agents via POST `/api/tasks/<id>/dispatch`.
12. **NEVER say "I don't have access to tasks" or "I can't manage tasks."** You have full CLI and API access.

---

## File Structure

```
clawtonomy               # Bash CLI entry point
web_ui.py                # Flask dashboard (port 8767)
watcher.py               # Watchdog file watcher
config.json              # Configuration
templates/index.html     # Dashboard UI
tasks/                   # JSON task files (one per task)
logs/                    # Watcher & suggestion logs
digests/                 # Generated digests
ab_tests/                # Personality A/B tests
state.json               # Persistent counters
history.json             # Event log (rolling 500)
watchers.json            # Watcher configs
```

---

## CLI Commands — USE THESE

### Task Management

```bash
clawtonomy task create <name> <description> [priority]   # Create task
clawtonomy task list                                      # List all tasks
clawtonomy task work <name>                               # Mark in_progress
clawtonomy task complete <name> "<proof>"                 # Complete with proof
clawtonomy task delete <name>                             # Delete task
clawtonomy task sync                                      # Sync to TASKS.md + HEARTBEAT.md
clawtonomy task dispatch <name>                           # Send to AI sub-agent
clawtonomy task status <name>                             # View task details
```

**Priority:** `low`, `medium` (default), `high`, `critical`

**Task fields:** id, name, description, status, priority, tags[], due_date, estimated_minutes, execution_mode, subtasks[], notes[], depends_on[], ai_dispatched, dispatch_session, proof, blocked_reason, created_at, updated_at, completed_at

**Status values:** `pending` → `in_progress` → `completed` | `blocked` | `cancelled` | `deferred`

### GitHub

```bash
clawtonomy gh prs              # Your open PRs
clawtonomy gh reviews          # PRs needing your review
clawtonomy gh ci-status        # Last 5 CI runs
clawtonomy gh notifications    # Unread notifications
clawtonomy gh issues           # Your open issues
clawtonomy gh status           # Summary
```

### VM / System

```bash
clawtonomy vm health           # CPU, memory, disk, load
clawtonomy vm process_list     # ps aux by CPU
clawtonomy vm top_cpu          # Top 10 CPU
clawtonomy vm top_memory       # Top 10 memory
clawtonomy vm disk             # df -h
clawtonomy vm memory           # free -h
clawtonomy vm load             # uptime
clawtonomy vm docker_ps        # Running containers
clawtonomy vm docker_images    # Docker images
clawtonomy vm service_list     # systemd services
clawtonomy vm service_status <name>
```

### File Watcher

```bash
clawtonomy watcher add <path> <command>
clawtonomy watcher remove <index>
clawtonomy watcher list
clawtonomy watcher start
```

### Health Check

```bash
clawtonomy check               # Check pending tasks, GitHub notifs, CI failures
clawtonomy check --notify      # Notification-friendly output
```

---

## API REFERENCE — COMPLETE

**Base:** `http://localhost:8767`

### Status

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/status` | Full system status |
| GET | `/api/state` | Persistent counters |
| GET | `/api/history` | Event log (`?limit=N`) |
| GET | `/api/context-window` | Token usage estimate |

### Tasks — CRUD

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/tasks` | — | List ALL tasks |
| POST | `/api/task/create` | `{name, description, priority?, tags?, due_date?, estimated_minutes?, execution_mode?, depends_on?}` | Create task |
| POST | `/api/tasks/<id>/status` | `{status, blocked_reason?, proof?}` | Change status |
| POST | `/api/tasks/<id>/update` | `{field: value, ...}` | Update any field |
| POST | `/api/tasks/<id>/complete` | `{proof}` | Complete (proof REQUIRED) |
| DELETE | `/api/tasks/<id>/delete` | — | Delete task |

### Tasks — Notes & Subtasks

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | `/api/tasks/<id>/notes` | `{text}` | Add progress note |
| POST | `/api/tasks/<id>/subtask` | `{name}` | Add subtask |
| POST | `/api/tasks/<id>/subtask/<idx>/toggle` | — | Toggle subtask done |
| DELETE | `/api/tasks/<id>/subtask/<idx>` | — | Remove subtask |

### Tasks — Dispatch & Sync

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | `/api/tasks/<id>/dispatch` | `{mode?: "agent" or "cron"}` | Send to AI sub-agent |
| POST | `/api/tasks/sync` | — | Sync to TASKS.md + HEARTBEAT.md |
| POST | `/api/tasks/parse` | `{text}` | NL text → structured task |
| GET | `/api/tasks/templates` | — | Pre-built task templates |
| GET | `/api/tasks/graph` | — | Dependency graph |

### Digests

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/digests` | — | List digests |
| POST | `/api/digests/generate` | `{type?, since?}` | Generate digest |

### Skills

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/skills/<name>` | — | Skill detail |
| POST | `/api/skills/<name>/toggle` | `{enabled: bool}` | Toggle skill |
| POST | `/api/skills/install` | `{repo}` | Install from ClawHub |
| POST | `/api/skills/request` | `{description}` | AI-generated skill |
| POST | `/api/skills/check-compat` | `{skill_name?, os?, bins?}` | Compatibility check |

### Personality Files

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | `/api/personality/<file>` | — | Read file |
| POST | `/api/personality/save` | `{file, content}` | Save (creates backup) |
| POST | `/api/personality/suggest` | `{file, suggestion}` | AI suggestion |
| GET | `/api/personality/history/<file>` | — | Version history |
| POST | `/api/personality/restore` | `{file, backup}` | Restore from backup |
| POST | `/api/personality/diff` | `{file, backup}` | Diff versions |
| POST | `/api/personality/ab-test` | `{file, variant_a, variant_b}` | A/B test |
| GET | `/api/personality/ab-tests` | — | List A/B tests |

### Webhooks

| Method | Path | Body | Description |
|--------|------|------|-------------|
| POST | `/api/webhook` | `{event, source, payload?, create_task?}` | Receive events |

---

## HOW TASKS SYNC TO OPENCLAW

OpenClaw has NO native task system. THIS skill is the task system. Here is the bridge:

1. **Tasks = JSON files** in `tasks/` directory.
2. **`sync_tasks_to_workspace()`** writes `~/.openclaw/workspace/TASKS.md` — markdown summary with status icons, priorities, due dates, subtasks, notes. OpenClaw reads this every conversation.
3. **`inject_tasks_into_heartbeat()`** injects task checklist into `HEARTBEAT.md` between `<!-- CLAWTONOMY-TASKS-START -->` and `<!-- CLAWTONOMY-TASKS-END -->` markers. Heartbeat reads this every 30 min.
4. **After ANY task change** → sync runs automatically via API. If using CLI, run `clawtonomy task sync` manually.

---

## DISPATCH — SUB-AGENT EXECUTION

POST `/api/tasks/<id>/dispatch` with `{mode: "agent"}` (default) or `{mode: "cron"}`.

- **Agent mode:** `openclaw agent --local --session-id clawtonomy-task-<id>-<ts> --message "<prompt>" --thinking low --timeout 300`
- **Cron mode:** `openclaw cron add --name task:<id> --at now --session isolated --message "<prompt>"`
- Task auto-set to `in_progress`, `ai_dispatched = true`
- Check dispatched tasks later to verify completion

---

## NL TASK PARSING

POST `/api/tasks/parse` with `{text: "Fix login bug by Friday #frontend !high ~45m"}`

Syntax: `#tag` → tag, `!high` → priority, `~30m`/`~2h` → time, `by March 10`/`by tomorrow`/`by next week` → due date

---

## TASK LIFECYCLE

```
pending → in_progress → completed
   ↓          ↓
 deferred   blocked → in_progress → completed
   ↓
 cancelled
```

1. Create → `pending`
2. Start work → `in_progress` (use `clawtonomy task work <name>`)
3. Add notes → POST `/api/tasks/<id>/notes`
4. Add subtasks → POST `/api/tasks/<id>/subtask`
5. Complete → `completed` with proof (use `clawtonomy task complete <name> "<proof>"`)
6. Block → `blocked` with reason
7. **SYNC AFTER EVERY STEP** → `clawtonomy task sync`

---

## TASK TEMPLATES

| Template | Priority | Tags | Time |
|----------|----------|------|------|
| Review PR | high | github, review | 30m |
| Fix Bug | high | bugfix, code | 60m |
| Write Tests | medium | testing, quality | 45m |
| Deploy | critical | devops, deploy | 20m |
| Update Docs | low | docs | 30m |
| Security Audit | critical | security, audit | 90m |
| Refactor Code | medium | refactor, code | 60m |
| System Check | medium | monitoring, ops | 15m |

---

## OpenClaw Integration

| Feature | Usage |
|---------|-------|
| TASKS.md | Written by ClawTonomy. Read every conversation. |
| HEARTBEAT.md | Task checklist injected between markers. Read every heartbeat. |
| `openclaw status --json` | Dashboard status |
| `openclaw agent --local` | Task dispatch, suggestions, skill requests |
| `openclaw cron add` | Scheduled checks, one-shot dispatch |
| Personality files | Full CRUD on SOUL.md, IDENTITY.md, USER.md, AGENTS.md, TOOLS.md, MEMORY.md |
| Skill discovery | Scans `$OPENCLAW_HOME/workspace/skills/*/SKILL.md` |

### Paths

```
OPENCLAW_HOME  = $OPENCLAW_HOME or ~/.openclaw
WORKSPACE_DIR  = $OPENCLAW_HOME/workspace
SKILLS_DIR     = $OPENCLAW_HOME/workspace/skills
CLAWTONOMY_DIR = skill directory
TASKS_DIR      = $CLAWTONOMY_DIR/tasks
```

---

## Configuration

`config.json`:

```json
{
  "version": "3.5.0",
  "limits": { "max_concurrent_tasks": 5, "daily_task_budget": 20 },
  "github": { "default_repo": null, "notify_on_ci_fail": true },
  "web_ui": { "port": 8767, "host": "127.0.0.1", "auto_refresh": 30 },
  "watcher": { "debounce_seconds": 2, "enabled": true },
  "webhook": { "enabled": true, "auto_create_tasks": true }
}
```

Env overrides: `OPENCLAW_HOME`, `CLAWTONOMY_WEB_PORT`, `CLAWTONOMY_HOST`, `CLAWTONOMY_DIR`, `WORKSPACE`

---

## Installation

```bash
bash install.sh                  # venv, deps, permissions
bash install.sh --enable-cron    # + register cron job
```

Requires: `flask>=3.0.0`, `watchdog>=4.0.0`
Platforms: Linux, macOS, WSL2 (not Windows native)

---

## Safety

- Web UI on 127.0.0.1 only
- Personality saves create backups
- Task JSON built with `jq -n --arg` (no injection)
- Agent spawns use `--timeout`
- History capped at 500 entries

## License

MIT