# Autonomy Skill for OpenClaw

Context-aware autonomous monitoring and execution framework.

## What It Does

Instead of running generic checks on "nothing," this skill lets you activate autonomy for **specific contexts**:
- A business you're building
- A web app you're running  
- A project you're tracking
- Any folder/workspace you care about

## Installation

### From ClawHub (recommended)

```bash
clawhub install autonomy
```

### From Local Copy

If a friend sent you this skill folder:

```bash
# Copy to your workspace
cp -r ./autonomy ~/.openclaw/workspace/skills/

# Run install script
~/.openclaw/workspace/skills/autonomy/scripts/install.sh
```

## Quick Start

```bash
# Check if autonomy is installed and running
autonomy status

# Turn on autonomy for your workspace
autonomy on

# Add a context for your web app
autonomy context add myapp ~/projects/myapp

# Turn on for that specific context
autonomy on myapp

# Turn off when you don't need it
autonomy off
```

## Commands

| Command | Description |
|---------|-------------|
| `autonomy status` | Show current autonomy state |
| `autonomy on [context]` | Activate autonomy for a context |
| `autonomy off` | Deactivate autonomy |
| `autonomy context add <name> <path>` | Add a new monitored context |
| `autonomy context remove <name>` | Remove a context |
| `autonomy context list` | List all contexts |
| `autonomy check now` | Run checks immediately |
| `autonomy config` | Show configuration |

## How It Works

1. **Contexts** are defined in `contexts/` — each has its own checks and goals
2. When `autonomy on <context>` is called, the skill:
   - Loads that context's configuration
   - Activates HEARTBEAT.md for that context only
   - Runs context-specific checks (not generic ones)
3. When `autonomy off` is called:
   - HEARTBEAT.md is disabled
   - No checks run until reactivated

## Creating Custom Checks

Add check scripts to `checks/` directory:

```bash
#!/bin/bash
# checks/my_check.sh

CONTEXT="$1"  # Context name passed as argument
CONTEXT_FILE="/path/to/workspace/skills/autonomy/contexts/${CONTEXT}.json"
PATH_TO_CHECK=$(jq -r '.path' "$CONTEXT_FILE")

# Your check logic here
echo "{\"check\": \"my_check\", \"status\": \"pass\", \"timestamp\": \"$(date -Iseconds)\"}"
```

Then add to your context:

```json
{
  "checks": ["my_check", "git_status", "file_integrity"]
}
```

## Configuration

Edit `config.json` to set:
- Default context
- Check frequency per context
- Token budgets
- Alert thresholds

## Publishing

To share this skill:

```bash
# Option 1: Publish to ClawHub
clawhub login
clawhub publish ./skills/autonomy --slug autonomy --name "Autonomy" --version 1.0.0

# Option 2: Zip and share
cd ~/.openclaw/workspace/skills
tar czf autonomy-1.0.0.tar.gz autonomy/
# Send autonomy-1.0.0.tar.gz to friend
```

## License

MIT
