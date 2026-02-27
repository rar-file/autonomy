---
name: autonomy
description: >-
  AI-driven self-improving autonomy system for OpenClaw agents.
  Agentic decision making, sub-agent spawning, scheduled heartbeats,
  continuous improvement, and a real-time web dashboard.
version: 2.2.0
user-invocable: true
metadata:
  openclaw:
    skillKey: autonomy
    emoji: "\U0001F916"
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
      env:
        - AUTONOMY_DIR
      config: []
    primaryEnv: AUTONOMY_DIR
---

# Agentic Autonomy — OpenClaw Plugin

**Version:** 2.2.0
**Type:** Agentic Self-Improvement System
**Requires:** OpenClaw Gateway, bash, jq, python3

## Quick Install

```bash
# Clone to your OpenClaw skills directory
cd "${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills"
git clone https://github.com/rar-file/autonomy.git

# Run install script
cd autonomy
bash install.sh

# Start using
autonomy on
autonomy work "Your first task"
```

## What It Does

This plugin turns your OpenClaw agent into a **self-improving autonomous system** that:

- **Decides what to do** based on context and priorities
- **Creates its own tasks** when it identifies needs
- **Spawns sub-agents** for parallel work
- **Schedules recurring checks** (every 20 minutes by default)
- **Updates itself** from GitHub automatically
- **Verifies its work** before marking complete
- **Respects hard limits** to prevent runaway usage

## Key Features

### Agentic Decision Making
The AI decides what to work on based on:
- Pending tasks
- Scheduled work
- System state
- User needs

### Continuous Improvement
- Runs every 20 minutes via heartbeat
- Spawns sub-agents for parallel research
- Updates web UI continuously
- Adds new features automatically

### Safety First
- Hard limits: 5 tasks, 3 agents, 50k tokens/day
- Anti-hallucination: Must verify work before completion
- Approval required for risky actions
- Built-in token budget tracking

### Web Dashboard
Beautiful web UI at `http://localhost:8767`:
- Real-time status monitoring
- Task management with complete/delete
- Activity logs
- Quick action buttons
- Dark theme with brand colors

## Configuration

Edit `config.json` to customize:

```json
{
  "agentic_config": {
    "hard_limits": {
      "max_concurrent_tasks": 5,
      "max_sub_agents": 3,
      "daily_token_budget": 50000
    },
    "requires_approval": [
      "external_api_calls",
      "sending_messages",
      "file_deletion"
    ]
  }
}
```

## Commands

```bash
autonomy on                          # Activate agentic mode
autonomy off                         # Deactivate
autonomy work "Build X"              # Give the AI a task
autonomy task list                   # View all tasks
autonomy spawn "Research Y"          # Spawn sub-agent
autonomy schedule add 30m "Check Z"  # Schedule recurring work
autonomy status                      # View system status
autonomy update check                # Check for updates
```

## OpenClaw Integration

This skill integrates deeply with OpenClaw's runtime:

- **Gateway**: Heartbeat triggers arrive via the OpenClaw Gateway WebSocket
- **Sessions**: Sub-agents can bridge to `sessions_send` / `sessions_spawn` for cross-session coordination when the OpenClaw CLI is available
- **Centralized Config**: AI provider, model, and API keys are read from `~/.openclaw/openclaw.json` when not overridden locally
- **OPENCLAW_HOME**: All paths respect the `OPENCLAW_HOME` environment variable (defaults to `~/.openclaw`)
- **ClawHub**: This skill is structured for publishing to ClawHub (`clawhub.com`)

## Heartbeat Integration

The plugin integrates with OpenClaw's heartbeat system:

1. **Heartbeat triggers** every 20 minutes
2. **AI reads HEARTBEAT.md** for instructions
3. **AI checks workstation** for pending work
4. **AI decides** what to prioritize
5. **AI executes** within hard limits
6. **AI reports** brief status update

### Smart Updates (No Spam)

- Work completed -> Brief summary + proof
- Phase transitioned -> Single notification
- Limit reached -> Alert with details
- Nothing to do -> HEARTBEAT_OK (silent)

## Continuous Improvement Workflow

Once installed, the system automatically:

1. **Creates 9 improvement tasks:**
   - Web UI enhancements
   - API endpoints
   - Autonomy levels
   - Monitoring tools
   - CLI improvements
   - Integrations
   - Documentation

2. **Sets 4 schedules:**
   - Every 20m: Check web UI improvements
   - Every 30m: Monitor sub-agents
   - Every 1h: Review new features
   - Every 2h: Check integrations

3. **Spawns sub-agents** for parallel research

## Production Ready

- Self-contained — no external dependencies beyond bash/jq/python3
- Self-updating — checks GitHub for new versions
- Self-monitoring — tracks token usage and limits
- Self-documenting — creates its own docs
- Safe — hard limits prevent runaway usage

## Support

- **Dashboard:** http://localhost:8767
- **Docs:** `IMPROVEMENT_WORKFLOW.md`
- **Logs:** `logs/agentic.jsonl`

## License

MIT
