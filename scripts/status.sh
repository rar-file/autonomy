#!/bin/bash
# Quick presence updater - updates Discord status without full bot
# Can be run as a standalone script or cron job

WORKSPACE="/root/.openclaw/workspace"
AUTONOMY_DIR="$WORKSPACE/skills/autonomy"
CONFIG="$AUTONOMY_DIR/config.json"
LOOP="$AUTONOMY_DIR/state/loop_config.json"

# Read state (simplified version for shell)
get_state() {
    if [[ -f "$CONFIG" ]]; then
        ACTIVE=$(jq -r '.active_context // empty' "$CONFIG")
        if [[ -n "$ACTIVE" ]]; then
            echo "active"
        else
            echo "off"
        fi
    else
        echo "off"
    fi
}

# Main status detection
STATE=$(get_state)

case "$STATE" in
    active)
        INTERVAL=$(jq -r '.autonomy_loop.base_interval_minutes // 20' "$LOOP")
        LAST=$(jq -r '.autonomy_loop.last_evaluation // empty' "$LOOP")
        
        if [[ -n "$LAST" ]]; then
            # Calculate time since last check (simplified)
            echo "Status: 🟢 Idle | Autonomy active"
        else
            echo "Status: 🔵 Active | Starting up"
        fi
        ;;
    off)
        echo "Status: ⚫ Off | Autonomy disabled"
        ;;
    *)
        echo "Status: ⚪ Unknown"
        ;;
esac
