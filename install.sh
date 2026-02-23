#!/bin/bash
# Quick install script for sharing
# This script can be run directly by a friend

set -e

echo "=== Autonomy Skill Installer ==="
echo ""

# Detect OpenClaw workspace
if [[ -n "$OPENCLAW_WORKSPACE" ]]; then
  WORKSPACE="$OPENCLAW_WORKSPACE"
elif [[ -d "$HOME/.openclaw/workspace" ]]; then
  WORKSPACE="$HOME/.openclaw/workspace"
elif [[ -d "/root/.openclaw/workspace" ]]; then
  WORKSPACE="/root/.openclaw/workspace"
else
  echo "Error: Could not find OpenClaw workspace"
  echo "Set OPENCLAW_WORKSPACE environment variable"
  exit 1
fi

echo "Found workspace: $WORKSPACE"

# Check if we're in extracted folder or need to download
if [[ -f "./SKILL.md" && -f "./autonomy" ]]; then
  # Running from extracted folder
  SOURCE_DIR="$(pwd)"
  echo "Installing from: $SOURCE_DIR"
else
  echo "Error: Run this script from the extracted autonomy folder"
  exit 1
fi

# Create skills directory
mkdir -p "$WORKSPACE/skills"

# Copy skill files
if [[ -d "$WORKSPACE/skills/autonomy" ]]; then
  echo "Backing up existing autonomy skill..."
  mv "$WORKSPACE/skills/autonomy" "$WORKSPACE/skills/autonomy.backup.$(date +%s)"
fi

cp -r "$SOURCE_DIR" "$WORKSPACE/skills/autonomy"
echo "✓ Skill files copied"

# Set permissions
chmod +x "$WORKSPACE/skills/autonomy/autonomy"
chmod +x "$WORKSPACE/skills/autonomy/scripts/"*.sh
chmod +x "$WORKSPACE/skills/autonomy/checks/"*.sh
echo "✓ Permissions set"

# Create default context if none exists
if [[ ! -f "$WORKSPACE/skills/autonomy/contexts/default.json" ]]; then
  cp "$WORKSPACE/skills/autonomy/contexts/example-default.json" \
     "$WORKSPACE/skills/autonomy/contexts/default.json"
fi

# Create logs directory
mkdir -p "$WORKSPACE/skills/autonomy/logs"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Usage:"
echo "  $WORKSPACE/skills/autonomy/autonomy status"
echo "  $WORKSPACE/skills/autonomy/autonomy on"
echo "  $WORKSPACE/skills/autonomy/autonomy context add myproject ~/myproject"
echo ""
echo "For Discord notifications:"
echo "  $WORKSPACE/skills/autonomy/scripts/setup-discord.sh YOUR_BOT_TOKEN"
echo ""
echo "Documentation:"
echo "  $WORKSPACE/skills/autonomy/README.md"
echo "  $WORKSPACE/skills/autonomy/NOTIFICATIONS.md"
