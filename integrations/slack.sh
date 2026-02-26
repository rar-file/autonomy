#!/bin/bash
# Integration Module - Slack Notifications
# Usage: ./integrations/slack.sh "message"

AUTONOMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
LOG_FILE="$AUTONOMY_DIR/logs/integrations.log"

# Get Slack webhook
get_webhook() {
    jq -r '.integrations.slack.webhook_url // empty' "$CONFIG_FILE" 2>/dev/null
}

# Send Slack notification
send_slack() {
    local message="$1"
    local webhook_url=$(get_webhook)
    
    if [[ -z "$webhook_url" ]]; then
        echo "Slack webhook not configured" >> "$LOG_FILE"
        return 1
    fi
    
    local payload="{\"text\": \"$message\"}"
    
    response=$(curl -s -X POST "$webhook_url" \
        -H 'Content-type: application/json' \
        --data "$payload" 2>&1)
    
    if [[ -z "$response" ]] || [[ "$response" == "ok" ]]; then
        echo "[$(date -Iseconds)] Slack notification sent" >> "$LOG_FILE"
        return 0
    else
        echo "[$(date -Iseconds)] Slack notification failed: $response" >> "$LOG_FILE"
        return 1
    fi
}

# Send rich Slack message with blocks
send_slack_rich() {
    local title="$1"
    local text="$2"
    local color="${3:-#36a64f}"
    local webhook_url=$(get_webhook)
    
    if [[ -z "$webhook_url" ]]; then
        echo "Slack webhook not configured" >> "$LOG_FILE"
        return 1
    fi
    
    local payload=$(cat << EOF
{
    "attachments": [{
        "color": "$color",
        "title": "$title",
        "text": "$text",
        "footer": "Autonomy System",
        "ts": $(date +%s)
    }]
}
EOF
)
    
    response=$(curl -s -X POST "$webhook_url" \
        -H 'Content-type: application/json' \
        --data "$payload" 2>&1)
    
    if [[ -z "$response" ]] || [[ "$response" == "ok" ]]; then
        echo "[$(date -Iseconds)] Slack rich notification sent" >> "$LOG_FILE"
        return 0
    else
        echo "[$(date -Iseconds)] Slack notification failed: $response" >> "$LOG_FILE"
        return 1
    fi
}

# Test Slack integration
test_slack() {
    send_slack_rich "🤖 Autonomy Test" "Slack integration is working!" "#36a64f"
}

# Command dispatcher
case "${1:-help}" in
    send)
        shift
        send_slack "$*"
        ;;
    rich)
        send_slack_rich "$2" "$3" "$4"
        ;;
    test)
        test_slack
        ;;
    *)
        echo "Usage: $0 {send <message>|rich <title> <text> [color]|test}"
        ;;
esac
