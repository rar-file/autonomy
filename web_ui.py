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
                if skill_file.exists():
                    try:
                        with open(skill_file) as f:
                            content = f.read()
                            # Parse basic info from SKILL.md
                            name = skill_dir.name
                            desc = ""
                            for line in content.split("\n")[:10]:
                                if line.startswith("description:") or line.startswith("_"):
                                    desc = line.split(":", 1)[1].strip() if ":" in line else line.strip("_ ")
                                    break
                            skills.append({
                                "name": name,
                                "description": desc or "No description",
                                "path": str(skill_dir),
                                "active": True
                            })
                    except:
                        pass
    return skills

def get_personality_files():
    files = []
    workspace = Path("/root/.openclaw/workspace")
    personality_files = ["SOUL.md", "IDENTITY.md", "USER.md", "AGENTS.md", "TOOLS.md"]
    
    for fname in personality_files:
        fpath = workspace / fname
        if fpath.exists():
            try:
                stat = fpath.stat()
                files.append({
                    "name": fname,
                    "path": str(fpath),
                    "size": stat.st_size,
                    "modified": datetime.fromtimestamp(stat.st_mtime).isoformat()
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

@app.route("/api/personality/suggest", methods=["POST"])
def suggest_personality():
    data = request.json
    file = data.get("file", "")
    suggestion = data.get("suggestion", "")
    
    if not file or not suggestion:
        return jsonify({"success": False, "error": "File and suggestion required"})
    
    # Save suggestion to a pending file
    pending_dir = Path("/root/.openclaw/workspace/pending_changes")
    pending_dir.mkdir(exist_ok=True)
    
    pending_file = pending_dir / f"{file.replace('.', '_')}_{int(datetime.now().timestamp())}.txt"
    with open(pending_file, "w") as f:
        f.write(f"File: {file}\n")
        f.write(f"Date: {datetime.now().isoformat()}\n")
        f.write(f"Suggestion:\n{suggestion}\n")
    
    return jsonify({"success": True, "message": "Suggestion saved for review"})

if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", 8767))
    app.run(host="0.0.0.0", port=port, debug=False)
