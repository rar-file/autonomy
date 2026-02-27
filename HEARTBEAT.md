# HEARTBEAT.md — Agentic Autonomy System v2.1

> **Generated:** 2026-02-27T20:15:45+01:00
> **Autonomy Level:** semi-autonomous
> **Pending Tasks:** 0

---

## Your Current Assignment


**No task assigned.** Nothing in the queue needs attention.

If you think something valuable should be done, create a task:
```bash
bash /root/.openclaw/workspace/skills/autonomy/autonomy task create "task-name" "description of what to do"
```

Otherwise: **HEARTBEAT_OK** — nothing to do.


---

## Session History

Last session (): Task= Status= — 

## Workspace Context

Language:  | Framework:  | Type:  | Files:  | Dirs:  | Git: 

## Token Budget

0/50000 tokens (0%) — 50000 remaining across 0 sessions.

## Sub-Agents

Sub-agents: 0/3 active

To spawn a sub-agent: `bash /root/.openclaw/workspace/skills/autonomy/lib/sub-agents.sh spawn "" "sub-task-name" "description"`

## System Capabilities

### VM Integration (Full System Access)
- Process management: `autonomy vm process_list`, `autonomy vm top_cpu`
- Service control: `autonomy vm service_list`, `autonomy vm service_status <svc>`
- Docker control: `autonomy vm docker_ps`, `autonomy vm docker_logs <c>`
- Resources: `autonomy vm cpu`, `autonomy vm memory`, `autonomy vm disk`
- Network: `autonomy vm network_connections`, `autonomy vm ping <host>`
- Storage: `autonomy vm storage_df`, `autonomy vm storage_du <path>`

### File Watching
- Add watcher: `autonomy watcher add <path> <action> [name]`
- List watchers: `autonomy watcher list`
- Check changes: `autonomy watcher check`
- Daemon: `autonomy watcher daemon_start`

### Diagnostics
- Health check: `autonomy diagnostic health`
- Auto-repair: `autonomy diagnostic repair`
- System info: `autonomy diagnostic system`

### Enhanced Execution
- With retry: `autonomy execute retry "<cmd>" [max] [delay]`
- Async: `autonomy execute async "<cmd>" [name]`
- Parallel: `autonomy execute parallel "cmd1" "cmd2" ...`
- Timeout: `autonomy execute timeout <secs> "<cmd>"`

### Intelligent Logging
- Query logs: `autonomy log query --level INFO --last 20`
- Tail: `autonomy log tail [n]`
- Stats: `autonomy log stats`
- Errors: `autonomy log errors [n]`

### Plugins
- List: `autonomy plugin list`
- Load: `autonomy plugin load <name>`
- Create: `autonomy plugin create <name>`
- Discover: `autonomy plugin discover`

---

## Hard Limits (Always Respect)

| Limit | Value |
|-------|-------|
| Max concurrent tasks | 5 |
| Max file edits / session | 50 |
| Max web searches | 10 |
| Max iterations / task | 5 |
| Daily token budget | 50000 |

## Execution Rules

1. **Check** — Read this HEARTBEAT.md. What's assigned? What's the history?
2. **Plan** — Break the task into subtasks if you haven't already.
3. **Execute** — Work through one subtask at a time. Stay focused.
4. **Verify** — Test your work. Use `ai-engine.sh terminal` to run tests. Gather evidence.
5. **Evidence** — After work, run verification and attach proof:
   ```bash
   bash /root/.openclaw/workspace/skills/autonomy/lib/ai-engine.sh evidence "" "test_command_1" "test_command_2"
   ```
6. **Journal** — After finishing, log what you did:
   ```bash
   bash /root/.openclaw/workspace/skills/autonomy/lib/journal.sh append "" "summary of what I did" "status" "next step"
   ```
7. **Memory** — Store any important discoveries or decisions:
   ```bash
   bash /root/.openclaw/workspace/skills/autonomy/lib/memory.sh store decisions "Chose X approach because Y"
   ```
8. **Complete or Continue** — Mark the task done if finished, or let the next heartbeat pick up where you left off.

## Anti-Hallucination Rules (CRITICAL)

- **Verify files exist** — Use `ai-engine.sh terminal "ls -la file"` to check.
- **Test your work** — Run the code/tool. Use terminal access to verify.
- **Require evidence** — Use `ai-engine.sh evidence` to gather proof. Don't say "it works" without it.
- **Check for existing solutions** — Don't rebuild what exists.
- **Max 5 attempts** — If stuck after 5 tries, report failure.
- **Store learnings** — Use `memory.sh store patterns "what I learned"` to remember.

## Completion

A task is **DONE** when:
- It works (you tested it)
- It solves the original problem
- You verified it (anti-hallucination check)
- You logged a journal entry

Mark complete:
```bash
bash /root/.openclaw/workspace/skills/autonomy/autonomy task complete "" "Tested: [describe what was tested and proven]"
```

## If Nothing To Do

Respond with: **HEARTBEAT_OK**

Do NOT invent work. Do NOT build things nobody asked for. Wait for the next task.

