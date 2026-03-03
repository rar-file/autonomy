#!/usr/bin/env python3
"""
Autonomy Web UI v3.5
Complete dashboard with Skills, Personality, Logs, Alerts
"""

import os
import json
import subprocess
import glob
from datetime import datetime, timedelta
from pathlib import Path
from flask import Flask, render_template, jsonify, request

app = Flask(__name__)

AUTONOMY_DIR = Path(__file__).parent
TASKS_DIR = AUTONOMY_DIR / "tasks"
LOGS_DIR = AUTONOMY_DIR / "logs"
CONFIG_FILE = AUTONOMY_DIR / "config.json"
SKILLS_DIR = Path("/root/.openclaw/workspace/skills")

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

def get_skills():
    skills = []
    if SKILLS_DIR.exists():
        for skill_dir in SKILLS_DIR.iterdir():
            if skill_dir.is_dir():
                skill_file = skill_dir / "SKILL.md"
                readme_file = skill_dir / "README.md"
                if skill_file.exists():
                    try:
                        with open(skill_file) as f:
                            content = f.read()
                            name = skill_dir.name
                            desc = ""
                            version = "1.0.0"
                            # Parse SKILL.md
                            for line in content.split("\n")[:20]:
                                if line.startswith("description:") or line.startswith("_"):
                                    desc = line.split(":", 1)[1].strip() if ":" in line else line.strip("_ ")
                                if "version" in line.lower() and ":" in line:
                                    version = line.split(":", 1)[1].strip().strip('"').strip("'")
                            
                            # Check for enabled/disabled state
                            config_file = skill_dir / ".disabled"
                            enabled = not config_file.exists()
                            
                            skills.append({
                                "name": name,
                                "description": desc or "No description",
                                "path": str(skill_dir),
                                "version": version,
                                "enabled": enabled,
                                "icon": "⚡"
                            })
                    except:
                        pass
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
    workspace = Path("/root/.openclaw/workspace")
    personality_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    
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
    name = data.get("name", "").replace(" ", "_").lower()
    desc = data.get("description", "")
    if not name:
        return jsonify({"success": False, "error": "Name required"}), 400
    
    task_file = TASKS_DIR / f"{name}.json"
    if task_file.exists():
        return jsonify({"success": False, "error": "Task exists"}), 400
    
    task = {
        "id": int(datetime.now().timestamp()),
        "name": name,
        "description": desc,
        "status": "pending",
        "created_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
        "completed_at": None,
        "proof": None
    }
    
    with open(task_file, "w") as f:
        json.dump(task, f, indent=2)
    
    return jsonify({"success": True, "task": task})

@app.route("/api/tasks/<task_id>/complete", methods=["POST"])
def complete_task(task_id):
    task_file = TASKS_DIR / f"{task_id}.json"
    if task_file.exists():
        with open(task_file) as f:
            task = json.load(f)
        task["status"] = "completed"
        task["completed_at"] = datetime.now().isoformat()
        task["proof"] = request.json.get("proof", "")
        with open(task_file, "w") as f:
            json.dump(task, f, indent=2)
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Task not found"}), 404

@app.route("/api/skills/<name>")
def skill_detail(name):
    """Get detailed info about a specific skill"""
    detail = get_skill_detail(name)
    if detail:
        return jsonify(detail)
    return jsonify({"error": "Skill not found"}), 404

@app.route("/api/skills/<name>/toggle", methods=["POST"])
def toggle_skill(name):
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

@app.route("/api/personality/<filename>")
def get_personality_file(filename):
    """Get content of a specific personality file"""
    workspace = Path("/root/.openclaw/workspace")
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
    
    workspace = Path("/root/.openclaw/workspace")
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
    """Submit a suggestion for personality changes - triggers immediate OpenClaw action"""
    data = request.json
    filename = data.get("file", "")
    suggestion = data.get("suggestion", "")
    
    if not filename or not suggestion:
        return jsonify({"success": False, "error": "File and suggestion required"})
    
    safe_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md", "MEMORY.md"]
    if filename not in safe_files:
        return jsonify({"success": False, "error": "Invalid file"})
    
    workspace = Path("/root/.openclaw/workspace")
    fpath = workspace / filename
    
    try:
        # Read current content
        current_content = ""
        if fpath.exists():
            with open(fpath) as f:
                current_content = f.read()
        
        # Create the prompt for OpenClaw
        prompt = f"""[PERSONALITY UPDATE REQUEST]

The user wants to update {filename} with the following suggestion:
"{suggestion}"

Please read the current content of {filename} and apply the user's suggestion. Edit the file directly using the edit tool.

Current content preview (first 2000 chars):
{current_content[:2000]}
{"..." if len(current_content) > 2000 else ""}
"""
        
        # Write to trigger file
        trigger_dir = workspace / ".autonomy_triggers"
        trigger_dir.mkdir(exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        trigger_file = trigger_dir / f"suggestion_{timestamp}.txt"
        
        with open(trigger_file, 'w') as f:
            f.write(prompt)
        
        # INSTANT ACTION: Spawn OpenClaw agent via subprocess
        # This creates a detached process that runs immediately
        spawn_script = f"""#!/usr/bin/env python3
import subprocess
import sys
import json

# Read the trigger file
with open('{trigger_file}') as f:
    prompt = f.read()

# Call openclaw to run the task immediately
try:
    result = subprocess.run(
        ["openclaw", "run", "--inline", prompt],
        capture_output=True, text=True, timeout=60
    )
    # Also write completion marker
    with open('{trigger_file}.done', 'w') as f:
        f.write('completed')
except Exception as e:
    with open('{trigger_file}.error', 'w') as f:
        f.write(str(e))
"""
        
        spawn_path = trigger_dir / f"spawn_{timestamp}.py"
        with open(spawn_path, 'w') as f:
            f.write(spawn_script)
        
        # Execute immediately in background
        subprocess.Popen(
            [sys.executable, str(spawn_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        
        return jsonify({
            "success": True, 
            "message": f"OpenClaw is now updating {filename}",
            "trigger": str(trigger_file)
        })
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


if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", 8767))
    app.run(host="0.0.0.0", port=port, debug=False)
