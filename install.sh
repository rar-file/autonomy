#!/bin/bash
# Autonomy v2 - Installation Script

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     AUTONOMY V2 — INSTALLATION                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

AUTONOMY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
if ! python3 -c "import flask" 2>/dev/null; then
    echo "📦 Installing Flask..."
    pip3 install flask --quiet || {
        echo "⚠️  Failed to install Flask. Web UI will not work."
        echo "   Run: pip3 install flask"
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
chmod +x "$AUTONOMY_DIR/autonomy"
chmod +x "$AUTONOMY_DIR/web_ui.py"
echo "✅ Permissions set"
echo ""

# Initialize config if needed
if [ ! -f "$AUTONOMY_DIR/config.json" ]; then
    echo "⚙️  Creating default config..."
    cat > "$AUTONOMY_DIR/config.json" << 'EOF'
{
  "version": "3.0.0",
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
echo "🚀 Quick Start:"
echo "   autonomy task create 'my-task' 'Description'"
echo "   autonomy task list"
echo "   autonomy gh prs"
echo ""
echo "🌐 Web Dashboard:"
echo "   python3 $AUTONOMY_DIR/web_ui.py"
echo "   http://localhost:8767"
echo ""
