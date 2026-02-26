#!/bin/bash
# Master Integration Script
# Usage: ./integrations/notify.sh <platform> <message>

AUTONOMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTEGRATIONS_DIR="$AUTONOMY_DIR/integrations"

notify() {
    local platform="$1"
    local message="$2"
    
    case "$platform" in
        discord)
            "$INTEGRATIONS_DIR/discord.sh" send "$message"
            ;;
        telegram)
            "$INTEGRATIONS_DIR/telegram.sh" send "$message"
            ;;
        slack)
            "$INTEGRATIONS_DIR/slack.sh" send "$message"
            ;;
        all)
            "$INTEGRATIONS_DIR/discord.sh" send "$message" &
            "$INTEGRATIONS_DIR/telegram.sh" send "$message" &
            "$INTEGRATIONS_DIR/slack.sh" send "$message" &
            wait
            ;;
        *)
            echo "Unknown platform: $platform"
            echo "Available: discord, telegram, slack, all"
            return 1
            ;;
    esac
}

notify_task() {
    local task_name="$1"
    local status="$2"
    local details="${3:-}"
    
    local message="Autonomy Task: $task_name is $status"
    [[ -n "$details" ]] && message="$message - $details"
    
    notify discord "$message"
}

# Command dispatcher
case "${1:-help}" in
    notify)
        notify "$2" "$3"
        ;;
    task)
        notify_task "$2" "$3" "$4"
        ;;
    test)
        echo "Testing all integrations..."
        "$INTEGRATIONS_DIR/discord.sh" test 2>/dev/null &
        "$INTEGRATIONS_DIR/telegram.sh" test 2>/dev/null &
        "$INTEGRATIONS_DIR/slack.sh" test 2>/dev/null &
        wait
        echo "Tests complete (check logs for results)"
        ;;
    *)
        echo "Usage: $0 {notify <platform> <message>|task <name> <status> [details]|test}"
        echo ""
        echo "Platforms: discord, telegram, slack, all"
        ;;
esac
