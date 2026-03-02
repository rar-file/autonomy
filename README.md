# Agentic Autonomy for OpenClaw

<p align="center">
  <img src="assets/logo-banner.svg" alt="Autonomy" width="600">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0.0-blue.svg" alt="Version 3.0.0">
  <img src="https://img.shields.io/badge/mode-agentic-green.svg" alt="Mode: Agentic">
  <img src="https://img.shields.io/badge/status-active-brightgreen.svg" alt="Status: Active">
</p>

<p align="center">
  <b>AI-driven self-improving autonomy system for OpenClaw.</b><br>
  The AI decides what to do, creates its own tasks, and improves itself — with safety guards to prevent runaway usage.
</p>

---

<p align="center">
  <img src="assets/diagram-workflow.svg" alt="Workflow" width="700">
</p>

---

## What's New in v3

**Complete rewrite using OpenClaw native tools:**

| Feature | v1 (Old) | v3 (This) |
|---------|----------|-----------|
| Custom sub-agent spawning | ✅ `sessions_spawn` tool |
| Custom memory system | ✅ `memory_search` / `memory_get` |
| Overwrites HEARTBEAT.md | ✅ Respects your file |
| Bash daemon (5 min loop) | ✅ OpenClaw cron |
| ~23k lines of bash | ✅ ~500 lines, focused |

---

## Quick Start

```bash
# Clone to your OpenClaw skills directory
cd "${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills"
git clone https://github.com/rar-file/autonomy.git

# Run install script
cd autonomy
bash install.sh

# Start using
autonomy task create "my-first-task" "Explore the autonomy system"
autonomy task list

# Start the web dashboard
python3 web_ui.py
# Open http://localhost:8767
```

---

## Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `autonomy task create <name> [desc]` | Create a new task |
| `autonomy task list` | Show all tasks |
| `autonomy task work <name>` | Mark as in-progress |
| `autonomy task complete <name> "proof"` | Mark complete with proof |
| `autonomy task delete <name>` | Delete a task |

### GitHub Integration

| Command | Description |
|---------|-------------|
| `autonomy gh prs` | Your open PRs |
| `autonomy gh reviews` | PRs waiting for review |
| `autonomy gh ci-status` | CI status on default branch |
| `autonomy gh notifications` | Unread notifications |

### System Monitoring

| Command | Description |
|---------|-------------|
| `autonomy vm health` | System health overview |
| `autonomy vm process_list` | List all processes |
| `autonomy vm top_cpu` | Top CPU consumers |
| `autonomy vm docker_ps` | Docker containers |

---

## Safety Guards

<p align="center">
  <img src="assets/diagram-limits.svg" alt="Safety Limits" width="600">
</p>

### Hard Limits

| Limit | Value | Purpose |
|-------|-------|---------|
| Max concurrent tasks | 5 | Prevent overload |
| Max sub-agents | 3 | Limit parallelism |
| Max schedules | 5 | Control recurring work |
| Daily token budget | 50,000 | Cost protection |
| Max iterations per task | 5 | Stop endless building |

### Anti-Hallucination

```
❌ WRONG: "Task complete" (no proof)
✅ RIGHT: "Task complete. Proof: Tested X, verified Y exists"
```

| Guard | Description |
|-------|-------------|
| Verification Required | Must prove work before marking complete |
| Attempt Tracking | Max 3 attempts before forced stop |
| File Verification | Files must exist (actually checked) |
| Command Testing | Commands must work (actually run) |
| Evidence Required | Hand-waving rejected |

### Approval Required

These actions need explicit approval:
- External API calls
- Sending messages
- File deletion
- Public posts
- Git push
- Installing packages

---

## How It Works

<p align="center">
  <img src="assets/diagram-heartbeat.svg" alt="Heartbeat Flow" width="500">
</p>

### 1. Heartbeat Triggers

```
OpenClaw → Read HEARTBEAT.md → AI decides what to do
```

### 2. AI Checks Workstation

- Pending tasks?
- Scheduled work due?
- What needs attention?

### 3. AI Reasons & Acts

```
"I should build a token tracker"
↓
Create task → Plan approach → Build → Test → Verify → Complete
```

### 4. Verification Required

```bash
# ❌ WRONG - No proof
autonomy task complete X

# ✅ RIGHT - With proof
autonomy task complete X "Tested: logs tokens, file exists with data"
```

---

## Example Session

```bash
# User creates a task
$ autonomy task create "fix-auth" "Fix OAuth login bug"
✓ Task 'fix-auth' created

# User checks tasks
$ autonomy task list
  [pending] fix-auth: Fix OAuth login bug

# (On next heartbeat, AI sees the task)
# AI uses sessions_spawn to research OAuth2
# AI creates a fix
# AI marks complete with proof

# User checks status
$ autonomy task list
  [completed] fix-auth: Fix OAuth login bug
```

---

## Architecture

```
autonomy/
├── autonomy              # Main CLI
├── config.json           # Configuration & limits
├── HEARTBEAT.md          # AI instructions
├── ARCHITECTURE.md       # Design docs
├── README.md             # This file
├── USAGE.md              # Usage guide
├── checks/               # Update checker
├── lib/                  # Shared libraries
├── tasks/                # Active tasks (JSON)
├── agents/               # Running agents
├── tools/                # Custom tools created by AI
├── logs/                 # Activity logs
├── state/                # Runtime state
├── templates/            # Web UI templates
└── assets/               # Visual assets
```

<p align="center">
  <img src="assets/diagram-architecture.svg" alt="Architecture" width="700">
</p>

---

## Web Dashboard

Beautiful real-time dashboard at `http://localhost:8767`:

**Features:**
- 📋 Live task list with status badges
- 📊 Token usage pulled from OpenClaw API
- 💻 System health monitoring (CPU, memory, disk, load)
- 🎨 Dark theme with custom SVG assets
- 🔄 Auto-refresh every 30 seconds

**Start the dashboard:**
```bash
python3 web_ui.py              # Default port 8767
AUTONOMY_WEB_PORT=8080 python3 web_ui.py  # Custom port
```

---

## OpenClaw Integration

### Native Sub-Agents

Instead of custom bash spawning, use OpenClaw's native tool:

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

### Native Memory

Store context in MEMORY.md, retrieve via semantic search:

```bash
# AI stores decision
echo "## Decision: Chose JWT over session tokens" >> ~/.openclaw/workspace/MEMORY.md

# AI retrieves via memory_search tool
```

### Native Scheduling

Use OpenClaw cron instead of a bash daemon:

```bash
# Check every 30 minutes
openclaw cron add --name autonomy-check \
  --schedule "*/30 * * * *" \
  --command "autonomy check --notify"
```

---

## Assets

<p align="center">
  <img src="assets/logo.svg" alt="Logo" width="200">
</p>

<p align="center">
  This plugin includes visual assets:<br>
  <code>assets/logo.svg</code> — Main logo<br>
  <code>assets/logo-banner.svg</code> — Banner for README<br>
  <code>assets/diagram-*.svg</code> — Workflow diagrams
</p>

---

## Configuration

Edit `config.json`:

```json
{
  "version": "3.0.0",
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
    "auto_refresh": 30
  }
}
```

---

## Self-Update

The autonomy can update itself from GitHub:

```bash
autonomy update check  # Check if new version available
autonomy update apply  # Download and install
```

<p align="center">
  <img src="assets/diagram-update.svg" alt="Self-Update" width="500">
</p>

---

## Migration from v1

If you were using Autonomy v1:

1. **Backup tasks**: `cp -r autonomy/tasks autonomy-v2/tasks/`
2. **Stop v1 daemon**: `autonomy off`
3. **Remove v1 HEARTBEAT.md** (if auto-generated)
4. **Use OpenClaw cron** instead of `autonomy schedule`
5. **Use `sessions_spawn`** instead of `autonomy spawn`

---

## License

MIT License — Built for OpenClaw

---

<p align="center">
  <sub>Built with 💙 for the OpenClaw community</sub>
</p>
