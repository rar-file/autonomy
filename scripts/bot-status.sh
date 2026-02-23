#!/bin/bash
# Check Discord bot status

PID_FILE="/tmp/autonomy-discord-bot.pid"

echo "=== Autonomy Discord Bot Status ==="
echo ""

if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "✅ Bot is running (PID: $PID)"
        echo ""
        echo "Process:"
        ps -p "$PID" -o pid,cmd,etime
    else
        echo "❌ Bot is not running (stale PID file)"
        rm -f "$PID_FILE"
    fi
else
    echo "❌ Bot is not running"
fi

echo ""
echo "Autonomy state:"
"$(dirname "$0")/../autonomy" status 2>/dev/null || echo "  (autonomy command not available)"
