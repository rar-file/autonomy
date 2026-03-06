#!/usr/bin/env python3
"""
Autonomy Web UI v3.5
Complete dashboard with Skills, Personality, Logs, Alerts
"""

import os
import re
import json
import subprocess
import glob
import platform
import shutil
import difflib
from datetime import datetime, timedelta
from pathlib import Path
from flask import Flask, render_template, jsonify, request

app = Flask(__name__)

def require_feature(name: str):
    if not CONFIG.get("features", {}).get(name, False):
        return jsonify({"success": False, "error": f"Feature disabled: {name}"}), 403
    return None


AUTONOMY_DIR = Path(__file__).parent
TASKS_DIR = AUTONOMY_DIR / "tasks"


def task_path(task_id: str) -> Path:
    """Resolve a task JSON path from either an id or a task name.

    Canonical storage is <id>.json. For backwards-compat, we also support
    legacy <name>.json and auto-migrate when possible.
    """
    # direct id
    p = TASKS_DIR / f"{task_id}.json"
    if p.exists():
        return p

    # legacy: name.json
    legacy = TASKS_DIR / f"{task_id}.json"  # (same as above)
    if legacy.exists():
        return legacy

    name_path = TASKS_DIR / f"{task_id}.json"
    if name_path.exists():
        return name_path

    # scan by .name or .id
    for f in TASKS_DIR.glob("*.json"):
        try:
            data = json.loads(f.read_text())
        except Exception:
            continue
        if str(data.get("id")) == str(task_id) or data.get("name") == task_id:
            # migrate: if filename != <id>.json and id present
            tid = str(data.get("id")) if data.get("id") is not None else None
            if tid and f.name != f"{tid}.json":
                newp = TASKS_DIR / f"{tid}.json"
                if not newp.exists():
                    try:
                        f.rename(newp)
                        return newp
                    except Exception:
                        pass
            return f
    return p
LOGS_DIR = AUTONOMY_DIR / "logs"
CONFIG_FILE = AUTONOMY_DIR / "config.json"
OPENCLAW_HOME = Path(os.environ.get("OPENCLAW_HOME", str(Path.home() / ".openclaw")))
WORKSPACE_DIR = OPENCLAW_HOME / "workspace"
SKILLS_DIR = WORKSPACE_DIR / "skills"
STATE_FILE = AUTONOMY_DIR / "state.json"
HISTORY_FILE = AUTONOMY_DIR / "history.json"
DIGESTS_DIR = AUTONOMY_DIR / "digests"
ABTESTS_DIR = AUTONOMY_DIR / "ab_tests"

MODEL_CONTEXT_LIMITS = {
    "claude-4-opus": 200000, "claude-3.5-sonnet": 200000, "claude-3-haiku": 200000,
    "claude-3-opus": 200000, "claude-3.7-sonnet": 200000,
    "gpt-4o": 128000, "gpt-4-turbo": 128000, "gpt-4": 128000, "gpt-3.5-turbo": 16385,
    "gemini-2.0-flash": 1000000, "gemini-1.5-pro": 1000000, "gemini-1.5-flash": 1000000,
    "o1": 200000, "o1-mini": 128000, "o3-mini": 200000,
}

# ── Task Templates ──
TASK_TEMPLATES = [
    {"id": "review-pr", "name": "Review PR", "description": "Review pull request and provide feedback", "priority": "high", "tags": ["github", "review"], "estimated_minutes": 30},
    {"id": "fix-bug", "name": "Fix Bug", "description": "Investigate and fix reported bug", "priority": "high", "tags": ["bugfix", "code"], "estimated_minutes": 60},
    {"id": "write-tests", "name": "Write Tests", "description": "Write unit/integration tests for feature", "priority": "medium", "tags": ["testing", "quality"], "estimated_minutes": 45},
    {"id": "deploy", "name": "Deploy", "description": "Deploy latest changes to environment", "priority": "critical", "tags": ["devops", "deploy"], "estimated_minutes": 20},
    {"id": "docs-update", "name": "Update Docs", "description": "Update documentation for recent changes", "priority": "low", "tags": ["docs"], "estimated_minutes": 30},
    {"id": "security-audit", "name": "Security Audit", "description": "Review code for security vulnerabilities", "priority": "critical", "tags": ["security", "audit"], "estimated_minutes": 90},
    {"id": "refactor", "name": "Refactor Code", "description": "Refactor and improve code quality", "priority": "medium", "tags": ["refactor", "code"], "estimated_minutes": 60},
    {"id": "monitor-check", "name": "System Check", "description": "Check system health and resolve issues", "priority": "medium", "tags": ["monitoring", "ops"], "estimated_minutes": 15},
]



def load_config():
    """Load config.json with sane defaults."""
    cfg = {
        "web_ui": {"host": "0.0.0.0", "port": 8767, "auto_refresh": 30},
        "features": {"inject_agents_instructions": False, "skills_manager": False},
    }
    try:
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE) as f:
                user = json.load(f)
            # shallow merge
            for k,v in user.items():
                if isinstance(v, dict) and isinstance(cfg.get(k), dict):
                    cfg[k].update(v)
                else:
                    cfg[k]=v
    except Exception as e:
        print(f"[autonomy] config load failed: {e}")
    return cfg

CONFIG = load_config()

def sync_tasks_to_workspace():
    """Write current tasks to ~/.openclaw/workspace/TASKS.md so the AI agent can see them.
    This is THE critical bridge — OpenClaw reads workspace files in every conversation."""
    tasks = get_all_tasks()
    tasks_md = WORKSPACE_DIR / "TASKS.md"
    try:
        WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
        lines = ["# Autonomy Tasks\n"]
        lines.append(f"> **AI Agent: You MUST check these tasks at the start of every conversation. "
                     f"If tasks are active, tell the user. If tasks are overdue, warn the user. "
                     f"Use `autonomy task` CLI or POST to localhost:8767 API to manage them. "
                     f"Run `autonomy task sync` after any changes.**\n")
        lines.append(f"*Auto-synced at {datetime.now().strftime('%Y-%m-%d %H:%M')}*\n")
        lines.append(f"**{len([t for t in tasks if t.get('status') == 'pending'])}** pending · "
                     f"**{len([t for t in tasks if t.get('status') == 'in_progress'])}** in progress · "
                     f"**{len([t for t in tasks if t.get('status') == 'completed'])}** completed · "
                     f"**{len([t for t in tasks if t.get('status') == 'blocked'])}** blocked\n")

        # Active tasks first (pending + in_progress)
        active = [t for t in tasks if t.get("status") in ("pending", "in_progress")]
        if active:
            lines.append("\n## Active Tasks\n")
            for t in active:
                status_icon = "🔄" if t.get("status") == "in_progress" else "⏳"
                priority_icon = {"critical": "🔴", "high": "🟠", "medium": "🟡", "low": "🟢"}.get(t.get("priority", "medium"), "⚪")
                line = f"- {status_icon} {priority_icon} **{t['name']}** — {t.get('description', 'No description')}"
                if t.get("due_date"):
                    line += f" (due: {t['due_date']})"
                if t.get("tags"):
                    line += f" [{', '.join(t['tags'])}]"
                lines.append(line)
                # Include subtasks
                for sub in t.get("subtasks", []):
                    check = "✅" if sub.get("completed") else "⬜"
                    lines.append(f"  - {check} {sub['name']}")
                # Include latest note
                notes = t.get("notes", [])
                if notes:
                    lines.append(f"  > Latest note: {notes[-1].get('text', '')}")

        # Blocked tasks
        blocked = [t for t in tasks if t.get("status") == "blocked"]
        if blocked:
            lines.append("\n## Blocked Tasks\n")
            for t in blocked:
                lines.append(f"- 🚫 **{t['name']}** — {t.get('description', '')}")
                if t.get("blocked_reason"):
                    lines.append(f"  > Blocked: {t['blocked_reason']}")

        # Recently completed
        completed = [t for t in tasks if t.get("status") == "completed"][:5]
        if completed:
            lines.append("\n## Recently Completed\n")
            for t in completed:
                lines.append(f"- ✅ ~~{t['name']}~~ — {t.get('proof', 'completed')}")

        lines.append("\n---\n")
        lines.append("*Managed by the [autonomy](autonomy/) skill. "
                     "CLI: `autonomy task {create|list|work|complete|delete|sync|dispatch|status}` | "
                     "Dashboard: http://localhost:8767 | "
                     "API: POST `/api/task/create`, GET `/api/tasks`, POST `/api/tasks/sync`*\n")
        lines.append("> **After ANY task change, run `autonomy task sync` to update this file.**\n")

        with open(tasks_md, "w") as f:
            f.write("\n".join(lines))
        return True
    except Exception as e:
        print(f"[autonomy] Failed to sync tasks to workspace: {e}")
        return False


def inject_tasks_into_heartbeat():
    """Append task summary to HEARTBEAT.md so the heartbeat checks tasks every 30 min.
    OpenClaw's heartbeat reads HEARTBEAT.md and decides what needs attention.
    Written to be IMPOSSIBLE for the AI to misunderstand or ignore."""
    heartbeat_path = WORKSPACE_DIR / "HEARTBEAT.md"
    tasks = get_all_tasks()
    active = [t for t in tasks if t.get("status") in ("pending", "in_progress")]
    blocked = [t for t in tasks if t.get("status") == "blocked"]

    try:
        # Read existing HEARTBEAT.md
        existing = ""
        if heartbeat_path.exists():
            with open(heartbeat_path) as f:
                existing = f.read()

        # Remove any previous autonomy section
        marker_start = "<!-- AUTONOMY-TASKS-START -->"
        marker_end = "<!-- AUTONOMY-TASKS-END -->"
        if marker_start in existing:
            before = existing[:existing.index(marker_start)]
            after = existing[existing.index(marker_end) + len(marker_end):] if marker_end in existing else ""
            existing = before.rstrip() + "\n" + after.lstrip()

        # Build task section — harsh and explicit
        section_lines = [marker_start]
        section_lines.append(f"\n## Autonomy Tasks — YOU MUST CHECK THESE")
        section_lines.append(f"**{len(active)} active** | **{len(blocked)} blocked** | "
                           f"**{len([t for t in tasks if t.get('status') == 'completed'])} completed**")

        if active:
            overdue = [t for t in active if t.get("due_date") and t["due_date"] < datetime.now().strftime("%Y-%m-%d")]
            if overdue:
                section_lines.append(f"\n**⚠️ {len(overdue)} OVERDUE TASK(S) — DEAL WITH THESE IMMEDIATELY:**")
                for t in overdue:
                    section_lines.append(f"- **OVERDUE** 🔴 **{t['name']}**: {t.get('description', '')[:80]} (was due: {t['due_date']})")

            section_lines.append("\n**Active tasks — report status on each:**")
            for t in active[:10]:
                priority_icon = {"critical": "🔴", "high": "🟠", "medium": "🟡", "low": "🟢"}.get(t.get("priority", "medium"), "⚪")
                status_label = "IN PROGRESS" if t.get("status") == "in_progress" else "PENDING"
                line = f"- [ ] {priority_icon} [{status_label}] **{t['name']}**: {t.get('description', '')[:80]}"
                if t.get("due_date"):
                    line += f" (due: {t['due_date']})"
                if t.get("ai_dispatched"):
                    line += " [DISPATCHED TO AI]"
                section_lines.append(line)
                # Show subtask progress if any
                subtasks = t.get("subtasks", [])
                if subtasks:
                    done = sum(1 for s in subtasks if s.get("completed"))
                    section_lines.append(f"  ↳ Subtasks: {done}/{len(subtasks)} done")
            if len(active) > 10:
                section_lines.append(f"- ...and {len(active) - 10} more tasks (see TASKS.md for full list)")
        else:
            section_lines.append("\n✅ No active tasks right now.")

        if blocked:
            section_lines.append(f"\n**🚫 {len(blocked)} BLOCKED task(s) — check if blockers are resolved:**")
            for t in blocked[:5]:
                reason = t.get("blocked_reason", "no reason given")
                section_lines.append(f"- 🚫 **{t['name']}** — blocked: {reason}")

        section_lines.append(f"\n**Instructions:** Report the status of each active task. If overdue tasks exist, warn the user. "
                           f"Use `autonomy task work <name>` to start, `autonomy task complete <name> \"proof\"` to finish. "
                           f"Run `autonomy task sync` after any changes.")
        section_lines.append(f"*Synced: {datetime.now().strftime('%Y-%m-%d %H:%M')}* | Dashboard: http://localhost:8767")
        section_lines.append(marker_end)

        # Append to heartbeat
        content = existing.rstrip() + "\n\n" + "\n".join(section_lines) + "\n"
        with open(heartbeat_path, "w") as f:
            f.write(content)
        return True
    except Exception as e:
        print(f"[autonomy] Failed to inject tasks into heartbeat: {e}")
        return False


def ensure_agents_instructions():
    """Write/update the autonomy instructions block in AGENTS.md so the AI
    agent ALWAYS knows how to use the task system. This is injected between
    markers so it doesn't clobber user content."""
    agents_path = WORKSPACE_DIR / "AGENTS.md"
    marker_start = "<!-- AUTONOMY-INSTRUCTIONS-START -->"
    marker_end = "<!-- AUTONOMY-INSTRUCTIONS-END -->"

    instructions = f"""{marker_start}

## Autonomy Task System — MANDATORY INSTRUCTIONS

> **YOU ARE REQUIRED TO FOLLOW THESE INSTRUCTIONS. THEY ARE NOT OPTIONAL. NOT SUGGESTIONS. NOT GUIDELINES. THEY ARE RULES. VIOLATING THEM MEANS TASKS WILL BE LOST, IGNORED, OR INVISIBLE.**

### What Is Autonomy?

Autonomy is YOUR task management system. It stores tasks as JSON files in the `autonomy/tasks/` directory and syncs them to `TASKS.md` (this workspace) and `HEARTBEAT.md` (your heartbeat loop). You have a CLI (`autonomy`) and a web API (`localhost:8767`) to manage tasks.

### RULES — READ EVERY SINGLE ONE

1. **USE THE TASK SYSTEM.** When the user asks you to track work, create tasks, manage a to-do list, or anything involving work items — use `autonomy task create`. Do NOT track work in your head, in memory files, in conversation, or anywhere else. The task system exists. Use it.

2. **CHECK TASKS.MD AT CONVERSATION START.** Every single time a new conversation begins, read `TASKS.md` in this workspace. If there are active tasks, tell the user: "You have N active tasks." List the top priorities. Ask if they want to work on any.

3. **SYNC AFTER EVERY CHANGE.** After you create, complete, update, delete, or change the status of any task — you MUST run `autonomy task sync` (CLI) or POST to `http://localhost:8767/api/tasks/sync` (API). If you do not sync, your changes will NOT appear in TASKS.md or HEARTBEAT.md. The user will think nothing happened. This is the #1 cause of "tasks don't work."

4. **MARK TASKS IN PROGRESS.** Before you start working on a task, mark it as in_progress: `autonomy task work <name>`. This tells the user (and the dashboard) that you are actively working on it.

5. **COMPLETE WITH PROOF.** When you finish a task, you MUST provide proof: `autonomy task complete <name> "What I actually did"`. Examples of good proof: "Fixed the null check in auth.py line 42, added unit test", "Deployed v2.1.0 to staging, verified health endpoint". Examples of BAD proof: "Done", "Completed", "Finished task". Be specific.

6. **BREAK BIG TASKS INTO SUBTASKS.** If a task has multiple steps, create subtasks. POST to `/api/tasks/<id>/subtask` with `{{"name": "step description"}}`. Toggle them done as you complete each step. This gives the user visibility into your progress.

7. **ADD NOTES FOR LONG TASKS.** If you're working on something that takes multiple messages or you find important information, add a note: POST to `/api/tasks/<id>/notes` with `{{"text": "Found root cause: the config file was missing..."}}`.

8. **USE DISPATCH FOR PARALLEL WORK.** If the user wants multiple things done simultaneously, use task dispatch: POST to `/api/tasks/<id>/dispatch`. This spawns a sub-agent that works on the task independently. Do NOT try to do everything sequentially when parallel execution is possible.

9. **RESPECT STATUS LIFECYCLE.** Valid statuses: `pending`, `in_progress`, `completed`, `blocked`, `cancelled`, `deferred`. Only move forward in the lifecycle. If you're blocked, set status to `blocked` with a `blocked_reason`. Don't leave tasks in limbo.

10. **DURING HEARTBEAT.** When the heartbeat fires, check the Autonomy Tasks section of HEARTBEAT.md. If there are overdue tasks (past due_date), WARN the user immediately. Report status of in_progress tasks. Suggest next actions for pending tasks.

### Quick Reference

| Action | CLI Command | API Endpoint |
|--------|------------|--------------|
| Create task | `autonomy task create "name" "desc" [priority]` | POST `/api/task/create` |
| List tasks | `autonomy task list` | GET `/api/tasks` |
| Start work | `autonomy task work "name"` | POST `/api/tasks/<id>/status` `{{"status":"in_progress"}}` |
| Complete | `autonomy task complete "name" "proof"` | POST `/api/tasks/<id>/complete` `{{"proof":"..."}}` |
| Delete | `autonomy task delete "name"` | DELETE `/api/tasks/<id>/delete` |
| Add note | — | POST `/api/tasks/<id>/notes` `{{"text":"..."}}` |
| Add subtask | — | POST `/api/tasks/<id>/subtask` `{{"name":"..."}}` |
| Dispatch to AI | `autonomy task dispatch "name"` | POST `/api/tasks/<id>/dispatch` |
| **Sync (REQUIRED)** | `autonomy task sync` | POST `/api/tasks/sync` |
| Parse NL | — | POST `/api/tasks/parse` `{{"text":"Fix bug by Friday #urgent !high"}}` |
| Templates | — | GET `/api/tasks/templates` |

### NL Parsing Syntax

`"Fix the auth bug by March 10 #security #backend !critical ~60m"`

- `#tag` → tags: ["security", "backend"]
- `!critical` → priority: critical (also: !high, !medium, !low)
- `~60m` → estimated_minutes: 60 (also: ~2h = 120)
- `by March 10` → due_date: 2026-03-10 (also: by tomorrow, by next week, by Friday)

### Dashboard

Web UI at `http://localhost:8767` — has full task management, skill browser, personality editor, system health, GitHub integration, and activity history. Tell the user about it if they want a visual overview.

### What Happens If You Ignore These Rules

- Tasks will be invisible to the user
- The heartbeat will show "No active tasks" even when work is pending
- The dashboard will be empty
- The user will be frustrated
- You will have failed at your job

**Do not fail at your job.**

{marker_end}"""

    try:
        WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
        existing = ""
        if agents_path.exists():
            with open(agents_path) as f:
                existing = f.read()

        # Remove old autonomy section if present
        if marker_start in existing:
            before = existing[:existing.index(marker_start)]
            after = existing[existing.index(marker_end) + len(marker_end):] if marker_end in existing else ""
            existing = before.rstrip() + "\n" + after.lstrip()

        # Append instructions
        content = existing.rstrip() + "\n\n" + instructions + "\n"
        with open(agents_path, "w") as f:
            f.write(content)
        return True
    except Exception as e:
        print(f"[autonomy] Failed to write AGENTS.md instructions: {e}")
        return False


def sync_all_tasks():
    """Sync tasks to workspace TASKS.md + HEARTBEAT.md (and optionally AGENTS.md instructions)."""
    s1 = sync_tasks_to_workspace()
    s2 = inject_tasks_into_heartbeat()
    if CONFIG.get("features", {}).get("inject_agents_instructions", False):
        s3 = ensure_agents_instructions()
    else:
        s3 = True
    return s1 and s2 and s3


def estimate_tokens(text):
    """Rough token estimate: ~4 chars per token for English text."""
    return len(text) // 4

def calculate_progress(task):
    """Calculate task progress percentage from subtasks."""
    subtasks = task.get("subtasks", [])
    if not subtasks:
        return 100 if task.get("status") == "completed" else 0
    completed = sum(1 for s in subtasks if s.get("completed"))
    return round(completed / len(subtasks) * 100)

def get_openclaw_status():
    try:
        result = subprocess.run(
            ["openclaw", "status", "--json"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except:
        pass
    return None

def get_github_status():
    try:
        result = subprocess.run(
            ["gh", "api", "notifications", "--jq", "[.[] | select(.unread)] | length"],
            capture_output=True, text=True, timeout=10
        )
        notifications = int(result.stdout.strip()) if result.returncode == 0 else 0

        result = subprocess.run(
            ["gh", "pr", "list", "--author", "@me", "--state", "open", "--json", "number", "-q", "length"],
            capture_output=True, text=True, timeout=10
        )
        my_prs = int(result.stdout.strip()) if result.returncode == 0 else 0

        result = subprocess.run(
            ["gh", "pr", "list", "--review-requested=@me", "--state", "open", "--json", "number", "-q", "length"],
            capture_output=True, text=True, timeout=10
        )
        reviews = int(result.stdout.strip()) if result.returncode == 0 else 0

        return {"notifications": notifications, "my_prs": my_prs, "reviews": reviews, "connected": True}
    except:
        return {"notifications": 0, "my_prs": 0, "reviews": 0, "connected": False}

def get_all_tasks():
    tasks = []
    if TASKS_DIR.exists():
        for task_file in TASKS_DIR.glob("*.json"):
            try:
                with open(task_file) as f:
                    task = json.load(f)
                    tasks.append(task)
            except:
                pass
    return sorted(tasks, key=lambda x: x.get("created_at", ""), reverse=True)

def parse_skill_frontmatter(content: str):
    """Very small frontmatter parser for SKILL.md."""
    name = None
    desc = None
    version = None
    if content.lstrip().startswith('---'):
        # take lines between first two ---
        parts = content.split("\n")
        # find second ---
        try:
            i0 = parts.index('---')
            i1 = parts.index('---', i0+1)
            fm = parts[i0+1:i1]
        except ValueError:
            fm = []
        for line in fm:
            line=line.strip()
            if line.startswith('name:'):
                name=line.split(':',1)[1].strip().strip('"').strip("'")
            elif line.startswith('description:'):
                desc=line.split(':',1)[1].strip().strip('"').strip("'")
            elif line.startswith('version:'):
                version=line.split(':',1)[1].strip().strip('"').strip("'")
    # fallback: scan top few lines
    if not desc:
        for line in content.split("\n")[:30]:
            if line.startswith('description:'):
                desc=line.split(':',1)[1].strip().strip('"').strip("'")
                break
    return name, desc, version


def get_skills():
    skills = []
    if SKILLS_DIR.exists():
        for skill_dir in sorted([d for d in SKILLS_DIR.iterdir() if d.is_dir()], key=lambda p: p.name.lower()):
            skill_file = skill_dir / 'SKILL.md'
            if not skill_file.exists():
                continue
            try:
                content = skill_file.read_text(errors='replace')
                fm_name, fm_desc, fm_ver = parse_skill_frontmatter(content)
                # display name: frontmatter name or folder name
                display = fm_name or skill_dir.name
                desc = fm_desc or 'No description'
                version = fm_ver or '1.0.0'
                enabled = not (skill_dir / '.disabled').exists()
                skills.append({
                    'name': skill_dir.name,            # folder key
                    'displayName': display,            # frontmatter name
                    'description': desc,
                    'path': str(skill_dir),
                    'version': version,
                    'enabled': enabled,
                    'icon': '⚡'
                })
            except Exception:
                continue
    return skills

def get_skill_detail(name):
    """Get detailed info about a specific skill"""
    skill_dir = SKILLS_DIR / name
    if not skill_dir.exists():
        return None

    result = {
        "name": name,
        "description": "",
        "version": "1.0.0",
        "commands": [],
        "files": [],
        "readme": "",
        "enabled": True
    }

    # Parse SKILL.md
    skill_file = skill_dir / "SKILL.md"
    if skill_file.exists():
        with open(skill_file) as f:
            content = f.read()
            result["skill_md"] = content
            for line in content.split("\n")[:30]:
                if line.startswith("description:") or line.startswith("_"):
                    result["description"] = line.split(":", 1)[1].strip() if ":" in line else line.strip("_ ")
                if "version" in line.lower() and ":" in line:
                    result["version"] = line.split(":", 1)[1].strip().strip('"').strip("'")

    # Parse README.md
    readme_file = skill_dir / "README.md"
    if readme_file.exists():
        with open(readme_file) as f:
            result["readme"] = f.read()

    # List files
    for f in skill_dir.iterdir():
        if f.is_file():
            result["files"].append({
                "name": f.name,
                "size": f.stat().st_size
            })

    # Check if enabled
    result["enabled"] = not (skill_dir / ".disabled").exists()

    return result

def get_personality_files():
    files = []
    workspace = WORKSPACE_DIR
    personality_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md", "HEARTBEAT.md", "TASKS.md", "BOOT.md"]

    for fname in personality_files:
        fpath = workspace / fname
        if fpath.exists():
            try:
                stat = fpath.stat()
                with open(fpath) as f:
                    content = f.read()
                files.append({
                    "name": fname,
                    "path": str(fpath),
                    "size": stat.st_size,
                    "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "content": content[:5000]  # First 5000 chars
                })
            except:
                pass
    return files

def get_logs():
    logs = []
    # Check system logs
    try:
        result = subprocess.run(
            ["journalctl", "-u", "openclaw", "-n", "50", "--no-pager", "-o", "short-iso"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split("\n")[-20:]:
                if line:
                    parts = line.split(" ", 2)
                    if len(parts) >= 3:
                        logs.append({
                            "time": parts[0],
                            "level": "info",
                            "message": parts[2]
                        })
    except:
        pass
    return logs

def get_alerts():
    alerts = []
    # Check for pending tasks
    tasks = get_all_tasks()
    pending = [t for t in tasks if t.get("status") == "pending"]
    if len(pending) > 3:
        alerts.append({
            "type": "warning",
            "title": f"{len(pending)} pending tasks",
            "message": "You have several tasks waiting to be started."
        })

    # Check GitHub notifications
    gh = get_github_status()
    if gh.get("notifications", 0) > 0:
        alerts.append({
            "type": "info",
            "title": f"{gh['notifications']} GitHub notifications",
            "message": "You have unread notifications on GitHub."
        })

    # Check CI failures
    try:
        result = subprocess.run(
            ["gh", "run", "list", "--status", "failure", "--limit", "1", "--json", "status"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0 and "failure" in result.stdout:
            alerts.append({
                "type": "error",
                "title": "CI Failure",
                "message": "Recent workflow run failed."
            })
    except:
        pass

    return alerts

def get_system_health():
    health = {}
    try:
        with open("/proc/stat") as f:
            line = f.readline()
            fields = line.split()
            if len(fields) >= 5:
                user, nice, system, idle = int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4])
                total = user + nice + system + idle
                health["cpu"] = f"{(user + nice + system) / total * 100:.1f}%"
    except:
        health["cpu"] = "N/A"

    try:
        result = subprocess.run(["free"], capture_output=True, text=True)
        for line in result.stdout.split("\n"):
            if line.startswith("Mem:"):
                parts = line.split()
                used, total = int(parts[2]), int(parts[1])
                health["memory"] = f"{used/total*100:.1f}%"
                health["memory_gb"] = f"{used/1024/1024:.1f}G / {total/1024/1024:.1f}G"
                break
    except:
        health["memory"] = "N/A"

    try:
        result = subprocess.run(["df", "/"], capture_output=True, text=True)
        lines = result.stdout.strip().split("\n")
        if len(lines) > 1:
            health["disk"] = lines[1].split()[4]
    except:
        health["disk"] = "N/A"

    try:
        result = subprocess.run(["uptime"], capture_output=True, text=True)
        if "load average:" in result.stdout:
            health["load"] = result.stdout.split("load average:")[1].strip()
    except:
        health["load"] = "N/A"

    return health

def get_processes():
    processes = {"cpu": [], "memory": []}
    try:
        result = subprocess.run(["ps", "aux", "--sort=-%cpu"], capture_output=True, text=True)
        for line in result.stdout.strip().split("\n")[1:6]:
            parts = line.split()
            if len(parts) >= 11:
                processes["cpu"].append({
                    "pid": parts[1], "cpu": parts[2], "mem": parts[3],
                    "cmd": " ".join(parts[10:])[:30]
                })
    except:
        pass
    return processes

def get_docker():
    containers = []
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}|{{.Status}}|{{.Ports}}"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split("\n"):
                if line:
                    parts = line.split("|")
                    containers.append({
                        "name": parts[0], "status": parts[1], "ports": parts[2] if len(parts) > 2 else ""
                    })
    except:
        pass
    return containers

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status")
def api_status():
    return jsonify({
        "openclaw": get_openclaw_status(),
        "github": get_github_status(),
        "tasks": get_all_tasks(),
        "skills": get_skills(),
        "personality": get_personality_files(),
        "logs": get_logs(),
        "alerts": get_alerts(),
        "health": get_system_health(),
        "processes": get_processes(),
        "docker": get_docker(),
        "timestamp": datetime.now().isoformat()
    })

@app.route("/api/tasks")
def api_tasks():
    return jsonify(get_all_tasks())

@app.route("/api/task/create", methods=["POST"])
def create_task():
    data = request.json
    name = data.get("name", "").strip().replace(" ", "_").lower()
    name = re.sub(r'[^a-z0-9_-]', '', name)  # Sanitize
    desc = data.get("description", "")
    if not name:
        return jsonify({"success": False, "error": "Name required"}), 400

    TASKS_DIR.mkdir(exist_ok=True)

    priority = data.get("priority", "medium")
    if priority not in ("critical", "high", "medium", "low"):
        priority = "medium"

    task = {
        "id": int(datetime.now().timestamp()),
        "name": name,
        "description": desc,
        "status": "pending",
        "priority": priority,
        "depends_on": data.get("depends_on", []),
        "tags": data.get("tags", []),
        "due_date": data.get("due_date", None),
        "estimated_minutes": data.get("estimated_minutes", None),
        "execution_mode": data.get("execution_mode", "manual"),  # manual | agent | cron
        "notes": [],
        "subtasks": [],
        "created_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
        "completed_at": None,
        "proof": None,
        "blocked_reason": None,
        "ai_dispatched": False,
        "dispatch_session": None
    }

    task_file = TASKS_DIR / f"{task['id']}.json"
    if task_file.exists():
        return jsonify({"success": False, "error": "Task already exists"}), 400

    record_event("task_created", f"Task '{name}' (priority: {priority})")

    with open(task_file, "w") as f:
        json.dump(task, f, indent=2)

    # Sync to workspace so OpenClaw AI can see the task
    sync_all_tasks()

    return jsonify({"success": True, "task": task})


@app.route("/api/tasks/<task_id>/complete", methods=["POST"])
def complete_task(task_id):
    task_file = task_path(task_id)
    if task_file.exists():
        with open(task_file) as f:
            task = json.load(f)
        task["status"] = "completed"
        task["completed_at"] = datetime.now().isoformat()
        task["updated_at"] = datetime.now().isoformat()
        task["proof"] = request.json.get("proof", "")
        with open(task_file, "w") as f:
            json.dump(task, f, indent=2)
        record_event("task_completed", f"Task '{task_id}' completed")
        sync_all_tasks()
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Task not found"}), 404


@app.route("/api/tasks/<task_id>/status", methods=["POST"])
def update_task_status(task_id):
    """Change task status with full lifecycle support."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    data = request.json
    new_status = data.get("status", "")
    valid_statuses = ["pending", "in_progress", "completed", "blocked", "cancelled", "deferred"]
    if new_status not in valid_statuses:
        return jsonify({"success": False, "error": f"Invalid status. Use: {', '.join(valid_statuses)}"}), 400
    with open(task_file) as f:
        task = json.load(f)
    old_status = task.get("status")
    task["status"] = new_status
    task["updated_at"] = datetime.now().isoformat()
    if new_status == "completed":
        task["completed_at"] = datetime.now().isoformat()
    if new_status == "blocked":
        task["blocked_reason"] = data.get("reason", "")
    with open(task_file, "w") as f:
        json.dump(task, f, indent=2)
    record_event("task_status_changed", f"Task '{task_id}': {old_status} → {new_status}")
    sync_all_tasks()
    return jsonify({"success": True, "old_status": old_status, "new_status": new_status})


@app.route("/api/tasks/<task_id>/update", methods=["POST"])
def update_task(task_id):
    """Update any task fields (description, priority, tags, due_date, etc)."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    data = request.json
    with open(task_file) as f:
        task = json.load(f)
    # Allow updating these fields
    updatable = ["description", "priority", "tags", "due_date", "estimated_minutes",
                 "depends_on", "execution_mode", "blocked_reason"]
    changed = []
    for key in updatable:
        if key in data:
            task[key] = data[key]
            changed.append(key)
    if changed:
        task["updated_at"] = datetime.now().isoformat()
        with open(task_file, "w") as f:
            json.dump(task, f, indent=2)
        record_event("task_updated", f"Task '{task_id}' updated: {', '.join(changed)}")
        sync_all_tasks()
    return jsonify({"success": True, "updated": changed})


@app.route("/api/tasks/<task_id>/delete", methods=["DELETE"])
def delete_task(task_id):
    """Delete a task permanently."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    task_file.unlink()
    record_event("task_deleted", f"Task '{task_id}' deleted")
    sync_all_tasks()
    return jsonify({"success": True})


@app.route("/api/tasks/<task_id>/notes", methods=["POST"])
def add_task_note(task_id):
    """Add a note/comment to a task."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    data = request.json
    text = data.get("text", "").strip()
    if not text:
        return jsonify({"success": False, "error": "Note text required"}), 400
    with open(task_file) as f:
        task = json.load(f)
    if "notes" not in task:
        task["notes"] = []
    task["notes"].append({
        "text": text,
        "timestamp": datetime.now().isoformat()
    })
    task["updated_at"] = datetime.now().isoformat()
    with open(task_file, "w") as f:
        json.dump(task, f, indent=2)
    return jsonify({"success": True, "notes_count": len(task["notes"])})


@app.route("/api/tasks/<task_id>/dispatch", methods=["POST"])
def dispatch_task(task_id):
    """Send a task to OpenClaw AI for execution via sub-agent or cron.
    This is the key integration — makes the AI actually work on the task."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    with open(task_file) as f:
        task = json.load(f)

    data = request.json or {}
    mode = data.get("mode", task.get("execution_mode", "agent"))

    # Build the prompt for the AI
    prompt_lines = [f"Work on this task: {task['name']}"]
    prompt_lines.append(f"Description: {task.get('description', 'No description')}")
    if task.get("priority") in ("critical", "high"):
        prompt_lines.append(f"⚠️ This is a {task['priority']} priority task.")
    if task.get("subtasks"):
        prompt_lines.append("Subtasks:")
        for s in task["subtasks"]:
            check = "✅" if s.get("completed") else "⬜"
            prompt_lines.append(f"  {check} {s['name']}")
    if task.get("notes"):
        prompt_lines.append(f"Latest note: {task['notes'][-1]['text']}")
    prompt_lines.append(f"\nWhen done, update the task status. The task file is at: {task_file}")
    prompt_lines.append("Mark subtasks as completed as you work through them.")
    prompt = "\n".join(prompt_lines)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    session_id = f"autonomy-task-{task_id}-{timestamp}"

    try:
        if mode == "cron":
            # Register as a one-shot cron job
            result = subprocess.run(
                ["openclaw", "cron", "add",
                 "--name", f"task:{task_id}",
                 "--at", "1s",
                 "--session", "isolated",
                 "--message", prompt],
                capture_output=True, text=True, timeout=15
            )
            dispatch_type = "cron"
        else:
            # Spawn a sub-agent (default — most reliable)
            result = subprocess.run(
                ["openclaw", "agent",
                 "--local",
                 "--session-id", session_id,
                 "--message", prompt,
                 "--thinking", "low",
                 "--timeout", "300"],
                capture_output=True, text=True,
                timeout=310
            )
            dispatch_type = "agent"

        # Update task status and record dispatch
        task["status"] = "in_progress"
        task["updated_at"] = datetime.now().isoformat()
        task["ai_dispatched"] = True
        task["dispatch_session"] = session_id
        task["execution_mode"] = mode
        with open(task_file, "w") as f:
            json.dump(task, f, indent=2)

        record_event("task_dispatched", f"Task '{task_id}' sent to AI ({dispatch_type})")
        sync_all_tasks()

        # Parse AI response
        output = ""
        if result.stdout:
            lines = [l.strip() for l in result.stdout.strip().split('\n') if l.strip()]
            content_lines = [l for l in lines if not l.startswith(('Runtime:', 'Session:', 'Model:', 'Tools:'))]
            output = '\n'.join(content_lines[-10:]) if content_lines else ""

        return jsonify({
            "success": True,
            "dispatch_type": dispatch_type,
            "session_id": session_id,
            "output": output,
            "return_code": result.returncode
        })

    except subprocess.TimeoutExpired:
        task["status"] = "in_progress"
        task["ai_dispatched"] = True
        task["dispatch_session"] = session_id
        task["updated_at"] = datetime.now().isoformat()
        with open(task_file, "w") as f:
            json.dump(task, f, indent=2)
        sync_all_tasks()
        return jsonify({"success": True, "dispatch_type": "agent", "session_id": session_id,
                        "output": "Task dispatched — AI is still working on it in the background."})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/tasks/sync", methods=["POST"])
def api_sync_tasks():
    """Force sync tasks to OpenClaw workspace files."""
    success = sync_all_tasks()
    return jsonify({"success": success, "message": "Tasks synced to TASKS.md and HEARTBEAT.md"})


@app.route("/api/tasks/parse", methods=["POST"])
def parse_natural_language_task():
    """Parse natural language into a structured task using AI."""
    data = request.json
    text = data.get("text", "").strip()
    if not text:
        return jsonify({"success": False, "error": "Text required"}), 400

    # Try local parsing first (fast, no AI needed)
    parsed = local_parse_task(text)

    # If local parse is confident, use it
    if parsed.get("confidence", 0) > 0.7:
        return jsonify({"success": True, "task": parsed, "method": "local"})

    # Fall back to AI parsing
    prompt = f"""Parse this into a task JSON. Return ONLY valid JSON, no explanation.
Input: "{text}"
Return format: {{"name": "slug-name", "description": "what to do", "priority": "low|medium|high|critical", "tags": ["tag1"], "due_date": "YYYY-MM-DD or null", "estimated_minutes": number_or_null}}"""

    try:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        result = subprocess.run(
            ["openclaw", "agent", "--local", "--session-id", f"webui-parse-{timestamp}",
             "--message", prompt, "--thinking", "minimal", "--timeout", "20"],
            capture_output=True, text=True, timeout=25
        )
        if result.stdout:
            # Extract JSON from response
            stdout = result.stdout.strip()
            # Find JSON in output
            json_match = re.search(r'\{[^{}]*"name"[^{}]*\}', stdout)
            if json_match:
                ai_parsed = json.loads(json_match.group())
                # Sanitize name
                ai_parsed["name"] = re.sub(r'[^a-z0-9_-]', '', ai_parsed.get("name", "").replace(" ", "_").lower())
                return jsonify({"success": True, "task": ai_parsed, "method": "ai"})
    except:
        pass

    # Return local parse as fallback
    return jsonify({"success": True, "task": parsed, "method": "local"})


def local_parse_task(text):
    """Fast local parser for natural language task input."""
    text_lower = text.lower().strip()

    # Extract priority from keywords
    priority = "medium"
    if any(w in text_lower for w in ["urgent", "asap", "critical", "emergency", "immediately"]):
        priority = "critical"
    elif any(w in text_lower for w in ["important", "high priority", "high prio"]):
        priority = "high"
    elif any(w in text_lower for w in ["when you can", "low priority", "eventually", "someday"]):
        priority = "low"

    # Extract due date
    due_date = None
    today = datetime.now()
    if "tomorrow" in text_lower:
        due_date = (today + timedelta(days=1)).strftime("%Y-%m-%d")
    elif "today" in text_lower:
        due_date = today.strftime("%Y-%m-%d")
    elif "next week" in text_lower:
        due_date = (today + timedelta(days=7)).strftime("%Y-%m-%d")
    elif "next month" in text_lower:
        due_date = (today + timedelta(days=30)).strftime("%Y-%m-%d")
    else:
        # Try to match YYYY-MM-DD
        date_match = re.search(r'(\d{4}-\d{2}-\d{2})', text)
        if date_match:
            due_date = date_match.group(1)

    # Extract tags from hashtags
    tags = re.findall(r'#(\w+)', text)

    # Detect common task types for implicit tags
    if any(w in text_lower for w in ["review pr", "pull request", "code review"]):
        tags.append("review")
    if any(w in text_lower for w in ["fix bug", "bugfix", "broken", "not working"]):
        tags.append("bugfix")
    if any(w in text_lower for w in ["deploy", "release", "ship"]):
        tags.append("deploy")
    if any(w in text_lower for w in ["test", "testing", "write test"]):
        tags.append("testing")
    if any(w in text_lower for w in ["docs", "documentation", "readme"]):
        tags.append("docs")

    # Extract estimated time
    estimated_minutes = None
    time_match = re.search(r'(\d+)\s*(min|minute|minutes|mins|m)\b', text_lower)
    if time_match:
        estimated_minutes = int(time_match.group(1))
    else:
        hr_match = re.search(r'(\d+)\s*(hour|hours|hr|hrs|h)\b', text_lower)
        if hr_match:
            estimated_minutes = int(hr_match.group(1)) * 60

    # Clean up the text to generate name and description
    # Remove special tokens we already parsed
    clean = re.sub(r'#\w+', '', text)  # Remove hashtags
    clean = re.sub(r'\d{4}-\d{2}-\d{2}', '', clean)  # Remove dates
    clean = re.sub(r'\d+\s*(min|minute|minutes|mins|m|hour|hours|hr|hrs|h)\b', '', clean, flags=re.I)
    for word in ["urgent", "asap", "critical", "important", "tomorrow", "today", "next week", "next month",
                 "high priority", "low priority", "when you can", "eventually", "someday"]:
        clean = clean.replace(word, "")
    clean = re.sub(r'\s+', ' ', clean).strip()

    # Generate slug name (first ~4 words)
    words = clean.split()[:4]
    name = re.sub(r'[^a-z0-9_-]', '', "-".join(words).lower())
    if not name:
        name = f"task-{int(datetime.now().timestamp())}"

    confidence = 0.8 if (priority != "medium" or due_date or tags) else 0.5

    return {
        "name": name,
        "description": clean or text,
        "priority": priority,
        "tags": list(set(tags)),
        "due_date": due_date,
        "estimated_minutes": estimated_minutes,
        "confidence": confidence
    }


@app.route("/api/tasks/templates")
def api_task_templates():
    """Get available task templates."""
    return jsonify(TASK_TEMPLATES)

@app.route("/api/skills/<name>")
def skill_detail(name):
    blocked = require_feature("skills_manager")
    if blocked:
        return blocked

    """Get detailed info about a specific skill"""
    detail = get_skill_detail(name)
    if detail:
        return jsonify(detail)
    return jsonify({"error": "Skill not found"}), 404

@app.route("/api/skills/<name>/toggle", methods=["POST"])
def toggle_skill(name):
    blocked = require_feature("skills_manager")
    if blocked:
        return blocked

    """Enable/disable a skill"""
    skill_dir = SKILLS_DIR / name
    if not skill_dir.exists():
        return jsonify({"success": False, "error": "Skill not found"}), 404

    data = request.json
    enabled = data.get("enabled", True)

    disabled_file = skill_dir / ".disabled"

    if enabled:
        # Enable: remove .disabled file if exists
        if disabled_file.exists():
            disabled_file.unlink()
    else:
        # Disable: create .disabled file
        disabled_file.touch()

    return jsonify({"success": True, "enabled": enabled})


@app.route("/api/skills/<name>/files")
def list_skill_files(name):
    blocked = require_feature("skills_manager")
    if blocked:
        return blocked

    skill_dir = (SKILLS_DIR / name).resolve()
    if not skill_dir.exists():
        return jsonify({"success": False, "error": "Skill not found"}), 404

    # Prevent traversal
    if SKILLS_DIR.resolve() not in skill_dir.parents:
        return jsonify({"success": False, "error": "Invalid skill path"}), 400

    files = []
    for f in skill_dir.rglob("*"):
        if f.is_file():
            rel = str(f.relative_to(skill_dir))
            if any(part in rel.split("/") for part in (".git", "__pycache__")):
                continue
            files.append({"path": rel, "bytes": f.stat().st_size})

    files.sort(key=lambda x: x["path"])
    return jsonify({"success": True, "name": name, "files": files})


@app.route("/api/skills/<name>/file")
def get_skill_file(name):
    blocked = require_feature("skills_manager")
    if blocked:
        return blocked

    relpath = request.args.get("path", "SKILL.md")
    skill_dir = (SKILLS_DIR / name).resolve()
    if not skill_dir.exists():
        return jsonify({"success": False, "error": "Skill not found"}), 404

    if SKILLS_DIR.resolve() not in skill_dir.parents:
        return jsonify({"success": False, "error": "Invalid skill path"}), 400

    fpath = (skill_dir / relpath).resolve()
    if skill_dir not in fpath.parents and fpath != skill_dir:
        return jsonify({"success": False, "error": "Invalid file path"}), 400

    if not fpath.exists() or not fpath.is_file():
        return jsonify({"success": False, "error": "File not found"}), 404

    if fpath.stat().st_size > 200_000:
        return jsonify({"success": False, "error": "File too large"}), 413

    return jsonify({"success": True, "name": name, "path": relpath, "content": fpath.read_text(errors="replace")})


@app.route("/api/skills/<name>/file", methods=["POST"])
def save_skill_file(name):
    blocked = require_feature("skills_manager")
    if blocked:
        return blocked

    data = request.json or {}
    relpath = (data.get("path") or "SKILL.md").strip()
    content = data.get("content")
    if content is None:
        return jsonify({"success": False, "error": "content required"}), 400

    skill_dir = (SKILLS_DIR / name).resolve()
    if not skill_dir.exists():
        return jsonify({"success": False, "error": "Skill not found"}), 404

    if SKILLS_DIR.resolve() not in skill_dir.parents:
        return jsonify({"success": False, "error": "Invalid skill path"}), 400

    fpath = (skill_dir / relpath).resolve()
    if skill_dir not in fpath.parents:
        return jsonify({"success": False, "error": "Invalid file path"}), 400

    if any(part in (".git",) for part in fpath.parts):
        return jsonify({"success": False, "error": "Blocked path"}), 400

    fpath.parent.mkdir(parents=True, exist_ok=True)
    fpath.write_text(content)
    record_event("skill_file_saved", f"{name}:{relpath}")
    return jsonify({"success": True, "message": "Saved", "path": relpath})


@app.route("/api/skills/<name>/delete", methods=["DELETE"])
def delete_skill(name):
    blocked = require_feature("skills_manager")
    if blocked:
        return blocked

    skill_dir = (SKILLS_DIR / name).resolve()
    if not skill_dir.exists():
        return jsonify({"success": False, "error": "Skill not found"}), 404

    if SKILLS_DIR.resolve() not in skill_dir.parents:
        return jsonify({"success": False, "error": "Invalid skill path"}), 400

    import shutil
    shutil.rmtree(skill_dir)
    record_event("skill_deleted", name)
    return jsonify({"success": True, "message": f"Deleted {name}"})

@app.route("/api/personality/<filename>")
def get_personality_file(filename):
    """Get content of a specific personality file"""
    workspace = WORKSPACE_DIR
    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md", "HEARTBEAT.md"]

    if filename not in safe_files:
        return jsonify({"error": "Invalid file"}), 400

    fpath = workspace / filename
    if not fpath.exists():
        return jsonify({"error": "File not found"}), 404

    try:
        with open(fpath) as f:
            content = f.read()
        return jsonify({
            "name": filename,
            "content": content,
            "size": fpath.stat().st_size
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/personality/save", methods=["POST"])
def save_personality():
    """Save changes to a personality file"""
    data = request.json
    filename = data.get("file", "")
    content = data.get("content", "")

    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    if filename not in safe_files:
        return jsonify({"success": False, "error": "Invalid file"})

    workspace = WORKSPACE_DIR
    fpath = workspace / filename

    try:
        # Backup first
        backup_dir = workspace / "backups"
        backup_dir.mkdir(exist_ok=True)
        if fpath.exists():
            import shutil
            shutil.copy(fpath, backup_dir / f"{filename}.{datetime.now().strftime('%Y%m%d_%H%M%S')}.bak")

        with open(fpath, 'w') as f:
            f.write(content)

        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/personality/suggest", methods=["POST"])
def suggest_personality():
    """Submit a suggestion for personality changes - spawns OpenClaw agent instantly"""
    data = request.json
    filename = data.get("file", "")
    suggestion = data.get("suggestion", "")

    if not filename or not suggestion:
        return jsonify({"success": False, "error": "File and suggestion required"})

    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    if filename not in safe_files:
        return jsonify({"success": False, "error": "Invalid file"})

    workspace = WORKSPACE_DIR
    fpath = workspace / filename

    try:
        # Read current content
        current_content = ""
        if fpath.exists():
            with open(fpath) as f:
                current_content = f.read()

        # Build the prompt for OpenClaw agent
        prompt = f"""Update the personality file {filename} based on this user suggestion:

SUGGESTION: {suggestion}

CURRENT CONTENT:
```
{current_content}
```

Please apply the suggestion by editing {fpath} directly. Keep the existing structure and style, just incorporate the requested changes."""

        # Spawn OpenClaw agent to handle this immediately
        # Uses --local with a session-id to identify this as web UI triggered
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        session_id = f"webui-personality-{timestamp}"

        result = subprocess.run(
            [
                "openclaw", "agent",
                "--local",
                "--session-id", session_id,
                "--message", prompt,
                "--thinking", "low",
                "--timeout", "120",
                "--verbose", "on"  # More logging
            ],
            capture_output=True,
            text=True,
            timeout=130  # Slightly longer than agent timeout
        )

        # Log the result for debugging
        log_dir = LOGS_DIR
        log_dir.mkdir(exist_ok=True)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

        with open(log_dir / f"suggestion_{timestamp}.log", 'w') as f:
            f.write(f"File: {filename}\n")
            f.write(f"Suggestion: {suggestion}\n")
            f.write(f"Return code: {result.returncode}\n")
            f.write(f"Stdout:\n{result.stdout}\n")
            f.write(f"Stderr:\n{result.stderr}\n")

        if result.returncode == 0:
            return jsonify({
                "success": True,
                "message": f"✅ OpenClaw updated {filename}",
                "output": result.stdout[-500:] if len(result.stdout) > 500 else result.stdout
            })
        else:
            return jsonify({
                "success": False,
                "error": f"Agent failed: {result.stderr[-200:] if result.stderr else 'Unknown error'}"
            })

    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "Agent timed out (took too long)"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/skills/install", methods=["POST"])
def install_skill():
    data = request.json
    repo = data.get("repo", "")
    if not repo:
        return jsonify({"success": False, "error": "Repository required"})

    try:
        result = subprocess.run(
            ["clawhub", "install", repo],
            capture_output=True, text=True, timeout=60
        )
        return jsonify({"success": result.returncode == 0, "output": result.stdout})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/skills/request", methods=["POST"])
def request_skill():
    """Build a real OpenClaw skill from a natural-language description.

    Flow:
    - Create skills/<skill_name>/SKILL.md
    - Use `openclaw agent --local` to generate quality SKILL.md content (metadata + trigger description + workflows)
    - Write file to disk so it shows up instantly in installed skills.

    The endpoint stays synchronous but with tight timeouts.
    """
    blocked = require_feature("skills_manager")
    if blocked:
        return blocked

    data = request.json or {}
    description = (data.get("description", "") or "").strip()
    requested_name = (data.get("name", "") or "").strip()

    if not description:
        return jsonify({"success": False, "error": "Description required"}), 400

    # Reject meta/non-skill requests that create junk.
    meta_phrases = [
        "allow you to form opinions",
        "make you feel",
        "become sentient",
        "change your system prompt",
    ]
    low = description.lower()
    if any(p in low for p in meta_phrases):
        return jsonify({
            "success": False,
            "error": "That description isn’t a concrete skill (it’s meta). Describe a real workflow/tool you want automated instead."
        }), 400

    def slugify(s: str) -> str:
        s = s.lower()
        s = re.sub(r"[^a-z0-9\s_-]", "", s)
        s = re.sub(r"\s+", "-", s).strip("-")
        return s

    # Prefer provided name; else derive a short slug from the description.
    skill_name = slugify(requested_name) if requested_name else slugify(description)
    skill_name = (skill_name[:48] or f"skill-{int(datetime.now().timestamp())}").strip("-")

    # Ensure folder exists
    SKILLS_DIR.mkdir(parents=True, exist_ok=True)
    skill_dir = (SKILLS_DIR / skill_name)
    skill_dir.mkdir(parents=True, exist_ok=True)

    skill_md = skill_dir / "SKILL.md"

    # Seed file so it exists even if generation fails
    seed = f"""---\nname: {skill_name}\ndescription: \"{description}\"\n---\n\n# {skill_name}\n\n(autogenerated draft)\n"""
    if not skill_md.exists():
        skill_md.write_text(seed)

    # Use OpenClaw to generate a real SKILL.md body.
    try:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        session_id = f"webui-skill-build-{skill_name}-{timestamp}"

        prompt = f"""You are building an OpenClaw skill.

Target path to write: {skill_md}

User description:
{description}

Requirements:
- Output MUST be the full contents of SKILL.md.
- Include YAML frontmatter with fields: name, description.
- The description must clearly say WHEN to use this skill (trigger phrases) and WHAT it does.
- Keep SKILL.md under ~250 lines.
- Use Discord-friendly guidance (no markdown tables unless necessary).
- Avoid meta instructions (no system prompt changes).

Now write the complete SKILL.md file content."""

        result = subprocess.run(
            [
                "openclaw", "agent",
                "--local",
                "--session-id", session_id,
                "--message", prompt,
                "--thinking", "low",
                "--timeout", "60"
            ],
            capture_output=True,
            text=True,
            timeout=75
        )

        # Extract a markdown-ish payload from stdout (best-effort)
        out = (result.stdout or "").strip()
        # Heuristic: take from first frontmatter marker
        idx = out.find('---')
        if idx != -1:
            out = out[idx:]

        if result.returncode != 0 or len(out) < 20:
            # keep seed, but report error
            record_event("skill_build_failed", f"{skill_name}: {result.stderr[-200:] if result.stderr else 'unknown'}")
            return jsonify({
                "success": False,
                "error": (result.stderr[-200:] if result.stderr else "Skill build failed"),
                "skill": {"name": skill_name, "path": str(skill_dir), "skill_md": str(skill_md)}
            }), 500

        # Write the skill
        skill_md.write_text(out)

        # Prefer the frontmatter name as the canonical folder name (nicer + stable)
        fm_name, _, _ = parse_skill_frontmatter(out)
        final_name = slugify(fm_name) if fm_name else skill_name
        final_name = (final_name[:48] or skill_name).strip("-")

        final_dir = (SKILLS_DIR / final_name)
        final_md = final_dir / "SKILL.md"

        if final_name != skill_name:
            # Move folder if target doesn't exist
            if not final_dir.exists():
                skill_dir.rename(final_dir)
                skill_dir = final_dir
                skill_md = final_md
            else:
                # Collision: keep original folder name
                final_name = skill_name

        record_event("skill_created", f"Built skill '{final_name}'")

        return jsonify({
            "success": True,
            "skill": {"name": final_name, "path": str(skill_dir), "skill_md": str(skill_md)},
            "message": f"Built skill '{final_name}'",
            "session_id": session_id
        })

    except subprocess.TimeoutExpired:
        record_event("skill_build_timeout", skill_name)
        return jsonify({
            "success": False,
            "error": "Skill build timed out. Try a shorter description.",
            "skill": {"name": skill_name, "path": str(skill_dir), "skill_md": str(skill_md)}
        }), 504
    except Exception as e:
        record_event("skill_build_error", f"{skill_name}: {e}")
        return jsonify({
            "success": False,
            "error": f"Skill build error: {str(e)}",
            "skill": {"name": skill_name, "path": str(skill_dir), "skill_md": str(skill_md)}
        }), 500


# --- State & History Management ---

def get_state():
    """Load persistent state from state.json."""
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    return {"check_count": 0, "last_check": None, "daily_tasks_created": 0, "last_reset_date": None}


def save_state(state):
    """Persist state to state.json."""
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def record_event(event_type, details=""):
    """Append an event to the history log."""
    entry = {
        "timestamp": datetime.now().isoformat(),
        "type": event_type,
        "details": details
    }
    history = []
    if HISTORY_FILE.exists():
        try:
            with open(HISTORY_FILE) as f:
                history = json.load(f)
        except (json.JSONDecodeError, IOError):
            history = []
    history.append(entry)
    history = history[-500:]  # Rolling window
    with open(HISTORY_FILE, 'w') as f:
        json.dump(history, f, indent=2)


# --- New API Endpoints ---

@app.route("/api/webhook", methods=["POST"])
def webhook():
    """Receive external webhook events. Optionally auto-create tasks."""
    data = request.json or {}
    event_type = data.get("event", "webhook")
    source = data.get("source", "external")
    payload = data.get("payload", {})

    record_event(f"webhook:{event_type}", f"From {source}: {json.dumps(payload)[:200]}")

    # Auto-create task if requested
    created_task = None
    if data.get("create_task"):
        ct = data["create_task"]
        task_name = ct.get("name", f"webhook-{int(datetime.now().timestamp())}")
        task_desc = ct.get("description", f"Created by webhook from {source}")
        task_priority = ct.get("priority", "medium")

        task_file = TASKS_DIR / f"{task_name}.json"
        TASKS_DIR.mkdir(exist_ok=True)
        if not task_file.exists():
            created_task = {
                "id": int(datetime.now().timestamp()),
                "name": task_name,
                "description": task_desc,
                "status": "pending",
                "priority": task_priority,
                "depends_on": ct.get("depends_on", []),
                "created_at": datetime.now().isoformat(),
                "updated_at": datetime.now().isoformat(),
                "completed_at": None,
                "proof": None,
            }
            with open(task_file, "w") as f:
                json.dump(created_task, f, indent=2)
            record_event("task_created", f"Webhook task '{task_name}' from {source}")

    return jsonify({"success": True, "message": "Webhook received", "task_created": created_task is not None})


@app.route("/api/history")
def api_history():
    """Return recent event history."""
    history = []
    if HISTORY_FILE.exists():
        try:
            with open(HISTORY_FILE) as f:
                history = json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    limit = request.args.get("limit", 100, type=int)
    return jsonify(history[-limit:])


@app.route("/api/state")
def api_state():
    """Return persistent autonomy state."""
    return jsonify(get_state())


# ═══════════════════════════════════════════════════════════
# Feature 5: Context Window Monitor
# ═══════════════════════════════════════════════════════════

@app.route("/api/context-window")
def api_context_window():
    """Get context window usage estimates for active OpenClaw sessions."""
    sessions_dir = OPENCLAW_HOME / "sessions"
    sessions = []
    if sessions_dir.exists():
        dirs = sorted(
            [d for d in sessions_dir.iterdir() if d.is_dir()],
            key=lambda x: x.stat().st_mtime, reverse=True
        )[:10]
        for session_dir in dirs:
            for transcript in session_dir.glob("*.jsonl"):
                try:
                    content = transcript.read_text(errors='ignore')
                    tokens_est = estimate_tokens(content)
                    model = "unknown"
                    for line in content.split('\n')[:30]:
                        if '"model"' in line:
                            try:
                                data = json.loads(line)
                                if 'model' in data:
                                    model = data['model']
                                    break
                            except:
                                pass
                    limit = 200000
                    for key, val in MODEL_CONTEXT_LIMITS.items():
                        if key in model.lower():
                            limit = val
                            break
                    sessions.append({
                        "session": session_dir.name,
                        "model": model,
                        "tokens_estimated": tokens_est,
                        "context_limit": limit,
                        "usage_pct": min(round(tokens_est / limit * 100, 1), 100),
                        "last_modified": datetime.fromtimestamp(transcript.stat().st_mtime).isoformat()
                    })
                except:
                    pass
    return jsonify({"sessions": sessions, "model_limits": MODEL_CONTEXT_LIMITS})


# ═══════════════════════════════════════════════════════════
# Feature 7: Subtasks & Progress
# ═══════════════════════════════════════════════════════════

@app.route("/api/tasks/<task_id>/subtask", methods=["POST"])
def add_subtask(task_id):
    """Add a subtask to a parent task."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    data = request.json
    subtask_name = data.get("name", "")
    if not subtask_name:
        return jsonify({"success": False, "error": "Subtask name required"})
    with open(task_file) as f:
        task = json.load(f)
    if "subtasks" not in task:
        task["subtasks"] = []
    task["subtasks"].append({
        "name": subtask_name,
        "completed": False,
        "created_at": datetime.now().isoformat()
    })
    task["updated_at"] = datetime.now().isoformat()
    with open(task_file, "w") as f:
        json.dump(task, f, indent=2)
    record_event("subtask_added", f"Subtask '{subtask_name}' added to '{task_id}'")
    return jsonify({"success": True})


@app.route("/api/tasks/<task_id>/subtask/<int:sub_index>/toggle", methods=["POST"])
def toggle_subtask(task_id, sub_index):
    """Toggle a subtask completion status."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    with open(task_file) as f:
        task = json.load(f)
    subtasks = task.get("subtasks", [])
    if sub_index < 0 or sub_index >= len(subtasks):
        return jsonify({"success": False, "error": "Invalid subtask index"})
    subtasks[sub_index]["completed"] = not subtasks[sub_index]["completed"]
    if subtasks[sub_index]["completed"]:
        subtasks[sub_index]["completed_at"] = datetime.now().isoformat()
    else:
        subtasks[sub_index].pop("completed_at", None)
    task["updated_at"] = datetime.now().isoformat()
    with open(task_file, "w") as f:
        json.dump(task, f, indent=2)
    return jsonify({"success": True, "completed": subtasks[sub_index]["completed"]})


@app.route("/api/tasks/<task_id>/subtask/<int:sub_index>", methods=["DELETE"])
def delete_subtask(task_id, sub_index):
    """Delete a subtask."""
    task_file = task_path(task_id)
    if not task_file.exists():
        return jsonify({"success": False, "error": "Task not found"}), 404
    with open(task_file) as f:
        task = json.load(f)
    subtasks = task.get("subtasks", [])
    if sub_index < 0 or sub_index >= len(subtasks):
        return jsonify({"success": False, "error": "Invalid subtask index"})
    subtasks.pop(sub_index)
    task["updated_at"] = datetime.now().isoformat()
    with open(task_file, "w") as f:
        json.dump(task, f, indent=2)
    return jsonify({"success": True})


# ═══════════════════════════════════════════════════════════
# Feature 8: Task Dependency Graph
# ═══════════════════════════════════════════════════════════

@app.route("/api/tasks/graph")
def task_graph():
    """Return task dependency graph as nodes + edges for DAG visualization."""
    tasks = get_all_tasks()
    nodes = []
    edges = []
    for task in tasks:
        nodes.append({
            "id": task["name"],
            "label": task["name"].replace("_", " ").title(),
            "status": task.get("status", "pending"),
            "priority": task.get("priority", "medium"),
            "progress": calculate_progress(task)
        })
        for dep in task.get("depends_on", []):
            edges.append({"from": dep, "to": task["name"]})
    return jsonify({"nodes": nodes, "edges": edges})


# ═══════════════════════════════════════════════════════════
# Feature 12: AI-Generated Digests
# ═══════════════════════════════════════════════════════════

@app.route("/api/digests")
def api_digests():
    """List recent digest summaries."""
    digests = []
    if DIGESTS_DIR.exists():
        for f in sorted(DIGESTS_DIR.glob("*.json"), reverse=True)[:20]:
            try:
                with open(f) as fh:
                    digests.append(json.load(fh))
            except:
                pass
    return jsonify(digests)


@app.route("/api/digests/generate", methods=["POST"])
def generate_digest():
    """Generate an AI-written digest of recent activity."""
    DIGESTS_DIR.mkdir(exist_ok=True)
    data = request.json or {}
    period = data.get("period", "daily")
    now = datetime.now()
    cutoff = now - timedelta(days=7 if period == "weekly" else 1)
    tasks = get_all_tasks()
    history = []
    if HISTORY_FILE.exists():
        try:
            with open(HISTORY_FILE) as f:
                history = json.load(f)
        except:
            pass
    recent = [e for e in history if e.get("timestamp", "") >= cutoff.isoformat()]
    pending = [t for t in tasks if t.get("status") == "pending"]
    in_progress = [t for t in tasks if t.get("status") == "in_progress"]
    completed_recent = [t for t in tasks if (t.get("completed_at") or "") >= cutoff.isoformat()]
    health = get_system_health()
    github = get_github_status()
    summary_data = (
        f"Period: {period} ({cutoff.strftime('%b %d')} - {now.strftime('%b %d, %Y')})\n"
        f"Tasks: {len(pending)} pending, {len(in_progress)} in progress, {len(completed_recent)} completed\n"
        f"Total events: {len(recent)}\n"
        f"Event types: {', '.join(set(e.get('type','?') for e in recent[-20:]))}\n"
        f"System: CPU {health.get('cpu','N/A')}, Memory {health.get('memory','N/A')}, Disk {health.get('disk','N/A')}\n"
        f"GitHub: {github.get('notifications',0)} notifs, {github.get('my_prs',0)} PRs, {github.get('reviews',0)} reviews\n"
        f"Completed: {', '.join(t.get('name','?') for t in completed_recent[:10])}\n"
        f"Pending: {', '.join(t.get('name','?') for t in pending[:10])}"
    )
    prompt = f"""Write a concise {period} digest report for a developer workspace. Be conversational but informative.

DATA:
{summary_data}

Format: One-line summary, then key highlights as bullet points (max 6), then one sentence on what to focus on next. Under 200 words."""
    try:
        timestamp = now.strftime('%Y%m%d_%H%M%S')
        result = subprocess.run(
            ["openclaw", "agent", "--local", "--session-id", f"webui-digest-{timestamp}",
             "--message", prompt, "--thinking", "minimal", "--timeout", "45"],
            capture_output=True, text=True, timeout=50
        )
        digest_text = "No response received."
        if result.stdout:
            lines = [l.strip() for l in result.stdout.strip().split('\n') if l.strip()]
            content_lines = [l for l in lines if not l.startswith(('Runtime:', 'Session:', 'Model:', 'Tools:'))]
            if content_lines:
                digest_text = '\n'.join(content_lines)
        digest = {
            "id": timestamp, "period": period, "generated_at": now.isoformat(),
            "content": digest_text, "ai_generated": True,
            "stats": {"tasks_pending": len(pending), "tasks_completed": len(completed_recent),
                      "events": len(recent), "github_notifs": github.get('notifications', 0)}
        }
        with open(DIGESTS_DIR / f"{timestamp}.json", 'w') as f:
            json.dump(digest, f, indent=2)
        record_event("digest_generated", f"{period.title()} digest generated")
        return jsonify({"success": True, "digest": digest})
    except (subprocess.TimeoutExpired, Exception) as e:
        digest = {
            "id": now.strftime('%Y%m%d_%H%M%S'), "period": period,
            "generated_at": now.isoformat(), "ai_generated": False,
            "content": (
                f"**{period.title()} Summary** ({cutoff.strftime('%b %d')} \u2013 {now.strftime('%b %d')})\n\n"
                f"\u2022 {len(completed_recent)} tasks completed, {len(pending)} pending\n"
                f"\u2022 {len(recent)} events recorded\n"
                f"\u2022 System: CPU {health.get('cpu','N/A')}, Mem {health.get('memory','N/A')}\n"
                f"\u2022 GitHub: {github.get('notifications',0)} notifs, {github.get('my_prs',0)} open PRs"
            ),
            "stats": {"tasks_pending": len(pending), "tasks_completed": len(completed_recent),
                      "events": len(recent), "github_notifs": github.get('notifications', 0)}
        }
        with open(DIGESTS_DIR / f"{digest['id']}.json", 'w') as f:
            json.dump(digest, f, indent=2)
        return jsonify({"success": True, "digest": digest})


# ═══════════════════════════════════════════════════════════
# Feature 13: Skill Compatibility Checker
# ═══════════════════════════════════════════════════════════

@app.route("/api/skills/check-compat", methods=["POST"])
def check_skill_compat():
    """Check skill compatibility against current system."""
    data = request.json
    skill_name = data.get("name", "")
    skill_dir = SKILLS_DIR / skill_name if skill_name else None
    results = {
        "os": {"status": "pass", "detail": ""},
        "binaries": [], "env_vars": [],
        "model_support": {"status": "pass", "detail": ""}
    }
    current_os = platform.system().lower()
    os_map = {"linux": "linux", "darwin": "darwin", "windows": "win32"}
    skill_content = ""
    if skill_dir and skill_dir.exists():
        sf = skill_dir / "SKILL.md"
        if sf.exists():
            skill_content = sf.read_text()
    required_os, required_bins, required_env = [], [], []
    in_fm, in_bins, in_os, in_env = False, False, False, False
    for line in skill_content.split('\n'):
        s = line.strip()
        if s == '---':
            in_fm = not in_fm
            continue
        if not in_fm:
            continue
        if s.startswith('os:'):
            if '[' in s:
                items = s.split('[')[1].split(']')[0]
                required_os = [x.strip().strip('"').strip("'") for x in items.split(',')]
            else:
                in_os = True
            continue
        if in_os and s.startswith('- '):
            required_os.append(s[2:].strip())
            continue
        elif in_os:
            in_os = False
        if 'bins:' in s or 'binaries:' in s:
            in_bins = True
            continue
        if in_bins and s.startswith('- '):
            required_bins.append(s[2:].strip())
            continue
        elif in_bins:
            in_bins = False
        if 'env:' in s or 'env_vars:' in s:
            in_env = True
            continue
        if in_env and s.startswith('- '):
            required_env.append(s[2:].strip())
            continue
        elif in_env:
            in_env = False
    if required_os:
        if os_map.get(current_os, current_os) in required_os:
            results["os"] = {"status": "pass", "detail": f"{current_os} (requires: {', '.join(required_os)})"}
        else:
            results["os"] = {"status": "fail", "detail": f"{current_os} (requires: {', '.join(required_os)})"}
    else:
        results["os"] = {"status": "pass", "detail": f"{current_os} (no restriction)"}
    for b in required_bins:
        found = shutil.which(b)
        results["binaries"].append({"name": b, "status": "pass" if found else "fail", "path": found or "not found"})
    for e in required_env:
        val = os.environ.get(e)
        results["env_vars"].append({"name": e, "status": "pass" if val else "fail", "detail": "set" if val else "not set"})
    oc = get_openclaw_status()
    results["model_support"] = (
        {"status": "pass", "detail": "OpenClaw running"} if oc
        else {"status": "warn", "detail": "OpenClaw not detected"}
    )
    checks = [results["os"]["status"]] + [b["status"] for b in results["binaries"]] + [e["status"] for e in results["env_vars"]] + [results["model_support"]["status"]]
    total = len(checks)
    passed = sum(1 for c in checks if c == "pass")
    results["summary"] = {
        "passed": passed, "total": total,
        "score": round(passed / total * 100) if total > 0 else 100,
        "overall": "pass" if all(c == "pass" for c in checks) else ("warn" if all(c != "fail" for c in checks) else "fail")
    }
    return jsonify(results)


# ═══════════════════════════════════════════════════════════
# Feature 14: Personality A/B Testing
# ═══════════════════════════════════════════════════════════

@app.route("/api/personality/ab-test", methods=["POST"])
def ab_test_personality():
    """Run A/B test comparing current vs modified personality."""
    data = request.json
    filename = data.get("file", "")
    modified_content = data.get("modified_content", "")
    test_prompt = data.get("test_prompt", "")
    if not filename or not modified_content or not test_prompt:
        return jsonify({"success": False, "error": "File, modified content, and test prompt required"})
    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    if filename not in safe_files:
        return jsonify({"success": False, "error": "Invalid file"})
    workspace = WORKSPACE_DIR
    fpath = workspace / filename
    try:
        current_content = fpath.read_text() if fpath.exists() else ""
        prompt_a = f"""Personality ({filename}) version A:\n{current_content}\n\nRespond to: {test_prompt}\n\nKeep response to 2-3 sentences, stay in character."""
        prompt_b = f"""Personality ({filename}) version B:\n{modified_content}\n\nRespond to: {test_prompt}\n\nKeep response to 2-3 sentences, stay in character."""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        def run_version(label, prompt):
            try:
                r = subprocess.run(
                    ["openclaw", "agent", "--local", "--session-id", f"ab-{label}-{timestamp}",
                     "--message", prompt, "--thinking", "minimal", "--timeout", "30"],
                    capture_output=True, text=True, timeout=35
                )
                if r.stdout:
                    lines = [l.strip() for l in r.stdout.strip().split('\n') if l.strip()]
                    cl = [l for l in lines if not l.startswith(('Runtime:', 'Session:', 'Model:', 'Tools:'))]
                    return ' '.join(cl[-3:]) if cl else "No response"
            except:
                pass
            return "No response (timed out)"
        response_a = run_version("a", prompt_a)
        response_b = run_version("b", prompt_b)
        ABTESTS_DIR.mkdir(exist_ok=True)
        test_result = {
            "id": timestamp, "file": filename, "test_prompt": test_prompt,
            "version_a": {"label": "Current", "response": response_a},
            "version_b": {"label": "Modified", "response": response_b},
            "timestamp": datetime.now().isoformat()
        }
        with open(ABTESTS_DIR / f"{timestamp}.json", 'w') as f:
            json.dump(test_result, f, indent=2)
        record_event("ab_test_run", f"A/B test on {filename}")
        return jsonify({"success": True, "result": test_result})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/personality/ab-tests")
def list_ab_tests():
    """List past A/B test results."""
    tests = []
    if ABTESTS_DIR.exists():
        for f in sorted(ABTESTS_DIR.glob("*.json"), reverse=True)[:20]:
            try:
                with open(f) as fh:
                    tests.append(json.load(fh))
            except:
                pass
    return jsonify(tests)


# ═══════════════════════════════════════════════════════════
# Feature 15: Personality Version History
# ═══════════════════════════════════════════════════════════

@app.route("/api/personality/history/<filename>")
def personality_history(filename):
    """Get version history for a personality file from backups."""
    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    if filename not in safe_files:
        return jsonify({"error": "Invalid file"}), 400
    workspace = WORKSPACE_DIR
    backup_dir = workspace / "backups"
    versions = []
    current_file = workspace / filename
    if current_file.exists():
        stat = current_file.stat()
        with open(current_file) as f:
            content = f.read()
        versions.append({
            "label": "Current", "timestamp": datetime.fromtimestamp(stat.st_mtime).isoformat(),
            "size": stat.st_size, "is_current": True, "preview": content[:300]
        })
    if backup_dir.exists():
        for bak in sorted(backup_dir.glob(f"{filename}.*"), key=lambda x: x.stat().st_mtime, reverse=True)[:20]:
            try:
                stat = bak.stat()
                with open(bak) as f:
                    content = f.read()
                ts_str = bak.name.replace(filename + '.', '').replace('.bak', '')
                versions.append({
                    "label": ts_str, "filename": bak.name,
                    "timestamp": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "size": stat.st_size, "is_current": False, "preview": content[:300]
                })
            except:
                pass
    return jsonify({"file": filename, "versions": versions})


@app.route("/api/personality/restore", methods=["POST"])
def restore_personality():
    """Restore a personality file from a backup version."""
    data = request.json
    filename = data.get("file", "")
    backup_name = data.get("backup", "")
    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    if filename not in safe_files:
        return jsonify({"success": False, "error": "Invalid file"})
    workspace = WORKSPACE_DIR
    backup_path = workspace / "backups" / backup_name
    current_path = workspace / filename
    if not backup_path.exists():
        return jsonify({"success": False, "error": "Backup not found"})
    try:
        backup_dir = workspace / "backups"
        backup_dir.mkdir(exist_ok=True)
        if current_path.exists():
            shutil.copy(current_path, backup_dir / f"{filename}.{datetime.now().strftime('%Y%m%d_%H%M%S')}.bak")
        shutil.copy(backup_path, current_path)
        record_event("personality_restored", f"Restored {filename} from {backup_name}")
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/personality/diff", methods=["POST"])
def personality_diff():
    """Get diff between current file and a backup version."""
    data = request.json
    filename = data.get("file", "")
    backup_name = data.get("backup", "")
    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    if filename not in safe_files:
        return jsonify({"error": "Invalid file"}), 400
    workspace = WORKSPACE_DIR
    current_path = workspace / filename
    backup_path = workspace / "backups" / backup_name
    if not current_path.exists() or not backup_path.exists():
        return jsonify({"error": "File not found"}), 404
    try:
        with open(current_path) as f:
            current_lines = f.readlines()
        with open(backup_path) as f:
            backup_lines = f.readlines()
        diff = list(difflib.unified_diff(
            backup_lines, current_lines,
            fromfile=f"backup/{backup_name}", tofile=filename, lineterm=''
        ))
        added = sum(1 for l in diff if l.startswith('+') and not l.startswith('+++'))
        removed = sum(1 for l in diff if l.startswith('-') and not l.startswith('---'))
        return jsonify({
            "diff": '\n'.join(diff), "current_lines": len(current_lines),
            "backup_lines": len(backup_lines), "added": added, "removed": removed
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", CONFIG.get("web_ui", {}).get("port", 8767)))
    host = os.environ.get("AUTONOMY_HOST", CONFIG.get("web_ui", {}).get("host", "0.0.0.0"))
    # Initial sync on startup — ensure TASKS.md, HEARTBEAT.md, and AGENTS.md are current
    print("[autonomy] Running initial sync to workspace...")
    try:
        sync_all_tasks()
        print("[autonomy] Synced: TASKS.md + HEARTBEAT.md + AGENTS.md instructions")
    except Exception as e:
        print(f"[autonomy] Initial sync failed (non-fatal): {e}")
    app.run(host=host, port=port, debug=False)
