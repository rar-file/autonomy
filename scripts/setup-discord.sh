#!/bin/bash
# Setup Discord connection for autonomy notifications

echo "Setting up Discord connection for Autonomy skill..."
echo ""

# Check if token provided as argument
TOKEN="${1:-}"

if [[ -z "$TOKEN" ]]; then
  echo "Usage: ./setup-discord.sh <bot-token>"
  echo ""
  echo "Get your bot token from:"
  echo "  https://discord.com/developers/applications"
  echo ""
  echo "Create a bot, copy the token, and run:"
  echo "  ./setup-discord.sh YOUR_TOKEN_HERE"
  exit 1
fi

echo "Adding Discord channel to OpenClaw..."
openclaw channels add discord \
  --token "$TOKEN" \
  --name "autonomy-bot" \
  --account "autonomy"

if [[ $? -eq 0 ]]; then
  echo ""
  echo "✓ Discord connection added successfully!"
  echo ""
  echo "Bot will be available as: @autonomy"
  echo ""
  echo "To enable notifications in a context, add to the context JSON:"
  echo '  "notifications": {"discord": "true", "channel": "your-channel-id"}'
  echo ""
  echo "Test it:"
  echo "  openclaw message send --channel discord --target autonomy --message 'Test from autonomy'"
else
  echo ""
  echo "✗ Failed to add Discord connection"
  echo "Check the error above and try again."
  exit 1
fi
