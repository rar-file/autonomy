#!/bin/bash
# Integration Module - Discord Notifications
# Usage: ./integrations/discord.sh "message" [channel_id]

AUTONOMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
LOG_FILE="$AUTONOMY_DIR/logs/integrations.log"

mkdir -p "$AUTONOMY_DIR/logs"

# Get Discord webhook from config
get_webhook() {
    jq -r '.integrations.discord.webhook_url // empty' "$CONFIG_FILE" 2>/dev/null
}

# Send Discord notification
send_discord() {
    local message="$1"
    local webhook_url=$(get_webhook)
    
    if [[ -z "$webhook_url" ]]; then
        echo "Discord webhook not configured" >> "$LOG_FILE"
        return 1
    fi
    
    # Truncate message if too long
    if [[ ${#message} -gt 2000 ]]; then
        message="${message:0:1997}..."
    fi
    
    # Send webhook
    response=$(curl -s -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"$message\"}" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo "[$(date -Iseconds)] Discord notification sent" >> "$LOG_FILE"
        return 0
    else
        echo "[$(date -Iseconds)] Discord notification failed: $response" >> "$LOG_FILE"
        return 1
    fi
}

# Test Discord integration
test_discord() {
    send_discord "🤖 **Autonomy Test** - Discord integration is working!"
}

# Send task notification
notify_task() {
    local task_name="$1"
    local status="$2"
    local details="${3:-}"
    
    local emoji="📝"
    case "$status" in
        completed) emoji="✅" ;;
        failed) emoji="❌" ;;
        processing) emoji="🔄" ;;
        *) emoji="📝" ;;
    esac
    
    local message="$emoji **Autonomy Task Update**\n\n**Task:** $task_name\n**Status:** $status"
    [[ -n "$details" ]] && message="$message\n**Details:** $details"
    
    send_discord "$message"
}

# Command dispatcher
case "${1:-help}" in
    send)
        shift
        send_discord "$*"
        ;;
    test)
        test_discord
        ;;
    task)
        notify_task "$2" "$3" "$4"
        ;;
    *)
        echo "Usage: $0 {send <message>|test|task <name> <status> [details]}"
        ;;
esac
