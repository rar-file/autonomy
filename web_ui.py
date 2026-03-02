#!/usr/bin/env python3
"""
Autonomy Web UI v3
Enhanced dashboard with GitHub, processes, and activity
"""

import os
import json
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from flask import Flask, render_template, jsonify, request

app = Flask(__name__)

# Paths
AUTONOMY_DIR = Path(__file__).parent
TASKS_DIR = AUTONOMY_DIR / "tasks"
LOGS_DIR = AUTONOMY_DIR / "logs"
CONFIG_FILE = AUTONOMY_DIR / "config.json"

def get_openclaw_status():
    """Get OpenClaw status via CLI"""
    try:
        result = subprocess.run(
            ["openclaw", "status", "--json"],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except:
        pass
    return None

def get_github_status():
    """Get GitHub status"""
    try:
        result = subprocess.run(
            ["gh", "api", "notifications", "--jq", "[.[] | select(.unread)] | length"],
            capture_output=True,
            text=True,
            timeout=10
        )
        notifications = int(result.stdout.strip()) if result.returncode == 0 else 0
        
        result = subprocess.run(
            ["gh", "pr", "list", "--author", "@me", "--state", "open", "--json", "number", "-q", "length"],
            capture_output=True,
            text=True,
            timeout=10
        )
        my_prs = int(result.stdout.strip()) if result.returncode == 0 else 0
        
        result = subprocess.run(
            ["gh", "pr", "list", "--review-requested=@me", "--state", "open", "--json", "number", "-q", "length"],
            capture_output=True,
            text=True,
            timeout=10
        )
        reviews = int(result.stdout.strip()) if result.returncode == 0 else 0
        
        return {
            "notifications": notifications,
            "my_prs": my_prs,
            "reviews": reviews,
            "connected": True
        }
    except:
        return {"notifications": 0, "my_prs": 0, "reviews": 0, "connected": False}

def get_tasks():
    """Read task files"""
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

def get_system_health():
    """Get basic system stats"""
    health = {}
    
    # CPU - Try multiple methods
    try:
        # Method 1: mpstat
        result = subprocess.run(
            ["mpstat", "1", "1"],
            capture_output=True,
            text=True,
            timeout=2
        )
        for line in result.stdout.split("\n"):
            if "Average" in line or "all" in line:
                parts = line.split()
                if len(parts) >= 4:
                    idle = float(parts[-1].replace(",", "."))
                    health["cpu"] = f"{100 - idle:.1f}%"
                    break
    except:
        try:
            # Method 2: /proc/stat
            with open("/proc/stat") as f:
                line = f.readline()
                fields = line.split()
                if len(fields) >= 5:
                    user = int(fields[1])
                    nice = int(fields[2])
                    system = int(fields[3])
                    idle = int(fields[4])
                    total = user + nice + system + idle
                    health["cpu"] = f"{(user + nice + system) / total * 100:.1f}%"
        except:
            health["cpu"] = "N/A"
    
    try:
        result = subprocess.run(
            ["free"],
            capture_output=True,
            text=True
        )
        for line in result.stdout.split("\n"):
            if line.startswith("Mem:"):
                parts = line.split()
                used = int(parts[2])
                total = int(parts[1])
                health["memory"] = f"{used/total*100:.1f}%"
                health["memory_gb"] = f"{used/1024/1024:.1f}G / {total/1024/1024:.1f}G"
                break
    except:
        health["memory"] = "N/A"
    
    try:
        result = subprocess.run(
            ["df", "/"],
            capture_output=True,
            text=True
        )
        lines = result.stdout.strip().split("\n")
        if len(lines) > 1:
            health["disk"] = lines[1].split()[4]
    except:
        health["disk"] = "N/A"
    
    try:
        result = subprocess.run(
            ["uptime"],
            capture_output=True,
            text=True
        )
        line = result.stdout
        if "load average:" in line:
            health["load"] = line.split("load average:")[1].strip()
    except:
        health["load"] = "N/A"
    
    return health

def get_top_processes():
    """Get top CPU and memory processes"""
    processes = {"cpu": [], "memory": []}
    try:
        result = subprocess.run(
            ["ps", "aux", "--sort=-%cpu"],
            capture_output=True,
            text=True
        )
        lines = result.stdout.strip().split("\n")[1:6]  # Skip header, top 5
        for line in lines:
            parts = line.split()
            if len(parts) >= 11:
                processes["cpu"].append({
                    "pid": parts[1],
                    "cpu": parts[2],
                    "mem": parts[3],
                    "cmd": " ".join(parts[10:])[:30]
                })
    except:
        pass
    
    try:
        result = subprocess.run(
            ["ps", "aux", "--sort=-%mem"],
            capture_output=True,
            text=True
        )
        lines = result.stdout.strip().split("\n")[1:6]
        for line in lines:
            parts = line.split()
            if len(parts) >= 11:
                processes["memory"].append({
                    "pid": parts[1],
                    "cpu": parts[2],
                    "mem": parts[3],
                    "cmd": " ".join(parts[10:])[:30]
                })
    except:
        pass
    
    return processes

def get_docker_containers():
    """Get Docker container status"""
    containers = []
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}|{{.Status}}|{{.Ports}}"],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split("\n"):
                if line:
                    parts = line.split("|")
                    containers.append({
                        "name": parts[0],
                        "status": parts[1],
                        "ports": parts[2] if len(parts) > 2 else ""
                    })
    except:
        pass
    return containers

def get_recent_activity():
    """Get recent activity from logs"""
    activity = []
    try:
        # Check if logs dir exists and has files
        if LOGS_DIR.exists():
            log_files = sorted(LOGS_DIR.glob("*.jsonl"), reverse=True)[:1]
            for log_file in log_files:
                with open(log_file) as f:
                    lines = f.readlines()[-10:]  # Last 10 entries
                    for line in lines:
                        try:
                            entry = json.loads(line)
                            activity.append(entry)
                        except:
                            pass
    except:
        pass
    return activity

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status")
def api_status():
    """Get combined status"""
    status = {
        "openclaw": get_openclaw_status(),
        "github": get_github_status(),
        "tasks": get_tasks(),
        "health": get_system_health(),
        "processes": get_top_processes(),
        "docker": get_docker_containers(),
        "activity": get_recent_activity(),
        "timestamp": datetime.now().isoformat()
    }
    return jsonify(status)

@app.route("/api/tasks")
def api_tasks():
    return jsonify(get_tasks())

@app.route("/api/tasks/<task_id>/complete", methods=["POST"])
def complete_task(task_id):
    """Mark task as complete"""
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

@app.route("/api/task/create", methods=["POST"])
def create_task():
    """Create a new task"""
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

@app.route("/api/health")
def api_health():
    return jsonify(get_system_health())

if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", 8767))
    app.run(host="0.0.0.0", port=port, debug=False)
