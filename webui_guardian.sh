#!/bin/bash
# Persistent Web UI Guardian
# Ensures web UI is always running — daemon.sh also monitors this,
# but this script can be run standalone for extra reliability.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
LOG_FILE="$AUTONOMY_DIR/logs/webui.log"
PORT=${AUTONOMY_WEB_PORT:-8767}

mkdir -p "$AUTONOMY_DIR/logs"

start_webui() {
    echo "[$(date)] Starting Web UI..." >> "$LOG_FILE"
    cd "$AUTONOMY_DIR"
    python3 "$AUTONOMY_DIR/web_ui.py" >> "$LOG_FILE" 2>&1 &
    echo "[$(date)] Web UI started (PID: $!)" >> "$LOG_FILE"
}

# Main loop
while true; do
    if ! pgrep -f "web_ui.py" >/dev/null 2>&1; then
        echo "[$(date)] Web UI not running, restarting..." >> "$LOG_FILE"
        start_webui
        sleep 5
    fi
    sleep 15
done
