# USAGE.md — Autonomy v3.5

## For Humans

### Task Management

```bash
# Create a task
autonomy task create "refactor-auth" "Refactor authentication to use JWT tokens" high

# List all tasks
autonomy task list

# Mark as in-progress
autonomy task work "refactor-auth"

# Complete with proof
autonomy task complete "refactor-auth" "Refactored auth.py to JWT, added refresh tokens, all tests pass"

# Delete a task
autonomy task delete "refactor-auth"

# Sync to OpenClaw (updates TASKS.md + HEARTBEAT.md + AGENTS.md)
autonomy task sync

# Send task to AI sub-agent for autonomous work
autonomy task dispatch "refactor-auth"

# View task details
autonomy task status "refactor-auth"
```

### GitHub

```bash
autonomy gh prs           # Your open PRs
autonomy gh reviews       # PRs waiting for your review
autonomy gh ci-status     # CI run status
autonomy gh status        # Summary
```

### System Monitoring

```bash
autonomy vm health        # CPU, memory, disk, load
autonomy vm top_cpu       # Top CPU processes
autonomy vm docker_ps     # Running containers
autonomy vm service_status nginx
```

### Web Dashboard

```bash
python3 web_ui.py         # Start at http://localhost:8767
```

---

## For the AI Agent (Claude/OpenClaw)

> **THIS SECTION IS FOR YOU, THE AI AGENT. READ IT. FOLLOW IT. NO EXCEPTIONS.**

### Conversation Start Checklist

Every time a conversation starts:

1. Read `TASKS.md` in the workspace.
2. If there are active tasks, tell the user: "You have N active tasks: [list top 3]"
3. Ask: "Want to work on any of these, or something new?"

### Heartbeat Checklist

Every time the heartbeat fires:

1. Read the `<!-- AUTONOMY-TASKS-START -->` section of `HEARTBEAT.md`.
2. For each active task, report its status.
3. If any tasks are overdue (past due_date), **WARN the user immediately**.
4. If any tasks are blocked, ask if the blocker has been resolved.
5. If tasks have been dispatched to sub-agents, check if they've completed.

### When the User Says "Create a Task"

```bash
autonomy task create "task-name" "Description of what to do" high
autonomy task sync
```

Or via API:
```
POST http://localhost:8767/api/task/create
{"name": "task-name", "description": "Description", "priority": "high", "tags": ["relevant-tag"]}

POST http://localhost:8767/api/tasks/sync
```

### When You Start Working on a Task

```bash
autonomy task work "task-name"
autonomy task sync
```

### When You Complete a Task

```bash
autonomy task complete "task-name" "Specific proof: fixed X in file Y, tested by Z"
autonomy task sync
```

**Your proof MUST be specific.** Not "Done." Not "Completed." Describe what you did, what files you changed, what you tested.

### When a Task Is Complex (Multiple Steps)

Break it into subtasks via API:
```
POST http://localhost:8767/api/tasks/<id>/subtask
{"name": "Step 1: Research the problem"}

POST http://localhost:8767/api/tasks/<id>/subtask
{"name": "Step 2: Write the fix"}

POST http://localhost:8767/api/tasks/<id>/subtask
{"name": "Step 3: Write tests"}

POST http://localhost:8767/api/tasks/<id>/subtask
{"name": "Step 4: Update docs"}
```

Toggle subtasks as you complete them:
```
POST http://localhost:8767/api/tasks/<id>/subtask/0/toggle
```

### When You Need Parallel Work

Dispatch to a sub-agent:
```
POST http://localhost:8767/api/tasks/<id>/dispatch
{"mode": "agent"}
```

This spawns an independent AI agent that works on the task. The task auto-moves to `in_progress` with `ai_dispatched = true`.

### Natural Language Task Creation

```
POST http://localhost:8767/api/tasks/parse
{"text": "Fix the login page by Friday #frontend #auth !critical ~90m"}
```

Returns structured task data. Then create it with the parsed fields.

### When You're Blocked

```
POST http://localhost:8767/api/tasks/<id>/status
{"status": "blocked", "blocked_reason": "Waiting for API credentials from the user"}
```

Then tell the user what you need.

---

## OpenClaw Integration Examples

### Cron Scheduling

```bash
# Health check every 30 minutes
openclaw cron add --name autonomy-check \
  --schedule "*/30 * * * *" \
  --command "autonomy check --notify"

# Daily task summary at 9am
openclaw cron add --name daily-summary \
  --schedule "0 9 * * *" \
  --command "autonomy task list"
```

### File Watcher → Auto-Task

```bash
autonomy watcher add ./src "autonomy task create review-changes 'Review source changes' medium"
autonomy watcher start
```

### Webhook → Auto-Task

```json
POST http://localhost:8767/api/webhook
{
  "event": "deploy",
  "source": "ci-pipeline",
  "create_task": {
    "name": "verify-deploy",
    "description": "Verify deployment succeeded — check /health endpoint",
    "priority": "high"
  }
}
```

---

## What Gets Written to the Workspace

After every `autonomy task sync`:

| File | Content |
|------|---------|
| `~/.openclaw/workspace/TASKS.md` | Full task list: active tasks with status/priority/subtasks/notes, blocked tasks with reasons, recently completed with proof |
| `~/.openclaw/workspace/HEARTBEAT.md` | Task checklist section between `<!-- AUTONOMY-TASKS-START/END -->` markers: overdue warnings, active task list, instructions for the AI |
| `~/.openclaw/workspace/AGENTS.md` | Mandatory instructions section between `<!-- AUTONOMY-INSTRUCTIONS-START/END -->` markers: all rules, quick reference table, NL parsing syntax |

---

## Troubleshooting

**"Tasks aren't showing up"**
→ Run `autonomy task sync`. The tasks exist in JSON files but need to be synced to TASKS.md for the AI to see them.

**"The AI ignores tasks"**
→ Check that AGENTS.md has the autonomy instructions section. Run `python3 web_ui.py` (it syncs on startup) or `POST /api/tasks/sync`.

**"Tasks aren't in the heartbeat"**
→ Run `autonomy task sync`. Check that HEARTBEAT.md has the `<!-- AUTONOMY-TASKS-START -->` section.

**"The dashboard is empty"**
→ Make sure `python3 web_ui.py` is running. Check that `tasks/` directory has JSON files.

**"Can't dispatch to AI"**
→ Make sure `openclaw agent --local` works. Check that OpenClaw is installed and configured.