# Heartbeat Coordination System

## Overview

The Autonomy Plugin uses a multi-layered heartbeat coordination system to ensure the AI actually processes tasks, not just flags them.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         HEARTBEAT COORDINATION                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  LAYER 1: DAEMON (10 min cycle)                                         │
│  ├── Detects pending tasks                                              │
│  ├── Flags as "needs_ai_attention"                                      │
│  ├── Creates state/needs_attention.json                                 │
│  └── Sleeps 10 minutes                                                  │
│                                                                         │
│  LAYER 2: COORDINATOR (Event-driven)                                    │
│  ├── Health checks (daemon, web UI, API)                                │
│  ├── Detects flagged tasks                                              │
│  ├── Marks as "ai_processing"                                           │
│  ├── Monitors for stuck tasks (>1hr)                                    │
│  └── Updates statistics                                                 │
│                                                                         │
│  LAYER 3: WORKFLOW (5 min cycle)                                        │
│  ├── Phase 1: Health & Testing (API tests)                              │
│  ├── Phase 2: Process flagged work → AI notification                    │
│  ├── Phase 3: Updates & maintenance (logs, archive)                     │
│  ├── Phase 4: Web UI refresh                                            │
│  └── Phase 5: Reporting & coordination                                  │
│                                                                         │
│  LAYER 4: AI (Triggered by OpenClaw)                                    │
│  ├── Receives HEARTBEAT.md prompt                                       │
│  ├── Checks state/needs_attention.json                                  │
│  ├── Processes flagged tasks                                            │
│  ├── Marks complete with verification                                   │
│  └── Clears notification files                                          │
│                                                                         │
│  LAYER 5: WEB UI (Real-time)                                            │
│  ├── Shows task status with live updates                                │
│  ├── Displays heartbeat history                                         │
│  ├── Shows coordinator statistics                                       │
│  └── Allows manual triggers                                             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Task Lifecycle

```
PENDING → FLAGGED → AI_PROCESSING → COMPLETED
   ↑         ↑            ↑             ↑
  Daemon  Coordinator    AI          Verified
```

1. **Task Created** → Status: `pending`
2. **Daemon Finds** → Status: `needs_ai_attention`
3. **Coordinator Processes** → Status: `ai_processing`
4. **AI Completes** → Status: `completed` + verification

### File States

| File | Purpose | Updated By |
|------|---------|------------|
| `tasks/{name}.json` | Task data | All layers |
| `state/needs_attention.json` | Flagged task info | Daemon |
| `state/currently_processing.json` | Current AI task | Coordinator |
| `state/workflow_summary.json` | System status | Workflow |
| `state/coordinator_stats.json` | Statistics | Coordinator |
| `logs/agentic.jsonl` | Activity log | All layers |
| `logs/workflow.log` | Workflow log | Workflow |
| `logs/heartbeat_history.jsonl` | Heartbeat log | Coordinator |

## Components

### 1. Daemon (`daemon.sh`)

```bash
# Runs every 10 minutes
while true; do
    find_pending_task()
    flag_for_ai_attention()  # Status: needs_ai_attention
    sleep 600
done
```

**Purpose:** Background task detection

### 2. Coordinator (`coordinator.sh`)

```bash
# Event-driven via workflow or manual
coordinator_cycle() {
    health_checks()
    process_flagged_tasks()  # Status: ai_processing
    update_statistics()
}
```

**Purpose:** Bridge between daemon and AI

### 3. Workflow (`workflow.sh`)

```bash
# Runs every 5 minutes
run_workflow() {
    phase_1_health()      # Test APIs
    phase_2_process()     # Trigger AI
    phase_3_updates()     # Maintenance
    phase_4_webui()       # Refresh UI
    phase_5_report()      # Generate report
}
```

**Purpose:** Orchestrate full system

### 4. AI Integration

**Triggered by:** OpenClaw HEARTBEAT.md prompt

```
1. Read HEARTBEAT.md
2. Check state/needs_attention.json
3. If flagged task exists:
   a. Read task description
   b. Do the actual work
   c. Mark complete with verification
   d. Clear notification files
4. Report completion
```

### 5. Web UI (`web_ui.py`)

**Endpoints:**
- `GET /api/tasks` - All tasks
- `GET /api/task/{name}` - Single task
- `GET /api/status` - System status
- `GET /api/heartbeat` - Heartbeat info
- `POST /api/task/create` - Create task
- `POST /api/task/{name}/complete` - Complete task
- `POST /api/task/{name}/update` - Update task
- `DELETE /api/task/{name}` - Delete task

**Features:**
- Real-time task status (5s refresh)
- Click task for detail modal
- Heartbeat countdown timer
- Daemon control buttons
- Statistics dashboard

## Heartbeat Information Display

### Web UI Heartbeat Panel

```
┌─────────────────────────────────────────────┐
│ Heartbeat Status                            │
├─────────────────────────────────────────────┤
│ Next: 02:34                                 │
│ Last: 2026-02-25T00:10:54+01:00            │
│ Cycles: 12                                  │
│ Success Rate: 100%                          │
│                                             │
│ Recent:                                     │
│  ✓ 00:10:54 - Task processed               │
│  ✓ 00:05:43 - No tasks                     │
│  ✓ 00:00:12 - Health check                 │
│                                             │
│ [Trigger Now] [View Logs]                  │
└─────────────────────────────────────────────┘
```

### Information Tracked

1. **Timing**
   - Last heartbeat timestamp
   - Next heartbeat countdown
   - Average interval

2. **Statistics**
   - Total cycles
   - Successful cycles
   - Failed cycles
   - Success rate

3. **Activity**
   - Tasks processed
   - Health check results
   - Errors encountered

4. **Current State**
   - Flagged tasks
   - Processing tasks
   - System health

## Testing Strategy

### Automated Tests

```bash
tests/
├── run_tests.sh          # Master test runner
├── test_core.sh          # Core functionality
├── test_daemon.sh        # Daemon tests
├── test_api.sh           # API endpoint tests
├── test_actions.sh       # Action tests
├── test_security.sh      # Security tests
└── test_utils.sh         # Utility tests
```

**Test Coverage:**
- Daemon start/stop/restart
- API all endpoints (GET/POST/DELETE)
- Task lifecycle (create/update/complete/delete)
- Web UI responsiveness
- Health check validation

### Manual Testing

1. **Create test task**
   ```bash
   curl -X POST http://localhost:8767/api/task/create \
     -H "Content-Type: application/json" \
     -d '{"name":"test","description":"Test task"}'
   ```

2. **Verify daemon flags it**
   ```bash
   cat state/needs_attention.json
   ```

3. **Check coordinator processes it**
   ```bash
   cat state/currently_processing.json
   ```

4. **AI processes on heartbeat**
   - Wait for HEARTBEAT.md prompt
   - Task shows "ai_processing"
   - AI completes and marks done

5. **Verify completion**
   ```bash
   curl http://localhost:8767/api/task/test
   ```

## Subagent Roles

| Agent | Role | Triggers |
|-------|------|----------|
| Daemon | Task detection | Every 10 min |
| Coordinator | Task coordination | Workflow or manual |
| Workflow | System orchestration | Every 5 min |
| AI | Actual work execution | On heartbeat |
| Web UI | User interface | Real-time |

## Recovery Procedures

### Daemon Crashed
```bash
autonomy daemon restart
# Or: ./control.sh restart
```

### Task Stuck
```bash
# Auto-recovery: Coordinator resets tasks >1hr
# Manual reset:
jq '.status = "pending" | del(.processing_started)' tasks/stuck-task.json
```

### Web UI Down
```bash
cd /root/.openclaw/workspace/skills/autonomy
python3 web_ui.py &
```

### Full System Reset
```bash
./control.sh stop
./control.sh start
```

## Configuration

### config.json
```json
{
  "scheduler": {
    "type": "daemon",
    "auto_start": true,
    "interval_minutes": 10
  },
  "workflow": {
    "enabled": true,
    "interval_minutes": 5
  }
}
```

## Monitoring

### Key Metrics
- Tasks processed per hour
- Average processing time
- API response times
- Error rates
- System uptime

### Alerts
- Task stuck >1 hour
- Daemon not running
- Web UI down
- API errors >5%

## Future Enhancements

1. **Metrics Dashboard** - Prometheus/Grafana integration
2. **Alerting** - PagerDuty/OpsGenie integration
3. **Task Queue** - Redis/RabbitMQ for scale
4. **Multi-AI** - Distribute tasks across AIs
5. **Mobile App** - React Native companion app

## Summary

This heartbeat coordination system ensures:
- ✅ Tasks are actually processed (not just flagged)
- ✅ AI is triggered properly on heartbeats
- ✅ System is self-healing with health checks
- ✅ Real-time visibility via Web UI
- ✅ Comprehensive testing coverage
- ✅ 5-minute workflow cycles for coordination

The system is production-ready for autonomous task management.
