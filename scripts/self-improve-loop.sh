#!/bin/bash
# Self-Improvement Loop Controller
# Runs the autonomy cycle every 20 minutes

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
PID_FILE="/tmp/autonomy-self-improve.pid"
LOG_FILE="/tmp/autonomy-self-improve-loop.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

start_loop() {
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "Loop already running (PID: $old_pid)"
            return 1
        fi
    fi
    
    log "Starting self-improvement loop (20 min cycles)"
    
    (
        while true; do
            log "=== Starting Cycle ==="
            
            # Run the check
            "$AUTONOMY_DIR/checks/self_improvement_cycle.sh" check >> "$LOG_FILE" 2>&1
            
            log "=== Cycle Complete. Sleeping 20 minutes ==="
            
            # Sleep 20 minutes (1200 seconds)
            # Use a loop to allow graceful shutdown
            for i in {1..1200}; do
                sleep 1
                if [[ ! -f "$PID_FILE" ]]; then
                    log "PID file removed, stopping loop"
                    exit 0
                fi
            done
        done
    ) &
    
    echo $! > "$PID_FILE"
    log "Loop started (PID: $!)"
}

stop_loop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        log "Stopping loop (PID: $pid)..."
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
        log "Loop stopped"
    else
        log "No loop running"
    fi
}

status_loop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "✓ Self-improvement loop running (PID: $pid)"
            echo "  Log: $LOG_FILE"
            echo "  Last lines:"
            tail -5 "$LOG_FILE" 2>/dev/null || echo "  (no log yet)"
        else
            echo "✗ Loop process not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        echo "✗ Self-improvement loop not running"
    fi
}

case "${1:-start}" in
    start)
        start_loop
        ;;
    stop)
        stop_loop
        ;;
    restart)
        stop_loop
        sleep 2
        start_loop
        ;;
    status)
        status_loop
        ;;
    log)
        tail -f "$LOG_FILE"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|log}"
        exit 1
        ;;
esac
