#!/bin/bash
# Stop the Discord bot

PID_FILE="/tmp/autonomy-discord-bot.pid"

if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "🛑 Stopping bot (PID: $PID)..."
        kill "$PID"
        rm -f "$PID_FILE"
        echo "✅ Bot stopped"
    else
        echo "⚠️  Bot not running"
        rm -f "$PID_FILE"
    fi
else
    echo "⚠️  No PID file found"
    echo "   Try: pkill -f discord_bot.py"
fi
