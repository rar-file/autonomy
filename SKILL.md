````skill
---
name: autonomy-v2
description: >-
  Lightweight task management and system toolkit for OpenClaw agents.
  JSON-based tasks with priority, file watching via watchdog, webhook receiver,
  GitHub integration, VM diagnostics, and a Flask web dashboard.
version: 3.1.0
user-invocable: true
metadata:
  openclaw:
    skillKey: autonomy-v2
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

# Autonomy v3.1 — Task Management & System Toolkit

**Version:** 3.1.0
**Type:** Task Management · GitHub · VM · File Watching · Web Dashboard
**Stack:** Bash CLI + Python (Flask) + Single-page HTML dashboard

---

## File Structure

```
autonomy/             # Bash CLI (main entry point)
web_ui.py             # Flask web dashboard (port 8767)
watcher.py            # Watchdog-based file watcher
config.json           # User configuration
requirements.txt      # Python deps (flask, watchdog)
install.sh            # Installer (venv, deps, optional cron)
templates/
  index.html          # Single-page dashboard (dark theme)
assets/
  *.svg               # Logo and diagram assets
tasks/                # Created at runtime — JSON task files
logs/                 # Created at runtime — watcher & suggestion logs
state.json            # Created at runtime — persistent counters
history.json          # Created at runtime — event log (rolling 500)
watchers.json         # Created at runtime — watcher configurations
```

---

## CLI Reference (`autonomy`)

All commands are implemented in the `autonomy` bash script.

### Task Management

```bash
autonomy task create <name> <description> [priority]
autonomy task list
autonomy task work <name>
autonomy task complete <name> <proof>
autonomy task delete <name>
```

- Tasks stored as individual JSON files in `tasks/`
- Priority: `low`, `medium` (default), `high`, `critical`
- Each task has: `id`, `name`, `description`, `status`, `priority`, `depends_on`, `created_at`, `updated_at`, `completed_at`, `proof`
- Task creation uses `jq -n` for safe JSON building (no shell injection)

### GitHub Integration

Requires `gh` CLI authenticated.

```bash
autonomy gh prs              # Your open PRs
autonomy gh reviews          # PRs needing your review
autonomy gh ci-status        # Last 5 CI runs
autonomy gh notifications    # Unread notifications
autonomy gh issues           # Your open issues
autonomy gh status           # Summary (PR count + review count)
```

### VM / System Diagnostics

```bash
autonomy vm health           # CPU, memory, disk, load summary
autonomy vm process_list     # ps aux sorted by CPU
autonomy vm top_cpu          # Top 10 CPU processes
autonomy vm top_memory       # Top 10 memory processes
autonomy vm disk             # df -h
autonomy vm memory           # free -h
autonomy vm load             # uptime
autonomy vm docker_ps        # Running containers
autonomy vm docker_images    # Docker images
autonomy vm service_list     # systemd running services
autonomy vm service_status <name>  # Status of a specific service
```

### File Watcher

Delegates to `watcher.py` (requires `watchdog`).

```bash
autonomy watcher add <path> <command>   # Add a watcher
autonomy watcher remove <index>         # Remove by index
autonomy watcher list                   # List configured watchers
autonomy watcher start                  # Start watching (foreground, blocking)
```

- Watcher configs stored in `watchers.json`
- Commands support `{file}` and `{event}` placeholders
- Events are debounced (default 2s, configurable in `config.json`)
- Logs written to `logs/watcher.log`

### Health Check

```bash
autonomy check               # Check for pending tasks, GitHub notifs, CI failures
autonomy check --notify      # Same, with notification-friendly output
```

---

## Web Dashboard (`web_ui.py`)

Flask server on port **8767**, bound to **127.0.0.1** by default.

```bash
python3 web_ui.py
# or with env overrides:
AUTONOMY_WEB_PORT=9000 AUTONOMY_HOST=0.0.0.0 python3 web_ui.py
```

### Dashboard Pages

| Page | What it shows |
|------|--------------|
| Dashboard | Task counts, GitHub summary, system health, OpenClaw status |
| Tasks | Full task list with create/complete actions |
| Alerts | Auto-generated alerts (pending task backlog, GitHub notifs, CI failures) |
| Skills | Installed OpenClaw skills — view detail, toggle enable/disable |
| Personality | SOUL.md, IDENTITY.md, USER.md, etc. — view/edit, AI-powered suggestions |
| Logs | Recent journalctl entries for the `openclaw` service |
| System | CPU, memory, disk, load, top processes, Docker containers |
| GitHub | PRs, reviews, notifications, CI status |
| History | Activity timeline, event stats (tasks created, webhooks received, checks run) |

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/status` | Full status JSON (tasks, skills, health, github, alerts, etc.) |
| `GET` | `/api/tasks` | All tasks |
| `POST` | `/api/task/create` | Create task `{name, description, priority?, depends_on?}` |
| `POST` | `/api/tasks/<id>/complete` | Complete task `{proof}` |
| `GET` | `/api/skills/<name>` | Skill detail (version, files, readme, SKILL.md content) |
| `POST` | `/api/skills/<name>/toggle` | Enable/disable `{enabled: bool}` |
| `POST` | `/api/skills/install` | Install from ClawHub `{repo}` |
| `POST` | `/api/skills/request` | AI skill request — spawns `openclaw agent` `{description}` |
| `GET` | `/api/personality/<file>` | Read personality file content |
| `POST` | `/api/personality/save` | Save personality file `{file, content}` (creates timestamped backup) |
| `POST` | `/api/personality/suggest` | AI suggestion — spawns `openclaw agent --local` `{file, suggestion}` |
| `POST` | `/api/webhook` | Receive external events `{event, source, payload?, create_task?}` |
| `GET` | `/api/history` | Event history (rolling 500, `?limit=N`) |
| `GET` | `/api/state` | Persistent state (check_count, daily_tasks_created) |

### Webhook Details

The `/api/webhook` endpoint accepts:

```json
{
  "event": "deploy",
  "source": "ci",
  "payload": {},
  "create_task": {
    "name": "verify-deploy",
    "description": "Verify deployment succeeded",
    "priority": "high",
    "depends_on": []
  }
}
```

When `create_task` is present and `webhook.auto_create_tasks` is enabled in config, a task JSON file is created automatically.

---

## Watcher Module (`watcher.py`)

Standalone Python script using the `watchdog` library. Can be run directly or via the CLI.

```bash
python3 watcher.py start               # Start all enabled watchers
python3 watcher.py add ./src "echo changed"
python3 watcher.py remove 0
python3 watcher.py list
```

- `AutonomyEventHandler` — debounced handler for `on_modified` and `on_created`
- Skips directory events
- Placeholder substitution: `{file}` → changed file path, `{event}` → `modified` / `created`
- Debounce interval from `config.json` → `watcher.debounce_seconds` (default 2)
- Watchers persisted in `watchers.json`, each with `path`, `command`, `enabled`, `created_at`

---

## Installation

```bash
bash install.sh                  # Create venv, install deps, set permissions
bash install.sh --enable-cron    # Also register OpenClaw cron job
```

What `install.sh` does:

1. Detects platform (Linux / macOS / WSL2 via `/proc/version`)
2. Checks for required binaries (`jq`, `python3`, `git`, `gh`)
3. Creates Python venv at `./venv/` and installs from `requirements.txt`
4. Falls back to global pip install if venv creation fails
5. Creates `tasks/` and `logs/` directories
6. Sets execute permissions on `autonomy`, `web_ui.py`, `watcher.py`
7. Creates default `config.json` if missing
8. With `--enable-cron`: registers `openclaw cron add --name autonomy-check --schedule "*/30 * * * *"`

### Python Dependencies

Managed via `requirements.txt`:

- `flask>=3.0.0,<4.0.0` — web dashboard server
- `watchdog>=4.0.0,<5.0.0` — file system watcher

### Platform Notes

- **Linux** — fully supported
- **macOS (darwin)** — fully supported; `free` / `systemctl` commands degrade gracefully
- **WSL2** — detected automatically; fully functional
- **Windows native** — not supported (bash CLI requires a POSIX shell)

---

## OpenClaw Integration Points

This skill uses the following OpenClaw features when available:

| Feature | How it's used |
|---------|--------------|
| `openclaw status --json` | Dashboard fetches session info via `get_openclaw_status()` |
| `openclaw agent --local` | Personality suggestions and skill requests spawn a local agent |
| `openclaw cron add` | Optional scheduled health checks via `install.sh --enable-cron` |
| `clawhub install` | Install skills from ClawHub registry via web UI |
| Personality files | Reads/writes `SOUL.md`, `IDENTITY.md`, `USER.md`, `AGENTS.md`, `TOOLS.md`, `MEMORY.md` from workspace |
| Skill discovery | Scans `$OPENCLAW_HOME/workspace/skills/*/SKILL.md` for installed skills |

### Path Resolution

```
OPENCLAW_HOME  = $OPENCLAW_HOME or ~/.openclaw
WORKSPACE_DIR  = $OPENCLAW_HOME/workspace
SKILLS_DIR     = $OPENCLAW_HOME/workspace/skills
AUTONOMY_DIR   = directory containing this skill's files
```

---

## Configuration

`config.json` (created by `install.sh` or on first CLI run):

```json
{
  "version": "3.1.0",
  "limits": {
    "max_concurrent_tasks": 5,
    "daily_task_budget": 20
  },
  "github": {
    "default_repo": null,
    "notify_on_ci_fail": true
  },
  "web_ui": {
    "port": 8767,
    "host": "127.0.0.1",
    "auto_refresh": 30
  },
  "watcher": {
    "debounce_seconds": 2,
    "enabled": true
  },
  "webhook": {
    "enabled": true,
    "auto_create_tasks": true
  }
}
```

Environment variable overrides:

- `OPENCLAW_HOME` — base OpenClaw directory (default `~/.openclaw`)
- `AUTONOMY_WEB_PORT` — web UI port (default `8767`)
- `AUTONOMY_HOST` — web UI bind address (default `127.0.0.1`)
- `AUTONOMY_DIR` — skill directory override (CLI only)
- `WORKSPACE` — workspace directory override (CLI only)

---

## Safety Notes

- Web UI binds to `127.0.0.1` by default (not exposed to network)
- Personality file saves create timestamped backups in `workspace/backups/`
- Personality file access limited to a hardcoded safe list of filenames
- Task JSON built with `jq -n --arg` in the CLI (no shell injection)
- Agent spawns use `--timeout` to prevent runaway processes
- History log capped at 500 entries (rolling window)

## License

MIT

````
