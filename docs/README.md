# Autonomy Plugin

## Overview
AI-driven self-improving autonomy system for OpenClaw agents.

## Quick Start

```bash
./control.sh start    # Start all services
./control.sh status   # Check status
./control.sh stop     # Stop all services
```

## Architecture

### Components
- **Daemon** (10 min) - Detects and flags tasks
- **Processor** (5 min) - Processes tasks, generates improvements
- **Web UI** - Real-time dashboard
- **AI** - Does actual work on heartbeats

### Task Flow
```
pending → needs_ai_attention → ai_processing → completed
```

## Commands

| Command | Description |
|---------|-------------|
| `autonomy work "task"` | Give AI a task |
| `autonomy daemon start/stop/status` | Control daemon |
| `autonomy wizard` | Interactive setup |
| `autonomy alias` | Manage aliases |

## Web UI

Visit http://localhost:8767 for dashboard.

## API Endpoints

- `GET /api/tasks` - List all tasks
- `GET /api/task/{name}` - Get task details
- `POST /api/task/create` - Create task
- `POST /api/task/{name}/complete` - Complete task

## Hard Limits

- Max 3 sub-agents
- Max 5 schedules
- 50,000 daily token budget
- Max 50 file edits per session
