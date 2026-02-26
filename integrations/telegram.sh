#!/bin/bash
# Integration Module - Telegram Notifications
# Usage: ./integrations/telegram.sh "message"

AUTONOMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
LOG_FILE="$AUTONOMY_DIR/logs/integrations.log"

# Get Telegram config
get_bot_token() {
    jq -r '.integrations.telegram.bot_token // empty' "$CONFIG_FILE" 2>/dev/null
}

get_chat_id() {
    jq -r '.integrations.telegram.chat_id // empty' "$CONFIG_FILE" 2>/dev/null
}

# Send Telegram message
send_telegram() {
    local message="$1"
    local bot_token=$(get_bot_token)
    local chat_id=$(get_chat_id)
    
    if [[ -z "$bot_token" || -z "$chat_id" ]]; then
        echo "Telegram not configured" >> "$LOG_FILE"
        return 1
    fi
    
    # Escape special characters for URL
    message=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
    
    local url="https://api.telegram.org/bot${bot_token}/sendMessage"
    
    response=$(curl -s -X POST "$url" \
        -d "chat_id=$chat_id" \
        -d "text=$message" \
        -d "parse_mode=HTML" 2>&1)
    
    if echo "$response" | grep -q '"ok":true'; then
        echo "[$(date -Iseconds)] Telegram notification sent" >> "$LOG_FILE"
        return 0
    else
        echo "[$(date -Iseconds)] Telegram notification failed: $response" >> "$LOG_FILE"
        return 1
    fi
}

# Test Telegram integration
test_telegram() {
    send_telegram "🤖 <b>Autonomy Test</b>\n\nTelegram integration is working!"
}

# Command dispatcher
case "${1:-help}" in
    send)
        shift
        send_telegram "$*"
        ;;
    test)
        test_telegram
        ;;
    *)
        echo "Usage: $0 {send <message>|test}"
        ;;
esac
