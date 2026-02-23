#!/bin/bash
# Simplified Capability Auditor - Fast Version
# Recognizes OpenClaw integrations without hanging

WORKSPACE="/root/.openclaw/workspace"
AUTONOMY_DIR="$WORKSPACE/skills/autonomy"
CAPABILITIES_FILE="$AUTONOMY_DIR/state/capabilities.json"
OPENCLAW_CONFIG="/root/.openclaw/openclaw.json"

mkdir -p "$AUTONOMY_DIR/state"

# Quick check if OpenClaw gateway responds (3 second timeout)
check_openclaw() {
    if timeout 3 bash -c 'openclaw gateway status' 2>/dev/null | grep -q "running"; then
        echo "running"
    else
        echo "unknown"
    fi
}

# Check OpenClaw config directly (fast)
parse_openclaw_config() {
    if [[ -f "$OPENCLAW_CONFIG" ]]; then
        # Check for Discord in config
        if jq -e '.channels.discord' "$OPENCLAW_CONFIG" >/dev/null 2>&1; then
            echo "discord_configured"
        fi
    fi
}

echo "=== Autonomy Capability Audit ==="
echo ""
echo "OpenClaw:"
echo -n "  Gateway: "
if [[ $(check_openclaw) == "running" ]]; then
    echo "✅ Running"
else
    echo "❌ Not responding (may still be running)"
fi

echo -n "  Discord: "
if jq -e '.channels.discord' "$OPENCLAW_CONFIG" >/dev/null 2>&1; then
    DISCORD_NAME=$(jq -r '.channels.discord.name // "unknown"' "$OPENCLAW_CONFIG")
    echo "✅ Configured ($DISCORD_NAME)"
    
    # Check if bot is running
    if pgrep -f "discord_bot.py" > /dev/null 2>&1; then
        echo "  Discord Bot: ✅ Running (PID: $(pgrep -f "discord_bot.py" | head -1))"
    else
        echo "  Discord Bot: ❌ Not running"
        echo "    Start with: ./skills/autonomy/scripts/start-discord-bot.sh"
    fi
else
    echo "❌ Not configured"
fi

echo ""
echo "System Tools:"

for tool in git docker ssh kubectl gh; do
    echo -n "  $tool: "
    if command -v $tool &> /dev/null; then
        case $tool in
            git)
                VER=$(git --version | awk '{print $3}')
                echo "✅ $VER"
                ;;
            docker)
                if docker ps >/dev/null 2>&1; then
                    echo "✅ Running"
                else
                    echo "⚠️  Installed but no daemon access"
                fi
                ;;
            ssh)
                KEYS=$(ls ~/.ssh/id_* 2>/dev/null | wc -l)
                if [[ $KEYS -gt 0 ]]; then
                    echo "✅ Keys present ($KEYS)"
                else
                    echo "⚠️  No SSH keys"
                fi
                ;;
            *)
                echo "✅ Available"
                ;;
        esac
    else
        echo "❌ Not installed"
    fi
done

echo ""
echo "Autonomy Status:"
./skills/autonomy/autonomy status 2>/dev/null || echo "  Command not available"
