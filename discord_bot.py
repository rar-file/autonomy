import discord
from discord import app_commands
from discord.ext import commands, tasks
import json
from datetime import datetime
from pathlib import Path
import asyncio

class AutonomyBot(commands.Bot):
    def __init__(self):
        intents = discord.Intents.default()
        intents.message_content = True
        
        super().__init__(
            command_prefix="!",  # Keep prefix as fallback
            intents=intents,
            activity=discord.CustomActivity(name="🟢 | Autonomy standby")
        )
        
        self.workspace = Path("/root/.openclaw/workspace")
        self.autonomy_dir = self.workspace / "skills" / "autonomy"
        self.config_file = self.autonomy_dir / "config.json"
        self.loop_file = self.autonomy_dir / "state" / "loop_config.json"
        
        # Status configuration
        self.status_config = {
            "emojis": {
                "active": "🔵",
                "checking": "🟡",
                "idle": "🟢", 
                "sleeping": "🔴",
                "off": "⚫"
            },
            "discord_status": {
                "active": discord.Status.online,
                "checking": discord.Status.online,
                "idle": discord.Status.idle,
                "sleeping": discord.Status.dnd,
                "off": discord.Status.invisible
            }
        }
    
    async def setup_hook(self):
        """Called when bot starts - register slash commands"""
        # Start presence update loop
        self.update_presence_loop.start()
        print("[Autonomy] Presence loop started")
        
        # Sync slash commands
        try:
            synced = await self.tree.sync()
            print(f"[Autonomy] Synced {len(synced)} slash command(s)")
        except Exception as e:
            print(f"[Autonomy] Failed to sync commands: {e}")
    
    def read_autonomy_state(self):
        """Read autonomy state from files"""
        try:
            if not self.config_file.exists():
                return None
                
            with open(self.config_file) as f:
                config = json.load(f)
            
            with open(self.loop_file) as f:
                loop = json.load(f)
            
            return {
                "enabled": config.get("active_context") is not None,
                "active_context": config.get("active_context"),
                "base_interval": loop.get("autonomy_loop", {}).get("base_interval_minutes", 20),
                "last_evaluation": loop.get("autonomy_loop", {}).get("last_evaluation"),
                "next_evaluation": loop.get("autonomy_loop", {}).get("next_evaluation"),
                "evaluation_count": loop.get("autonomy_loop", {}).get("evaluation_count", 0)
            }
        except Exception as e:
            print(f"[Autonomy] Error reading state: {e}")
            return None
    
    def calculate_autonomy_status(self, state):
        """Determine current autonomy status"""
        if not state:
            return "off", "Autonomy offline"
        
        if not state["enabled"]:
            return "off", "Autonomy disabled"
        
        now = datetime.now()
        
        # Parse times
        next_eval = state.get("next_evaluation")
        last_eval = state.get("last_evaluation")
        
        if not next_eval or not last_eval:
            return "active", f"Active | {state['active_context']}"
        
        try:
            next_time = datetime.fromisoformat(next_eval.replace('Z', '+00:00').replace('+00:00', ''))
            last_time = datetime.fromisoformat(last_eval.replace('Z', '+00:00').replace('+00:00', ''))
            
            time_until_next = (next_time - now).total_seconds()
            time_since_last = (now - last_time).total_seconds()
            interval_seconds = state["base_interval"] * 60
            
            # About to check (within 30s of next heartbeat)
            if -10 < time_until_next < 30:
                return "idle", f"Next heartbeat in {max(0, int(time_until_next))}s"
            
            # Just checked (within 15s of last heartbeat)
            if 0 < time_since_last < 15:
                return "checking", "Checking..."
            
            # Recently active (within last 5 min)
            if time_since_last < 300:
                return "active", f"Active | {state['active_context']}"
            
            # Calculate idle time
            idle_minutes = time_since_last / 60
            
            # Long idle (sleeping) - more than 2x base interval
            if idle_minutes > (state["base_interval"] * 2):
                return "sleeping", f"Sleeping | {int(idle_minutes)}m idle"
            
            # Normal idle - in between heartbeats
            next_in_min = time_until_next / 60 if time_until_next > 0 else 0
            return "idle", f"Idle | Next in {int(next_in_min)}m"
            
        except Exception as e:
            print(f"[Autonomy] Error calculating status: {e}")
            return "active", f"Active | {state['active_context']}"
    
    @tasks.loop(seconds=30)
    async def update_presence_loop(self):
        """Update bot presence every 30 seconds"""
        try:
            state = self.read_autonomy_state()
            status_key, status_text = self.calculate_autonomy_status(state)
            
            emoji = self.status_config["emojis"].get(status_key, "⚪")
            discord_status = self.status_config["discord_status"].get(status_key, discord.Status.online)
            
            # Create custom activity
            activity = discord.CustomActivity(name=f"{emoji} | {status_text}")
            
            # Update presence
            await self.change_presence(activity=activity, status=discord_status)
            
        except Exception as e:
            print(f"[Autonomy] Presence update error: {e}")
    
    @update_presence_loop.before_loop
    async def before_presence_loop(self):
        """Wait for bot to be ready"""
        await self.wait_until_ready()
    
    async def on_ready(self):
        """Called when bot connects"""
        print(f"[Autonomy] Bot logged in as {self.user}")
        print(f"[Autonomy] Monitoring workspace: {self.workspace}")
        print(f"[Autonomy] Invite URL: https://discord.com/oauth2/authorize?client_id={self.user.id}&permissions=2048&scope=bot%20applications.commands")
    
    # ========== SLASH COMMANDS ==========
    
    @app_commands.command(name="autonomy", description="Show autonomy system status")
    async def slash_autonomy(self, interaction: discord.Interaction):
        """Show current autonomy status"""
        state = self.read_autonomy_state()
        
        if not state:
            await interaction.response.send_message("⚫ Autonomy not configured", ephemeral=True)
            return
        
        if not state["enabled"]:
            await interaction.response.send_message(
                "⚫ Autonomy disabled. Use `/autonomy_on` to enable.", 
                ephemeral=True
            )
            return
        
        status_key, status_text = self.calculate_autonomy_status(state)
        emoji = self.status_config["emojis"].get(status_key, "⚪")
        
        embed = discord.Embed(
            title=f"{emoji} Autonomy Status",
            description=f"**Context:** `{state['active_context']}`\n**Status:** {status_text}",
            color=discord.Color.blue() if status_key == "active" else discord.Color.green(),
            timestamp=datetime.now()
        )
        embed.add_field(name="Check Interval", value=f"`{state['base_interval']}` min", inline=True)
        embed.add_field(name="Evaluations", value=f"`{state['evaluation_count']}`", inline=True)
        embed.add_field(name="Workspace", value=f"`{self.workspace}`", inline=False)
        
        await interaction.response.send_message(embed=embed, ephemeral=False)
    
    @app_commands.command(name="autonomy_on", description="Enable autonomy system")
    @app_commands.describe(context="Context to activate (optional)")
    async def slash_autonomy_on(self, interaction: discord.Interaction, context: str = None):
        """Enable autonomy"""
        ctx_name = context or "default"
        
        # Update config
        try:
            with open(self.config_file, 'r') as f:
                config = json.load(f)
            
            config["active_context"] = ctx_name
            
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            # Enable heartbeat
            heartbeat = self.workspace / "HEARTBEAT.md"
            if not heartbeat.exists():
                disabled = self.workspace / "HEARTBEAT.md.disabled"
                if disabled.exists():
                    disabled.rename(heartbeat)
            
            embed = discord.Embed(
                title="🟢 Autonomy Enabled",
                description=f"Context: `{ctx_name}`",
                color=discord.Color.green()
            )
            await interaction.response.send_message(embed=embed, ephemeral=False)
            
        except Exception as e:
            await interaction.response.send_message(
                f"❌ Error: {str(e)}", 
                ephemeral=True
            )
    
    @app_commands.command(name="autonomy_off", description="Disable autonomy system")
    async def slash_autonomy_off(self, interaction: discord.Interaction):
        """Disable autonomy"""
        try:
            with open(self.config_file, 'r') as f:
                config = json.load(f)
            
            config["active_context"] = None
            
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            # Disable heartbeat
            heartbeat = self.workspace / "HEARTBEAT.md"
            if heartbeat.exists():
                heartbeat.rename(self.workspace / "HEARTBEAT.md.disabled")
            
            embed = discord.Embed(
                title="⚫ Autonomy Disabled",
                description="System is now offline",
                color=discord.Color.red()
            )
            await interaction.response.send_message(embed=embed, ephemeral=False)
            
        except Exception as e:
            await interaction.response.send_message(
                f"❌ Error: {str(e)}", 
                ephemeral=True
            )
    
    @app_commands.command(name="autonomy_context", description="Switch to a different context")
    @app_commands.describe(name="Name of the context to activate")
    async def slash_autonomy_context(self, interaction: discord.Interaction, name: str):
        """Switch context"""
        try:
            with open(self.config_file, 'r') as f:
                config = json.load(f)
            
            # Check if context exists
            context_file = self.autonomy_dir / "contexts" / f"{name}.json"
            if not context_file.exists():
                # List available contexts
                contexts_dir = self.autonomy_dir / "contexts"
                available = [f.stem for f in contexts_dir.glob("*.json") if not f.stem.startswith("example")]
                
                embed = discord.Embed(
                    title="❌ Context Not Found",
                    description=f"Available contexts: {', '.join(f'`{c}`' for c in available)}",
                    color=discord.Color.red()
                )
                await interaction.response.send_message(embed=embed, ephemeral=True)
                return
            
            config["active_context"] = name
            
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
            
            embed = discord.Embed(
                title="🟡 Context Switched",
                description=f"Now monitoring: `{name}`",
                color=discord.Color.yellow()
            )
            await interaction.response.send_message(embed=embed, ephemeral=False)
            
        except Exception as e:
            await interaction.response.send_message(
                f"❌ Error: {str(e)}", 
                ephemeral=True
            )
    
    @app_commands.command(name="autonomy_contexts", description="List available contexts")
    async def slash_autonomy_contexts(self, interaction: discord.Interaction):
        """List all contexts"""
        try:
            contexts_dir = self.autonomy_dir / "contexts"
            contexts = []
            
            for ctx_file in contexts_dir.glob("*.json"):
                if ctx_file.stem.startswith("example"):
                    continue
                with open(ctx_file) as f:
                    ctx = json.load(f)
                    contexts.append({
                        "name": ctx.get("name", ctx_file.stem),
                        "description": ctx.get("description", "No description"),
                        "path": ctx.get("path", "Unknown")
                    })
            
            embed = discord.Embed(
                title="📋 Available Contexts",
                color=discord.Color.blue()
            )
            
            for ctx in contexts:
                embed.add_field(
                    name=f"`{ctx['name']}`",
                    value=f"{ctx['description']}\nPath: `{ctx['path']}`",
                    inline=False
                )
            
            await interaction.response.send_message(embed=embed, ephemeral=False)
            
        except Exception as e:
            await interaction.response.send_message(
                f"❌ Error: {str(e)}", 
                ephemeral=True
            )


# Run the bot
def main():
    import os
    
    # Get token from environment or OpenClaw config
    token = os.getenv("DISCORD_BOT_TOKEN")
    
    if not token:
        # Try reading from OpenClaw config
        try:
            openclaw_config = Path("/root/.openclaw/openclaw.json")
            with open(openclaw_config) as f:
                config = json.load(f)
            
            # Extract token from channels config (direct path)
            token = config.get("channels", {}).get("discord", {}).get("token")
        except Exception as e:
            print(f"Error reading config: {e}")
    
    if not token:
        print("Error: Could not find Discord bot token")
        print("Please set DISCORD_BOT_TOKEN environment variable")
        print("Or ensure OpenClaw has the Discord channel configured")
        return
    
    bot = AutonomyBot()
    bot.run(token)


if __name__ == "__main__":
    main()
