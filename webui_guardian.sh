#!/bin/bash
# Persistent Web UI Launcher
# Ensures web UI is always running

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
PID_FILE="/tmp/webui.pid"
LOG_FILE="/tmp/webui.log"
PORT=8767

start_webui() {
    echo "[$(date)] Starting Web UI..." >> "$LOG_FILE"
    cd "$AUTONOMY_DIR"
    python3 web_ui.py >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "[$(date)] Web UI started with PID: $(cat $PID_FILE)" >> "$LOG_FILE"
}

check_webui() {
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0  # Running
        fi
    fi
    return 1  # Not running
}

# Main loop
while true; do
    if ! check_webui; then
        echo "[$(date)] Web UI not running, restarting..." >> "$LOG_FILE"
        start_webui
    fi
    
    # Also check if port is responding
    sleep 5
    if ! curl -s http://localhost:$PORT/api/status >/dev/null 2>&1; then
        echo "[$(date)] Web UI not responding, restarting..." >> "$LOG_FILE"
        pkill -f "web_ui.py" 2>/dev/null
        sleep 1
        start_webui
    fi
    
    sleep 10  # Check every 10 seconds
done
