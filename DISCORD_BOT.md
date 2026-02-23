# Discord Bot with Autonomy Presence

This bot updates its Discord status to reflect the autonomy system's current state.

## Features

- **Real-time status updates** every 30 seconds
- **Visual indicators:**
  - 🔵 Active - Currently working on a context
  - 🟡 Checking - Executing heartbeat checks  
  - 🟢 Idle - Waiting for next heartbeat
  - 🔴 Sleeping - Long idle period (DND mode)
  - ⚫ Off - Autonomy disabled

## Status Logic

| Status | Condition | Discord State |
|--------|-----------|---------------|
| Checking | Within 15s of last heartbeat | Online |
| Next Heartbeat | Within 30s of next heartbeat | Idle |
| Active | Within 5min of activity | Online |
| Idle | Normal waiting period | Idle |
| Sleeping | Idle > 2x base interval | DND |
| Off | Autonomy disabled | Invisible |

## Setup

### 1. Install dependencies

```bash
pip3 install discord.py
```

### 2. Start the bot

```bash
cd ~/.openclaw/workspace/skills/autonomy
./scripts/start-discord-bot.sh
```

Or manually:

```bash
export DISCORD_BOT_TOKEN="your-token"
python3 discord_bot.py
```

### 3. Commands

Once running, users can interact with the bot:

- `!autonomy` - Show current status
- `!autonomy on` - Enable autonomy
- `!autonomy off` - Disable autonomy
- `!autonomy context <name>` - Switch context

## Integration with Autonomy Skill

The bot reads from:
- `autonomy/config.json` - Active context
- `autonomy/state/loop_config.json` - Timing info

And updates Discord presence accordingly.

## Customization

Edit `discord_bot.py` to adjust:
- Update interval (default: 30s)
- Status emojis
- Status messages
- Idle thresholds

## Running as Service

To keep the bot running:

```bash
# Using systemd
cat > /etc/systemd/system/autonomy-discord.service << EOF
[Unit]
Description=Autonomy Discord Bot
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/.openclaw/workspace/skills/autonomy
ExecStart=/usr/bin/python3 $HOME/.openclaw/workspace/skills/autonomy/discord_bot.py
Environment=DISCORD_BOT_TOKEN=your-token
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable autonomy-discord
systemctl start autonomy-discord
```
