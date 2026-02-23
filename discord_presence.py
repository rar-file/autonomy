# Discord Presence Integration for Autonomy
# Updates bot status based on autonomy system state

import discord
import json
import time
import asyncio
from datetime import datetime, timedelta
from pathlib import Path

class AutonomyPresence:
    def __init__(self, bot, workspace_path="/root/.openclaw/workspace"):
        self.bot = bot
        self.workspace = Path(workspace_path)
        self.autonomy_dir = self.workspace / "skills" / "autonomy"
        self.config_file = self.autonomy_dir / "config.json"
        self.loop_file = self.autonomy_dir / "state" / "loop_config.json"
        self.heartbeat_file = self.workspace / "HEARTBEAT.md"
        
        # Status mapping
        self.status_emojis = {
            "active": "🔵",
            "checking": "🟡", 
            "idle": "🟢",
            "sleeping": "🔴",
            "off": "⚫"
        }
        
        self.discord_status_map = {
            "active": discord.Status.online,
            "checking": discord.Status.online,
            "idle": discord.Status.idle,
            "sleeping": discord.Status.dnd,
            "off": discord.Status.invisible
        }
    
    def read_autonomy_state(self):
        """Read current autonomy state from files"""
        try:
            with open(self.config_file) as f:
                config = json.load(f)
            
            with open(self.loop_file) as f:
                loop = json.load(f)
            
            return {
                "enabled": config.get("active_context") is not None,
                "active_context": config.get("active_context"),
                "base_interval": loop.get("autonomy_loop", {}).get("base_interval_minutes", 20),
                "last_evaluation": loop.get("autonomy_loop", {}).get("last_evaluation"),
                "next_evaluation": loop.get("autonomy_loop", {}).get("next_evaluation")
            }
        except Exception as e:
            print(f"Error reading autonomy state: {e}")
            return None
    
    def calculate_status(self, state):
        """Determine autonomy status based on state"""
        if not state:
            return "off", "Autonomy offline"
        
        if not state["enabled"]:
            return "off", "Autonomy disabled"
        
        now = datetime.now()
        
        # Parse next evaluation time
        next_eval = state.get("next_evaluation")
        last_eval = state.get("last_evaluation")
        
        if next_eval:
            try:
                next_time = datetime.fromisoformat(next_eval.replace('Z', '+00:00'))
                last_time = datetime.fromisoformat(last_eval.replace('Z', '+00:00')) if last_eval else None
                
                time_until_next = (next_time - now).total_seconds()
                time_since_last = (now - last_time).total_seconds() if last_time else None
                
                # Calculate heartbeat cycle position
                interval_seconds = state["base_interval"] * 60
                
                # If we're within 30 seconds of next heartbeat, show "next heartbeat"
                if time_until_next and time_until_next < 30:
                    return "idle", f"Next heartbeat in {int(time_until_next)}s"
                
                # If we just had a heartbeat (within last 10 seconds), show "checking"
                if time_since_last and time_since_last < 10:
                    return "checking", "Checking..."
                
                # If heartbeat was recent (within last 5 min), show "active"
                if time_since_last and time_since_last < 300:
                    return "active", f"Active | {state['active_context']}"
                
                # Calculate idle time
                idle_minutes = time_since_last / 60 if time_since_last else 0
                
                # Long idle (sleeping) - more than 2x the base interval
                if idle_minutes > (state["base_interval"] * 2):
                    return "sleeping", f"Sleeping | {int(idle_minutes)}m idle"
                
                # Normal idle
                return "idle", f"Idle | {state['active_context']}"
                
            except Exception as e:
                print(f"Error parsing dates: {e}")
                return "active", f"Active | {state['active_context']}"
        
        return "active", f"Active | {state['active_context']}"
    
    async def update_presence(self):
        """Update Discord bot presence based on autonomy state"""
        state = self.read_autonomy_state()
        status_key, status_text = self.calculate_status(state)
        
        emoji = self.status_emojis.get(status_key, "⚪")
        discord_status = self.discord_status_map.get(status_key, discord.Status.online)
        
        # Create custom activity
        activity = discord.CustomActivity(name=f"{emoji} | {status_text}")
        
        # Update presence
        await self.bot.change_presence(activity=activity, status=discord_status)
        
        print(f"[Presence] {emoji} {status_text} ({discord_status})")
    
    async def presence_loop(self, update_interval=30):
        """Continuously update presence every N seconds"""
        await self.bot.wait_until_ready()
        
        while not self.bot.is_closed():
            try:
                await self.update_presence()
            except Exception as e:
                print(f"[Presence Error] {e}")
            
            await asyncio.sleep(update_interval)


# Example bot setup with autonomy presence
async def setup_autonomy_presence(bot, workspace_path="/root/.openclaw/workspace"):
    """Call this from your bot's setup hook"""
    presence = AutonomyPresence(bot, workspace_path)
    
    # Start the presence update loop
    bot.loop.create_task(presence.presence_loop(update_interval=30))
    
    return presence


# Standalone usage example
if __name__ == "__main__":
    # Test reading state without bot
    presence = AutonomyPresence(None, "/root/.openclaw/workspace")
    state = presence.read_autonomy_state()
    print("State:", state)
    
    if state:
        status_key, status_text = presence.calculate_status(state)
        emoji = presence.status_emojis.get(status_key, "⚪")
        print(f"Status: {emoji} | {status_text}")
