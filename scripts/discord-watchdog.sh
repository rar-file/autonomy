#!/bin/bash
# Discord Bot Watchdog
# Restarts the bot if it crashes or hangs

PID_FILE="/tmp/autonomy-discord-bot.pid"
LOG_FILE="/tmp/autonomy-discord-watchdog.log"
BOT_SCRIPT="/root/.openclaw/workspace/skills/autonomy/discord_bot.py"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_bot() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            # Check if it's actually responding (not hung)
            local cpu_time=$(ps -p "$pid" -o cputime= 2>/dev/null | tr -d ' ')
            if [[ -n "$cpu_time" ]]; then
                return 0  # Bot is running
            fi
        fi
    fi
    return 1  # Bot is not running
}

start_bot() {
    log "Starting Discord bot..."
    cd "$(dirname "$BOT_SCRIPT")"
    
    # Get token from OpenClaw config
    TOKEN=$(jq -r '.channels.discord.token' "/root/.openclaw/openclaw.json" 2>/dev/null)
    
    if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
        log "ERROR: Could not find Discord token"
        exit 1
    fi
    
    export DISCORD_BOT_TOKEN="$TOKEN"
    
    # Start bot in background
    python3 "$BOT_SCRIPT" > /tmp/autonomy-discord.log 2>&1 &
    local pid=$!
    echo $pid > "$PID_FILE"
    
    # Wait a moment and check if it started
    sleep 3
    if kill -0 $pid 2>/dev/null; then
        log "Bot started successfully (PID: $pid)"
        return 0
    else
        log "ERROR: Bot failed to start"
        return 1
    fi
}

stop_bot() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        log "Stopping bot (PID: $pid)..."
        kill "$pid" 2>/dev/null
        sleep 2
        rm -f "$PID_FILE"
    fi
}

restart_bot() {
    log "Restarting bot..."
    stop_bot
    sleep 2
    start_bot
}

# Main watchdog loop
log "Watchdog started"

while true; do
    if ! check_bot; then
        log "Bot not running or unresponsive, restarting..."
        restart_bot
    fi
    
    # Check every 60 seconds
    sleep 60
done
