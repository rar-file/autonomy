#!/bin/bash
# Post-install script for autonomy skill

echo "Installing autonomy skill..."

SKILL_DIR="${1:-$(dirname $(dirname $0))}"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"

# Create logs directory
mkdir -p "$SKILL_DIR/logs"

# Link command to workspace bin if exists
if [[ -d "$WORKSPACE/bin" ]]; then
  ln -sf "$SKILL_DIR/autonomy" "$WORKSPACE/bin/autonomy"
  echo "Linked autonomy command to workspace bin"
fi

# Copy example contexts if none exist
if [[ ! -f "$SKILL_DIR/contexts/default.json" ]]; then
  cp "$SKILL_DIR/contexts/example-default.json" "$SKILL_DIR/contexts/default.json"
fi

echo "Autonomy skill installed successfully!"
echo ""
echo "Usage:"
echo "  autonomy status     - Check autonomy state"
echo "  autonomy on         - Turn on autonomy"
echo "  autonomy off        - Turn off autonomy"
echo "  autonomy context    - Manage contexts"
echo ""
echo "To publish to clawhub:"
echo "  clawhub publish ./skills/autonomy --slug autonomy --version 1.0.0"
