# Scheduling Options for Autonomy Plugin

## Option 1: Built-in Daemon (Current Implementation)
**What it is:** Self-contained bash daemon that runs independently

**Pros:**
- ✅ Zero external dependencies
- ✅ Works on any system (macOS, Linux, Windows WSL)
- ✅ No root/sudo required
- ✅ Full control within the plugin
- ✅ "Truly autonomous" - doesn't rely on external schedulers
- ✅ Easy to debug (logs in one place)

**Cons:**
- ❌ Must manually start (`autonomy daemon start`)
- ❌ Won't survive reboot without additional setup
- ❌ One more process to manage

**Installation Impact:** 
- **Easiest** - Just run the plugin, start daemon when ready
- No system configuration needed
- User has full control

---

## Option 2: System Cron (Traditional)
**What it is:** Uses system crontab to trigger heartbeats

**Pros:**
- ✅ Survives reboots automatically
- ✅ Battle-tested, reliable
- ✅ No daemon process to manage
- ✅ Runs even if user not logged in

**Cons:**
- ❌ Requires crontab access (sometimes restricted)
- ❌ Not available on all systems (Windows without WSL)
- ❌ Requires `crontab -e` setup step
- ❌ Less "autonomy" feeling - relies on system

**Installation Impact:**
- **Medium** - Requires one-time crontab setup
- Need to document the crontab entry
- Might fail on restricted systems

---

## Option 3: OpenClaw Native Schedules
**What it is:** Uses OpenClaw's built-in scheduling system

**Pros:**
- ✅ Native integration with OpenClaw
- ✅ Single interface for everything
- ✅ Automatically handles timing

**Cons:**
- ❌ Requires OpenClaw scheduler to be configured
- ❌ Not all OpenClaw installations have scheduler enabled
- ❌ Less transparent - "magic" happens elsewhere

**Installation Impact:**
- **Variable** - Depends on user's OpenClaw setup
- Some users will have it work immediately
- Others will need to enable OpenClaw scheduler first

---

## Recommendation: Hybrid Approach

**For easiest installation across ALL OpenClaw setups:**

1. **Default:** Built-in daemon (works everywhere)
2. **Optional:** Auto-start daemon on `autonomy on`
3. **Optional:** Detect and use cron if available
4. **Optional:** Detect and use OpenClaw scheduler if available

### Installation Flow (Easiest):
```bash
# 1. Install plugin (same for all)
cd ~/.openclaw/workspace/skills
git clone https://github.com/rar-file/autonomy

# 2. Activate (auto-starts daemon)
cd autonomy
./autonomy on
# [Daemon starts automatically]

# 3. Done! Heartbeats running every 10 min
```

### For Users Who Want Cron:
```bash
# Optional: Install cron job
./autonomy install cron
# [Adds entry to crontab, disables daemon]
```

### For Users Who Want OpenClaw Scheduler:
```bash
# Optional: Use OpenClaw scheduler
./autonomy install openclaw-schedule
# [Adds OpenClaw schedule, disables daemon]
```

---

## Implementation Plan

Add to `autonomy` CLI:
```bash
autonomy install daemon          # Use built-in daemon (default)
autonomy install cron            # Use system cron
autonomy install auto            # Auto-detect best option
```

Add to config.json:
```json
{
  "scheduler": {
    "type": "daemon",  // daemon | cron | openclaw
    "auto_start": true,
    "cron_expression": "*/10 * * * *"
  }
}
```

---

## Verdict

**For maximum compatibility and ease of installation:**

✅ **Built-in daemon as default** - Works on every system
✅ **Auto-start on `autonomy on`** - Zero extra steps
✅ **Optional cron/OpenClaw** - Power users can switch

This means:
- New users: Install → `autonomy on` → Working immediately
- Advanced users: Can switch to cron if they prefer
- All systems supported: macOS, Linux, Windows WSL
