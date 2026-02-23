# Autonomy Skill

A toggleable, context-aware autonomous monitoring and execution framework for OpenClaw.

## What It Does

Instead of running generic checks on "nothing," this skill lets you activate autonomy for **specific contexts**:
- A business you're building
- A web app you're running
- A project you're tracking
- Any folder/workspace you care about

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
| `autonomy config` | Show/edit configuration |

## Usage Examples

```bash
# Turn on autonomy for your web app
autonomy on webapp

# Check current state
autonomy status

# Add a new business context
autonomy context add mystartup ~/projects/startup

# Run checks manually
autonomy check now

# Turn off completely
autonomy off
```

## How It Works

1. **Contexts** are defined in `contexts/` — each has its own checks and goals
2. When `autonomy on <context>` is called, the skill:
   - Loads that context's configuration
   - Activates HEARTBEAT.md for that context only
   - Runs context-specific checks (not generic ones)
3. When `autonomy off` is called:
   - HEARTBEAT.md is disabled or reset to minimal
   - No checks run until reactivated

## Configuration

Edit `config.json` to set:
- Default context
- Check frequency per context
- Token budgets
- Alert thresholds
