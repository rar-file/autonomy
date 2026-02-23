# Notifications Add-on for Autonomy Skill

## Discord Integration

The autonomy skill can send notifications to Discord when:
- Checks fail
- Goals are due
- Errors are detected
- Context switches occur

## Setup

### 1. Create Discord Bot

1. Go to https://discord.com/developers/applications
2. Click "New Application"
3. Go to "Bot" section
4. Click "Add Bot"
5. Copy the token
6. Enable "MESSAGE CONTENT INTENT" if you want the bot to read messages

### 2. Add Bot to Server

1. Go to OAuth2 → URL Generator
2. Select scopes: `bot`, `applications.commands`
3. Select bot permissions: `Send Messages`, `Read Messages`
4. Copy the URL and open it
5. Select your server and authorize

### 3. Connect to OpenClaw

Run the setup script:

```bash
cd ~/.openclaw/workspace/skills/autonomy
./scripts/setup-discord.sh YOUR_BOT_TOKEN
```

Or manually:

```bash
openclaw channels add discord --token YOUR_TOKEN --name autonomy
```

### 4. Enable in Context

Add to your context JSON:

```json
{
  "name": "myproject",
  "notifications": {
    "discord": true,
    "on_check_fail": true,
    "on_goal_due": true,
    "channel_id": "123456789"
  }
}
```

## Usage

Once set up, the autonomy skill will:
1. Send notifications to Discord when checks fail
2. Alert when goals are approaching deadline
3. Report context switches

## Manual Testing

```bash
# Send test message
openclaw message send --channel discord --target autonomy --message "Autonomy test"

# Check status
openclaw channels list
```
