#!/bin/bash
# Simple Fixed-Interval Heartbeat Daemon
# Runs every 5 minutes, logs activity, never changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
PID_FILE="$AUTONOMY_DIR/state/daemon.pid"
LOG_FILE="$AUTONOMY_DIR/logs/heartbeat.log"
CHECK_FILE="$AUTONOMY_DIR/state/last-check.json"

INTERVAL_SECONDS=300  # 5 minutes, NEVER CHANGES

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

# Simple check - log that we ran, flag tasks if found
do_check() {
    local timestamp=$(date -Iseconds)
    
    # Always log that heartbeat ran
    log "HEARTBEAT CHECK: $timestamp"
    
    # Update last-check file (for web UI)
    echo "{\"last_check\": \"$timestamp\", \"interval_seconds\": $INTERVAL_SECONDS}" > "$CHECK_FILE"
    
    # Look for pending tasks and flag them (don't wait, don't block)
    local found_task=false
    for task_file in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$task_file" ]] || continue
        
        local status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        local completed=$(jq -r '.completed // false' "$task_file" 2>/dev/null)
        local task_name=$(jq -r '.name // "unknown"' "$task_file" 2>/dev/null)
        
        # Skip if not a simple pending task
        [[ "$status" != "pending" ]] && continue
        [[ "$completed" == "true" ]] && continue
        [[ "$task_name" == "continuous-improvement" ]] && continue
        
        # Flag it for AI
        jq '.status = "needs_ai_attention" | .flagged_at = "'"$timestamp"'"' "$task_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
        log "FLAGGED TASK: $task_name"
        found_task=true
        break  # Only flag one per check
    done
    
    if [[ "$found_task" == "false" ]]; then
        log "NO TASKS TO FLAG"
    fi
}

# Main loop - runs every 5 minutes, NO EXCEPTIONS
main_loop() {
    echo $$ > "$PID_FILE"
    log "DAEMON STARTED - Interval: ${INTERVAL_SECONDS}s (5 min)"
    
    while true; do
        # Check if stop signal
        if [[ -f "$AUTONOMY_DIR/state/stop-daemon" ]]; then
            rm -f "$AUTONOMY_DIR/state/stop-daemon"
            log "DAEMON STOPPED (signal received)"
            rm -f "$PID_FILE"
            exit 0
        fi
        
        # DO THE CHECK (always runs, never waits)
        do_check
        
        # Sleep EXACTLY 5 minutes (300 seconds), checking for stop every second
        local slept=0
        while [[ $slept -lt $INTERVAL_SECONDS ]]; do
            if [[ -f "$AUTONOMY_DIR/state/stop-daemon" ]]; then
                rm -f "$AUTONOMY_DIR/state/stop-daemon"
                log "DAEMON STOPPED (signal during sleep)"
                rm -f "$PID_FILE"
                exit 0
            fi
            sleep 1
            ((slept++))
        done
    done
}

# Command handling
case "${1:-status}" in
    start)
        if [[ -f "$PID_FILE" ]] && ps -p $(cat "$PID_FILE") >/dev/null 2>&1; then
            echo "Daemon already running (PID: $(cat "$PID_FILE"))"
            exit 1
        fi
        main_loop &
        echo $! > "$PID_FILE"
        echo "✅ Daemon started (runs every 5 minutes)"
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            touch "$AUTONOMY_DIR/state/stop-daemon"
            sleep 2
            rm -f "$PID_FILE"
            echo "✅ Daemon stopped"
        else
            echo "Daemon not running"
        fi
        ;;
    status)
        if [[ -f "$PID_FILE" ]] && ps -p $(cat "$PID_FILE") >/dev/null 2>&1; then
            echo "✅ Daemon running (PID: $(cat "$PID_FILE"))"
            if [[ -f "$CHECK_FILE" ]]; then
                cat "$CHECK_FILE"
            fi
        else
            echo "❌ Daemon not running"
        fi
        ;;
    check)
        # Manual check (for testing)
        do_check
        ;;
    *)
        echo "Usage: $0 {start|stop|status|check}"
        exit 1
        ;;
esac
