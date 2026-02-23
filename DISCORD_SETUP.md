# Discord Setup Note

The Discord connection requires OpenClaw gateway configuration.

## To Add Discord Channel:

1. Ensure your OpenClaw gateway has Discord provider enabled
2. Run: `openclaw channels add --channel discord --token YOUR_TOKEN --name autonomy-bot`
3. Verify: `openclaw channels list`

## Alternative: Webhook Notifications

If direct Discord integration isn't available, the autonomy skill can use webhook notifications:

1. Create a Discord webhook in your server (Server Settings → Integrations → Webhooks)
2. Add webhook URL to context config:
   ```json
   {
     "notifications": {
       "webhook": "https://discord.com/api/webhooks/..."
     }
   }
   ```

## Current Status

Discord channel needs to be configured at the OpenClaw gateway level.
The autonomy skill is ready to use Discord once the channel is available.

To check available channels:
```bash
openclaw channels list
openclaw status --deep
```
