#!/usr/bin/env python3
"""rar-file/autonomy Dashboard with Heartbeat Timer"""

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
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta name="theme-color" content="#e94560">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <link rel="manifest" href="/manifest.json">
    <link rel="apple-touch-icon" href="/icon-192.png">
    <title>rar-file/autonomy</title>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root {
            --bg-0: #050508;
            --bg-1: #0a0a0f;
            --bg-2: #12121a;
            --bg-3: #1a1a2e;
            --accent: #e94560;
            --accent-light: #ff6b8a;
            --text: #ffffff;
            --text-muted: #6b6b8a;
        }
        
        [data-theme="light"] {
            --bg-0: #f5f5f7;
            --bg-1: #ffffff;
            --bg-2: #f0f0f2;
            --bg-3: #e8e8eb;
            --accent: #e94560;
            --accent-light: #ff6b8a;
            --text: #1a1a2e;
            --text-muted: #6b6b8a;
        }
        
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg-0);
            color: var(--text);
            min-height: 100vh;
            transition: background 0.3s ease, color 0.3s ease;
        }
        .bg-animation {
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background-image: 
                linear-gradient(rgba(233, 69, 96, 0.03) 1px, transparent 1px),
                linear-gradient(90deg, rgba(233, 69, 96, 0.03) 1px, transparent 1px);
            background-size: 50px 50px;
            z-index: -2;
        }
        .app {
            display: grid;
            grid-template-columns: 300px 1fr;
            min-height: 100vh;
        }
        .sidebar {
            background: linear-gradient(180deg, var(--bg-1) 0%, var(--bg-2) 100%);
            border-right: 1px solid rgba(233,69,96,0.1);
            padding: 24px 16px;
            display: flex;
            flex-direction: column;
            position: sticky;
            top: 0;
            height: 100vh;
        }
        .brand {
            display: flex;
            align-items: center;
            gap: 14px;
            padding: 16px;
            margin-bottom: 32px;
            background: linear-gradient(135deg, rgba(233, 69, 96, 0.1), rgba(83, 52, 131, 0.1));
            border: 1px solid rgba(233, 69, 96, 0.2);
            border-radius: 16px;
        }
        .brand-logo {
            width: 44px;
            height: 44px;
            flex-shrink: 0;
            filter: drop-shadow(0 0 10px rgba(233, 69, 96, 0.4));
        }
        .brand-text h1 {
            font-family: 'JetBrains Mono', monospace;
            font-size: 16px;
            font-weight: 700;
            color: #ffffff;
            text-shadow: 0 0 20px rgba(233, 69, 96, 0.5);
        }
        .brand-text span {
            font-size: 11px;
            color: #b8b8d8;
            font-weight: 500;
        }
        .nav-section {
            margin-bottom: 24px;
        }
        .nav-title {
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            color: #8080a0;
            margin-bottom: 8px;
            padding-left: 16px;
            font-weight: 700;
        }
        .nav-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 14px 18px;
            border-radius: 12px;
            cursor: pointer;
            color: #e0e0f0;
            font-weight: 600;
            font-size: 15px;
            transition: all 0.3s;
            margin-bottom: 6px;
            border: 1px solid transparent;
            background: rgba(255, 255, 255, 0.03);
        }
        .nav-item:hover {
            background: rgba(233, 69, 96, 0.15);
            color: #ffffff;
            transform: translateX(6px);
            border-color: rgba(233, 69, 96, 0.3);
        }
        .nav-item.active {
            background: linear-gradient(135deg, rgba(233, 69, 96, 0.25), rgba(233, 69, 96, 0.1));
            color: #ffffff;
            border-color: rgba(233, 69, 96, 0.5);
            box-shadow: 0 0 30px rgba(233, 69, 96, 0.2);
        }
        .nav-item i {
            width: 22px;
            text-align: center;
            font-size: 17px;
            color: #ff6b8a;
        }
        .main {
            padding: 32px;
            overflow-y: auto;
            max-height: 100vh;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 40px;
            padding-bottom: 24px;
            border-bottom: 1px solid rgba(233,69,96,0.1);
        }
        .header-title h2 {
            font-size: 36px;
            font-weight: 800;
            margin-bottom: 8px;
            background: linear-gradient(135deg, #fff 0%, #a0a0c0 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .header-title p {
            color: #a0a0c0;
            font-size: 15px;
        }
        .heartbeat-box {
            background: linear-gradient(135deg, rgba(233,69,96,0.15), rgba(233,69,96,0.05));
            border: 1px solid rgba(233,69,96,0.3);
            border-radius: 12px;
            padding: 12px 20px;
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 12px;
        }
        .heartbeat-box i {
            color: #e94560;
            font-size: 20px;
            animation: pulse 1.5s ease-in-out infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.6; transform: scale(1.1); }
        }
        .heartbeat-label {
            font-size: 11px;
            color: #a0a0c0;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .heartbeat-timer {
            font-size: 24px;
            font-weight: 800;
            color: #ffffff;
            font-family: 'JetBrains Mono', monospace;
            text-shadow: 0 0 20px rgba(255,255,255,0.3);
        }
        .system-status-box {
            background: linear-gradient(135deg, rgba(34,197,94,0.15), rgba(34,197,94,0.05));
            border: 1px solid rgba(34,197,94,0.3);
            border-radius: 12px;
            padding: 10px 16px;
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 13px;
            font-weight: 600;
            color: #22c55e;
            margin-bottom: 12px;
        }
        .system-status-box.warning {
            background: linear-gradient(135deg, rgba(245,158,11,0.15), rgba(245,158,11,0.05));
            border-color: rgba(245,158,11,0.3);
            color: #f59e0b;
        }
        .system-status-box.error {
            background: linear-gradient(135deg, rgba(239,68,68,0.15), rgba(239,68,68,0.05));
            border-color: rgba(239,68,68,0.3);
            color: #ef4444;
        }
        .btn {
            padding: 12px 24px;
            border-radius: 12px;
            border: none;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            transition: all 0.3s;
        }
        .btn-primary {
            background: linear-gradient(135deg, #e94560, #ff6b8a);
            color: white;
            box-shadow: 0 4px 20px rgba(233, 69, 96, 0.3);
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 30px rgba(233, 69, 96, 0.4);
        }
        .btn-secondary {
            background: var(--bg-2);
            color: var(--text);
            border: 1px solid rgba(233,69,96,0.2);
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 20px;
            margin-bottom: 40px;
        }
        @media (max-width: 1400px) { .stats-grid { grid-template-columns: repeat(2, 1fr); } }
        @media (max-width: 768px) { .stats-grid { grid-template-columns: 1fr; } }
        .stat-card {
            background: linear-gradient(135deg, var(--bg-2), var(--bg-3));
            border: 1px solid rgba(233,69,96,0.1);
            border-radius: 20px;
            padding: 28px;
            position: relative;
            overflow: hidden;
        }
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0; left: 0; right: 0; height: 3px;
            background: linear-gradient(90deg, #e94560, #ff6b8a);
        }
        .stat-value {
            font-size: 48px;
            font-weight: 900;
            color: #ffffff !important;
            text-shadow: 0 0 40px rgba(255,255,255,0.5), 0 0 80px rgba(233,69,96,0.3);
            margin-bottom: 8px;
            letter-spacing: -1px;
        }
        .stat-label {
            font-size: 14px;
            color: #c0c0d8;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .page { display: none; }
        .page.active { display: block; animation: fadeIn 0.4s ease; }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .card {
            background: linear-gradient(135deg, var(--bg-2), var(--bg-3));
            border: 1px solid rgba(233,69,96,0.1);
            border-radius: 20px;
            padding: 28px;
        }
        .task-list {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }
        .task-item {
            background: linear-gradient(135deg, var(--bg-1), var(--bg-2));
            border: 1px solid rgba(233,69,96,0.08);
            border-radius: 16px;
            padding: 20px;
            transition: all 0.3s;
            cursor: pointer;
        }
        .task-item:hover {
            border-color: rgba(233,69,96,0.3);
            transform: translateX(8px);
        }
        .task-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 8px;
        }
        .task-name {
            font-weight: 600;
            font-size: 16px;
            color: #ffffff;
        }
        .task-status {
            font-size: 11px;
            padding: 6px 14px;
            border-radius: 20px;
            font-weight: 600;
            text-transform: uppercase;
        }
        .task-status.pending {
            background: linear-gradient(135deg, rgba(245,158,11,0.15), rgba(245,158,11,0.05));
            color: #f59e0b;
            border: 1px solid rgba(245,158,11,0.2);
        }
        .task-status.completed {
            background: linear-gradient(135deg, rgba(34,197,94,0.15), rgba(34,197,94,0.05));
            color: #22c55e;
            border: 1px solid rgba(34,197,94,0.2);
        }
        .task-status.needs_ai_attention {
            background: linear-gradient(135deg, rgba(233, 69, 96, 0.2), rgba(233, 69, 96, 0.1));
            color: #e94560;
            border: 1px solid rgba(233, 69, 96, 0.3);
            animation: pulse-attention 2s infinite;
        }
        .task-status.needs_ai {
            background: linear-gradient(135deg, rgba(233, 69, 96, 0.2), rgba(233, 69, 96, 0.1));
            color: #e94560;
            border: 1px solid rgba(233, 69, 96, 0.3);
            animation: pulse-attention 2s infinite;
        }
        .task-status.processing {
            background: linear-gradient(135deg, rgba(59, 130, 246, 0.2), rgba(59, 130, 246, 0.1));
            color: #3b82f6;
            border: 1px solid rgba(59, 130, 246, 0.3);
        }
        @keyframes pulse-attention {
            0%, 100% { opacity: 1; box-shadow: 0 0 0 0 rgba(233, 69, 96, 0.4); }
            50% { opacity: 0.9; box-shadow: 0 0 0 8px rgba(233, 69, 96, 0); }
        }
        .task-desc {
            font-size: 14px;
            color: #c0c0d8;
            line-height: 1.6;
            margin-bottom: 12px;
        }
        /* Task Detail Modal */
        .modal-overlay {
            display: none;
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.8);
            z-index: 1000;
            backdrop-filter: blur(8px);
        }
        .modal-overlay.active {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .modal {
            background: linear-gradient(135deg, var(--bg-2), var(--bg-3));
            border: 1px solid rgba(233,69,96,0.2);
            border-radius: 24px;
            width: 90%;
            max-width: 800px;
            max-height: 90vh;
            overflow: hidden;
            animation: modalIn 0.3s ease;
        }
        @keyframes modalIn {
            from { opacity: 0; transform: scale(0.95); }
            to { opacity: 1; transform: scale(1); }
        }
        .modal-header {
            background: linear-gradient(135deg, rgba(233,69,96,0.1), rgba(83,52,131,0.1));
            border-bottom: 1px solid rgba(233,69,96,0.1);
            padding: 24px 32px;
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
        }
        .modal-title {
            font-size: 24px;
            font-weight: 700;
            color: #ffffff;
            margin-bottom: 8px;
        }
        .modal-status {
            font-size: 12px;
            padding: 6px 16px;
            border-radius: 20px;
            font-weight: 600;
            text-transform: uppercase;
        }
        .modal-close {
            background: none;
            border: none;
            color: #8080a0;
            font-size: 24px;
            cursor: pointer;
            padding: 8px;
            transition: color 0.3s;
        }
        .modal-close:hover {
            color: #ffffff;
        }
        .modal-body {
            padding: 32px;
            overflow-y: auto;
            max-height: 60vh;
        }
        .modal-section {
            margin-bottom: 28px;
        }
        .modal-section:last-child {
            margin-bottom: 0;
        }
        .modal-section-title {
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 1.5px;
            color: #e94560;
            font-weight: 600;
            margin-bottom: 12px;
        }
        .modal-description {
            font-size: 15px;
            color: #d0d0e8;
            line-height: 1.8;
            white-space: pre-wrap;
        }
        .modal-verification {
            background: linear-gradient(135deg, rgba(34,197,94,0.1), rgba(34,197,94,0.05));
            border: 1px solid rgba(34,197,94,0.2);
            border-radius: 12px;
            padding: 20px;
            font-size: 14px;
            color: #d0f0d8;
            line-height: 1.7;
            white-space: pre-wrap;
        }
        .modal-evidence {
            background: linear-gradient(135deg, var(--bg-1), var(--bg-2));
            border: 1px solid rgba(233,69,96,0.1);
            border-radius: 12px;
            padding: 16px;
        }
        .modal-meta-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 16px;
        }
        .modal-meta-item {
            background: linear-gradient(135deg, var(--bg-1), var(--bg-2));
            border: 1px solid rgba(233,69,96,0.1);
            border-radius: 12px;
            padding: 16px;
        }
        .modal-meta-label {
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: #8080a0;
            margin-bottom: 6px;
        }
        .modal-meta-value {
            font-size: 14px;
            color: #ffffff;
            font-weight: 500;
        }
        .task-meta {
            font-size: 12px;
            color: #a0a0c0;
            display: flex;
            gap: 20px;
        }
        .loading {
            text-align: center;
            padding: 80px;
            color: #a0a0c0;
        }
        .spinner {
            width: 48px;
            height: 48px;
            border: 3px solid rgba(233,69,96,0.2);
            border-top-color: #e94560;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        @media (max-width: 1024px) {
            .app { grid-template-columns: 1fr; }
            .sidebar { display: none; }
        }
        
        /* Onboarding Modal */
        .onboarding-overlay {
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.8);
            z-index: 1000;
            display: flex;
            align-items: center;
            justify-content: center;
            backdrop-filter: blur(5px);
        }
        .onboarding-modal {
            background: var(--bg-2);
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            width: 90%;
            border: 1px solid var(--bg-3);
            box-shadow: 0 25px 50px rgba(0,0,0,0.5);
            animation: slideIn 0.3s ease;
        }
        @keyframes slideIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .onboarding-modal h2 {
            font-size: 28px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .onboarding-modal h2 i {
            color: var(--accent);
        }
        .onboarding-step {
            margin: 20px 0;
            padding: 20px;
            background: var(--bg-1);
            border-radius: 12px;
            border-left: 4px solid var(--accent);
        }
        .onboarding-step h3 {
            font-size: 16px;
            margin-bottom: 10px;
            color: var(--accent-light);
        }
        .onboarding-step p {
            color: var(--text-muted);
            font-size: 14px;
            line-height: 1.6;
        }
        .onboarding-actions {
            display: flex;
            gap: 12px;
            margin-top: 30px;
            justify-content: flex-end;
        }
        .feature-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
            margin: 20px 0;
        }
        .feature-item {
            padding: 16px;
            background: var(--bg-1);
            border-radius: 10px;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .feature-item i {
            color: var(--accent);
            font-size: 20px;
            width: 24px;
        }
        .feature-item span {
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="bg-animation"></div>
    
    <!-- Onboarding Modal -->
    <div id="onboarding-modal" class="onboarding-overlay" style="display: none;">
        <div class="onboarding-modal">
            <h2><i class="fas fa-robot"></i> Welcome to Autonomy</h2>
            <p style="color: var(--text-muted); margin-bottom: 20px;">
                Your AI-powered self-improvement system. Let's get you set up in 2 minutes.
            </p>
            
            <div class="feature-grid">
                <div class="feature-item">
                    <i class="fas fa-brain"></i>
                    <span>Agentic AI</span>
                </div>
                <div class="feature-item">
                    <i class="fas fa-tasks"></i>
                    <span>Task Management</span>
                </div>
                <div class="feature-item">
                    <i class="fas fa-clock"></i>
                    <span>Auto Scheduling</span>
                </div>
                <div class="feature-item">
                    <i class="fas fa-chart-line"></i>
                    <span>Metrics Dashboard</span>
                </div>
            </div>
            
            <div class="onboarding-step">
                <h3><i class="fas fa-power-off"></i> Step 1: Activate Workstation</h3>
                <p>The AI processes tasks automatically when the workstation is active.</p>
                <button class="btn btn-primary" onclick="activateWorkstation()" style="margin-top: 10px;">
                    <i class="fas fa-play"></i> Activate Now
                </button>
            </div>
            
            <div class="onboarding-step">
                <h3><i class="fas fa-heartbeat"></i> Step 2: Start the Daemon</h3>
                <p>The daemon runs every 10 minutes to flag tasks for AI processing.</p>
                <button class="btn btn-primary" onclick="startDaemon()" style="margin-top: 10px;">
                    <i class="fas fa-heartbeat"></i> Start Daemon
                </button>
            </div>
            
            <div class="onboarding-actions">
                <button class="btn btn-secondary" onclick="skipOnboarding()">
                    Skip for Now
                </button>
                <button class="btn btn-primary" onclick="completeOnboarding()">
                    <i class="fas fa-check"></i> Get Started
                </button>
            </div>
        </div>
    </div>
    
    <div class="app">
        <aside class="sidebar">
            <div class="brand">
                <svg class="brand-logo" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
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
                <div class="brand-text">
                    <h1>rar-file/autonomy</h1>
                    <span>Agentic Self-Improvement</span>
                </div>
            </div>
            
            <div class="nav-section">
                <div class="nav-title">Main</div>
                <div class="nav-item active" onclick="showPage('dashboard', this)"><i class="fas fa-chart-pie"></i> Dashboard</div>
                <div class="nav-item" onclick="showPage('tasks', this)"><i class="fas fa-tasks"></i> Tasks</div>
                <div class="nav-item" onclick="showPage('agents', this)"><i class="fas fa-microchip"></i> Agents</div>
            </div>
            
            <div class="nav-section">
                <div class="nav-title">System</div>
                <div class="nav-item" onclick="showPage('schedules', this)"><i class="fas fa-clock"></i> Schedules</div>
                <div class="nav-item" onclick="window.open('/metrics', '_blank')"><i class="fas fa-chart-line"></i> Metrics</div>
                <div class="nav-item" onclick="showPage('settings', this)"><i class="fas fa-cog"></i> Settings</div>
            </div>
        </aside>
        
        <main class="main">
            <!-- Dashboard Page -->
            <div id="page-dashboard" class="page active">
                <header class="header">
                    <div class="header-title">
                        <h2>Dashboard</h2>
                        <p>Overview of your autonomous system</p>
                    </div>
                    <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 12px;">
                        <div class="heartbeat-box">
                            <i class="fas fa-heartbeat"></i>
                            <div>
                                <div class="heartbeat-label">Next Heartbeat</div>
                                <div class="heartbeat-timer" id="heartbeat-timer">--:--</div>
                            </div>
                        </div>
                        <div class="system-status-box" id="system-status">
                            <i class="fas fa-circle" style="color: #22c55e;"></i>
                            <span>System Healthy</span>
                        </div>
                        <div style="display: flex; gap: 12px;">
                            <button class="btn btn-secondary" onclick="showHeartbeatInfo()">
                                <i class="fas fa-heartbeat"></i> Heartbeat Info
                            </button>
                            <button class="btn btn-secondary" onclick="loadData()">
                                <i class="fas fa-sync"></i> Refresh
                            </button>
                            <button class="btn btn-secondary" onclick="toggleTheme()" id="theme-toggle">
                                <i class="fas fa-moon"></i> Theme
                            </button>
                            <button class="btn btn-primary" onclick="createTask()">
                                <i class="fas fa-plus"></i> New Task
                            </button>
                        </div>
                    </div>
                </header>
                
                <div class="stats-grid">
                    <div class="stat-card">
                        <div class="stat-value" id="stat-total">-</div>
                        <div class="stat-label">Total Tasks</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value" id="stat-pending">-</div>
                        <div class="stat-label">Pending</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value" id="stat-completed">-</div>
                        <div class="stat-label">Completed</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value" id="stat-agents">-</div>
                        <div class="stat-label">Active Agents</div>
                    </div>
                </div>
                
                <div class="card" style="border-left: 4px solid #e94560;">
                    <h3 style="font-size: 20px; font-weight: 700; margin-bottom: 20px; color: #e94560;"><i class="fas fa-robot"></i> Needs AI Attention <span id="count-needs-ai" style="font-size: 14px; background: rgba(233,69,96,0.2); padding: 4px 12px; border-radius: 20px;">0</span></h3>
                    <div id="dashboard-needs-ai">
                        <p style="color: #8080a0; padding: 20px;">No tasks waiting for AI</p>
                    </div>
                </div>
                
                <div class="card" style="border-left: 4px solid #3b82f6; margin-top: 20px;">
                    <h3 style="font-size: 20px; font-weight: 700; margin-bottom: 20px; color: #3b82f6;"><i class="fas fa-spinner fa-spin"></i> AI Processing <span id="count-processing" style="font-size: 14px; background: rgba(59,130,246,0.2); padding: 4px 12px; border-radius: 20px;">0</span></h3>
                    <div id="dashboard-processing">
                        <p style="color: #8080a0; padding: 20px;">No tasks currently being processed</p>
                    </div>
                </div>
                
                <div class="card" style="border-left: 4px solid #f59e0b; margin-top: 20px;">
                    <h3 style="font-size: 20px; font-weight: 700; margin-bottom: 20px; color: #f59e0b;"><i class="fas fa-clock"></i> Pending <span id="count-pending" style="font-size: 14px; background: rgba(245,158,11,0.2); padding: 4px 12px; border-radius: 20px;">0</span></h3>
                    <div id="dashboard-pending">
                        <p style="color: #8080a0; padding: 20px;">No pending tasks</p>
                    </div>
                </div>
                
                <div class="card" style="border-left: 4px solid #22c55e; margin-top: 20px;">
                    <h3 style="font-size: 20px; font-weight: 700; margin-bottom: 20px; color: #22c55e;"><i class="fas fa-check-circle"></i> Completed <span id="count-completed" style="font-size: 14px; background: rgba(34,197,94,0.2); padding: 4px 12px; border-radius: 20px;">0</span></h3>
                    <div id="dashboard-completed">
                        <p style="color: #8080a0; padding: 20px;">No completed tasks</p>
                    </div>
                </div>
            </div>
            
            <!-- Tasks Page -->
            <div id="page-tasks" class="page">
                <header class="header">
                    <div class="header-title">
                        <h2>Tasks</h2>
                        <p>Manage your autonomous tasks</p>
                    </div>
                    <button class="btn btn-primary" onclick="createTask()">
                        <i class="fas fa-plus"></i> New Task
                    </button>
                </header>
                
                <div id="all-tasks">
                    <div class="loading">
                        <div class="spinner"></div>
                        <p>Loading all tasks...</p>
                    </div>
                </div>
            </div>
            
            <!-- Other pages -->
            <div id="page-agents" class="page"><header class="header"><div class="header-title"><h2>Agents</h2></div></header><div class="card"><p style="text-align:center;padding:60px;color:#a0a0c0;"><i class="fas fa-robot" style="font-size:64px;margin-bottom:20px;opacity:0.3;"></i><br>No Active Agents</p></div></div>
            <div id="page-schedules" class="page"><header class="header"><div class="header-title"><h2>Schedules</h2></div></header><div class="card"><p style="text-align:center;padding:40px;">Every 10 Minutes - Check for improvements</p></div></div>
            <div id="page-settings" class="page"><header class="header"><div class="header-title"><h2>Settings</h2></div></header><div class="card"><button class="btn btn-primary" onclick="workstationOn()" style="margin-right:10px;">Activate</button><button class="btn btn-secondary" onclick="workstationOff()">Deactivate</button></div></div>
        </main>
    </div>
    
    <!-- Task Detail Modal -->
    <div id="task-modal" class="modal-overlay" onclick="closeTaskModal(event)">
        <div class="modal" onclick="event.stopPropagation()">
            <div class="modal-header">
                <div>
                    <div class="modal-title" id="modal-task-name">Task Name</div>
                    <span class="modal-status" id="modal-task-status">Pending</span>
                </div>
                <button class="modal-close" onclick="closeTaskModal()">&times;</button>
            </div>
            <div class="modal-body">
                <div class="modal-section">
                    <div class="modal-section-title">Description</div>
                    <div class="modal-description" id="modal-task-description">No description available.</div>
                </div>
                
                <div class="modal-section" id="modal-verification-section" style="display:none;">
                    <div class="modal-section-title"><i class="fas fa-check-circle"></i> Verification</div>
                    <div class="modal-verification" id="modal-task-verification">No verification provided.</div>
                </div>
                
                <div class="modal-section" id="modal-evidence-section" style="display:none;">
                    <div class="modal-section-title"><i class="fas fa-file-alt"></i> Evidence</div>
                    <div class="modal-evidence" id="modal-task-evidence">No evidence recorded.</div>
                </div>
                
                <div class="modal-section">
                    <div class="modal-section-title">Metadata</div>
                    <div class="modal-meta-grid">
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Priority</div>
                            <div class="modal-meta-value" id="modal-task-priority">normal</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Created</div>
                            <div class="modal-meta-value" id="modal-task-created">-</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Assignee</div>
                            <div class="modal-meta-value" id="modal-task-assignee">self</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Attempts</div>
                            <div class="modal-meta-value" id="modal-task-attempts">0/3</div>
                        </div>
                        <div class="modal-meta-item" id="modal-completed-at-item" style="display:none;">
                            <div class="modal-meta-label">Completed At</div>
                            <div class="modal-meta-value" id="modal-task-completed-at">-</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Subtasks</div>
                            <div class="modal-meta-value" id="modal-task-subtasks">0</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Heartbeat Info Modal -->
    <div id="heartbeat-modal" class="modal-overlay" onclick="closeHeartbeatModal(event)">
        <div class="modal" onclick="event.stopPropagation()" style="max-width: 700px;">
            <div class="modal-header">
                <div>
                    <div class="modal-title"><i class="fas fa-heartbeat"></i> Heartbeat Information</div>
                    <span class="modal-status" id="hb-status-badge">Active</span>
                </div>
                <button class="modal-close" onclick="closeHeartbeatModal()">&times;</button>
            </div>
            <div class="modal-body">
                <div class="modal-section">
                    <div class="modal-section-title"><i class="fas fa-clock"></i> Timing</div>
                    <div class="modal-meta-grid">
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Last Heartbeat</div>
                            <div class="modal-meta-value" id="hb-last">--</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Next Heartbeat</div>
                            <div class="modal-meta-value" id="hb-next">--:--</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Interval</div>
                            <div class="modal-meta-value">10 minutes</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Uptime</div>
                            <div class="modal-meta-value" id="hb-uptime">--</div>
                        </div>
                    </div>
                </div>
                
                <div class="modal-section">
                    <div class="modal-section-title"><i class="fas fa-chart-bar"></i> Statistics</div>
                    <div class="modal-meta-grid">
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Total Cycles</div>
                            <div class="modal-meta-value" id="hb-cycles">--</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Success Rate</div>
                            <div class="modal-meta-value" id="hb-success-rate">--%</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Tasks Processed</div>
                            <div class="modal-meta-value" id="hb-tasks">--</div>
                        </div>
                        <div class="modal-meta-item">
                            <div class="modal-meta-label">Health Checks</div>
                            <div class="modal-meta-value" id="hb-health">Passed</div>
                        </div>
                    </div>
                </div>
                
                <div class="modal-section">
                    <div class="modal-section-title"><i class="fas fa-history"></i> Recent Activity</div>
                    <div id="hb-activity-list" style="max-height: 200px; overflow-y: auto; font-family: monospace; font-size: 12px; line-height: 1.6;">
                        <div style="padding: 12px; background: linear-gradient(135deg, var(--bg-1), var(--bg-2)); border-radius: 8px; color: #a0a0c0;">
                            Loading activity log...
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        let allTasks = [];
        let lastHeartbeat = Date.now();
        let heartbeatInterval = 5 * 60 * 1000; // 5 minutes
        let heartbeatHistory = [];
        
        function showPage(pageId, navItem) {
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.getElementById('page-' + pageId).classList.add('active');
            document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
            if (navItem) navItem.classList.add('active');
        }
        
        async function loadData() {
            try {
                const res = await fetch('/api/tasks');
                allTasks = await res.json();
                updateDashboard();
            } catch (e) {
                console.error('Error:', e);
            }
        }
        
        function updateDashboard() {
            // Separate tasks by status
            const needsAI = allTasks.filter(t => t.status === 'needs_ai_attention');
            const processing = allTasks.filter(t => t.status === 'ai_processing');
            const pending = allTasks.filter(t => !t.completed && t.status !== 'completed' && t.status !== 'needs_ai_attention' && t.status !== 'ai_processing');
            const completed = allTasks.filter(t => t.completed || t.status === 'completed');
            
            // Update stats
            document.getElementById('stat-total').textContent = allTasks.length;
            document.getElementById('stat-pending').textContent = pending.length + needsAI.length + processing.length;
            document.getElementById('stat-completed').textContent = completed.length;
            document.getElementById('stat-agents').textContent = processing.length;
            
            // Update counts
            document.getElementById('count-needs-ai').textContent = needsAI.length;
            document.getElementById('count-processing').textContent = processing.length;
            document.getElementById('count-pending').textContent = pending.length;
            document.getElementById('count-completed').textContent = completed.length;
            
            // Render sections
            renderTaskSection('dashboard-needs-ai', needsAI, 'needs_ai');
            renderTaskSection('dashboard-processing', processing, 'processing');
            renderTaskSection('dashboard-pending', pending, 'pending');
            renderTaskSection('dashboard-completed', completed, 'completed');
            
            // Also update tasks page
            renderTasks('all-tasks', allTasks);
        }
        
        function renderTaskSection(containerId, tasks, type) {
            const container = document.getElementById(containerId);
            if (tasks.length === 0) {
                let msg = 'No tasks';
                if (type === 'needs_ai') msg = 'No tasks waiting for AI';
                if (type === 'processing') msg = 'No tasks currently being processed';
                if (type === 'pending') msg = 'No pending tasks';
                if (type === 'completed') msg = 'No completed tasks';
                container.innerHTML = `<p style="color: #8080a0; padding: 20px;">${msg}</p>`;
                return;
            }
            
            container.innerHTML = `<div class="task-list">${tasks.map(task => {
                const desc = task.description ? (task.description.substring(0, 80) + '...') : 'No description';
                let statusClass = type;
                let statusText = type === 'needs_ai' ? 'Needs AI' : type;
                if (type === 'needs_ai') statusText = '🔴 Needs AI';
                if (type === 'processing') statusText = '🔄 Processing';
                if (type === 'completed') statusText = '✅ Completed';
                
                return `<div class="task-item" onclick="openTaskModal('${task.name}')" style="cursor:pointer;">
                    <div class="task-header">
                        <span class="task-name">${task.name}</span>
                        <span class="task-status ${statusClass}">${statusText}</span>
                    </div>
                    <div class="task-desc">${desc}</div>
                    <div class="task-meta">
                        <span><i class="fas fa-flag"></i> ${task.priority || 'normal'}</span>
                        <span><i class="fas fa-calendar"></i> ${new Date(task.created).toLocaleDateString()}</span>
                    </div>
                </div>`;
            }).join('')}</div>`;
        }
        
        function renderTasks(containerId, tasks) {
            const container = document.getElementById(containerId);
            if (tasks.length === 0) {
                container.innerHTML = `<div style="text-align:center;padding:60px;color:#a0a0c0;"><i class="fas fa-clipboard" style="font-size:48px;margin-bottom:16px;opacity:0.5;"></i><p>No tasks found</p></div>`;
                return;
            }
            
            container.innerHTML = `<div class="task-list">${tasks.map(task => {
                const isCompleted = task.completed || task.status === 'completed';
                const isNeedsAttention = task.status === 'needs_ai_attention';
                const desc = task.description ? (task.description.substring(0, 100) + '...') : 'No description';
                let statusClass = 'pending';
                let statusText = 'Pending';
                if (isCompleted) {
                    statusClass = 'completed';
                    statusText = 'Completed';
                } else if (isNeedsAttention) {
                    statusClass = 'needs_ai_attention';
                    statusText = 'Needs AI';
                }
                return `<div class="task-item" onclick="openTaskModal('${task.name}')" style="cursor:pointer;">
                    <div class="task-header"><span class="task-name">${task.name}</span><span class="task-status ${statusClass}">${statusText}</span></div>
                    <div class="task-desc">${desc}</div>
                    <div class="task-meta"><span><i class="fas fa-flag"></i> ${task.priority || 'normal'}</span><span><i class="fas fa-calendar"></i> ${new Date(task.created).toLocaleDateString()}</span></div>
                </div>`;
            }).join('')}</div>`;
        }
        
        // Task Modal Functions
        function openTaskModal(taskName) {
            const task = allTasks.find(t => t.name === taskName);
            if (!task) return;
            
            const isCompleted = task.completed || task.status === 'completed';
            const isNeedsAttention = task.status === 'needs_ai_attention';
            
            document.getElementById('modal-task-name').textContent = task.name;
            
            let modalStatusText = 'Pending';
            let modalStatusClass = 'pending';
            if (isCompleted) {
                modalStatusText = 'Completed';
                modalStatusClass = 'completed';
            } else if (isNeedsAttention) {
                modalStatusText = 'Needs AI Attention';
                modalStatusClass = 'needs_ai_attention';
            }
            
            document.getElementById('modal-task-status').textContent = modalStatusText;
            document.getElementById('modal-task-status').className = 'modal-status ' + modalStatusClass;
            document.getElementById('modal-task-description').textContent = task.description || 'No description available.';
            document.getElementById('modal-task-priority').textContent = task.priority || 'normal';
            document.getElementById('modal-task-created').textContent = new Date(task.created).toLocaleString();
            document.getElementById('modal-task-assignee').textContent = task.assignee || 'self';
            document.getElementById('modal-task-attempts').textContent = (task.attempts || 0) + '/' + (task.max_attempts || 3);
            document.getElementById('modal-task-subtasks').textContent = (task.subtasks || []).length;
            
            // Show/hide verification section
            const verificationSection = document.getElementById('modal-verification-section');
            if (task.verification) {
                verificationSection.style.display = 'block';
                document.getElementById('modal-task-verification').textContent = task.verification;
            } else {
                verificationSection.style.display = 'none';
            }
            
            // Show/hide evidence section
            const evidenceSection = document.getElementById('modal-evidence-section');
            if (task.evidence && task.evidence.length > 0) {
                evidenceSection.style.display = 'block';
                document.getElementById('modal-task-evidence').innerHTML = task.evidence.map(e => `<p>${e}</p>`).join('');
            } else {
                evidenceSection.style.display = 'none';
            }
            
            // Show/hide completed at
            const completedAtItem = document.getElementById('modal-completed-at-item');
            if (task.completed_at) {
                completedAtItem.style.display = 'block';
                document.getElementById('modal-task-completed-at').textContent = new Date(task.completed_at).toLocaleString();
            } else {
                completedAtItem.style.display = 'none';
            }
            
            document.getElementById('task-modal').classList.add('active');
        }
        
        function closeTaskModal(event) {
            if (!event || event.target.id === 'task-modal' || event.target.classList.contains('modal-close')) {
                document.getElementById('task-modal').classList.remove('active');
            }
        }
        
        // Heartbeat Info Modal Functions
        function showHeartbeatInfo() {
            updateHeartbeatInfo();
            document.getElementById('heartbeat-modal').classList.add('active');
        }
        
        function closeHeartbeatModal(event) {
            if (!event || event.target.id === 'heartbeat-modal' || event.target.classList.contains('modal-close')) {
                document.getElementById('heartbeat-modal').classList.remove('active');
            }
        }
        
        async function updateHeartbeatInfo() {
            try {
                // Get heartbeat data
                const res = await fetch('/api/heartbeat');
                const data = await res.json();
                
                if (data.last_activity) {
                    const lastTime = new Date(data.last_activity);
                    const nextTime = new Date(lastTime.getTime() + (data.interval_minutes || 10) * 60 * 1000);
                    
                    document.getElementById('hb-last').textContent = lastTime.toLocaleString();
                    document.getElementById('hb-next').textContent = nextTime.toLocaleTimeString();
                }
                
                // Get coordinator stats
                const statsRes = await fetch('/api/coordinator/stats');
                if (statsRes.ok) {
                    const stats = await statsRes.json();
                    document.getElementById('hb-cycles').textContent = stats.cycle_number || 0;
                    document.getElementById('hb-tasks').textContent = stats.completed_tasks || 0;
                }
                
                // Mock activity log for now
                const activityList = document.getElementById('hb-activity-list');
                const activities = [
                    { time: new Date().toLocaleTimeString(), status: '✓', msg: 'System check passed' },
                    { time: new Date(Date.now() - 300000).toLocaleTimeString(), status: '✓', msg: 'Task processed: add-integrations' },
                    { time: new Date(Date.now() - 600000).toLocaleTimeString(), status: '✓', msg: 'Daemon cycle complete' },
                    { time: new Date(Date.now() - 900000).toLocaleTimeString(), status: '✓', msg: 'Health check passed' }
                ];
                
                activityList.innerHTML = activities.map(a => 
                    `\u003cdiv style="padding: 8px; border-bottom: 1px solid rgba(233,69,96,0.1);">` +
                    `\u003cspan style="color: #22c55e;">${a.status}\u003c/span> ` +
                    `\u003cspan style="color: #8080a0;">${a.time}\u003c/span> ` +
                    `\u003cspan style="color: #d0d0e8;">${a.msg}\u003c/span>` +
                    `\u003c/div\u003e`
                ).join('');
                
            } catch (e) {
                console.error('Error updating heartbeat info:', e);
            }
        }
        
        // Heartbeat Timer - Shows real daemon activity
        async function updateHeartbeatTimer() {
            try {
                const res = await fetch('/api/heartbeat');
                const data = await res.json();
                
                // Update interval from server
                heartbeatInterval = (data.interval_minutes || 5) * 60 * 1000;
                
                if (data.last_activity) {
                    // Use actual last daemon activity time
                    lastHeartbeat = new Date(data.last_activity).getTime();
                } else {
                    // No activity recorded yet
                    lastHeartbeat = Date.now();
                }
                
                // Update daemon status display
                const statusEl = document.getElementById('system-status');
                if (statusEl) {
                    if (data.daemon_running) {
                        statusEl.innerHTML = '<i class="fas fa-circle" style="color: #22c55e;"></i> <span>System Healthy</span>';
                    } else {
                        statusEl.innerHTML = '<i class="fas fa-circle" style="color: #ef4444;"></i> <span>Daemon Stopped</span>';
                    }
                }
            } catch (e) {
                console.log('Heartbeat fetch failed');
            }
        }
        
        function updateTimerDisplay() {
            const now = Date.now();
            const nextHeartbeat = lastHeartbeat + heartbeatInterval;
            const timeLeft = Math.max(0, nextHeartbeat - now);
            
            const minutes = Math.floor(timeLeft / 60000);
            const seconds = Math.floor((timeLeft % 60000) / 1000);
            
            const timerEl = document.getElementById('heartbeat-timer');
            if (timerEl) {
                timerEl.textContent = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
                if (timeLeft === 0) {
                    timerEl.textContent = 'DUE';
                    timerEl.style.color = '#e94560';
                } else if (minutes === 0 && seconds < 30) {
                    timerEl.style.color = '#ffc107';  // Yellow warning
                } else {
                    timerEl.style.color = '#ffffff';
                }
            }
        }
        
        function createTask() { 
            const name = prompt('Task name:');
            if (name) {
                fetch('/api/task/create', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({name, description: 'New task'})
                }).then(() => loadData());
            }
        }
        
        // Theme toggle functionality
        function initTheme() {
            const savedTheme = localStorage.getItem('theme') || 'auto';
            applyTheme(savedTheme);
        }
        
        function toggleTheme() {
            const currentTheme = document.documentElement.getAttribute('data-theme') || 'dark';
            const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
            applyTheme(newTheme);
            localStorage.setItem('theme', newTheme);
            updateThemeIcon(newTheme);
        }
        
        function applyTheme(theme) {
            if (theme === 'auto') {
                const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                document.documentElement.setAttribute('data-theme', prefersDark ? 'dark' : 'light');
                updateThemeIcon(prefersDark ? 'dark' : 'light');
            } else {
                document.documentElement.setAttribute('data-theme', theme);
                updateThemeIcon(theme);
            }
        }
        
        function updateThemeIcon(theme) {
            const btn = document.getElementById('theme-toggle');
            if (btn) {
                btn.innerHTML = theme === 'dark' 
                    ? '<i class="fas fa-moon"></i> Theme' 
                    : '<i class="fas fa-sun"></i> Theme';
            }
        }
        
        // Listen for system theme changes
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', e => {
            if (localStorage.getItem('theme') === 'auto' || !localStorage.getItem('theme')) {
                applyTheme(e.matches ? 'dark' : 'light');
            }
        });
        
        // Onboarding Functions
        function checkOnboarding() {
            const onboarded = localStorage.getItem('autonomy-onboarded');
            if (!onboarded) {
                showOnboarding();
            }
        }
        
        function showOnboarding() {
            document.getElementById('onboarding-modal').style.display = 'flex';
        }
        
        function hideOnboarding() {
            document.getElementById('onboarding-modal').style.display = 'none';
        }
        
        function activateWorkstation() {
            fetch('/api/workstation/on', {method: 'POST'})
                .then(() => {
                    alert('Workstation activated!');
                    loadData();
                });
        }
        
        function startDaemon() {
            fetch('/api/daemon/start', {method: 'POST'})
                .then(() => {
                    alert('Daemon started!');
                })
                .catch(() => {
                    // Try alternative endpoint
                    fetch('/api/heartbeat', {method: 'POST'});
                    alert('Heartbeat triggered!');
                });
        }
        
        function skipOnboarding() {
            hideOnboarding();
            localStorage.setItem('autonomy-onboarded', 'skipped');
        }
        
        function completeOnboarding() {
            hideOnboarding();
            localStorage.setItem('autonomy-onboarded', 'completed');
            alert('Welcome! Your autonomy system is ready.');
        }
        
        function resetOnboarding() {
            localStorage.removeItem('autonomy-onboarded');
            showOnboarding();
        }
        
        function workstationOn() { fetch('/api/workstation/on', {method: 'POST'}); }
        function workstationOff() { fetch('/api/workstation/off', {method: 'POST'}); }
        
        // Initialize
        initTheme();
        checkOnboarding();
        loadData();
        updateHeartbeatTimer();
        setInterval(loadData, 5000);
        setInterval(updateTimerDisplay, 1000);
        setInterval(updateHeartbeatTimer, 30000);
        
        // Register Service Worker for PWA
        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('/sw.js')
                .then(reg => console.log('Service Worker registered'))
                .catch(err => console.log('Service Worker registration failed'));
        }
    </script>
</body>
</html>'''

METRICS_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>rar-file/autonomy - Metrics</title>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-0: #050508;
            --bg-1: #0a0a0f;
            --bg-2: #12121a;
            --bg-3: #1a1a2e;
            --accent: #e94560;
            --accent-light: #ff6b8a;
            --text: #ffffff;
            --text-muted: #6b6b8a;
            --success: #00d9a3;
            --warning: #ffc107;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg-0);
            color: var(--text);
            min-height: 100vh;
            padding: 20px;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            padding: 20px;
            background: var(--bg-2);
            border-radius: 12px;
            border: 1px solid var(--bg-3);
        }
        .header h1 {
            font-size: 1.5rem;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .header h1 i {
            color: var(--accent);
        }
        .back-link {
            color: var(--text-muted);
            text-decoration: none;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .back-link:hover {
            color: var(--accent);
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: var(--bg-2);
            border-radius: 12px;
            padding: 20px;
            border: 1px solid var(--bg-3);
        }
        .card h3 {
            font-size: 0.9rem;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 15px;
        }
        .stat-value {
            font-size: 2.5rem;
            font-weight: 700;
            color: var(--accent);
        }
        .stat-label {
            color: var(--text-muted);
            font-size: 0.9rem;
        }
        .chart-container {
            position: relative;
            height: 250px;
        }
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 500;
        }
        .status-badge.running {
            background: rgba(0, 217, 163, 0.2);
            color: var(--success);
        }
        .status-badge.stopped {
            background: rgba(233, 69, 96, 0.2);
            color: var(--accent);
        }
        .activity-log {
            max-height: 300px;
            overflow-y: auto;
        }
        .activity-item {
            padding: 10px;
            border-bottom: 1px solid var(--bg-3);
            font-size: 0.9rem;
            display: flex;
            justify-content: space-between;
        }
        .activity-item:last-child {
            border-bottom: none;
        }
        .timestamp {
            color: var(--text-muted);
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.8rem;
        }
        .refresh-btn {
            background: var(--accent);
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .refresh-btn:hover {
            background: var(--accent-light);
        }
    </style>
</head>
<body>
    <div class="header">
        <h1><i class="fas fa-chart-line"></i> Metrics Dashboard</h1>
        <div style="display: flex; gap: 15px; align-items: center;">
            <span id="daemonStatus" class="status-badge stopped">
                <i class="fas fa-circle"></i> <span>Checking...</span>
            </span>
            <button class="refresh-btn" onclick="loadMetrics()">
                <i class="fas fa-sync"></i> Refresh
            </button>
            <a href="/" class="back-link">
                <i class="fas fa-arrow-left"></i> Back to Dashboard
            </a>
        </div>
    </div>

    <div class="grid">
        <div class="card">
            <h3>Total Tasks</h3>
            <div class="stat-value" id="totalTasks">-</div>
            <div class="stat-label">tasks in system</div>
        </div>
        <div class="card">
            <h3>Completed</h3>
            <div class="stat-value" id="completedTasks" style="color: var(--success)">-</div>
            <div class="stat-label">tasks finished</div>
        </div>
        <div class="card">
            <h3>Pending</h3>
            <div class="stat-value" id="pendingTasks">-</div>
            <div class="stat-label">tasks waiting</div>
        </div>
        <div class="card">
            <h3>Token Usage</h3>
            <div class="stat-value" id="tokenUsage" style="color: var(--warning)">-</div>
            <div class="stat-label">tokens today</div>
        </div>
    </div>

    <div class="grid">
        <div class="card" style="grid-column: span 2;">
            <h3>Task Distribution</h3>
            <div class="chart-container">
                <canvas id="taskChart"></canvas>
            </div>
        </div>
        <div class="card" style="grid-column: span 1;">
            <h3>Recent Activity</h3>
            <div class="activity-log" id="activityLog">
                <div class="activity-item">Loading...</div>
            </div>
        </div>
    </div>

    <script>
        let taskChart = null;

        async function loadMetrics() {
            try {
                const response = await fetch('/api/metrics');
                const data = await response.json();

                // Update stats
                document.getElementById('totalTasks').textContent = data.tasks.total;
                document.getElementById('completedTasks').textContent = data.tasks.completed;
                document.getElementById('pendingTasks').textContent = data.tasks.pending;
                document.getElementById('tokenUsage').textContent = data.token_usage.toLocaleString();

                // Update daemon status
                const statusBadge = document.getElementById('daemonStatus');
                if (data.daemon_running) {
                    statusBadge.className = 'status-badge running';
                    statusBadge.innerHTML = '<i class="fas fa-circle"></i> <span>Daemon Running</span>';
                } else {
                    statusBadge.className = 'status-badge stopped';
                    statusBadge.innerHTML = '<i class="fas fa-circle"></i> <span>Daemon Stopped</span>';
                }

                // Update chart
                updateChart(data.tasks);

                // Update activity log
                updateActivityLog(data.activity);
            } catch (error) {
                console.error('Failed to load metrics:', error);
            }
        }

        function updateChart(tasks) {
            const ctx = document.getElementById('taskChart').getContext('2d');
            
            if (taskChart) {
                taskChart.destroy();
            }

            taskChart = new Chart(ctx, {
                type: 'doughnut',
                data: {
                    labels: ['Pending', 'Completed', 'Processing', 'Needs Attention'],
                    datasets: [{
                        data: [
                            tasks.pending,
                            tasks.completed,
                            tasks.ai_processing,
                            tasks.needs_ai_attention
                        ],
                        backgroundColor: [
                            '#6b6b8a',
                            '#00d9a3',
                            '#e94560',
                            '#ffc107'
                        ],
                        borderWidth: 0
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                color: '#ffffff',
                                padding: 20
                            }
                        }
                    }
                }
            });
        }

        function updateActivityLog(activity) {
            const logContainer = document.getElementById('activityLog');
            logContainer.innerHTML = '';

            if (activity.length === 0) {
                logContainer.innerHTML = '<div class="activity-item">No recent activity</div>';
                return;
            }

            activity.reverse().forEach(item => {
                const div = document.createElement('div');
                div.className = 'activity-item';
                const time = new Date(item.timestamp).toLocaleTimeString();
                const action = item.action || 'Unknown';
                div.innerHTML = `<span>${action}</span><span class="timestamp">${time}</span>`;
                logContainer.appendChild(div);
            });
        }

        // Load on page load
        loadMetrics();
        
        // Auto-refresh every 30 seconds
        setInterval(loadMetrics, 30000);
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
        elif self.path == "/metrics":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(METRICS_TEMPLATE.encode())
        elif self.path == "/manifest.json":
            self.serve_manifest()
        elif self.path == "/sw.js":
            self.serve_service_worker()
        elif self.path == "/api/tasks":
            self.serve_tasks()
        elif self.path == "/api/metrics":
            self.serve_metrics()
        elif self.path.startswith("/api/task/"):
            task_name = self.path.split("/")[-1]
            self.serve_task(task_name)
        elif self.path == "/api/status":
            self.serve_status()
        elif self.path == "/api/heartbeat":
            self.serve_heartbeat()
        elif self.path == "/api/coordinator/stats":
            self.serve_coordinator_stats()
        else:
            self.send_error(404)
    
    def do_POST(self):
        if self.path == "/api/workstation/on":
            self.run_cmd("on")
        elif self.path == "/api/workstation/off":
            self.run_cmd("off")
        elif self.path == "/api/task/create":
            self.create_task()
        elif self.path.startswith("/api/task/") and self.path.endswith("/complete"):
            task_name = self.path.split("/")[-2]
            self.complete_task(task_name)
        elif self.path.startswith("/api/task/") and self.path.endswith("/update"):
            task_name = self.path.split("/")[-2]
            self.update_task(task_name)
        elif self.path == "/api/schedule/add":
            self.add_schedule()
        elif self.path == "/api/schedule/remove":
            self.remove_schedule()
        elif self.path == "/api/trigger":
            self.trigger_heartbeat()
        elif self.path == "/api/daemon":
            self.control_daemon()
        else:
            self.send_error(404)
    
    def do_DELETE(self):
        if self.path.startswith("/api/task/"):
            task_name = self.path.split("/")[-1]
            self.delete_task(task_name)
        else:
            self.send_error(404)
    
    def serve_tasks(self):
        try:
            tasks = []
            if os.path.exists(TASKS_DIR):
                for f in os.listdir(TASKS_DIR):
                    if f.endswith(".json"):
                        try:
                            with open(os.path.join(TASKS_DIR, f), 'r') as fp:
                                content = fp.read()
                                content = ''.join(c for c in content if ord(c) >= 32 or c in '\n\r\t')
                                tasks.append(json.loads(content))
                        except: pass
            self.send_json(tasks)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)
    
    def serve_task(self, task_name):
        try:
            task_file = os.path.join(TASKS_DIR, f"{task_name}.json")
            if os.path.exists(task_file):
                with open(task_file, 'r') as f:
                    content = f.read()
                    content = ''.join(c for c in content if ord(c) >= 32 or c in '\n\r\t')
                    task = json.loads(content)
                    self.send_json(task)
            else:
                self.send_json({"error": "Task not found"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)
    
    def serve_status(self):
        try:
            active = False
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE) as f:
                    config = json.load(f)
                    active = config.get("workstation", {}).get("active", False)
            self.send_json({"active": active})
        except:
            self.send_json({"active": False})
    
    def serve_heartbeat(self):
        try:
            last_activity = None
            
            # First check the heartbeat activity log (most accurate for daemon)
            heartbeat_log = f"{LOGS_DIR}/heartbeat-activity.jsonl"
            if os.path.exists(heartbeat_log):
                try:
                    with open(heartbeat_log, 'r') as f:
                        lines = f.readlines()
                        # Find last daemon entry
                        for line in reversed(lines):
                            try:
                                data = json.loads(line.strip())
                                if data.get('status') == 'daemon':
                                    last_activity = data.get("timestamp")
                                    break
                            except:
                                continue
                except:
                    pass
            
            # Fall back to state file
            if not last_activity:
                state_file = f"{AUTONOMY_DIR}/state/last-heartbeat.json"
                if os.path.exists(state_file):
                    try:
                        with open(state_file, 'r') as f:
                            state_data = json.load(f)
                            last_activity = state_data.get("timestamp")
                    except:
                        pass
            
            # Fall back to agentic log
            if not last_activity:
                log_file = f"{LOGS_DIR}/agentic.jsonl"
                if os.path.exists(log_file):
                    with open(log_file, 'r') as f:
                        lines = f.readlines()
                        if lines:
                            try:
                                data = json.loads(lines[-1].strip())
                                last_activity = data.get("timestamp")
                            except: pass
            
            # Get interval from config
            interval_minutes = 5
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE) as f:
                    config = json.load(f)
                    interval_minutes = config.get("global_config", {}).get("base_interval_minutes", 5)
            
            # Check if daemon is running
            daemon_running = os.path.exists(f"{AUTONOMY_DIR}/state/heartbeat-daemon.pid")
            
            self.send_json({
                "last_activity": last_activity,
                "interval_minutes": interval_minutes,
                "daemon_running": daemon_running
            })
        except Exception as e:
            self.send_json({"error": str(e)}, 500)
    
    def serve_coordinator_stats(self):
        """Serve coordinator statistics"""
        try:
            stats = {
                "daemon_running": os.path.exists(f"{AUTONOMY_DIR}/state/heartbeat-daemon.pid"),
                "timestamp": datetime.now().isoformat()
            }
            
            # Add cycle count if available
            cycle_file = f"{AUTONOMY_DIR}/state/cycle_count"
            if os.path.exists(cycle_file):
                try:
                    with open(cycle_file, 'r') as f:
                        stats["cycle_count"] = int(f.read().strip())
                except:
                    stats["cycle_count"] = 0
            
            self.send_json(stats)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)
    
    def run_cmd(self, cmd):
        try:
            subprocess.run(["bash", f"{AUTONOMY_DIR}/autonomy", cmd], 
                         capture_output=True, timeout=10)
            self.send_json({"success": True})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def create_task(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len))
            name = body.get("name", "task")
            desc = body.get("description", "No description")
            
            task_file = os.path.join(TASKS_DIR, f"{name}.json")
            task_data = {
                "name": name,
                "description": desc,
                "status": "pending",
                "priority": "normal",
                "created": datetime.now().isoformat(),
                "completed": False
            }
            
            with open(task_file, 'w') as f:
                json.dump(task_data, f, indent=2)
            
            self.send_json({"success": True})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def trigger_heartbeat(self):
        try:
            # Log that a manual heartbeat was triggered
            log_entry = {
                "timestamp": datetime.now().isoformat(),
                "action": "manual_heartbeat_triggered",
                "details": {"source": "web_ui"}
            }
            
            log_file = f"{LOGS_DIR}/agentic.jsonl"
            with open(log_file, 'a') as f:
                f.write(json.dumps(log_entry) + '\n')
            
            # Try to run a task if there are pending ones
            pending_tasks = [f for f in os.listdir(TASKS_DIR) if f.endswith('.json')]
            if pending_tasks:
                # Pick first pending task
                for task_file in pending_tasks:
                    try:
                        with open(os.path.join(TASKS_DIR, task_file), 'r') as f:
                            task = json.load(f)
                        if not task.get('completed') and task.get('status') != 'completed':
                            # Mark as in_progress
                            task['status'] = 'in_progress'
                            with open(os.path.join(TASKS_DIR, task_file), 'w') as f:
                                json.dump(task, f, indent=2)
                            
                            self.send_json({
                                "success": True, 
                                "message": f"Started working on: {task['name']}",
                                "task": task['name']
                            })
                            return
                    except:
                        continue
            
            self.send_json({"success": True, "message": "Heartbeat triggered - no pending tasks"})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def complete_task(self, task_name):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            verification = body.get("verification", "Task completed via API")
            
            task_file = os.path.join(TASKS_DIR, f"{task_name}.json")
            if not os.path.exists(task_file):
                self.send_json({"error": "Task not found"}, 404)
                return
            
            with open(task_file, 'r') as f:
                task = json.load(f)
            
            task['status'] = 'completed'
            task['completed'] = True
            task['completed_at'] = datetime.now().isoformat()
            task['verification'] = verification
            task['attempts'] = task.get('attempts', 0) + 1
            
            with open(task_file, 'w') as f:
                json.dump(task, f, indent=2)
            
            # Clear needs_attention if this was the flagged task
            if os.path.exists(f"{AUTONOMY_DIR}/state/needs_attention.json"):
                with open(f"{AUTONOMY_DIR}/state/needs_attention.json", 'r') as f:
                    attention = json.load(f)
                if attention.get('task_name') == task_name:
                    os.remove(f"{AUTONOMY_DIR}/state/needs_attention.json")
            
            self.send_json({"success": True, "message": f"Task {task_name} marked complete"})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def update_task(self, task_name):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            
            task_file = os.path.join(TASKS_DIR, f"{task_name}.json")
            if not os.path.exists(task_file):
                self.send_json({"error": "Task not found"}, 404)
                return
            
            with open(task_file, 'r') as f:
                task = json.load(f)
            
            # Update allowed fields
            for field in ['description', 'priority', 'status']:
                if field in body:
                    task[field] = body[field]
            
            with open(task_file, 'w') as f:
                json.dump(task, f, indent=2)
            
            self.send_json({"success": True, "message": f"Task {task_name} updated"})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def delete_task(self, task_name):
        try:
            task_file = os.path.join(TASKS_DIR, f"{task_name}.json")
            if not os.path.exists(task_file):
                self.send_json({"error": "Task not found"}, 404)
                return
            
            os.remove(task_file)
            self.send_json({"success": True, "message": f"Task {task_name} deleted"})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def add_schedule(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            interval = body.get("interval", "30m")
            task = body.get("task", "")
            
            subprocess.run(["bash", f"{AUTONOMY_DIR}/autonomy", "schedule", "add", interval, task], 
                         capture_output=True, timeout=10)
            self.send_json({"success": True, "message": f"Schedule added: {task} every {interval}"})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def remove_schedule(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            index = body.get("index", "0")
            
            subprocess.run(["bash", f"{AUTONOMY_DIR}/autonomy", "schedule", "remove", str(index)], 
                         capture_output=True, timeout=10)
            self.send_json({"success": True, "message": f"Schedule removed"})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)
    
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def serve_metrics(self):
        """Serve real-time metrics data"""
        try:
            # Count tasks by status
            tasks = {"pending": 0, "completed": 0, "ai_processing": 0, "needs_ai_attention": 0, "total": 0}
            for f in os.listdir(TASKS_DIR):
                if f.endswith('.json'):
                    try:
                        with open(os.path.join(TASKS_DIR, f), 'r') as tf:
                            task = json.load(tf)
                        tasks["total"] += 1
                        status = task.get('status', 'pending')
                        if status in tasks:
                            tasks[status] += 1
                        elif task.get('completed'):
                            tasks["completed"] += 1
                        else:
                            tasks["pending"] += 1
                    except:
                        pass
            
            # Get recent activity from logs
            activity = []
            log_file = f"{LOGS_DIR}/agentic.jsonl"
            if os.path.exists(log_file):
                with open(log_file, 'r') as f:
                    lines = f.readlines()[-50:]  # Last 50 entries
                for line in lines:
                    try:
                        entry = json.loads(line.strip())
                        activity.append(entry)
                    except:
                        pass
            
            # Get token usage estimate
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
            token_usage = config.get('workstation', {}).get('token_usage_today', 0)
            
            # Check daemon status
            daemon_running = os.path.exists(f"{AUTONOMY_DIR}/state/heartbeat-daemon.pid")
            
            self.send_json({
                "tasks": tasks,
                "activity": activity[-20:],  # Last 20 entries
                "token_usage": token_usage,
                "daemon_running": daemon_running,
                "timestamp": datetime.now().isoformat()
            })
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def serve_manifest(self):
        """Serve Web App Manifest for PWA"""
        manifest = {
            "name": "rar-file/autonomy",
            "short_name": "Autonomy",
            "description": "Agentic Self-Improvement Dashboard",
            "start_url": "/",
            "display": "standalone",
            "background_color": "#050508",
            "theme_color": "#e94560",
            "orientation": "portrait-primary",
            "icons": [
                {
                    "src": "/icon-192.png",
                    "sizes": "192x192",
                    "type": "image/png"
                },
                {
                    "src": "/icon-512.png",
                    "sizes": "512x512",
                    "type": "image/png"
                }
            ]
        }
        self.send_json(manifest)

    def serve_service_worker(self):
        """Serve Service Worker for PWA offline support"""
        sw_js = '''
const CACHE_NAME = 'autonomy-v1';
const urlsToCache = [
    '/',
    '/manifest.json'
];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(urlsToCache))
    );
});

self.addEventListener('fetch', event => {
    event.respondWith(
        caches.match(event.request)
            .then(response => {
                if (response) {
                    return response;
                }
                return fetch(event.request);
            })
    );
});
'''
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript")
        self.send_header("Cache-Control", "max-age=86400")
        self.end_headers()
        self.wfile.write(sw_js.encode())

if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", 8767))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"rar-file/autonomy dashboard at http://localhost:{port}")
    server.serve_forever()
