#!/bin/bash
# Autonomy v3.1 - Installation Script

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     AUTONOMY V3.1 — INSTALLATION                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

AUTONOMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
ENABLE_CRON=false
for arg in "$@"; do
    case "$arg" in
        --enable-cron) ENABLE_CRON=true ;;
    esac
done

# Detect environment
IS_WSL=false
IS_MACOS=false
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    echo "🐧 WSL2 detected"
elif [[ "$(uname)" == "Darwin" ]]; then
    IS_MACOS=true
    echo "🍎 macOS detected"
else
    echo "🐧 Linux detected"
fi

echo "📁 Installation Directory: $AUTONOMY_DIR"
echo ""

# Check dependencies
echo "🔍 Checking dependencies..."
MISSING=()

for cmd in jq python3 git gh; do
    if ! command -v $cmd >/dev/null 2>&1; then
        MISSING+=($cmd)
    fi
done

# Check for Flask
echo "🐍 Setting up Python environment..."
if [ ! -d "$AUTONOMY_DIR/venv" ]; then
    python3 -m venv "$AUTONOMY_DIR/venv" 2>/dev/null && {
        echo "✅ Virtual environment created"
    } || {
        echo "⚠️  venv creation failed; will install globally"
    }
fi

if [ -d "$AUTONOMY_DIR/venv" ]; then
    source "$AUTONOMY_DIR/venv/bin/activate" 2>/dev/null || source "$AUTONOMY_DIR/venv/Scripts/activate" 2>/dev/null || true
    pip install -r "$AUTONOMY_DIR/requirements.txt" --quiet 2>/dev/null && {
        echo "✅ Python dependencies installed (venv)"
    } || {
        echo "⚠️  Failed to install some dependencies in venv"
    }
else
    pip3 install -r "$AUTONOMY_DIR/requirements.txt" --quiet 2>/dev/null || {
        echo "⚠️  Failed to install Python dependencies globally"
        echo "   Run: pip3 install -r $AUTONOMY_DIR/requirements.txt"
    }
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "❌ Missing dependencies: ${MISSING[*]}"
    exit 1
fi

echo "✅ All dependencies found"
echo ""

# Create directories
echo "📂 Creating directories..."
mkdir -p "$AUTONOMY_DIR"/{tasks,logs}
echo "✅ Directories created"
echo ""

# Set permissions
echo "🔐 Setting permissions..."
chmod +x "$AUTONOMY_DIR/autonomy" 2>/dev/null || true
chmod +x "$AUTONOMY_DIR/web_ui.py" 2>/dev/null || true
chmod +x "$AUTONOMY_DIR/watcher.py" 2>/dev/null || true
echo "✅ Permissions set"
echo ""

# Initialize config if needed
if [ ! -f "$AUTONOMY_DIR/config.json" ]; then
    echo "⚙️  Creating default config..."
    cat > "$AUTONOMY_DIR/config.json" << 'EOF'
{
  "version": "3.1.0",
  "limits": {
    "max_concurrent_tasks": 5,
    "daily_task_budget": 20
  },
  "github": {
    "default_repo": null,
    "notify_on_ci_fail": true
  },
  "web_ui": {
    "port": 8767,
    "auto_refresh": 30
  }
}
EOF
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              INSTALLATION COMPLETE! 🎉                   ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# OpenClaw cron setup
if $ENABLE_CRON; then
    echo "⏰ Setting up OpenClaw cron..."
    if command -v openclaw >/dev/null 2>&1; then
        openclaw cron add --name autonomy-check \
            --schedule "*/30 * * * *" \
            --command "$AUTONOMY_DIR/autonomy check --notify" 2>/dev/null && {
            echo "✅ Cron job added: autonomy check every 30 minutes"
        } || {
            echo "⚠️  Failed to add cron job. Add manually:"
            echo "   openclaw cron add --name autonomy-check --schedule '*/30 * * * *' --command '$AUTONOMY_DIR/autonomy check --notify'"
        }
    else
        echo "⚠️  openclaw CLI not found. Install OpenClaw first, then re-run with --enable-cron"
    fi
    echo ""
fi

echo "🚀 Quick Start:"
echo "   autonomy task create 'my-task' 'Description' [priority]"
echo "   autonomy task list"
echo "   autonomy gh prs"
echo "   autonomy watcher add ./src 'autonomy task create review Review changes'"
echo ""
echo "🌐 Web Dashboard:"
echo "   python3 $AUTONOMY_DIR/web_ui.py"
echo "   http://localhost:8767"
echo ""
if ! $ENABLE_CRON; then
    echo "💡 Tip: Re-run with --enable-cron to set up automatic checks:"
    echo "   bash install.sh --enable-cron"
    echo ""
fi
