#!/bin/bash
# Post-enable script for autonomy skill

echo "Enabling autonomy skill..."

# Ensure HEARTBEAT.md is properly configured
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
HEARTBEAT="$WORKSPACE/HEARTBEAT.md"

if [[ -f "$HEARTBEAT" ]]; then
  echo "HEARTBEAT.md already exists"
else
  echo "Creating HEARTBEAT.md..."
  # The skill's SKILL.md contains the heartbeat template
fi

echo "Autonomy skill enabled!"
echo "Run 'autonomy on' to activate."
