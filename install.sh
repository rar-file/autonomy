#!/bin/bash
# Agentic Autonomy - Installation Script
# This script sets up the plugin for immediate use

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     AGENTIC AUTONOMY PLUGIN - INSTALLATION               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

AUTONOMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$AUTONOMY_DIR")"

echo "📁 Installation Directory: $AUTONOMY_DIR"
echo ""

# Check dependencies
echo "🔍 Checking dependencies..."
MISSING=()

if ! command -v jq >/dev/null 2>&1; then
    MISSING+=("jq")
fi

if ! command -v python3 >/dev/null 2>&1; then
    MISSING+=("python3")
fi

if ! command -v git >/dev/null 2>&1; then
    MISSING+=("git")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "❌ Missing dependencies: ${MISSING[*]}"
    echo "Please install them and run again."
    exit 1
fi

echo "✅ All dependencies found"
echo ""

# Create required directories
echo "📂 Creating directories..."
mkdir -p "$AUTONOMY_DIR"/{tasks,agents,tools,logs,state,backups,contexts}
echo "✅ Directories created"
echo ""

# Set permissions
echo "🔐 Setting permissions..."
chmod +x "$AUTONOMY_DIR"/autonomy
chmod +x "$AUTONOMY_DIR"/checks/*.sh 2>/dev/null || true
chmod +x "$AUTONOMY_DIR"/lib/*.sh 2>/dev/null || true
echo "✅ Permissions set"
echo ""

# Initialize config if not exists
if [ ! -f "$AUTONOMY_DIR/config.json" ]; then
    echo "⚙️  Initializing configuration..."
    cat > "$AUTONOMY_DIR/config.json" << 'EOF'
{
  "skill": "autonomy",
  "version": "2.1.0",
  "name": "Agentic Autonomy",
  "description": "AI-driven self-improving autonomy for OpenClaw agents",
  "status": "active",
  "mode": "agentic",
  "daemon": {
    "interval_minutes": 5
  },
  "agentic_config": {
    "enabled": true,
    "reasoning_model": "kimi-coding/k2p5",
    "thinking": "high",
    "hard_limits": {
      "max_concurrent_tasks": 5,
      "max_sub_agents": 3,
      "max_schedules": 5,
      "daily_token_budget": 50000,
      "max_reasoning_depth": 3,
      "max_file_edits_per_session": 50,
      "max_web_searches": 10
    },
    "requires_approval": [
      "external_api_calls",
      "sending_messages",
      "file_deletion",
      "public_posts",
      "git_push",
      "installing_packages"
    ],
    "auto_approve": [
      "reading_files",
      "writing_workspace_files",
      "local_commands",
      "web_search",
      "memory_search"
    ],
    "completion_criteria": {
      "require_verification": true,
      "max_attempts": 3,
      "success_definition": "Task works as intended and passes basic tests",
      "anti_hallucination": {
        "verify_files_exist": true,
        "verify_commands_work": true,
        "require_evidence": true,
        "self_review": true
      }
    },
    "innovation_guards": {
      "prevent_redundant_builds": true,
      "check_existing_solutions": true,
      "require_impact_assessment": true,
      "max_iterations_per_task": 5,
      "completion_threshold": "good_enough_not_perfect"
    }
  },
  "workstation": {
    "active": false,
    "tasks": [],
    "running_agents": [],
    "schedules": [],
    "created_tools": [],
    "token_usage_today": 0
  },
  "default_state": "off",
  "active_context": null,
  "last_activated": null,
  "last_deactivated": null,
  "global_config": {
    "heartbeat_prompt": "You are in AGENTIC mode. Reason about what needs attention. Check your schedules, running tasks, and pending work. Decide what to do next based on priority and impact. Create tasks if needed. You have hard limits - respect them.",
    "base_interval_minutes": 20,
    "max_interval_minutes": 120,
    "work_hours": "09:00-18:00",
    "quiet_mode_enabled": true
  },
  "contexts_dir": "contexts",
  "tasks_dir": "tasks",
  "agents_dir": "agents",
  "tools_dir": "tools",
  "logs_dir": "logs"
}
EOF
    echo "✅ Configuration initialized"
else
    echo "✅ Configuration already exists"
fi
echo ""

# Create symlink for easy access
if [ -d "$WORKSPACE_DIR" ]; then
    echo "🔗 Creating symlink..."
    ln -sf "$AUTONOMY_DIR/autonomy" "$WORKSPACE_DIR/autonomy" 2>/dev/null || true
    echo "✅ Symlink created"
    echo ""
fi

# Check if HEARTBEAT.md exists in workspace
if [ -f "$WORKSPACE_DIR/HEARTBEAT.md" ]; then
    echo "📄 Found existing HEARTBEAT.md"
    echo "   The plugin will use this for heartbeat instructions."
else
    echo "⚠️  No HEARTBEAT.md found in workspace"
    echo "   Copying template..."
    cp "$AUTONOMY_DIR/HEARTBEAT.md.template" "$WORKSPACE_DIR/HEARTBEAT.md" 2>/dev/null || true
fi
echo ""

# Test the installation
echo "🧪 Testing installation..."
cd "$AUTONOMY_DIR"
if bash autonomy status >/dev/null 2>&1; then
    echo "✅ Installation test passed"
else
    echo "⚠️  Installation test had issues, but continuing..."
fi
echo ""

# Start web UI
echo "🌐 Starting web dashboard..."
if ! pgrep -f "web_ui.py" >/dev/null 2>&1; then
    nohup python3 "$AUTONOMY_DIR/web_ui.py" > /tmp/autonomy_webui.log 2>&1 &
    sleep 2
    if pgrep -f "web_ui.py" >/dev/null 2>&1; then
        echo "✅ Web dashboard started on http://localhost:8767"
    else
        echo "⚠️  Web dashboard failed to start (port may be in use)"
    fi
else
    echo "✅ Web dashboard already running"
fi
echo ""

# Final message
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              INSTALLATION COMPLETE! 🎉                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🚀 Quick Start:"
echo "   autonomy on                      # Activate"
echo "   autonomy work 'Your task here'   # Give it work"
echo "   autonomy status                  # Check status"
echo ""
echo "🌐 Web Dashboard: http://localhost:8767"
echo "📚 Documentation:  SKILL.md"
echo "⚙️  Config:        config.json"
echo ""
echo "The plugin is now ready to use!"
echo "It will respond to heartbeats and improve itself automatically."
echo ""
