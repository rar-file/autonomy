#!/bin/bash
# Autonomy Heartbeat Daemon v2.0
# Coordinates with AI heartbeat via locking mechanism

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
PID_FILE="$AUTONOMY_DIR/state/heartbeat-daemon.pid"
LOG_FILE="$AUTONOMY_DIR/logs/daemon.log"
DAEMON_LOCK_FILE="$AUTONOMY_DIR/state/daemon.lock"

# Import heartbeat lock manager
source "$AUTONOMY_DIR/lib/heartbeat-lock.sh" 2>/dev/null || {
    echo "Error: heartbeat-lock.sh not found"
    exit 1
}

mkdir -p "$AUTONOMY_DIR/state" "$AUTONOMY_DIR/logs"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

is_running() {
    # Check PID file first
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
            # Verify it's actually our daemon (check for daemon-specific pattern)
            if ps -p "$pid" -o args= 2>/dev/null | grep -q "daemon.sh"; then
                return 0
            fi
        fi
    fi
    return 1
}

# Count running daemon processes
# Simply check if PID file points to a running process
count_daemons() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
            echo "1"
            return
        fi
    fi
    echo "0"
}

# Wait for AI heartbeat to complete (with timeout)
wait_for_heartbeat() {
    local timeout=${1:-60}  # Default 60 seconds
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if ! check_status | grep -q "LOCKED:"; then
            return 0  # Heartbeat completed
        fi
        sleep 1
        ((elapsed++))
    done
    
    return 1  # Timeout
}

# Process one task cycle (respects locks)
process_cycle() {
    log "=== Starting daemon cycle ==="
    
    # Wait for any running heartbeat to complete
    if check_status | grep -q "LOCKED:"; then
        log "AI heartbeat in progress, waiting..."
        if ! wait_for_heartbeat 60; then
            log "Timeout waiting for heartbeat, breaking stale lock"
            force_release
        fi
    fi
    
    # Now safe to process
    cd "$AUTONOMY_DIR"
    
    # Find first eligible task
    pending_task=""
    task_name=""
    
    for task_file in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$task_file" ]] || continue
        
        status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        completed=$(jq -r '.completed // false' "$task_file" 2>/dev/null)
        task_name=$(jq -r '.name // "unknown"' "$task_file" 2>/dev/null)
        
        # Skip completed tasks
        if [[ "$completed" == "true" || "$status" == "completed" ]]; then
            continue
        fi
        
        # Skip already flagged or processing tasks
        if [[ "$status" == "needs_ai_attention" || "$status" == "ai_processing" ]]; then
            log "Skipping $task_name (status: $status)"
            continue
        fi
        
        # Skip master tracking tasks
        if [[ "$task_name" == "continuous-improvement" ]]; then
            continue
        fi
        
        # Skip tasks with too many attempts
        attempts=$(jq -r '.attempts // 0' "$task_file" 2>/dev/null)
        max_attempts=$(jq -r '.max_attempts // 3' "$task_file" 2>/dev/null)
        if [[ "$attempts" -ge "$max_attempts" ]]; then
            log "Skipping $task_name (max attempts reached: $attempts/$max_attempts)"
            continue
        fi
        
        pending_task="$task_file"
        log "Found eligible task: $task_name (status: $status, attempts: $attempts)"
        break
    done
    
    if [[ -n "$pending_task" ]]; then
        # Flag task for AI processing
        log "Flagging for AI: $task_name"
        
        # Update task status
        tmp_file="${pending_task}.tmp"
        jq '.status = "needs_ai_attention" | .flagged_at = "'$(date -Iseconds)'" | .flagged_by = "daemon"' "$pending_task" > "$tmp_file" && mv "$tmp_file" "$pending_task"
        
        # Create notification
        task_desc=$(jq -r '.description // "No description"' "$pending_task" 2>/dev/null)
        cat > "$AUTONOMY_DIR/state/needs_attention.json" << WORK_NOTIFY
{
  "timestamp": "$(date -Iseconds)",
  "task_name": "$task_name",
  "task_file": "$pending_task",
  "description": "$task_desc",
  "status": "needs_ai_attention",
  "flagged_by": "daemon",
  "cycle_id": "$(date +%s)"
}
WORK_NOTIFY
        
        log "Task flagged. AI will process on next heartbeat."
        
        # Log activity
        echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"task_flagged\",\"task\":\"$task_name\",\"by\":\"daemon\"}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"
    else
        log "No eligible tasks found."
    fi
    
    log "=== Cycle complete ==="
}

start_daemon() {
    # Strict check - prevent multiple daemons
    local daemon_count=$(count_daemons)
    if [[ $daemon_count -gt 0 ]]; then
        echo "ERROR: $daemon_count daemon(s) already running!"
        echo "Use 'autonomy daemon restart' to restart cleanly."
        return 1
    fi
    
    # Startup lock
    if [[ -f "$DAEMON_LOCK_FILE" ]]; then
        local lock_pid=$(cat "$DAEMON_LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && ps -p "$lock_pid" >/dev/null 2>&1; then
            echo "ERROR: Daemon startup already in progress (PID: $lock_pid)"
            return 1
        fi
        rm -f "$DAEMON_LOCK_FILE"
    fi
    
    echo $$ > "$DAEMON_LOCK_FILE"
    
    # Start daemon in background
    (
        # Remove startup lock
        rm -f "$DAEMON_LOCK_FILE"
        
        exec >> "$LOG_FILE" 2>&1
        echo "[$(date -Iseconds)] Daemon starting (PID: $$)..."
        
        # Main loop
        while true; do
            # Check for stop signal
            if [[ -f "$AUTONOMY_DIR/state/daemon.stop" ]]; then
                echo "[$(date -Iseconds)] Stop signal received, shutting down..."
                rm -f "$PID_FILE" "$AUTONOMY_DIR/state/daemon.stop"
                exit 0
            fi
            
            # Check if workstation is active
            local active=$(jq -r '.workstation.active // false' "$AUTONOMY_DIR/config.json" 2>/dev/null)
            if [[ "$active" != "true" ]]; then
                echo "[$(date -Iseconds)] Workstation inactive, skipping cycle"
            else
                # Run cycle
                process_cycle
            fi
            
            # Sleep 5 minutes (check stop signal every 10 seconds)
            local sleep_count=0
            while [[ $sleep_count -lt 30 ]]; do
                if [[ -f "$AUTONOMY_DIR/state/daemon.stop" ]]; then
                    break
                fi
                sleep 10
                ((sleep_count++))
            done
        done
    ) &
    
    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    
    sleep 1
    if is_running; then
        echo "✅ Heartbeat daemon started (PID: $daemon_pid)"
        log "Daemon started with PID: $daemon_pid"
        
        # Update config
        tmp_config="${AUTONOMY_DIR}/config.json.tmp"
        jq '.workstation.daemon_running = true | .workstation.daemon_started = "'$(date -Iseconds)'"' "$AUTONOMY_DIR/config.json" > "$tmp_config" && mv "$tmp_config" "$AUTONOMY_DIR/config.json"
        return 0
    else
        echo "❌ Failed to start daemon"
        rm -f "$PID_FILE"
        return 1
    fi
}

stop_daemon() {
    if ! is_running; then
        echo "Daemon not running"
        rm -f "$PID_FILE" "$DAEMON_LOCK_FILE"
        return 1
    fi
    
    local pid=$(cat "$PID_FILE")
    echo "Stopping daemon (PID: $pid)..."
    
    # Signal graceful shutdown
    touch "$AUTONOMY_DIR/state/daemon.stop"
    
    # Wait for graceful shutdown
    sleep 2
    
    # Force kill if still running
    if ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null
        sleep 1
    fi
    
    if ps -p "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" 2>/dev/null
    fi
    
    rm -f "$PID_FILE" "$AUTONOMY_DIR/state/daemon.stop" "$DAEMON_LOCK_FILE"
    
    # Update config
    tmp_config="${AUTONOMY_DIR}/config.json.tmp"
    jq '.workstation.daemon_running = false | .workstation.daemon_stopped = "'$(date -Iseconds)'"' "$AUTONOMY_DIR/config.json" > "$tmp_config" && mv "$tmp_config" "$AUTONOMY_DIR/config.json"
    
    echo "✅ Daemon stopped"
    log "Daemon stopped"
}

status_daemon() {
    if is_running; then
        local pid=$(cat "$PID_FILE")
        local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
        echo "✅ Daemon running (PID: $pid, Uptime: $uptime)"
        
        # Show heartbeat lock status
        echo ""
        echo "Heartbeat Lock:"
        bash "$AUTONOMY_DIR/lib/heartbeat-lock.sh" status 2>&1 | sed 's/^/  /'
        
        # Show last activity
        if [[ -f "$LOG_FILE" ]]; then
            echo ""
            echo "Last 3 log entries:"
            tail -3 "$LOG_FILE" | sed 's/^/  /'
        fi
    else
        echo "❌ Daemon not running"
        rm -f "$PID_FILE"
    fi
}

run_once() {
    echo "Running single daemon cycle..."
    
    # Wait for any heartbeat to complete first
    if check_status | grep -q "LOCKED:"; then
        echo "AI heartbeat in progress, waiting..."
        if ! wait_for_heartbeat 60; then
            echo "Timeout waiting, breaking stale lock"
            force_release
        fi
    fi
    
    process_cycle
    echo "✅ Cycle complete"
}

# Command dispatcher
case "${1:-status}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 1
        start_daemon
        ;;
    status)
        status_daemon
        ;;
    once|run)
        run_once
        ;;
    logs)
        if [[ -f "$LOG_FILE" ]]; then
            tail -30 "$LOG_FILE"
        else
            echo "No logs yet"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|once|logs}"
        echo ""
        echo "Commands:"
        echo "  start    - Start the heartbeat daemon"
        echo "  stop     - Stop the daemon"
        echo "  restart  - Restart the daemon"
        echo "  status   - Check daemon and heartbeat status"
        echo "  once     - Run a single cycle now"
        echo "  logs     - Show recent daemon logs"
        exit 1
        ;;
esac
