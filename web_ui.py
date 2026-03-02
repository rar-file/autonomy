#!/usr/bin/env python3
"""
Autonomy Web UI v2
Lightweight dashboard using OpenClaw's native data
"""

import os
import json
import subprocess
from datetime import datetime
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
    try:
        # CPU
        result = subprocess.run(
            ["top", "-bn1"],
            capture_output=True,
            text=True
        )
        for line in result.stdout.split("\n"):
            if "Cpu(s)" in line:
                health["cpu"] = line.split("%")[0].split()[-1] + "%"
                break
    except:
        health["cpu"] = "N/A"
    
    try:
        # Memory
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
                break
    except:
        health["memory"] = "N/A"
    
    try:
        # Disk
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
        # Load
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

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status")
def api_status():
    """Get combined status"""
    status = {
        "openclaw": get_openclaw_status(),
        "tasks": get_tasks(),
        "health": get_system_health(),
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

@app.route("/api/health")
def api_health():
    return jsonify(get_system_health())

if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", 8767))
    app.run(host="0.0.0.0", port=port, debug=False)
