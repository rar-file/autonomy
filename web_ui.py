#!/usr/bin/env python3
"""Agentic Autonomy Web Dashboard Server - Enhanced Version"""

import json
import os
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

AUTONOMY_DIR = "/root/.openclaw/workspace/skills/autonomy"
CONFIG_FILE = f"{AUTONOMY_DIR}/config.json"
TASKS_DIR = f"{AUTONOMY_DIR}/tasks"
LOGS_DIR = f"{AUTONOMY_DIR}/logs"

HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Agentic Autonomy | Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-primary: #0f0f1a;
            --bg-secondary: #1a1a2e;
            --bg-card: #16213e;
            --border-color: rgba(233, 69, 96, 0.2);
            --text-primary: #ffffff;
            --text-secondary: #a0a0b0;
            --accent-primary: #e94560;
            --accent-secondary: #0f3460;
            --accent-blue: #533483;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
        }
        [data-theme="light"] {
            --bg-primary: #f5f5f7;
            --bg-secondary: #ffffff;
            --bg-card: #f0f0f5;
            --border-color: rgba(233, 69, 96, 0.3);
            --text-primary: #1a1a2e;
            --text-secondary: #666666;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
            transition: all 0.3s ease;
        }
        .header {
            padding: 20px 32px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border-color);
            background: var(--bg-secondary);
        }
        .logo { display: flex; align-items: center; gap: 16px; }
        .logo-icon {
            width: 48px; height: 48px;
            background: linear-gradient(135deg, var(--accent-primary), #ff6b8a);
            border-radius: 12px;
            display: flex; align-items: center; justify-content: center;
            font-size: 24px; color: white;
        }
        .header-actions { display: flex; gap: 12px; align-items: center; }
        .theme-toggle {
            width: 44px; height: 44px;
            border-radius: 10px;
            border: 1px solid var(--border-color);
            background: var(--bg-card);
            color: var(--text-primary);
            cursor: pointer;
            font-size: 18px;
            transition: all 0.2s;
        }
        .theme-toggle:hover { transform: scale(1.1); }
        .main-container { padding: 24px 32px; max-width: 1600px; margin: 0 auto; }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 20px;
            margin-bottom: 24px;
        }
        @media (max-width: 1200px) { .stats-grid { grid-template-columns: repeat(2, 1fr); } }
        @media (max-width: 768px) { .stats-grid { grid-template-columns: 1fr; } }
        .stat-card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 24px;
            position: relative;
            overflow: hidden;
        }
        .stat-card::before {
            content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
            background: linear-gradient(90deg, var(--accent-primary), var(--accent-blue));
        }
        .stat-header { display: flex; justify-content: space-between; margin-bottom: 16px; }
        .stat-value { font-size: 36px; font-weight: 800; }
        .stat-label { font-size: 14px; color: var(--text-secondary); }
        .search-bar {
            display: flex;
            gap: 12px;
            margin-bottom: 20px;
        }
        .search-input {
            flex: 1;
            padding: 12px 16px;
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 10px;
            color: var(--text-primary);
            font-size: 14px;
        }
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 10px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .btn-primary {
            background: linear-gradient(135deg, var(--accent-primary), #ff6b8a);
            color: white;
        }
        .btn-secondary {
            background: var(--bg-card);
            color: var(--text-primary);
            border: 1px solid var(--border-color);
        }
        .content-grid {
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 24px;
        }
        @media (max-width: 1200px) { .content-grid { grid-template-columns: 1fr; } }
        .card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 24px;
        }
        .section-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .task-list { display: flex; flex-direction: column; gap: 12px; }
        .task-item {
            background: var(--bg-primary);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            padding: 16px;
            transition: all 0.2s;
        }
        .task-item:hover { transform: translateX(4px); border-color: var(--accent-primary); }
        .task-item.hidden { display: none; }
        .task-header { display: flex; justify-content: space-between; margin-bottom: 8px; }
        .task-name { font-weight: 600; }
        .task-status {
            font-size: 11px;
            padding: 4px 10px;
            border-radius: 20px;
            font-weight: 600;
            text-transform: uppercase;
        }
        .task-status.pending { background: rgba(245, 158, 11, 0.15); color: var(--warning); }
        .task-status.completed { background: rgba(16, 185, 129, 0.15); color: var(--success); }
        .task-desc { font-size: 13px; color: var(--text-secondary); margin-bottom: 12px; }
        .task-meta { display: flex; justify-content: space-between; font-size: 12px; color: var(--text-secondary); }
        .chart-container {
            height: 200px;
            margin-bottom: 24px;
        }
        .export-buttons {
            display: flex;
            gap: 10px;
            margin-top: 16px;
        }
    </style>
</head>
<body>
    <header class="header">
        <div class="logo">
            <div class="logo-icon"><i class="fas fa-robot"></i></div>
            <div>
                <h1 style="font-size: 24px; font-weight: 700;">Agentic Autonomy</h1>
                <span style="font-size: 12px; color: var(--text-secondary);">AI-Driven Self-Improvement</span>
            </div>
        </div>
        <div class="header-actions">
            <button class="theme-toggle" onclick="toggleTheme()" title="Toggle Dark/Light Mode">
                <i class="fas fa-sun" id="theme-icon"></i>
            </button>
            <div id="status-badge" class="status-badge" style="display: flex; align-items: center; gap: 8px; padding: 10px 20px; background: rgba(16, 185, 129, 0.1); border: 1px solid rgba(16, 185, 129, 0.3); border-radius: 50px; color: var(--success);">
                <span class="pulse" style="width: 10px; height: 10px; background: currentColor; border-radius: 50%;"></span>
                <span id="status-text">Loading...</span>
            </div>
        </div>
    </header>

    <div class="main-container">
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-header"><div class="stat-value" id="stat-tasks">-</div></div>
                <div class="stat-label">Total Tasks</div>
            </div>
            <div class="stat-card">
                <div class="stat-header"><div class="stat-value" id="stat-pending">-</div></div>
                <div class="stat-label">Pending</div>
            </div>
            <div class="stat-card">
                <div class="stat-header"><div class="stat-value" id="stat-completed">-</div></div>
                <div class="stat-label">Completed</div>
            </div>
            <div class="stat-card">
                <div class="stat-header"><div class="stat-value" id="stat-agents">-</div></div>
                <div class="stat-label">Agents</div>
            </div>
        </div>

        <div class="content-grid">
            <div class="card">
                <h2 class="section-title"><i class="fas fa-chart-line"></i>Task Overview</h2>
                <div class="chart-container">
                    <canvas id="taskChart"></canvas>
                </div>
                
                <div class="search-bar">
                    <input type="text" class="search-input" id="taskSearch" placeholder="🔍 Search tasks..." onkeyup="filterTasks()">
                    <select class="search-input" id="statusFilter" onchange="filterTasks()" style="width: 150px;">
                        <option value="all">All Status</option>
                        <option value="pending">Pending</option>
                        <option value="completed">Completed</option>
                    </select>
                </div>

                <div class="export-buttons">
                    <button class="btn btn-secondary" onclick="exportTasks('json')"><i class="fas fa-file-code"></i>Export JSON</button>
                    <button class="btn btn-secondary" onclick="exportTasks('csv')"><i class="fas fa-file-csv"></i>Export CSV</button>
                </div>
                
                <div style="margin-top: 20px;">
                    <h3 style="font-size: 16px; margin-bottom: 12px;">Tasks</h3>
                    <div class="task-list" id="task-container">
                        <div style="text-align: center; padding: 40px; color: var(--text-secondary);">
                            <i class="fas fa-spinner fa-spin" style="font-size: 24px;"></i><p>Loading...</p>
                        </div>
                    </div>
                </div>
            </div>

            <div class="card">
                <h2 class="section-title"><i class="fas fa-bolt"></i>Quick Actions</h2>
                <div style="display: flex; flex-direction: column; gap: 12px;">
                    <button class="btn btn-primary" onclick="workstationOn()"><i class="fas fa-power-off"></i>Activate</button>
                    <button class="btn btn-secondary" onclick="workstationOff()"><i class="fas fa-stop"></i>Deactivate</button>
                    <button class="btn btn-secondary" onclick="refreshData()"><i class="fas fa-sync"></i>Refresh</button>
                </div>
                
                <h2 class="section-title" style="margin-top: 24px;"><i class="fas fa-history"></i>Activity</h2>
                <div id="activity-list" style="display: flex; flex-direction: column; gap: 10px;">
                    <div style="text-align: center; padding: 20px; color: var(--text-secondary);">
                        <i class="fas fa-circle-notch"></i><p>No activity</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let allTasks = [];
        let taskChart = null;

        function toggleTheme() {
            const html = document.documentElement;
            const icon = document.getElementById('theme-icon');
            if (html.getAttribute('data-theme') === 'dark') {
                html.setAttribute('data-theme', 'light');
                icon.className = 'fas fa-moon';
            } else {
                html.setAttribute('data-theme', 'dark');
                icon.className = 'fas fa-sun';
            }
            localStorage.setItem('theme', html.getAttribute('data-theme'));
        }

        // Load saved theme
        const savedTheme = localStorage.getItem('theme') || 'dark';
        document.documentElement.setAttribute('data-theme', savedTheme);
        document.getElementById('theme-icon').className = savedTheme === 'dark' ? 'fas fa-sun' : 'fas fa-moon';

        async function fetchData() {
            try {
                const [statusRes, tasksRes, logsRes] = await Promise.all([
                    fetch('/api/status'),
                    fetch('/api/tasks'),
                    fetch('/api/logs')
                ]);
                
                const status = await statusRes.json();
                allTasks = await tasksRes.json();
                const logs = await logsRes.json();
                
                updateStatus(status);
                updateStats(allTasks);
                updateChart(allTasks);
                renderTasks(allTasks);
                updateActivity(logs);
            } catch (e) {
                console.error('Fetch error:', e);
            }
        }

        function updateStatus(status) {
            const badge = document.getElementById('status-badge');
            const text = document.getElementById('status-text');
            if (status.active) {
                badge.style.background = 'rgba(16, 185, 129, 0.1)';
                badge.style.borderColor = 'rgba(16, 185, 129, 0.3)';
                badge.style.color = 'var(--success)';
                text.textContent = 'ACTIVE';
            } else {
                badge.style.background = 'rgba(239, 68, 68, 0.1)';
                badge.style.borderColor = 'rgba(239, 68, 68, 0.3)';
                badge.style.color = 'var(--danger)';
                text.textContent = 'INACTIVE';
            }
        }

        function updateStats(tasks) {
            const pending = tasks.filter(t => !t.completed && t.status !== 'completed').length;
            const completed = tasks.filter(t => t.completed || t.status === 'completed').length;
            
            document.getElementById('stat-tasks').textContent = tasks.length;
            document.getElementById('stat-pending').textContent = pending;
            document.getElementById('stat-completed').textContent = completed;
            document.getElementById('stat-agents').textContent = '0';
        }

        function updateChart(tasks) {
            const ctx = document.getElementById('taskChart').getContext('2d');
            const pending = tasks.filter(t => !t.completed && t.status !== 'completed').length;
            const completed = tasks.filter(t => t.completed || t.status === 'completed').length;
            
            if (taskChart) taskChart.destroy();
            
            taskChart = new Chart(ctx, {
                type: 'doughnut',
                data: {
                    labels: ['Pending', 'Completed'],
                    datasets: [{
                        data: [pending, completed],
                        backgroundColor: ['#f59e0b', '#10b981'],
                        borderWidth: 0
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { position: 'bottom', labels: { color: 'var(--text-primary)' } }
                    }
                }
            });
        }

        function renderTasks(tasks) {
            const container = document.getElementById('task-container');
            if (tasks.length === 0) {
                container.innerHTML = `<div style="text-align: center; padding: 40px; color: var(--text-secondary);"><i class="fas fa-clipboard-check" style="font-size: 48px;"></i><p>No tasks found</p></div>`;
                return;
            }
            
            container.innerHTML = `<div class="task-list">${tasks.map(task => {
                const isCompleted = task.completed || task.status === 'completed';
                return `
                    <div class="task-item" data-status="${isCompleted ? 'completed' : 'pending'}" data-name="${task.name.toLowerCase()}">
                        <div class="task-header">
                            <span class="task-name">${task.name}</span>
                            <span class="task-status ${isCompleted ? 'completed' : 'pending'}">${isCompleted ? 'Completed' : 'Pending'}</span>
                        </div>
                        <div class="task-desc">${task.description || 'No description'}</div>
                        <div class="task-meta">
                            <span>Priority: ${task.priority || 'normal'} &#8226; ${new Date(task.created).toLocaleDateString()}</span>
                        </div>
                    </div>
                `;
            }).join('')}</div>`;
        }

        function filterTasks() {
            const search = document.getElementById('taskSearch').value.toLowerCase();
            const statusFilter = document.getElementById('statusFilter').value;
            
            document.querySelectorAll('.task-item').forEach(item => {
                const name = item.getAttribute('data-name');
                const status = item.getAttribute('data-status');
                
                const matchesSearch = name.includes(search);
                const matchesStatus = statusFilter === 'all' || status === statusFilter;
                
                item.classList.toggle('hidden', !(matchesSearch && matchesStatus));
            });
        }

        function exportTasks(format) {
            if (format === 'json') {
                const dataStr = JSON.stringify(allTasks, null, 2);
                const blob = new Blob([dataStr], { type: 'application/json' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `autonomy-tasks-${new Date().toISOString().split('T')[0]}.json`;
                a.click();
            } else if (format === 'csv') {
                const headers = ['name', 'description', 'status', 'priority', 'created'];
                const csv = [
                    headers.join(','),
                    ...allTasks.map(t => headers.map(h => `"${(t[h] || '').toString().replace(/"/g, '"")}"`).join(','))
                ].join('\\n');
                const blob = new Blob([csv], { type: 'text/csv' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `autonomy-tasks-${new Date().toISOString().split('T')[0]}.csv`;
                a.click();
            }
        }

        function updateActivity(logs) {
            const container = document.getElementById('activity-list');
            if (!logs || logs.length === 0) return;
            
            container.innerHTML = logs.slice(-5).map(log => `
                <div style="padding: 12px; background: var(--bg-primary); border-radius: 8px; font-size: 13px;">
                    <div>${log.action.replace(/_/g, ' ')}</div>
                    <div style="font-size: 11px; color: var(--text-secondary); margin-top: 4px;">${new Date(log.timestamp).toLocaleTimeString()}</div>
                </div>
            `).join('');
        }

        async function workstationOn() {
            await fetch('/api/workstation/on', { method: 'POST' });
            fetchData();
        }

        async function workstationOff() {
            await fetch('/api/workstation/off', { method: 'POST' });
            fetchData();
        }

        function refreshData() { fetchData(); }

        setInterval(fetchData, 5000);
        fetchData();
    </script>
</body>
</html>'''

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass
    
    def do_GET(self):
        if self.path in ["/", "/index.html"]:
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(HTML_TEMPLATE.encode())
        elif self.path == "/api/status": self.serve_status()
        elif self.path == "/api/tasks": self.serve_tasks()
        elif self.path == "/api/logs": self.serve_logs()
        else: self.send_error(404)
    
    def do_POST(self):
        if self.path == "/api/workstation/on": self.run_cmd("on")
        elif self.path == "/api/workstation/off": self.run_cmd("off")
        else: self.send_error(404)
    
    def serve_status(self):
        try:
            with open(CONFIG_FILE) as f: config = json.load(f)
            active = config.get("workstation", {}).get("active", False)
            self.send_json({"active": active})
        except: self.send_json({"active": False})
    
    def serve_tasks(self):
        try:
            tasks = []
            for f in os.listdir(TASKS_DIR):
                if f.endswith(".json"):
                    try:
                        with open(f"{TASKS_DIR}/{f}", 'r', encoding='utf-8') as fp:
                            content = fp.read()
                            content = ''.join(char for char in content if ord(char) >= 32 or char in '\n\r\t')
                            tasks.append(json.loads(content))
                    except: continue
            self.send_json(tasks)
        except Exception as e: self.send_json({"error": str(e)}, 500)
    
    def serve_logs(self):
        try:
            logs = []
            log_file = f"{LOGS_DIR}/agentic.jsonl"
            if os.path.exists(log_file):
                with open(log_file) as f:
                    for line in f:
                        if line.strip():
                            try: logs.append(json.loads(line))
                            except: pass
            self.send_json(logs[-20:])
        except: self.send_json([])
    
    def run_cmd(self, cmd):
        try:
            subprocess.run(["bash", f"{AUTONOMY_DIR}/autonomy", cmd], capture_output=True, timeout=10)
            self.send_json({"success": True})
        except Exception as e: self.send_json({"success": False, "error": str(e)}, 500)
    
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", 8767))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Dashboard running at http://localhost:{port}")
    server.serve_forever()
