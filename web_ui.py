#!/usr/bin/env python3
"""
Agentic Autonomy Web UI
Lightweight web dashboard for monitoring and controlling autonomy
"""

import json
import os
import subprocess
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse

AUTONOMY_DIR = "/root/.openclaw/workspace/skills/autonomy"
CONFIG_FILE = f"{AUTONOMY_DIR}/config.json"
TASKS_DIR = f"{AUTONOMY_DIR}/tasks"
LOGS_DIR = f"{AUTONOMY_DIR}/logs"

class AutonomyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging
    
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        
        if path == "/":
            self.serve_dashboard()
        elif path == "/api/status":
            self.serve_api_status()
        elif path == "/api/tasks":
            self.serve_api_tasks()
        elif path == "/api/logs":
            self.serve_api_logs()
        elif path.startswith("/assets/"):
            self.serve_static(path)
        else:
            self.send_error(404)
    
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        
        if path == "/api/workstation/on":
            self.run_command("on")
        elif path == "/api/workstation/off":
            self.run_command("off")
        elif path == "/api/task/create":
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            data = json.loads(body)
            self.create_task(data.get('name'), data.get('description'))
        else:
            self.send_error(404)
    
    def serve_dashboard(self):
        html = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Agentic Autonomy Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0d1117;
            color: #e6edf3;
            line-height: 1.6;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        header {
            text-align: center;
            padding: 40px 0;
            border-bottom: 1px solid #30363d;
            margin-bottom: 30px;
        }
        h1 { color: #58a6ff; font-size: 2.5em; margin-bottom: 10px; }
        .subtitle { color: #8b949e; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 10px;
            padding: 20px;
        }
        .card h2 {
            color: #58a6ff;
            font-size: 1.2em;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-active { background: #3fb950; box-shadow: 0 0 10px #3fb950; }
        .status-inactive { background: #f85149; }
        .btn {
            background: #238636;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            margin-right: 10px;
            transition: background 0.2s;
        }
        .btn:hover { background: #2ea043; }
        .btn-danger { background: #f85149; }
        .btn-danger:hover { background: #ff6b6b; }
        .btn-secondary { background: #1f6feb; }
        .btn-secondary:hover { background: #388bfd; }
        .stat-value {
            font-size: 2em;
            font-weight: bold;
            color: #f85149;
        }
        .stat-label {
            color: #8b949e;
            font-size: 0.9em;
        }
        .task-list {
            list-style: none;
        }
        .task-item {
            background: #21262d;
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 6px;
            border-left: 3px solid #8957e5;
        }
        .task-item.completed {
            border-left-color: #3fb950;
            opacity: 0.7;
        }
        .task-name { font-weight: bold; margin-bottom: 4px; }
        .task-meta { font-size: 0.85em; color: #8b949e; }
        .log-entry {
            background: #21262d;
            padding: 8px 12px;
            margin-bottom: 4px;
            border-radius: 4px;
            font-family: monospace;
            font-size: 0.85em;
        }
        .controls {
            display: flex;
            gap: 10px;
            margin-top: 15px;
        }
        input, textarea {
            width: 100%;
            background: #21262d;
            border: 1px solid #30363d;
            color: #e6edf3;
            padding: 10px;
            border-radius: 6px;
            margin-bottom: 10px;
        }
        .limits-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 15px;
        }
        .limit-item {
            text-align: center;
            padding: 15px;
            background: #21262d;
            border-radius: 6px;
        }
        .refresh-btn {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #1f6feb;
            color: white;
            border: none;
            padding: 15px 20px;
            border-radius: 50px;
            cursor: pointer;
            font-size: 16px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🤖 Agentic Autonomy</h1>
            <p class="subtitle">AI-driven self-improving system for OpenClaw</p>
        </header>
        
        <div class="grid">
            <!-- Status Card -->
            <div class="card">
                <h2>Workstation Status</h2>
                <p id="status-display">
                    <span class="status-indicator status-inactive"></span>
                    <span id="status-text">Loading...</span>
                </p>
                <div class="controls">
                    <button class="btn" onclick="workstationOn()">Activate</button>
                    <button class="btn btn-danger" onclick="workstationOff()">Deactivate</button>
                </div>
            </div>
            
            <!-- Stats Card -->
            <div class="card">
                <h2>Statistics</h2>
                <div class="limits-grid">
                    <div class="limit-item">
                        <div class="stat-value" id="task-count">-</div>
                        <div class="stat-label">Tasks</div>
                    </div>
                    <div class="limit-item">
                        <div class="stat-value" id="agent-count">-</div>
                        <div class="stat-label">Agents</div>
                    </div>
                    <div class="limit-item">
                        <div class="stat-value" id="schedule-count">-</div>
                        <div class="stat-label">Schedules</div>
                    </div>
                    <div class="limit-item">
                        <div class="stat-value" id="token-usage">-</div>
                        <div class="stat-label">Tokens Today</div>
                    </div>
                </div>
            </div>
            
            <!-- Create Task Card -->
            <div class="card">
                <h2>Create Task</h2>
                <input type="text" id="task-name" placeholder="Task name (e.g., token-tracker)">
                <textarea id="task-desc" rows="3" placeholder="Description (e.g., Build a system to track daily token usage)"></textarea>
                <button class="btn btn-secondary" onclick="createTask()">Create Task</button>
            </div>
        </div>
        
        <div class="grid">
            <!-- Tasks Card -->
            <div class="card">
                <h2>📋 Active Tasks</h2>
                <ul class="task-list" id="task-list">
                    <li class="task-item">Loading...</li>
                </ul>
            </div>
            
            <!-- Logs Card -->
            <div class="card">
                <h2>📜 Recent Activity</h2>
                <div id="log-container">
                    <div class="log-entry">Loading...</div>
                </div>
            </div>
        </div>
    </div>
    
    <button class="refresh-btn" onclick="refreshData()">🔄 Refresh</button>
    
    <script>
        async function fetchStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                
                // Update status
                const isActive = data.active;
                document.getElementById('status-text').textContent = isActive ? 'ACTIVE' : 'INACTIVE';
                document.querySelector('.status-indicator').className = 
                    'status-indicator ' + (isActive ? 'status-active' : 'status-inactive');
                
                // Update stats
                document.getElementById('task-count').textContent = data.tasks;
                document.getElementById('agent-count').textContent = data.agents;
                document.getElementById('schedule-count').textContent = data.schedules;
                document.getElementById('token-usage').textContent = data.tokens;
            } catch (e) {
                console.error('Failed to fetch status:', e);
            }
        }
        
        async function fetchTasks() {
            try {
                const res = await fetch('/api/tasks');
                const tasks = await res.json();
                const list = document.getElementById('task-list');
                
                if (tasks.length === 0) {
                    list.innerHTML = '<li class="task-item">No active tasks</li>';
                    return;
                }
                
                list.innerHTML = tasks.map(t => `
                    <li class="task-item ${t.completed ? 'completed' : ''}">
                        <div class="task-name">${t.name}</div>
                        <div class="task-meta">${t.description} | ${t.status}</div>
                    </li>
                `).join('');
            } catch (e) {
                console.error('Failed to fetch tasks:', e);
            }
        }
        
        async function fetchLogs() {
            try {
                const res = await fetch('/api/logs');
                const logs = await res.json();
                const container = document.getElementById('log-container');
                
                if (logs.length === 0) {
                    container.innerHTML = '<div class="log-entry">No recent activity</div>';
                    return;
                }
                
                container.innerHTML = logs.map(l => `
                    <div class="log-entry">
                        [${new Date(l.timestamp).toLocaleTimeString()}] ${l.action}
                    </div>
                `).join('');
            } catch (e) {
                console.error('Failed to fetch logs:', e);
            }
        }
        
        async function workstationOn() {
            await fetch('/api/workstation/on', { method: 'POST' });
            refreshData();
        }
        
        async function workstationOff() {
            await fetch('/api/workstation/off', { method: 'POST' });
            refreshData();
        }
        
        async function createTask() {
            const name = document.getElementById('task-name').value;
            const desc = document.getElementById('task-desc').value;
            
            if (!name) {
                alert('Please enter a task name');
                return;
            }
            
            await fetch('/api/task/create', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name, description: desc })
            });
            
            document.getElementById('task-name').value = '';
            document.getElementById('task-desc').value = '';
            refreshData();
        }
        
        function refreshData() {
            fetchStatus();
            fetchTasks();
            fetchLogs();
        }
        
        // Auto-refresh every 10 seconds
        setInterval(refreshData, 10000);
        
        // Initial load
        refreshData();
    </script>
</body>
</html>'''
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def serve_api_status(self):
        try:
            with open(CONFIG_FILE) as f:
                config = json.load(f)
            
            active = config.get('workstation', {}).get('active', False)
            tasks = len([f for f in os.listdir(TASKS_DIR) if f.endswith('.json')])
            agents = len(config.get('workstation', {}).get('running_agents', []))
            schedules = len(config.get('workstation', {}).get('schedules', []))
            tokens = config.get('workstation', {}).get('token_usage_today', 0)
            
            data = {
                'active': active,
                'tasks': tasks,
                'agents': agents,
                'schedules': schedules,
                'tokens': tokens
            }
            
            self.send_json(data)
        except Exception as e:
            self.send_json({'error': str(e)}, 500)
    
    def serve_api_tasks(self):
        try:
            tasks = []
            for filename in os.listdir(TASKS_DIR):
                if filename.endswith('.json'):
                    with open(f"{TASKS_DIR}/{filename}") as f:
                        task = json.load(f)
                        tasks.append(task)
            self.send_json(tasks)
        except Exception as e:
            self.send_json({'error': str(e)}, 500)
    
    def serve_api_logs(self):
        try:
            logs = []
            log_file = f"{LOGS_DIR}/agentic.jsonl"
            if os.path.exists(log_file):
                with open(log_file) as f:
                    for line in f:
                        if line.strip():
                            logs.append(json.loads(line))
            # Return last 20 logs
            self.send_json(logs[-20:])
        except Exception as e:
            self.send_json({'error': str(e)}, 500)
    
    def run_command(self, cmd):
        try:
            result = subprocess.run(
                ['bash', f'{AUTONOMY_DIR}/autonomy', cmd],
                capture_output=True,
                text=True,
                timeout=10
            )
            self.send_json({'success': True, 'output': result.stdout})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def create_task(self, name, description):
        try:
            result = subprocess.run(
                ['bash', f'{AUTONOMY_DIR}/autonomy', 'task', 'create', name, description or 'No description'],
                capture_output=True,
                text=True,
                timeout=10
            )
            self.send_json({'success': True, 'output': result.stdout})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def serve_static(self, path):
        self.send_error(404)

def main():
    port = int(os.environ.get('AUTONOMY_WEB_PORT', 8765))
    server = HTTPServer(('0.0.0.0', port), AutonomyHandler)
    print(f"Agentic Autonomy Web UI running on http://localhost:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

if __name__ == '__main__':
    main()
