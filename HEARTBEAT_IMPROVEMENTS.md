# Heartbeat & Daemon Improvements

## Summary of Changes

Fixed the heartbeat/daemon coordination to prevent concurrent heartbeats and race conditions.

## Problem

1. **No locking mechanism** - Multiple heartbeats could run simultaneously
2. **Race conditions** - Between daemon and AI processing
3. **No coordination** - Daemon could flag tasks while AI was working
4. **Ghost processes** - Stale PID files caused startup failures

## Solution

### 1. Heartbeat Lock Manager (`lib/heartbeat-lock.sh`)
- Centralized lock management for heartbeat coordination
- 5-minute timeout for stuck heartbeats
- Functions: `acquire_lock`, `release_lock`, `force_release`, `check_status`
- Lock file: `state/heartbeat.lock`

### 2. Updated Daemon (`daemon.sh`)
- Waits for AI heartbeat to complete before flagging new tasks
- Proper PID file management
- Improved startup/shutdown logic
- Checks workstation active status

### 3. AI Heartbeat Wrapper (`ai-heartbeat.sh`)
- Handles locking automatically for AI
- Returns task info for processing
- Ensures lock cleanup on exit

### 4. Updated Documentation
- **HEARTBEAT.md** - Full protocol with lock examples
- **AGENTS.md** - Lock protocol for heartbeats

## Lock Protocol

```bash
# At START of heartbeat:
source /root/.openclaw/workspace/skills/autonomy/lib/heartbeat-lock.sh
LOCK_RESULT=$(acquire_lock "ai-heartbeat")

if [[ "$LOCK_RESULT" != "LOCK_ACQUIRED" ]]; then
    echo "Heartbeat already in progress, skipping"
    exit 0
fi

# Do work...

# At END:
release_lock
```

## Commands

```bash
# Check lock status
cd /root/.openclaw/workspace/skills/autonomy
bash heartbeat-lock status

# Daemon control
bash daemon.sh start
bash daemon.sh stop
bash daemon.sh restart
bash daemon.sh status
bash daemon.sh logs

# Test heartbeat
bash ai-heartbeat.sh
```

## Task Flow

1. **Daemon runs every 10 minutes**
2. **Checks for AI heartbeat lock** - Waits if busy
3. **Finds eligible pending task**
4. **Flags task** with `status: "needs_ai_attention"`
5. **Creates notification** at `state/needs_attention.json`
6. **On AI heartbeat** - Acquires lock, processes task
7. **Marks complete** with verification, releases lock
8. **Daemon continues** - Can now flag next task

## Status Values

| Status | Meaning | Set By |
|--------|---------|--------|
| `pending` | Waiting in queue | Initial |
| `needs_ai_attention` | Ready for AI | Daemon |
| `ai_processing` | AI working | AI (after lock) |
| `completed` | Done + verified | AI |

## Files Changed

- `daemon.sh` - Complete rewrite with lock coordination
- `lib/heartbeat-lock.sh` - New lock manager library
- `heartbeat-lock` - CLI for lock commands
- `ai-heartbeat.sh` - AI heartbeat wrapper
- `HEARTBEAT.md` - Updated protocol
- `AGENTS.md` - Added lock protocol section

## Testing

```bash
# Start daemon
bash daemon.sh start

# Check status
bash daemon.sh status
bash heartbeat-lock status

# Run single cycle
bash daemon.sh once

# View logs
bash daemon.sh logs
```

## Notes

- Lock timeout: 5 minutes (prevents stuck locks)
- Daemon interval: 10 minutes
- Daemon waits up to 60 seconds for AI heartbeat to complete
- Quiet mode still respected (work hours config)
