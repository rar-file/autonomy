#!/bin/bash
# Start the Discord bot with slash commands and autonomy presence

echo "=== Autonomy Discord Bot ==="
echo ""

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/root/.openclaw/workspace"

cd "$SCRIPT_DIR/.."

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: python3 not found"
    exit 1
fi

# Check if discord.py is installed
if ! python3 -c "import discord" 2>/dev/null; then
    echo "📦 Installing discord.py..."
    pip3 install discord.py
fi

# Get bot token from OpenClaw config
echo "🔍 Looking for Discord token..."
TOKEN=$(jq -r '.channels.discord.token' "/root/.openclaw/openclaw.json" 2>/dev/null)

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    echo "❌ Error: Could not find Discord bot token"
    echo ""
    echo "Please configure Discord first:"
    echo "  openclaw channels add --channel discord --token YOUR_TOKEN --name autonomy-bot"
    exit 1
fi

echo "✅ Token found"

# Set environment variable
export DISCORD_BOT_TOKEN="$TOKEN"

# Check if bot is already running
PID_FILE="/tmp/autonomy-discord-bot.pid"
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "⚠️  Bot already running (PID: $OLD_PID)"
        echo "   Stop it first with: kill $OLD_PID"
        exit 1
    fi
fi

echo "🚀 Starting bot..."
echo ""

# Start the bot in background
python3 "$SCRIPT_DIR/../discord_bot.py" &
echo $! > "$PID_FILE"

sleep 2

if kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "✅ Bot started successfully!"
    echo ""
    echo "Slash commands available:"
    echo "  /autonomy           - Show status"
    echo "  /autonomy_on        - Enable autonomy"
    echo "  /autonomy_off       - Disable autonomy"
    echo "  /autonomy_context   - Switch context"
    echo "  /autonomy_contexts  - List contexts"
    echo ""
    echo "PID: $(cat $PID_FILE)"
    echo "Logs: tail -f /tmp/autonomy-discord.log"
else
    echo "❌ Failed to start bot"
    rm -f "$PID_FILE"
    exit 1
fi
