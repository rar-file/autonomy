#!/usr/bin/env python3
"""Agentic Autonomy Web Dashboard Server"""

import json
import os
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

AUTONOMY_DIR = "/root/.openclaw/workspace/skills/autonomy"
CONFIG_FILE = f"{AUTONOMY_DIR}/config.json"
TASKS_DIR = f"{AUTONOMY_DIR}/tasks"
LOGS_DIR = f"{AUTONOMY_DIR}/logs"

# Colors from logo: #1a1a2e (bg), #16213e, #0f3460 (blues), #e94560 (accent red)
HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Agentic Autonomy | Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
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
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background: linear-gradient(135deg, var(--bg-primary) 0%, var(--bg-secondary) 100%);
            color: var(--text-primary);
            min-height: 100vh;
        }
        .bg-glow {
            position: fixed;
            width: 600px;
            height: 600px;
            background: radial-gradient(circle, rgba(233, 69, 96, 0.15) 0%, transparent 70%);
            top: -200px;
            right: -200px;
            pointer-events: none;
            z-index: -1;
        }
        .bg-glow-2 {
            position: fixed;
            width: 400px;
            height: 400px;
            background: radial-gradient(circle, rgba(83, 52, 131, 0.2) 0%, transparent 70%);
            bottom: -100px;
            left: -100px;
            pointer-events: none;
            z-index: -1;
        }
        .header {
            padding: 20px 32px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border-color);
            background: rgba(26, 26, 46, 0.8);
            backdrop-filter: blur(10px);
        }
        .logo {
            display: flex;
            align-items: center;
            gap: 16px;
        }
        .logo-svg {
            width: 48px;
            height: 48px;
        }
        .logo-text h1 {
            font-size: 24px;
            font-weight: 700;
            background: linear-gradient(135deg, var(--accent-primary), #ff6b8a);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .logo-text span {
            font-size: 12px;
            color: var(--text-secondary);
            letter-spacing: 0.5px;
        }
        .status-badge {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 10px 20px;
            background: rgba(16, 185, 129, 0.1);
            border: 1px solid rgba(16, 185, 129, 0.3);
            border-radius: 50px;
            font-size: 14px;
            font-weight: 600;
            color: var(--success);
        }
        .status-badge.inactive {
            background: rgba(239, 68, 68, 0.1);
            border-color: rgba(239, 68, 68, 0.3);
            color: var(--danger);
        }
        .pulse {
            width: 10px;
            height: 10px;
            background: currentColor;
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); box-shadow: 0 0 0 0 currentColor; }
            50% { opacity: 0.7; transform: scale(1.1); box-shadow: 0 0 0 8px transparent; }
        }
        .main-container {
            padding: 24px 32px;
            max-width: 1600px;
            margin: 0 auto;
        }
        .info-bar {
            display: flex;
            gap: 24px;
            margin-bottom: 24px;
            padding: 16px 20px;
            background: rgba(22, 33, 62, 0.6);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            font-size: 13px;
        }
        .info-item {
            display: flex;
            align-items: center;
            gap: 8px;
            color: var(--text-secondary);
        }
        .info-item i {
            color: var(--accent-primary);
        }
        .info-item strong {
            color: var(--text-primary);
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 20px;
            margin-bottom: 24px;
        }
        @media (max-width: 1200px) {
            .stats-grid { grid-template-columns: repeat(2, 1fr); }
        }
        @media (max-width: 768px) {
            .stats-grid { grid-template-columns: 1fr; }
        }
        .stat-card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 24px;
            position: relative;
            overflow: hidden;
            transition: all 0.3s ease;
        }
        .stat-card:hover {
            transform: translateY(-4px);
            border-color: rgba(233, 69, 96, 0.4);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
        }
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 3px;
            background: linear-gradient(90deg, var(--accent-primary), var(--accent-blue));
        }
        .stat-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 16px;
        }
        .stat-icon {
            width: 52px;
            height: 52px;
            border-radius: 14px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 22px;
            background: rgba(233, 69, 96, 0.1);
            color: var(--accent-primary);
            border: 1px solid rgba(233, 69, 96, 0.2);
        }
        .stat-card:nth-child(2) .stat-icon { background: rgba(83, 52, 131, 0.1); color: #a855f7; border-color: rgba(168, 85, 247, 0.2); }
        .stat-card:nth-child(3) .stat-icon { background: rgba(245, 158, 11, 0.1); color: var(--warning); border-color: rgba(245, 158, 11, 0.2); }
        .stat-card:nth-child(4) .stat-icon { background: rgba(16, 185, 129, 0.1); color: var(--success); border-color: rgba(16, 185, 129, 0.2); }
        .stat-value {
            font-size: 42px;
            font-weight: 800;
            line-height: 1;
            margin-bottom: 8px;
            background: linear-gradient(135deg, #fff, var(--text-secondary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .stat-label {
            font-size: 14px;
            color: var(--text-secondary);
            font-weight: 500;
        }
        .section-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 10px;
            color: var(--text-primary);
        }
        .section-title i {
            color: var(--accent-primary);
        }
        .content-grid {
            display: grid;
            grid-template-columns: 1fr 400px;
            gap: 24px;
        }
        @media (max-width: 1200px) {
            .content-grid { grid-template-columns: 1fr; }
        }
        .card {
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 24px;
        }
        .task-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 10px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .btn-primary {
            background: linear-gradient(135deg, var(--accent-primary), #ff6b8a);
            color: white;
            box-shadow: 0 4px 20px rgba(233, 69, 96, 0.3);
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 30px rgba(233, 69, 96, 0.4);
        }
        .btn-secondary {
            background: rgba(255, 255, 255, 0.05);
            color: var(--text-primary);
            border: 1px solid var(--border-color);
        }
        .btn-secondary:hover {
            background: rgba(255, 255, 255, 0.1);
            border-color: var(--accent-primary);
        }
        .btn-success {
            background: rgba(16, 185, 129, 0.2);
            color: var(--success);
            border: 1px solid rgba(16, 185, 129, 0.3);
        }
        .btn-success:hover {
            background: rgba(16, 185, 129, 0.3);
        }
        .btn-danger {
            background: rgba(239, 68, 68, 0.1);
            color: var(--danger);
            border: 1px solid rgba(239, 68, 68, 0.2);
            padding: 8px 16px;
            font-size: 12px;
        }
        .btn-danger:hover {
            background: rgba(239, 68, 68, 0.2);
        }
        .task-list {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .task-item {
            background: rgba(15, 15, 26, 0.6);
            border: 1px solid rgba(233, 69, 96, 0.15);
            border-radius: 12px;
            padding: 16px;
            transition: all 0.2s;
        }
        .task-item:hover {
            border-color: rgba(233, 69, 96, 0.3);
            transform: translateX(4px);
        }
        .task-item.completed {
            opacity: 0.6;
            border-left: 3px solid var(--success);
        }
        .task-item.pending {
            border-left: 3px solid var(--warning);
        }
        .task-header-row {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 8px;
        }
        .task-name {
            font-weight: 600;
            font-size: 15px;
            color: var(--text-primary);
        }
        .task-status {
            font-size: 11px;
            padding: 4px 10px;
            border-radius: 20px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .task-status.pending {
            background: rgba(245, 158, 11, 0.15);
            color: var(--warning);
        }
        .task-status.completed {
            background: rgba(16, 185, 129, 0.15);
            color: var(--success);
        }
        .task-desc {
            font-size: 13px;
            color: var(--text-secondary);
            margin-bottom: 12px;
            line-height: 1.5;
        }
        .task-meta {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 12px;
            color: var(--text-secondary);
        }
        .task-actions {
            display: flex;
            gap: 8px;
        }
        .sidebar {
            display: flex;
            flex-direction: column;
            gap: 20px;
        }
        .action-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
        }
        .action-btn {
            padding: 20px;
            background: rgba(15, 15, 26, 0.6);
            border: 1px solid rgba(233, 69, 96, 0.15);
            border-radius: 12px;
            color: var(--text-primary);
            cursor: pointer;
            transition: all 0.2s;
            text-align: center;
        }
        .action-btn:hover {
            background: rgba(233, 69, 96, 0.1);
            border-color: var(--accent-primary);
            transform: translateY(-2px);
        }
        .action-btn i {
            font-size: 24px;
            margin-bottom: 8px;
            display: block;
            color: var(--accent-primary);
        }
        .action-btn span {
            font-size: 13px;
            font-weight: 500;
        }
        .activity-list {
            display: flex;
            flex-direction: column;
            gap: 10px;
            max-height: 300px;
            overflow-y: auto;
        }
        .activity-item {
            display: flex;
            gap: 12px;
            padding: 12px;
            background: rgba(15, 15, 26, 0.6);
            border-radius: 10px;
            font-size: 13px;
            border-left: 2px solid var(--accent-primary);
        }
        .activity-icon {
            width: 36px;
            height: 36px;
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: rgba(233, 69, 96, 0.1);
            color: var(--accent-primary);
            flex-shrink: 0;
        }
        .activity-content {
            flex: 1;
        }
        .activity-text {
            margin-bottom: 4px;
            color: var(--text-primary);
        }
        .activity-time {
            font-size: 11px;
            color: var(--text-secondary);
        }
        .empty-state {
            text-align: center;
            padding: 40px;
            color: var(--text-secondary);
        }
        .empty-state i {
            font-size: 48px;
            margin-bottom: 16px;
            opacity: 0.3;
        }
        .modal-overlay {
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0, 0, 0, 0.8);
            backdrop-filter: blur(4px);
            display: none;
            align-items: center;
            justify-content: center;
            z-index: 1000;
        }
        .modal-overlay.active { display: flex; }
        .modal {
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 20px;
            padding: 28px;
            width: 90%;
            max-width: 500px;
            animation: modalIn 0.3s ease;
        }
        @keyframes modalIn {
            from { opacity: 0; transform: scale(0.95) translateY(10px); }
            to { opacity: 1; transform: scale(1) translateY(0); }
        }
        .modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
        }
        .modal-title {
            font-size: 20px;
            font-weight: 700;
            color: var(--text-primary);
        }
        .modal-close {
            background: none;
            border: none;
            color: var(--text-secondary);
            font-size: 24px;
            cursor: pointer;
            width: 40px;
            height: 40px;
            border-radius: 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
        }
        .modal-close:hover {
            background: rgba(255, 255, 255, 0.05);
            color: var(--text-primary);
        }
        .form-group { margin-bottom: 20px; }
        .form-label {
            display: block;
            font-size: 13px;
            font-weight: 600;
            margin-bottom: 8px;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .form-input, .form-textarea, .form-select {
            width: 100%;
            padding: 14px 18px;
            background: rgba(15, 15, 26, 0.8);
            border: 1px solid rgba(233, 69, 96, 0.2);
            border-radius: 12px;
            color: var(--text-primary);
            font-size: 15px;
            transition: all 0.2s;
        }
        .form-input:focus, .form-textarea:focus, .form-select:focus {
            outline: none;
            border-color: var(--accent-primary);
            box-shadow: 0 0 0 3px rgba(233, 69, 96, 0.1);
        }
        .form-textarea {
            resize: vertical;
            min-height: 120px;
        }
        ::-webkit-scrollbar {
            width: 8px;
        }
        ::-webkit-scrollbar-track {
            background: rgba(255, 255, 255, 0.02);
            border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb {
            background: rgba(233, 69, 96, 0.2);
            border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb:hover {
            background: rgba(233, 69, 96, 0.3);
        }
    </style>
</head>
<body>
    <div class="bg-glow"></div>
    <div class="bg-glow-2"></div>
    
    <header class="header">
        <div class="logo">
            <svg class="logo-svg" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
                <circle cx="100" cy="100" r="90" fill="#1a1a2e" stroke="#16213e" stroke-width="4"/>
                <circle cx="100" cy="100" r="80" fill="none" stroke="#0f3460" stroke-width="2"/>
                <circle cx="100" cy="50" r="15" fill="#e94560"/>
                <circle cx="100" cy="50" r="8" fill="#1a1a2e"/>
                <circle cx="55" cy="130" r="15" fill="#e94560"/>
                <circle cx="55" cy="130" r="8" fill="#1a1a2e"/>
                <circle cx="145" cy="130" r="15" fill="#e94560"/>
                <circle cx="145" cy="130" r="8" fill="#1a1a2e"/>
                <line x1="100" y1="65" x2="65" y2="118" stroke="#e94560" stroke-width="3"/>
                <line x1="100" y1="65" x2="135" y2="118" stroke="#e94560" stroke-width="3"/>
                <line x1="70" y1="130" x2="130" y2="130" stroke="#e94560" stroke-width="3"/>
                <circle cx="100" cy="100" r="20" fill="#16213e" stroke="#e94560" stroke-width="3"/>
                <circle cx="100" cy="100" r="8" fill="#e94560"/>
            </svg>
            <div class="logo-text">
                <h1>Agentic Autonomy</h1>
                <span>AI-DRIVEN SELF-IMPROVEMENT SYSTEM</span>
            </div>
        </div>
        
        <div id="status-badge" class="status-badge">
            <span class="pulse"></span>
            <span id="status-text">Loading...</span>
        </div>
    </header>
    
    <main class="main-container">
        <div class="info-bar">
            <div class="info-item">
                <i class="fas fa-robot"></i>
                <span>Mode: <strong>Agentic</strong></span>
            </div>
            <div class="info-item">
                <i class="fas fa-shield-alt"></i>
                <span>Limits: <strong>5 tasks, 3 agents, 50K tokens/day</strong></span>
            </div>
            <div class="info-item">
                <i class="fas fa-code-branch"></i>
                <span>Version: <strong>2.0.6</strong></span>
            </div>
            <div class="info-item">
                <i class="fas fa-sync"></i>
                <span>Auto-refresh: <strong>Every 5s</strong></span>
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon"><i class="fas fa-tasks"></i></div>
                </div>
                <div class="stat-value" id="stat-tasks">-</div>
                <div class="stat-label">Total Tasks</div>
            </div>
            
            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon"><i class="fas fa-microchip"></i></div>
                </div>
                <div class="stat-value" id="stat-agents">-</div>
                <div class="stat-label">Running Agents</div>
            </div>
            
            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon"><i class="fas fa-clock"></i></div>
                </div>
                <div class="stat-value" id="stat-schedules">-</div>
                <div class="stat-label">Scheduled Tasks</div>
            </div>
            
            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon"><i class="fas fa-coins"></i></div>
                </div>
                <div class="stat-value" id="stat-tokens">-</div>
                <div class="stat-label">Tokens Used Today</div>
            </div>
        </div>
        
        <div class="content-grid">
            <div class="card">
                <div class="task-header">
                    <h2 class="section-title"><i class="fas fa-clipboard-list"></i>Task Queue</h2>
                    <button class="btn btn-primary" onclick="openModal()">
                        <i class="fas fa-plus"></i>New Task
                    </button>
                </div>
                
                <div id="task-container">
                    <div class="empty-state">
                        <i class="fas fa-spinner fa-spin"></i>
                        <p>Loading tasks...</p>
                    </div>
                </div>
            </div>
            
            <div class="sidebar">
                <div class="card">
                    <h2 class="section-title"><i class="fas fa-bolt"></i>Quick Actions</h2>
                    
                    <div class="action-grid">
                        <button class="action-btn" onclick="workstationOn()">
                            <i class="fas fa-power-off"></i>
                            <span>Activate</span>
                        </button>
                        
                        <button class="action-btn" onclick="workstationOff()">
                            <i class="fas fa-stop"></i>
                            <span>Deactivate</span>
                        </button>
                        
                        <button class="action-btn" onclick="refreshData()">
                            <i class="fas fa-sync"></i>
                            <span>Refresh</span>
                        </button>
                        
                        <button class="action-btn" onclick="openModal()">
                            <i class="fas fa-plus-circle"></i>
                            <span>Add Task</span>
                        </button>
                    </div>
                </div>
                
                <div class="card">
                    <h2 class="section-title"><i class="fas fa-history"></i>Recent Activity</h2>
                    
                    <div class="activity-list" id="activity-list">
                        <div class="empty-state">
                            <i class="fas fa-circle-notch"></i>
                            <p>No recent activity</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </main>
    
    <div class="modal-overlay" id="modal">
        <div class="modal">
            <div class="modal-header">
                <h3 class="modal-title">Create New Task</h3>
                <button class="modal-close" onclick="closeModal()"><i class="fas fa-times"></i></button>
            </div>
            
            <div class="form-group">
                <label class="form-label">Task Name</label>
                <input type="text" class="form-input" id="new-task-name" placeholder="e.g., build-token-tracker">
            </div>
            
            <div class="form-group">
                <label class="form-label">Description</label>
                <textarea class="form-textarea" id="new-task-desc" placeholder="What should the AI build? Be specific..."></textarea>
            </div>
            
            <div class="form-group">
                <label class="form-label">Priority</label>
                <select class="form-select" id="new-task-priority">
                    <option value="high">🔴 High</option>
                    <option value="medium" selected>🟡 Medium</option>
                    <option value="low">🟢 Low</option>
                </select>
            </div>
            
            <button class="btn btn-primary" onclick="createTask()" style="width: 100%; justify-content: center;">
                <i class="fas fa-plus"></i>Create Task
            </button>
        </div>
    </div>
    
    <script>
        async function fetchStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                
                const badge = document.getElementById('status-badge');
                const text = document.getElementById('status-text');
                
                if (data.active) {
                    badge.className = 'status-badge';
                    text.textContent = 'ACTIVE';
                } else {
                    badge.className = 'status-badge inactive';
                    text.textContent = 'INACTIVE';
                }
                
                document.getElementById('stat-tasks').textContent = data.tasks || 0;
                document.getElementById('stat-agents').textContent = data.agents || 0;
                document.getElementById('stat-schedules').textContent = data.schedules || 0;
                
                const tokens = data.tokens || 0;
                document.getElementById('stat-tokens').textContent = tokens > 1000 
                    ? (tokens / 1000).toFixed(1) + 'k' 
                    : tokens.toString();
            } catch (e) {
                console.error('Status fetch failed:', e);
            }
        }
        
        async function fetchTasks() {
            try {
                const res = await fetch('/api/tasks');
                const tasks = await res.json();
                const container = document.getElementById('task-container');
                
                if (!tasks || tasks.length === 0) {
                    container.innerHTML = `
                        <div class="empty-state">
                            <i class="fas fa-clipboard-check"></i>
                            <p>No tasks found</p>
                            <button class="btn btn-primary" onclick="openModal()" style="margin-top: 16px;">Create First Task</button>
                        </div>
                    `;
                    return;
                }
                
                const pendingTasks = tasks.filter(t => t.status !== 'completed' && !t.completed);
                const completedTasks = tasks.filter(t => t.status === 'completed' || t.completed);
                
                let html = `<div class="task-list">`;
                
                // Pending tasks first
                pendingTasks.forEach(task => {
                    html += renderTaskCard(task);
                });
                
                // Completed tasks
                completedTasks.forEach(task => {
                    html += renderTaskCard(task);
                });
                
                html += `</div>`;
                container.innerHTML = html;
            } catch (e) {
                console.error('Tasks fetch failed:', e);
                document.getElementById('task-container').innerHTML = `
                    <div class="empty-state">
                        <i class="fas fa-exclamation-triangle"></i>
                        <p>Error loading tasks</p>
                    </div>
                `;
            }
        }
        
        function renderTaskCard(task) {
            const isCompleted = task.status === 'completed' || task.completed;
            const statusClass = isCompleted ? 'completed' : 'pending';
            const statusText = isCompleted ? 'Completed' : 'Pending';
            const priorityEmoji = { high: '🔴', medium: '🟡', low: '🟢' }[task.priority] || '⚪';
            
            return `
                <div class="task-item ${statusClass}">
                    <div class="task-header-row">
                        <div class="task-name">${task.name}</div>
                        <span class="task-status ${statusClass}">${statusText}</span>
                    </div>
                    <div class="task-desc">${task.description || 'No description'}</div>
                    <div class="task-meta">
                        <span>${priorityEmoji} ${task.priority || 'normal'} priority &#8226; Created ${new Date(task.created).toLocaleString()}</span>
                        ${!isCompleted ? `
                            <div class="task-actions">
                                <button class="btn btn-success" onclick="completeTask('${task.name}')"><i class="fas fa-check"></i> Complete</button>
                            </div>
                        ` : `
                            <div class="task-actions">
                                <button class="btn btn-danger" onclick="deleteTask('${task.name}')"><i class="fas fa-trash"></i> Delete</button>
                            </div>
                        `}
                    </div>
                </div>
            `;
        }
        
        async function completeTask(name) {
            if (!confirm(`Mark task "${name}" as complete?`)) return;
            // Call API to complete task
            await fetch('/api/task/complete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name })
            });
            refreshData();
        }
        
        async function deleteTask(name) {
            if (!confirm(`Delete task "${name}"? This cannot be undone.`)) return;
            // Call API to delete task
            await fetch('/api/task/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name })
            });
            refreshData();
        }
        
        async function fetchLogs() {
            try {
                const res = await fetch('/api/logs');
                const logs = await res.json();
                const container = document.getElementById('activity-list');
                
                if (!logs || logs.length === 0) {
                    container.innerHTML = `
                        <div class="empty-state">
                            <i class="fas fa-circle-notch"></i>
                            <p>No recent activity</p>
                        </div>
                    `;
                    return;
                }
                
                container.innerHTML = logs.reverse().slice(0, 10).map(log => {
                    const icon = log.action.includes('task') ? 'tasks' : 
                                log.action.includes('agent') ? 'microchip' : 
                                log.action.includes('workstation') ? 'power-off' : 'circle';
                    return `
                        <div class="activity-item">
                            <div class="activity-icon"><i class="fas fa-${icon}"></i></div>
                            <div class="activity-content">
                                <div class="activity-text">${log.action.replace(/_/g, ' ').replace(/\\b\\w/g, l => l.toUpperCase())}</div>
                                <div class="activity-time">${new Date(log.timestamp).toLocaleTimeString()}</div>
                            </div>
                        </div>
                    `;
                }).join('');
            } catch (e) {
                console.error('Logs fetch failed:', e);
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
        
        function openModal() { document.getElementById('modal').classList.add('active'); }
        function closeModal() { document.getElementById('modal').classList.remove('active'); }
        
        async function createTask() {
            const name = document.getElementById('new-task-name').value;
            const desc = document.getElementById('new-task-desc').value;
            
            if (!name) {
                alert('Please enter a task name');
                return;
            }
            
            await fetch('/api/task/create', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    name, 
                    description: desc, 
                    priority: document.getElementById('new-task-priority').value 
                })
            });
            
            document.getElementById('new-task-name').value = '';
            document.getElementById('new-task-desc').value = '';
            closeModal();
            refreshData();
        }
        
        function refreshData() { fetchStatus(); fetchTasks(); fetchLogs(); }
        setInterval(refreshData, 5000);
        refreshData();
        
        document.getElementById('modal').addEventListener('click', e => {
            if (e.target.id === 'modal') closeModal();
        });
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
        elif self.path == "/api/task/create": self.create_task()
        elif self.path == "/api/task/complete": self.complete_task()
        elif self.path == "/api/task/delete": self.delete_task()
        else: self.send_error(404)
    
    def serve_status(self):
        try:
            with open(CONFIG_FILE) as f: config = json.load(f)
            active = config.get("workstation", {}).get("active", False)
            tasks = len([f for f in os.listdir(TASKS_DIR) if f.endswith(".json")])
            agents = len(config.get("workstation", {}).get("running_agents", []))
            schedules = len(config.get("workstation", {}).get("schedules", []))
            tokens = config.get("workstation", {}).get("token_usage_today", 0)
            self.send_json({"active": active, "tasks": tasks, "agents": agents, "schedules": schedules, "tokens": tokens})
        except Exception as e: self.send_json({"error": str(e)}, 500)
    
    def serve_tasks(self):
        try:
            tasks = []
            for f in os.listdir(TASKS_DIR):
                if f.endswith(".json"):
                    try:
                        with open(f"{TASKS_DIR}/{f}", 'r', encoding='utf-8') as fp:
                            content = fp.read()
                            # Handle any invalid control characters
                            content = ''.join(char for char in content if ord(char) >= 32 or char in '\n\r\t')
                            tasks.append(json.loads(content))
                    except Exception as e:
                        print(f"Error reading task {f}: {e}")
                        continue
            self.send_json(tasks)
        except Exception as e: self.send_json({"error": str(e)}, 500)
    
    def serve_logs(self):
        try:
            logs = []
            log_file = f"{LOGS_DIR}/agentic.jsonl"
            if os.path.exists(log_file):
                with open(log_file) as f:
                    for line in f:
                        if line.strip(): logs.append(json.loads(line))
            self.send_json(logs[-30:])
        except Exception as e: self.send_json({"error": str(e)}, 500)
    
    def run_cmd(self, cmd):
        try:
            subprocess.run(["bash", f"{AUTONOMY_DIR}/autonomy", cmd], capture_output=True, timeout=10)
            self.send_json({"success": True})
        except Exception as e: self.send_json({"success": False, "error": str(e)}, 500)
    
    def create_task(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len))
            subprocess.run(["bash", f"{AUTONOMY_DIR}/autonomy", "task", "create", body.get("name", "task"), body.get("description", "No description")], capture_output=True, timeout=10)
            self.send_json({"success": True})
        except Exception as e: self.send_json({"success": False, "error": str(e)}, 500)
    
    def complete_task(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len))
            name = body.get("name", "")
            # Mark task as completed
            task_file = f"{TASKS_DIR}/{name}.json"
            if os.path.exists(task_file):
                with open(task_file) as f: task = json.load(f)
                task["status"] = "completed"
                task["completed"] = True
                task["completed_at"] = datetime.now().isoformat()
                with open(task_file, "w") as f: json.dump(task, f, indent=2)
            self.send_json({"success": True})
        except Exception as e: self.send_json({"success": False, "error": str(e)}, 500)
    
    def delete_task(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len))
            name = body.get("name", "")
            task_file = f"{TASKS_DIR}/{name}.json"
            if os.path.exists(task_file):
                os.remove(task_file)
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
