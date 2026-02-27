#!/usr/bin/env python3
"""rar-file/autonomy Dashboard with Heartbeat Timer"""

import json
import os
import signal
import subprocess
import sys
import threading
import html as html_module
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from datetime import datetime, timedelta

AUTONOMY_DIR = os.environ.get("AUTONOMY_DIR", os.path.dirname(os.path.abspath(__file__)))
CONFIG_FILE = f"{AUTONOMY_DIR}/config.json"
TASKS_DIR = f"{AUTONOMY_DIR}/tasks"
LOGS_DIR = f"{AUTONOMY_DIR}/logs"


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Multi-threaded HTTP server — prevents single-request hangs from blocking."""
    daemon_threads = True
    allow_reuse_address = True

HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover">
    <meta name="theme-color" content="#e94560">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <link rel="manifest" href="/manifest.json">
    <link rel="apple-touch-icon" href="/icon-192.png">
    <title>rar-file/autonomy</title>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
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
        
        /* AI Activity Box Styles */
        .ai-activity-box {
            background: linear-gradient(135deg, rgba(59,130,246,0.15), rgba(59,130,246,0.05));
            border: 1px solid rgba(59,130,246,0.3);
            border-radius: 12px;
            padding: 16px 20px;
            display: flex;
            align-items: flex-start;
            gap: 16px;
            margin-bottom: 12px;
            animation: aiBoxPulse 2s ease-in-out infinite;
        }
        
        @keyframes aiBoxPulse {
            0%, 100% { box-shadow: 0 0 0 0 rgba(59,130,246,0.4); }
            50% { box-shadow: 0 0 20px 5px rgba(59,130,246,0.2); }
        }
        
        .ai-activity-indicator {
            position: relative;
            width: 40px;
            height: 40px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .ai-activity-indicator i {
            font-size: 20px;
            color: #3b82f6;
            z-index: 2;
        }
        
        .ai-pulse {
            position: absolute;
            width: 100%;
            height: 100%;
            border-radius: 50%;
            background: rgba(59,130,246,0.3);
            animation: aiPulse 1.5s ease-out infinite;
        }
        
        @keyframes aiPulse {
            0% { transform: scale(0.5); opacity: 1; }
            100% { transform: scale(1.5); opacity: 0; }
        }
        
        .ai-activity-content {
            flex: 1;
            min-width: 0;
        }
        
        .ai-activity-label {
            font-size: 11px;
            color: #60a5fa;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 4px;
        }
        
        .ai-activity-task {
            font-size: 15px;
            font-weight: 600;
            color: #ffffff;
            margin-bottom: 8px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        .ai-activity-progress {
            height: 4px;
            background: rgba(59,130,246,0.2);
            border-radius: 2px;
            overflow: hidden;
            margin-bottom: 8px;
        }
        
        .ai-progress-bar {
            height: 100%;
            background: linear-gradient(90deg, #3b82f6, #60a5fa);
            border-radius: 2px;
            transition: width 0.5s ease;
            width: 0%;
        }
        
        .ai-activity-logs {
            font-size: 12px;
            color: #93c5fd;
            font-family: 'JetBrains Mono', monospace;
            max-height: 60px;
            overflow-y: auto;
        }
        
        .ai-activity-logs .log-entry {
            margin: 2px 0;
            padding-left: 12px;
            position: relative;
        }
        
        .ai-activity-logs .log-entry::before {
            content: '>';
            position: absolute;
            left: 0;
            color: #3b82f6;
        }
        
        @media (max-width: 768px) {
            .ai-activity-box {
                width: 100%;
                padding: 12px 16px;
            }
            
            .ai-activity-indicator {
                width: 32px;
                height: 32px;
            }
            
            .ai-activity-indicator i {
                font-size: 16px;
            }
            
            .ai-activity-task {
                font-size: 13px;
            }
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
        /* ============================================
           MOBILE RESPONSIVE STYLES
           ============================================ */
        
        /* Metrics chart grid - base styles (before media queries) */
        .metrics-chart-grid {
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 20px;
        }
        
        .metrics-chart-grid .card {
            min-width: 0;
            overflow: hidden;
        }
        
        .metrics-chart-wrap {
            position: relative;
            height: 280px;
            max-width: 100%;
            overflow: hidden;
        }
        
        /* Tablet breakpoint */
        @media (max-width: 1024px) {
            .app { grid-template-columns: 1fr; }
            .sidebar { display: none; }
        }
        
        /* Phone breakpoint - comprehensive mobile optimization */
        @media (max-width: 768px) {
            /* Prevent horizontal overflow everywhere */
            html, body {
                overflow-x: hidden;
                width: 100%;
                max-width: 100vw;
            }
            
            /* Layout adjustments */
            body {
                font-size: 15px; /* Prevent iOS zoom, balanced readability */
            }
            
            .app {
                display: flex;
                flex-direction: column;
                min-height: 100vh;
                min-height: 100dvh; /* Dynamic viewport for mobile browsers */
                padding-bottom: 72px; /* Space for bottom nav */
                overflow-x: hidden;
                width: 100%;
            }
            
            .main {
                padding: 16px;
                max-height: none;
                overflow-y: visible;
                overflow-x: hidden;
                width: 100%;
                box-sizing: border-box;
            }
            
            /* Header mobile optimization */
            .header {
                flex-direction: column;
                align-items: stretch;
                gap: 12px;
                margin-bottom: 20px;
                padding-bottom: 12px;
            }
            
            .header-title h2 {
                font-size: 22px;
                line-height: 1.2;
            }
            
            .header-title p {
                font-size: 13px;
            }
            
            /* Stats grid - 2 columns on phone for balance */
            .stats-grid {
                grid-template-columns: repeat(2, 1fr);
                gap: 10px;
                margin-bottom: 20px;
            }
            
            .stat-card {
                padding: 14px;
                display: flex;
                flex-direction: column;
                align-items: flex-start;
                gap: 4px;
            }
            
            .stat-card::before {
                left: 0;
                width: 3px;
                height: 100%;
            }
            
            .stat-value {
                font-size: 24px;
                margin-bottom: 0;
            }
            
            .stat-label {
                font-size: 11px;
            }
            
            /* Cards mobile optimization */
            .card {
                padding: 14px;
                margin-bottom: 14px;
                border-radius: 12px;
            }
            
            .card h3 {
                font-size: 15px;
                margin-bottom: 14px;
            }
            
            /* Task items mobile */
            .task-item {
                padding: 14px;
            }
            
            .task-header {
                flex-direction: row;
                flex-wrap: wrap;
                align-items: center;
                gap: 8px;
                margin-bottom: 8px;
            }
            
            .task-name {
                font-size: 14px;
                word-break: break-word;
                flex: 1;
                min-width: 0;
            }
            
            .task-status {
                flex-shrink: 0;
                font-size: 10px;
                padding: 3px 8px;
            }
            
            .task-desc {
                font-size: 13px;
                line-height: 1.5;
                display: -webkit-box;
                -webkit-line-clamp: 3;
                -webkit-box-orient: vertical;
                overflow: hidden;
            }
            
            .task-meta {
                flex-wrap: wrap;
                gap: 10px;
                font-size: 11px;
            }
            
            /* Button mobile sizing */
            .btn {
                padding: 12px 16px;
                font-size: 14px;
                min-height: 44px; /* Touch-friendly */
                justify-content: center;
                white-space: nowrap;
            }
            
            /* Header action buttons - wrap nicely */
            .header > div[style*="flex-direction: column"] {
                width: 100%;
            }
            
            .header > div[style*="gap: 12px"],
            .header > div[style*="gap: 8px"] {
                display: flex;
                flex-wrap: wrap;
                gap: 8px;
                width: 100%;
            }
            
            .header > div[style*="gap: 12px"] .btn,
            .header > div[style*="gap: 8px"] .btn {
                flex: 1 1 auto;
                min-width: 100px;
                max-width: calc(50% - 4px);
                font-size: 13px;
                padding: 10px 12px;
            }
            
            /* Heartbeat box mobile */
            .heartbeat-box {
                padding: 8px 14px;
                width: 100%;
                justify-content: center;
                box-sizing: border-box;
            }
            
            .heartbeat-timer {
                font-size: 18px;
            }
            
            .system-status-box {
                width: 100%;
                justify-content: center;
                padding: 8px 12px;
                box-sizing: border-box;
            }
            
            /* Modal mobile optimization — sheet style, not full screen */
            .modal {
                width: 100%;
                max-width: 100%;
                height: 90vh;
                height: 90dvh;
                max-height: 90vh;
                max-height: 90dvh;
                border-radius: 16px 16px 0 0;
                display: flex;
                flex-direction: column;
                position: fixed;
                bottom: 0;
                left: 0;
                right: 0;
                top: auto;
                transform: none;
                animation: slideUp 0.3s ease;
            }
            
            @keyframes slideUp {
                from { transform: translateY(100%); }
                to { transform: translateY(0); }
            }
            
            .modal-header {
                padding: 16px 20px;
                flex-shrink: 0;
                position: relative;
            }
            
            /* Drag handle for sheet-style modal */
            .modal-header::before {
                content: '';
                display: block;
                width: 36px;
                height: 4px;
                background: rgba(255,255,255,0.2);
                border-radius: 2px;
                margin: 0 auto 12px;
            }
            
            .modal-title {
                font-size: 17px;
                word-break: break-word;
                padding-right: 40px;
                line-height: 1.3;
            }
            
            .modal-close {
                position: absolute;
                top: 16px;
                right: 16px;
                width: 36px;
                height: 36px;
                display: flex;
                align-items: center;
                justify-content: center;
                font-size: 20px;
                z-index: 10;
            }
            
            .modal-body {
                padding: 16px 20px 24px;
                flex: 1;
                overflow-y: auto;
                -webkit-overflow-scrolling: touch;
                max-height: none;
            }
            
            .modal-section {
                margin-bottom: 18px;
            }
            
            .modal-section-title {
                font-size: 12px;
            }
            
            .modal-description {
                font-size: 14px;
                line-height: 1.6;
            }
            
            .modal-meta-grid {
                grid-template-columns: repeat(2, 1fr);
                gap: 10px;
            }
            
            .modal-meta-item {
                padding: 10px;
            }
            
            .modal-meta-label {
                font-size: 10px;
            }
            
            .modal-meta-value {
                font-size: 13px;
            }
            
            .modal-verification {
                padding: 14px;
                font-size: 13px;
            }
            
            /* Bottom navigation bar */
            .mobile-nav {
                display: flex;
                position: fixed;
                bottom: 0;
                left: 0;
                right: 0;
                background: linear-gradient(180deg, var(--bg-1) 0%, var(--bg-2) 100%);
                border-top: 1px solid rgba(233,69,96,0.2);
                padding: 6px 8px 10px;
                z-index: 100;
                justify-content: space-around;
                box-shadow: 0 -4px 20px rgba(0,0,0,0.3);
            }
            
            .mobile-nav-item {
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 3px;
                padding: 6px 4px;
                border-radius: 10px;
                cursor: pointer;
                color: #8080a0;
                font-size: 10px;
                font-weight: 500;
                transition: all 0.2s;
                flex: 1;
                min-width: 0;
                max-width: none;
                text-align: center;
                overflow: hidden;
                text-overflow: ellipsis;
                white-space: nowrap;
            }
            
            .mobile-nav-item i {
                font-size: 18px;
                color: #ff6b8a;
                transition: all 0.2s;
            }
            
            .mobile-nav-item.active {
                color: #ffffff;
                background: linear-gradient(135deg, rgba(233, 69, 96, 0.25), rgba(233, 69, 96, 0.1));
            }
            
            .mobile-nav-item.active i {
                color: #ffffff;
                transform: scale(1.1);
            }
            
            /* Hide desktop sidebar */
            .sidebar {
                display: none;
            }
            
            /* Onboarding - full page on mobile instead of modal */
            .onboarding-overlay {
                align-items: stretch;
                justify-content: stretch;
                background: var(--bg-0);
                backdrop-filter: none;
                overflow-y: auto;
                -webkit-overflow-scrolling: touch;
            }
            
            .onboarding-modal-content {
                padding: 24px 20px 40px;
                margin: 0;
                max-height: none;
                width: 100%;
                height: auto;
                min-height: 100%;
                border-radius: 0;
                border: none;
                box-shadow: none;
                overflow-y: visible;
                background: var(--bg-0);
            }
            
            .onboarding-modal-content h2 {
                font-size: 22px;
            }
            
            .feature-grid {
                grid-template-columns: 1fr;
                gap: 8px;
            }
            
            .feature-item {
                padding: 12px;
            }
            
            .onboarding-step {
                padding: 14px;
            }
            
            .onboarding-actions {
                flex-direction: column;
                gap: 8px;
                padding-bottom: 20px;
            }
            
            .onboarding-actions .btn {
                width: 100%;
            }
            
            /* Loading spinner mobile */
            .loading {
                padding: 40px;
            }
            
            /* Pulse animation for mobile */
            @keyframes pulse-mobile {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.7; }
            }
            
            /* Touch feedback */
            .task-item:active,
            .mobile-nav-item:active,
            .btn:active {
                transform: scale(0.98);
                opacity: 0.9;
            }
            
            /* Prevent select/textarea from being too wide */
            input, textarea, select {
                max-width: 100%;
                box-sizing: border-box;
            }
            
            /* Fix any inline-style divs that could overflow */
            div[style] {
                max-width: 100%;
                box-sizing: border-box;
            }
            
            /* Metrics page grid stacking on mobile */
            #page-metrics {
                overflow-x: hidden;
            }
            
            #page-metrics .stats-grid {
                grid-template-columns: repeat(2, 1fr) !important;
            }
            
            .metrics-chart-grid {
                display: grid !important;
                grid-template-columns: 1fr !important;
                gap: 16px !important;
                overflow: hidden;
            }
            
            .metrics-chart-wrap {
                height: 220px !important;
                max-width: 100% !important;
                overflow: hidden !important;
            }
            
            #page-metrics .card {
                min-width: 0;
                overflow: hidden;
            }
            
            #page-metrics canvas {
                max-width: 100% !important;
                width: 100% !important;
                height: auto !important;
            }
        }
        
        /* Extra small phones (< 380px like iPhone SE, Galaxy Fold) */
        @media (max-width: 380px) {
            .main {
                padding: 10px;
            }
            
            .header-title h2 {
                font-size: 18px;
            }
            
            .stats-grid {
                grid-template-columns: 1fr 1fr;
                gap: 8px;
            }
            
            .stat-value {
                font-size: 20px;
            }
            
            .stat-label {
                font-size: 10px;
            }
            
            .stat-card {
                padding: 10px;
            }
            
            .mobile-nav {
                padding: 4px 4px 8px;
            }
            
            .mobile-nav-item {
                padding: 4px 2px;
                font-size: 9px;
                gap: 2px;
            }
            
            .mobile-nav-item i {
                font-size: 16px;
            }
            
            .btn {
                padding: 10px 12px;
                font-size: 13px;
                min-height: 40px;
            }
            
            .card {
                padding: 12px;
            }
            
            .task-item {
                padding: 12px;
            }
            
            .task-name {
                font-size: 13px;
            }
            
            .task-desc {
                font-size: 12px;
            }
            
            .modal {
                height: 92vh;
                height: 92dvh;
            }
            
            .modal-title {
                font-size: 16px;
            }
            
            .modal-body {
                padding: 14px 16px 20px;
            }
            
            .modal-meta-grid {
                grid-template-columns: 1fr;
                gap: 8px;
            }
            
            .header > div[style*="gap: 12px"] .btn,
            .header > div[style*="gap: 8px"] .btn {
                min-width: 0;
                font-size: 12px;
                padding: 8px 10px;
            }
            
            /* Header buttons - wrap and shrink on mobile */
            .header {
                flex-direction: column !important;
                align-items: stretch !important;
            }
            
            .header > div[style] {
                align-items: stretch !important;
            }
            
            .header-actions {
                display: flex !important;
                flex-wrap: wrap !important;
                gap: 6px !important;
                width: 100%;
            }
            
            .header-actions .btn {
                flex: 1 1 calc(50% - 6px);
                min-width: 0;
                font-size: 12px;
                padding: 8px 10px;
                white-space: nowrap;
                justify-content: center;
            }
            
            .header-actions .btn-label {
                overflow: hidden;
                text-overflow: ellipsis;
            }
        }
        
        /* Medium phones (381-480px) - slight adjustments */
        @media (min-width: 381px) and (max-width: 480px) {
            .stat-value {
                font-size: 22px;
            }
            
            .modal-meta-grid {
                grid-template-columns: repeat(2, 1fr);
                gap: 8px;
            }
        }
        
        /* Hide mobile nav on desktop */
        .mobile-nav {
            display: none;
        }
        
        @media (max-width: 768px) {
            .mobile-nav {
                display: flex;
            }
        }
        
        /* Safe area support for notched phones */
        @supports (padding: max(0px)) {
            @media (max-width: 768px) {
                .mobile-nav {
                    padding-bottom: max(10px, env(safe-area-inset-bottom));
                }
                
                .main {
                    padding-left: max(16px, env(safe-area-inset-left));
                    padding-right: max(16px, env(safe-area-inset-right));
                }
                
                .modal {
                    padding-bottom: env(safe-area-inset-bottom);
                }
            }
        }
        @media (max-width: 768px) and (orientation: landscape) {
            .mobile-nav {
                position: relative;
                bottom: auto;
                left: auto;
                right: auto;
                border-top: none;
                border-bottom: 1px solid rgba(233,69,96,0.2);
                padding: 4px 8px;
            }
            
            .app {
                padding-bottom: 0;
            }
            
            .modal {
                height: 100vh;
                height: 100dvh;
                border-radius: 0;
            }
        }
        
        /* Onboarding Modal - Fixed */
        .onboarding-overlay {
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.95);
            z-index: 10000;
            display: none;
            align-items: center;
            justify-content: center;
            backdrop-filter: blur(8px);
            pointer-events: none;
        }
        
        .onboarding-overlay.active {
            display: flex;
            pointer-events: auto;
        }
        
        .onboarding-modal-content {
            background: var(--bg-2);
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            width: 90%;
            max-height: 90vh;
            overflow-y: auto;
            border: 1px solid var(--bg-3);
            box-shadow: 0 25px 50px rgba(0,0,0,0.5);
            animation: slideIn 0.3s ease;
        }
        
        @keyframes slideIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        .onboarding-modal-content h2 {
            font-size: 28px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .onboarding-modal-content h2 i {
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
    <div id="onboarding-modal" class="onboarding-overlay">
        <div class="onboarding-modal-content">
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
                <div class="nav-item" onclick="showPage('memory', this); loadMemory();"><i class="fas fa-brain"></i> Memory</div>
                <div class="nav-item" onclick="showPage('terminal', this); loadTerminalHistory();"><i class="fas fa-terminal"></i> Terminal</div>
                <div class="nav-item" onclick="showPage('schedules', this)"><i class="fas fa-clock"></i> Schedules</div>
                <div class="nav-item" onclick="showPage('journal', this); loadJournalData();"><i class="fas fa-book"></i> Journal</div>
                <div class="nav-item" onclick="showPage('metrics', this); loadMetricsData();"><i class="fas fa-chart-line"></i> Metrics</div>
                <div class="nav-item" onclick="showPage('settings', this); loadSettings();"><i class="fas fa-cog"></i> Settings</div>
            </div>
        </aside>
        
        <main class="main">
            <!-- Dashboard Page -->
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
                        <!-- AI Activity Box -->
                        <div id="ai-activity-box" class="ai-activity-box" style="display: none;">
                            <div class="ai-activity-indicator">
                                <div class="ai-pulse"></div>
                                <i class="fas fa-robot"></i>
                            </div>
                            <div class="ai-activity-content">
                                <div class="ai-activity-label">AI Processing</div>
                                <div class="ai-activity-task" id="ai-current-task">Starting...</div>
                                <div class="ai-activity-progress">
                                    <div class="ai-progress-bar" id="ai-progress-bar"></div>
                                </div>
                                <div class="ai-activity-logs" id="ai-activity-logs"></div>
                            </div>
                        </div>
                        <div class="system-status-box" id="system-status">
                            <i class="fas fa-circle" style="color: #22c55e;"></i>
                            <span>System Healthy</span>
                        </div>
                        <div class="header-actions" style="display: flex; gap: 12px; flex-wrap: wrap;">
                            <button class="btn btn-secondary" onclick="showHeartbeatInfo()">
                                <i class="fas fa-heartbeat"></i> <span class="btn-label">Heartbeat</span>
                            </button>
                            <button class="btn btn-secondary" onclick="loadData()">
                                <i class="fas fa-sync"></i> <span class="btn-label">Refresh</span>
                            </button>
                            <button class="btn btn-secondary" onclick="toggleTheme()" id="theme-toggle">
                                <i class="fas fa-moon"></i> <span class="btn-label">Theme</span>
                            </button>
                            <button class="btn btn-primary" onclick="createTask()">
                                <i class="fas fa-plus"></i> <span class="btn-label">New Task</span>
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
            <!-- Agents / Sub-Agents Page -->
            <div id="page-agents" class="page">
                <header class="header">
                    <div class="header-title">
                        <h2>Sub-Agents</h2>
                        <p>Manage and monitor autonomous sub-agents</p>
                    </div>
                    <div style="display: flex; gap: 12px; align-items: center;">
                        <span id="agent-slots" style="font-size: 14px; color: #c0c0d8;">0/3 active</span>
                        <button class="btn btn-secondary" onclick="loadSubAgents()"><i class="fas fa-sync"></i> Refresh</button>
                    </div>
                </header>
                <div class="card" style="margin-bottom: 20px;">
                    <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px; color: #e94560;"><i class="fas fa-users-cog"></i> Active Agents</h3>
                    <div id="agent-list">
                        <p style="text-align: center; padding: 40px; color: #a0a0c0;">
                            <i class="fas fa-robot" style="font-size: 48px; margin-bottom: 16px; opacity: 0.3; display: block;"></i>
                            No active sub-agents
                        </p>
                    </div>
                </div>
                <div class="card">
                    <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px;"><i class="fas fa-plus-circle" style="color: #22c55e;"></i> Spawn Sub-Agent</h3>
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 12px;">
                        <div>
                            <label style="font-size: 12px; color: #a0a0c0; display: block; margin-bottom: 4px;">Name</label>
                            <input id="spawn-name" placeholder="agent-name" style="width: 100%; padding: 10px; background: var(--bg-1); border: 1px solid rgba(233,69,96,0.15); border-radius: 12px; color: #fff; font-size: 14px;">
                        </div>
                        <div>
                            <label style="font-size: 12px; color: #a0a0c0; display: block; margin-bottom: 4px;">Priority</label>
                            <select id="spawn-priority" style="width: 100%; padding: 10px; background: var(--bg-1); border: 1px solid rgba(233,69,96,0.15); border-radius: 12px; color: #fff; font-size: 14px;">
                                <option value="normal">Normal</option><option value="high">High</option><option value="low">Low</option>
                            </select>
                        </div>
                    </div>
                    <div style="margin-bottom: 12px;">
                        <label style="font-size: 12px; color: #a0a0c0; display: block; margin-bottom: 4px;">Description</label>
                        <input id="spawn-desc" placeholder="What should this agent do?" style="width: 100%; padding: 10px; background: var(--bg-1); border: 1px solid rgba(233,69,96,0.15); border-radius: 12px; color: #fff; font-size: 14px;">
                    </div>
                    <button class="btn btn-primary" onclick="spawnSubAgent()" style="width: 100%;"><i class="fas fa-rocket"></i> Spawn Agent</button>
                    <div id="spawn-result" style="margin-top: 8px; font-size: 12px; color: #a0a0c0; display: none;"></div>
                </div>
            </div>
            <!-- Memory Page -->
            <div id="page-memory" class="page">
                <header class="header">
                    <div class="header-title">
                        <h2>Memory</h2>
                        <p>Persistent AI memory — facts, decisions, patterns</p>
                    </div>
                    <button class="btn btn-secondary" onclick="loadMemory()"><i class="fas fa-sync"></i> Refresh</button>
                </header>
                <div class="card" style="margin-bottom: 20px;">
                    <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px; color: #e94560;"><i class="fas fa-brain"></i> Stored Memories</h3>
                    <div id="memory-content" style="max-height: 500px; overflow-y: auto;">
                        <p style="text-align: center; padding: 40px; color: #a0a0c0;">
                            <i class="fas fa-brain" style="font-size: 48px; margin-bottom: 16px; opacity: 0.3; display: block;"></i>
                            No memories stored yet
                        </p>
                    </div>
                </div>
                <div class="card">
                    <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px;"><i class="fas fa-plus-circle" style="color: #22c55e;"></i> Store Memory</h3>
                    <div style="display: flex; gap: 12px; align-items: flex-end;">
                        <div>
                            <label style="font-size: 12px; color: #a0a0c0; display: block; margin-bottom: 4px;">Category</label>
                            <select id="mem-cat" style="padding: 10px 14px; background: var(--bg-1); border: 1px solid rgba(233,69,96,0.15); border-radius: 12px; color: #fff; font-size: 14px;">
                                <option value="facts">Fact</option><option value="decisions">Decision</option><option value="patterns">Pattern</option><option value="blockers">Blocker</option><option value="preferences">Preference</option>
                            </select>
                        </div>
                        <div style="flex: 1;">
                            <label style="font-size: 12px; color: #a0a0c0; display: block; margin-bottom: 4px;">Content</label>
                            <input id="mem-input" placeholder="Store a memory..." style="width: 100%; padding: 10px 14px; background: var(--bg-1); border: 1px solid rgba(233,69,96,0.15); border-radius: 12px; color: #fff; font-size: 14px;" onkeydown="if(event.key==='Enter')storeMemory()">
                        </div>
                        <button class="btn btn-primary" onclick="storeMemory()"><i class="fas fa-plus"></i> Store</button>
                    </div>
                </div>
            </div>

            <!-- Terminal Page -->
            <div id="page-terminal" class="page">
                <header class="header">
                    <div class="header-title">
                        <h2>Terminal</h2>
                        <p>Execute commands on the system</p>
                    </div>
                </header>
                <div class="card" style="margin-bottom: 20px;">
                    <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px; color: #e94560;"><i class="fas fa-terminal"></i> Command</h3>
                    <div style="display: flex; gap: 8px; margin-bottom: 12px;">
                        <input id="term-input" placeholder="Run a command..." style="flex: 1; padding: 10px 14px; background: var(--bg-1); border: 1px solid rgba(233,69,96,0.15); border-radius: 12px; color: #fff; font-family: 'JetBrains Mono', monospace; font-size: 14px;" onkeydown="if(event.key==='Enter')runTerminal()">
                        <button class="btn btn-primary" onclick="runTerminal()"><i class="fas fa-play"></i> Run</button>
                    </div>
                    <div id="term-output" style="max-height: 350px; overflow-y: auto; background: var(--bg-0); border-radius: 12px; padding: 16px; font-family: 'JetBrains Mono', monospace; font-size: 13px; line-height: 1.6; white-space: pre-wrap; display: none; border: 1px solid rgba(233,69,96,0.08);"></div>
                </div>
                <div class="card">
                    <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px;"><i class="fas fa-history" style="color: #f59e0b;"></i> Command History</h3>
                    <div id="term-history" style="max-height: 300px; overflow-y: auto;">
                        <p style="text-align: center; padding: 20px; color: #a0a0c0;">No recent commands</p>
                    </div>
                </div>
            </div>

            <div id="page-schedules" class="page"><header class="header"><div class="header-title"><h2>Schedules</h2></div></header><div class="card"><p style="text-align:center;padding:40px;">Every 10 Minutes - Check for improvements</p></div></div>
            <div id="page-settings" class="page"><header class="header"><div class="header-title"><h2>Settings</h2><p>Configure your autonomy system</p></div></header>
                <div class="card" style="margin-bottom:16px;">
                    <h3 style="margin-bottom:12px;">Quick Actions</h3>
                    <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                        <button class="btn btn-primary" onclick="workstationOn()"><i class="fas fa-power-off"></i> Activate</button>
                        <button class="btn btn-secondary" onclick="workstationOff()"><i class="fas fa-stop"></i> Deactivate</button>
                        <button class="btn btn-secondary" onclick="aiGitCommit()"><i class="fas fa-code-branch"></i> AI Commit</button>
                    </div>
                </div>
                <div class="card" style="margin-bottom:16px;">
                    <h3 style="margin-bottom:12px;"><i class="fas fa-rocket" style="color:var(--accent);"></i> Autonomy GO</h3>
                    <p style="color:var(--text-muted); margin-bottom:12px; font-size:13px;">One-shot bootstrap: activate + create task + build HEARTBEAT + go.</p>
                    <input type="text" id="go-instruction" placeholder='e.g., "Build a REST API for users"' style="width:100%; padding:10px; background:var(--bg-0); border:1px solid rgba(233,69,96,0.2); border-radius:8px; color:var(--text); margin-bottom:8px; font-family:inherit;">
                    <button class="btn btn-primary" onclick="autonomyGo()" style="width:100%;"><i class="fas fa-rocket"></i> GO</button>
                    <div id="go-result" style="margin-top:8px; font-size:12px; color:var(--text-muted); display:none;"></div>
                </div>

                <div class="card">
                    <h3 style="margin-bottom:12px;"><i class="fas fa-coins" style="color:#ffc107;"></i> Token Budget</h3>
                    <div id="token-budget-panel" style="color:var(--text-muted);">Loading...</div>
                </div>
            </div>

            <!-- Journal / Progress page -->
            <div id="page-journal" class="page">
                <header class="header"><div class="header-title"><h2><i class="fas fa-book" style="color:var(--accent);margin-right:8px;"></i>Session Journal</h2></div></header>
                <div class="card" style="margin-bottom:16px;">
                    <h3 style="margin-bottom:12px;">Workspace</h3>
                    <div id="workspace-info" style="color:var(--text-muted); font-size:13px;">Scanning...</div>
                </div>
                <div class="card" style="margin-bottom:16px;">
                    <h3 style="margin-bottom:12px;">Session Timeline</h3>
                    <div id="journal-timeline" style="max-height:400px; overflow-y:auto;">Loading...</div>
                </div>
                <div class="card">
                    <h3 style="margin-bottom:12px;">Completed Tasks</h3>
                    <div id="completions-feed" style="color:var(--text-muted); font-size:13px;">No completions yet.</div>
                </div>
            </div>

            <!-- Metrics Page -->
            <div id="page-metrics" class="page">
                <header class="header">
                    <div class="header-title">
                        <h2>Metrics</h2>
                        <p>System performance and task analytics</p>
                    </div>
                    <div style="display: flex; gap: 12px; align-items: center;">
                        <span id="metrics-daemon-status" class="task-status" style="font-size: 12px;">Checking...</span>
                        <button class="btn btn-secondary" onclick="loadMetricsData()"><i class="fas fa-sync"></i> Refresh</button>
                    </div>
                </header>
                <div class="stats-grid" style="grid-template-columns: repeat(4, 1fr);">
                    <div class="stat-card"><div class="stat-value" id="m-total">-</div><div class="stat-label">Total Tasks</div></div>
                    <div class="stat-card"><div class="stat-value" id="m-completed" style="color: #22c55e;">-</div><div class="stat-label">Completed</div></div>
                    <div class="stat-card"><div class="stat-value" id="m-pending">-</div><div class="stat-label">Pending</div></div>
                    <div class="stat-card"><div class="stat-value" id="m-tokens" style="color: #f59e0b;">-</div><div class="stat-label">Tokens Today</div></div>
                </div>
                <div class="metrics-chart-grid">
                    <div class="card">
                        <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px;"><i class="fas fa-chart-pie" style="color: var(--accent);"></i> Task Distribution</h3>
                        <div class="metrics-chart-wrap"><canvas id="metricsChart"></canvas></div>
                    </div>
                    <div class="card">
                        <h3 style="font-size: 18px; font-weight: 700; margin-bottom: 16px;"><i class="fas fa-history" style="color: #f59e0b;"></i> Recent Activity</h3>
                        <div id="metrics-activity" style="max-height: 300px; overflow-y: auto;"><p style="color: #a0a0c0;">Loading...</p></div>
                    </div>
                </div>
            </div>
        </main>
        
        <!-- Mobile Bottom Navigation -->
        <nav class="mobile-nav">
            <div class="mobile-nav-item active" onclick="showPage('dashboard', this); window.scrollTo({top: 0, behavior: 'smooth'});">
                <i class="fas fa-chart-pie"></i>
                <span>Home</span>
            </div>
            <div class="mobile-nav-item" onclick="showPage('tasks', this); window.scrollTo({top: 0, behavior: 'smooth'});">
                <i class="fas fa-tasks"></i>
                <span>Tasks</span>
            </div>
            <div class="mobile-nav-item" onclick="showPage('agents', this); loadSubAgents(); window.scrollTo({top: 0, behavior: 'smooth'});">
                <i class="fas fa-microchip"></i>
                <span>Agents</span>
            </div>
            <div class="mobile-nav-item" onclick="showPage('memory', this); loadMemory(); window.scrollTo({top: 0, behavior: 'smooth'});">
                <i class="fas fa-brain"></i>
                <span>Memory</span>
            </div>
            <div class="mobile-nav-item" onclick="showPage('terminal', this); loadTerminalHistory(); window.scrollTo({top: 0, behavior: 'smooth'});">
                <i class="fas fa-terminal"></i>
                <span>Terminal</span>
            </div>
            <div class="mobile-nav-item" onclick="showPage('metrics', this); loadMetricsData(); window.scrollTo({top: 0, behavior: 'smooth'});">
                <i class="fas fa-chart-line"></i>
                <span>Metrics</span>
            </div>
            <div class="mobile-nav-item" onclick="showPage('settings', this); loadSettings(); window.scrollTo({top: 0, behavior: 'smooth'});">
                <i class="fas fa-cog"></i>
                <span>Settings</span>
            </div>
        </nav>
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
            
            // Update desktop nav
            document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
            if (navItem && navItem.classList.contains('nav-item')) {
                navItem.classList.add('active');
            }
            
            // Update mobile nav
            document.querySelectorAll('.mobile-nav-item').forEach(n => n.classList.remove('active'));
            if (navItem && navItem.classList.contains('mobile-nav-item')) {
                navItem.classList.add('active');
            } else {
                // Find the mobile nav item for this page
                const mobileNavItems = document.querySelectorAll('.mobile-nav-item');
                mobileNavItems.forEach(item => {
                    if (item.getAttribute('onclick').includes(`'${pageId}'`)) {
                        item.classList.add('active');
                    }
                });
            }
            
            // Load data if going to tasks page
            if (pageId === 'tasks') {
                loadData();
            }
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
        
        // Heartbeat Timer - SIMPLE and RELIABLE
        // Shows actual last check time from daemon, always 5 min interval
        async function updateHeartbeatTimer() {
            try {
                const res = await fetch('/api/heartbeat');
                const data = await res.json();
                
                // Use actual last check time from daemon
                if (data.last_check) {
                    lastHeartbeat = new Date(data.last_check).getTime();
                }
                
                // Fixed 5 minute interval
                heartbeatInterval = 5 * 60 * 1000;
                
                // Update daemon status display
                const statusEl = document.getElementById('system-status');
                if (statusEl) {
                    if (data.daemon_running) {
                        const lastCheckStr = data.last_check ? 
                            new Date(data.last_check).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) :
                            'Unknown';
                        statusEl.innerHTML = '<i class="fas fa-circle" style="color: #22c55e;"></i> <span>Daemon Running - Last check: ' + lastCheckStr + '</span>';
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
            const nextCheck = lastHeartbeat + heartbeatInterval;
            const timeLeft = Math.max(0, nextCheck - now);
            
            const minutes = Math.floor(timeLeft / 60000);
            const seconds = Math.floor((timeLeft % 60000) / 1000);
            
            const timerEl = document.getElementById('heartbeat-timer');
            if (timerEl) {
                // Show time remaining until next check
                if (timeLeft === 0) {
                    timerEl.textContent = 'CHECKING...';
                    timerEl.style.color = '#e94560';
                } else {
                    timerEl.textContent = minutes + ':' + seconds.toString().padStart(2, '0');
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
            const modal = document.getElementById('onboarding-modal');
            if (modal) {
                modal.classList.add('active');
                modal.style.display = 'flex';
            }
        }
        
        function hideOnboarding() {
            const modal = document.getElementById('onboarding-modal');
            if (modal) {
                modal.classList.remove('active');
                modal.style.display = 'none';
            }
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
        
        // AI Activity Polling - Real-time updates
        let aiActivityInterval = null;
        let currentAiTask = null;
        
        async function updateAiActivity() {
            try {
                const res = await fetch('/api/ai/activity');
                const data = await res.json();
                
                const aiBox = document.getElementById('ai-activity-box');
                const aiTask = document.getElementById('ai-current-task');
                const aiProgress = document.getElementById('ai-progress-bar');
                const aiLogs = document.getElementById('ai-activity-logs');
                
                if (data.status === 'processing' || data.status === 'working') {
                    // Show AI activity box
                    aiBox.style.display = 'flex';
                    
                    // Update task name
                    if (data.task && data.task !== currentAiTask) {
                        currentAiTask = data.task;
                        aiTask.textContent = data.task;
                    }
                    
                    // Update progress
                    if (data.progress !== undefined) {
                        aiProgress.style.width = data.progress + '%';
                    }
                    
                    // Update logs
                    if (data.logs && data.logs.length > 0) {
                        aiLogs.innerHTML = data.logs.slice(-3).map(log => 
                            `<div class="log-entry">${log}</div>`
                        ).join('');
                    }
                    
                    // Also update system status
                    const statusEl = document.getElementById('system-status');
                    if (statusEl) {
                        statusEl.innerHTML = '<i class="fas fa-circle" style="color: #3b82f6;"></i> <span>AI Processing...</span>';
                        statusEl.className = 'system-status-box';
                    }
                } else {
                    // Hide AI activity box when idle
                    aiBox.style.display = 'none';
                    currentAiTask = null;
                    
                    // Reset system status
                    const statusEl = document.getElementById('system-status');
                    if (statusEl) {
                        statusEl.innerHTML = '<i class="fas fa-circle" style="color: #22c55e;"></i> <span>System Healthy</span>';
                        statusEl.className = 'system-status-box';
                    }
                }
            } catch (e) {
                console.log('AI activity fetch failed');
            }
        }
        
        // Start AI activity polling
        function startAiActivityPolling() {
            if (!aiActivityInterval) {
                updateAiActivity(); // Initial check
                aiActivityInterval = setInterval(updateAiActivity, 2000); // Poll every 2 seconds
            }
        }

        // ── New: Journal & Live Progress functions ──────────

        async function loadJournalData() {
            try {
                // Journal timeline
                const tlRes = await fetch('/api/journal/timeline');
                const tlData = await tlRes.json();
                const tlEl = document.getElementById('journal-timeline');
                if (tlEl && tlData.html) tlEl.innerHTML = tlData.html;

                // Completions
                const cRes = await fetch('/api/completions');
                const cData = await cRes.json();
                const cEl = document.getElementById('completions-feed');
                if (cEl) {
                    if (cData.exists && cData.content) {
                        cEl.innerHTML = '<pre style="white-space:pre-wrap; font-size:12px; color:var(--text-muted); max-height:300px; overflow-y:auto;">' + cData.content.replace(/</g,'&lt;') + '</pre>';
                    } else {
                        cEl.innerHTML = '<p style="color:var(--text-muted);">No completed tasks yet.</p>';
                    }
                }

                // Workspace info
                const wRes = await fetch('/api/workspace');
                const wData = await wRes.json();
                const wEl = document.getElementById('workspace-info');
                if (wEl && !wData.error) {
                    wEl.innerHTML = `<strong>Language:</strong> ${wData.languages || 'unknown'} | <strong>Framework:</strong> ${wData.framework || 'none'} | <strong>Type:</strong> ${wData.project_type || 'project'} | <strong>Files:</strong> ${wData.file_count || '?'}`;
                }
            } catch (e) {
                console.log('Journal data load failed:', e);
            }
        }

        async function loadTokenBudget() {
            try {
                const res = await fetch('/api/token-budget');
                const data = await res.json();
                const el = document.getElementById('token-budget-panel');
                if (el) {
                    const color = data.status === 'exceeded' ? '#e94560' : data.status === 'warning' ? '#ffc107' : '#00d26a';
                    const pct = data.percent_used || 0;
                    el.innerHTML = `
                        <div style="display:flex;justify-content:space-between;margin-bottom:8px;">
                            <span>${data.used || 0} / ${data.budget || 50000} tokens</span>
                            <span style="color:${color};font-weight:600;">${pct}%</span>
                        </div>
                        <div style="background:var(--bg-0);height:8px;border-radius:4px;overflow:hidden;">
                            <div style="background:${color};height:100%;width:${Math.min(pct,100)}%;border-radius:4px;transition:width 0.5s;"></div>
                        </div>
                        <div style="margin-top:6px;font-size:11px;color:var(--text-muted);">${data.remaining || 0} remaining | ${data.sessions || 0} sessions today</div>
                    `;
                }
            } catch (e) {
                console.log('Token budget fetch failed');
            }
        }

        async function autonomyGo() {
            const input = document.getElementById('go-instruction');
            const resultEl = document.getElementById('go-result');
            const instruction = input ? input.value.trim() : '';
            
            resultEl.style.display = 'block';
            resultEl.style.color = 'var(--text-muted)';
            resultEl.textContent = 'Launching...';
            
            try {
                const res = await fetch('/api/go', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({instruction: instruction})
                });
                const data = await res.json();
                if (data.success) {
                    resultEl.style.color = '#00d26a';
                    resultEl.textContent = '✓ ' + (data.message || 'Autonomy GO activated!');
                    if (input) input.value = '';
                    setTimeout(() => { loadData(); loadTokenBudget(); }, 2000);
                } else {
                    resultEl.style.color = '#e94560';
                    resultEl.textContent = '✗ ' + (data.error || 'Failed');
                }
            } catch (e) {
                resultEl.style.color = '#e94560';
                resultEl.textContent = '✗ Network error';
            }
        }

        // ── Memory Functions ──────────────────────────
        async function loadMemory() {
            try {
                const res = await fetch('/api/memory');
                const d = await res.json();
                const el = document.getElementById('memory-content');
                const categories = ['facts','decisions','patterns','blockers','preferences'];
                const icons = {facts:'fa-lightbulb',decisions:'fa-gavel',patterns:'fa-puzzle-piece',blockers:'fa-exclamation-triangle',preferences:'fa-star'};
                const colors = {facts:'#3b82f6',decisions:'#22c55e',patterns:'#f59e0b',blockers:'#e94560',preferences:'#ff6b8a'};
                let html = '';
                let total = 0;
                for (const cat of categories) {
                    const items = d[cat] || [];
                    total += items.length;
                    if (items.length === 0) continue;
                    html += '<div style="margin-bottom: 16px;">';
                    html += '<div style="font-size: 13px; font-weight: 600; color: ' + colors[cat] + '; margin-bottom: 6px;"><i class="fas ' + icons[cat] + '"></i> ' + cat.charAt(0).toUpperCase() + cat.slice(1) + ' (' + items.length + ')</div>';
                    items.slice(-8).forEach(function(m) {
                        html += '<div style="font-size: 13px; color: #c0c0d8; padding: 4px 0 4px 16px; border-left: 2px solid ' + colors[cat] + '33;">• ' + escapeHtml(m.content) + '</div>';
                    });
                    html += '</div>';
                }
                if (total === 0) html = '<p style="text-align: center; padding: 40px; color: #a0a0c0;"><i class="fas fa-brain" style="font-size: 48px; margin-bottom: 16px; opacity: 0.3; display: block;"></i>No memories stored yet</p>';
                el.innerHTML = html;
            } catch(e) { console.log('Memory load failed'); }
        }

        async function storeMemory() {
            const cat = document.getElementById('mem-cat').value;
            const input = document.getElementById('mem-input');
            const content = input.value.trim();
            if (!content) return;
            try {
                await fetch('/api/memory/store', {method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({category: cat, content: content, source: 'web_ui'})});
                input.value = '';
                loadMemory();
            } catch(e) { console.error('Memory store failed'); }
        }

        function escapeHtml(str) {
            const div = document.createElement('div');
            div.appendChild(document.createTextNode(str));
            return div.innerHTML;
        }

        // ── Sub-Agents Functions ────────────────────
        async function loadSubAgents() {
            try {
                const res = await fetch('/api/sub-agents');
                const d = await res.json();
                document.getElementById('agent-slots').textContent = (d.active_agents || 0) + '/' + (d.max_agents || 3) + ' active';
                document.getElementById('stat-agents').textContent = d.active_agents || 0;
                const el = document.getElementById('agent-list');
                const agents = d.agents || [];
                if (agents.length === 0) {
                    el.innerHTML = '<p style="text-align: center; padding: 40px; color: #a0a0c0;"><i class="fas fa-robot" style="font-size: 48px; margin-bottom: 16px; opacity: 0.3; display: block;"></i>No active sub-agents</p>';
                    return;
                }
                el.innerHTML = '<div class="task-list">' + agents.map(function(a) {
                    const statusColor = a.status === 'active' ? '#22c55e' : '#f59e0b';
                    return '<div class="task-item"><div class="task-header"><span class="task-name">' + escapeHtml(a.name) + '</span><span class="task-status" style="background: ' + statusColor + '20; color: ' + statusColor + '; border: 1px solid ' + statusColor + '40;">' + a.status + '</span></div><div class="task-desc">Parent: ' + escapeHtml(a.parent_task || 'manual') + '</div></div>';
                }).join('') + '</div>';
            } catch(e) { console.log('Sub-agents load failed'); }
        }

        async function spawnSubAgent() {
            const name = document.getElementById('spawn-name').value.trim();
            const desc = document.getElementById('spawn-desc').value.trim();
            const priority = document.getElementById('spawn-priority').value;
            const resultEl = document.getElementById('spawn-result');
            if (!name || !desc) { alert('Name and description required'); return; }
            resultEl.style.display = 'block';
            resultEl.textContent = 'Spawning...';
            resultEl.style.color = '#a0a0c0';
            try {
                const res = await fetch('/api/sub-agents/spawn', {method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({parent: 'manual', name: name, description: desc, priority: priority})});
                const d = await res.json();
                resultEl.textContent = d.success ? '✓ ' + (d.message || 'Agent spawned!') : '✗ ' + (d.error || 'Failed');
                resultEl.style.color = d.success ? '#22c55e' : '#e94560';
                if (d.success) { document.getElementById('spawn-name').value = ''; document.getElementById('spawn-desc').value = ''; loadSubAgents(); }
            } catch(e) { resultEl.textContent = '✗ Network error'; resultEl.style.color = '#e94560'; }
        }

        // ── Terminal Functions ───────────────────────
        async function runTerminal() {
            const input = document.getElementById('term-input');
            const out = document.getElementById('term-output');
            const cmd = input.value.trim();
            if (!cmd) return;
            out.style.display = 'block';
            out.textContent = '$ ' + cmd + '\\nRunning...';
            out.style.color = '#a0a0c0';
            try {
                const res = await fetch('/api/terminal/run', {method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({command: cmd, timeout: 30})});
                const d = await res.json();
                out.style.color = d.success ? '#22c55e' : '#e94560';
                out.textContent = '$ ' + cmd + '\\n' + (d.output || d.error || '(no output)') + '\\n[exit: ' + (d.exit_code !== undefined ? d.exit_code : '?') + ']';
                input.value = '';
                loadTerminalHistory();
            } catch(e) { out.style.color = '#e94560'; out.textContent = 'Network error'; }
        }

        async function loadTerminalHistory() {
            try {
                const res = await fetch('/api/terminal/history');
                const entries = await res.json();
                const el = document.getElementById('term-history');
                if (!entries.length) { el.innerHTML = '<p style="text-align: center; padding: 20px; color: #a0a0c0;">No recent commands</p>'; return; }
                el.innerHTML = entries.slice().reverse().slice(0, 15).map(function(entry) {
                    var ok = entry.exit_code === 0;
                    var time = entry.timestamp ? new Date(entry.timestamp).toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"}) : "";
                    var cmd = escapeHtml((entry.command || "").substring(0, 60));
                    var color = ok ? "#22c55e" : "#e94560";
                    return "<div class='task-item' style='cursor:pointer;padding:12px' data-cmd='" + escapeHtml(entry.command || "") + "'>" +
                        "<div class='task-header'><span class='task-name' style='font-family:JetBrains Mono,monospace;font-size:14px;color:" + color + "'>$ " + cmd + "</span><span style='font-size:12px;color:#a0a0c0'>" + time + "</span></div></div>";
                }).join("");
                el.querySelectorAll('[data-cmd]').forEach(function(div) {
                    div.addEventListener('click', function() {
                        document.getElementById('term-input').value = this.getAttribute('data-cmd');
                    });
                });
            } catch(e) {}
        }

        // ── Settings Functions ──────────────────────
        async function loadSettings() { /* AI config managed by OpenClaw */ }
        async function saveSettings() { /* AI config managed by OpenClaw */ }

        async function aiGitCommit() {
            const msg = prompt('Commit message (leave blank for AI-generated):') || '';
            try {
                const res = await fetch('/api/ai/commit', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({message: msg})});
                const d = await res.json();
                alert(d.output || d.error || 'Done');
            } catch(e) { alert('Commit failed'); }
        }

        // ── Metrics Functions ───────────────────────
        let metricsChart = null;

        async function loadMetricsData() {
            try {
                const res = await fetch('/api/metrics');
                const data = await res.json();
                document.getElementById('m-total').textContent = data.tasks.total;
                document.getElementById('m-completed').textContent = data.tasks.completed;
                document.getElementById('m-pending').textContent = data.tasks.pending;
                document.getElementById('m-tokens').textContent = data.token_usage.toLocaleString();

                var statusEl = document.getElementById('metrics-daemon-status');
                if (data.daemon_running) {
                    statusEl.textContent = 'Daemon Running';
                    statusEl.style.background = 'rgba(34,197,94,0.15)';
                    statusEl.style.color = '#22c55e';
                    statusEl.style.border = '1px solid rgba(34,197,94,0.2)';
                } else {
                    statusEl.textContent = 'Daemon Stopped';
                    statusEl.style.background = 'rgba(233,69,96,0.15)';
                    statusEl.style.color = '#e94560';
                    statusEl.style.border = '1px solid rgba(233,69,96,0.2)';
                }

                var ctx = document.getElementById('metricsChart');
                if (ctx) {
                    if (metricsChart) metricsChart.destroy();
                    metricsChart = new Chart(ctx.getContext('2d'), {
                        type: 'doughnut',
                        data: {
                            labels: ['Pending', 'Completed', 'Processing', 'Needs Attention'],
                            datasets: [{
                                data: [data.tasks.pending, data.tasks.completed, data.tasks.ai_processing, data.tasks.needs_ai_attention],
                                backgroundColor: ['#6b6b8a', '#00d9a3', '#e94560', '#ffc107'],
                                borderWidth: 0
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            plugins: { legend: { position: 'bottom', labels: { color: '#ffffff', padding: 20 } } }
                        }
                    });
                }

                var actEl = document.getElementById('metrics-activity');
                if (data.activity && data.activity.length > 0) {
                    actEl.innerHTML = data.activity.slice().reverse().map(function(item) {
                        var time = new Date(item.timestamp).toLocaleTimeString();
                        var action = item.action || 'Unknown';
                        return '<div style="padding:10px;border-bottom:1px solid rgba(233,69,96,0.08);display:flex;justify-content:space-between;font-size:14px"><span style="color:#d0d0e8">' + escapeHtml(action) + '</span><span style="color:#8080a0;font-family:JetBrains Mono,monospace;font-size:12px">' + time + '</span></div>';
                    }).join('');
                } else {
                    actEl.innerHTML = '<p style="color:#a0a0c0;text-align:center;padding:20px">No recent activity</p>';
                }
            } catch(e) { console.error('Metrics load failed:', e); }
        }

        initTheme();
        checkOnboarding();
        
        // Ensure dashboard is visible on load
        document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
        document.getElementById('page-dashboard').classList.add('active');
        document.querySelectorAll('.mobile-nav-item').forEach(n => n.classList.remove('active'));
        document.querySelector('.mobile-nav-item')?.classList.add('active');
        
        // Start real-time AI activity monitoring
        startAiActivityPolling();
        
        loadData();
        updateHeartbeatTimer();
        loadTokenBudget();
        loadSubAgents();
        setInterval(loadData, 5000);
        setInterval(updateTimerDisplay, 1000);
        setInterval(updateHeartbeatTimer, 30000);
        setInterval(loadTokenBudget, 30000);
        setInterval(loadSubAgents, 15000);
        
        // Swipe gesture support for mobile page navigation
        let touchStartX = 0;
        let touchStartY = 0;
        let touchEndX = 0;
        let touchEndY = 0;
        
        const pages = ['dashboard', 'tasks', 'agents', 'memory', 'terminal', 'schedules', 'journal', 'metrics', 'settings'];
        
        function handleTouchStart(e) {
            touchStartX = e.changedTouches[0].screenX;
            touchStartY = e.changedTouches[0].screenY;
        }
        
        function handleTouchEnd(e) {
            touchEndX = e.changedTouches[0].screenX;
            touchEndY = e.changedTouches[0].screenY;
            handleSwipe();
        }
        
        function handleSwipe() {
            // Only on mobile
            if (window.innerWidth > 768) return;
            
            const swipeThreshold = 80;
            const verticalThreshold = 100; // Prevent swipe if scrolling vertically
            
            const horizontalDiff = touchEndX - touchStartX;
            const verticalDiff = Math.abs(touchEndY - touchStartY);
            
            // Ignore if vertical scroll is dominant
            if (verticalDiff > verticalThreshold) return;
            
            // Find current page
            let currentPageIndex = 0;
            pages.forEach((page, index) => {
                const pageEl = document.getElementById('page-' + page);
                if (pageEl && pageEl.classList.contains('active')) {
                    currentPageIndex = index;
                }
            });
            
            if (Math.abs(horizontalDiff) > swipeThreshold) {
                if (horizontalDiff > 0 && currentPageIndex > 0) {
                    // Swipe right - go to previous page
                    showPage(pages[currentPageIndex - 1], null);
                } else if (horizontalDiff < 0 && currentPageIndex < pages.length - 1) {
                    // Swipe left - go to next page
                    showPage(pages[currentPageIndex + 1], null);
                }
            }
        }
        
        // Add touch listeners
        document.addEventListener('touchstart', handleTouchStart, {passive: true});
        document.addEventListener('touchend', handleTouchEnd, {passive: true});
        
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
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover">
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
        
        /* Mobile Responsive Styles for Metrics */
        @media (max-width: 768px) {
            body {
                padding: 12px;
                padding-bottom: 80px; /* Space for potential mobile nav */
                overflow-x: hidden;
            }
            
            .header {
                flex-direction: column;
                align-items: flex-start;
                gap: 16px;
                padding: 16px;
                margin-bottom: 20px;
            }
            
            .header h1 {
                font-size: 1.25rem;
            }
            
            .header > div {
                display: flex;
                flex-wrap: wrap;
                gap: 8px;
                width: 100%;
            }
            
            .refresh-btn {
                flex: 1;
                min-width: 100px;
                justify-content: center;
                padding: 12px 16px;
                min-height: 44px;
            }
            
            .back-link {
                padding: 12px 16px;
                background: var(--bg-3);
                border-radius: 8px;
                min-height: 44px;
                display: flex;
                align-items: center;
            }
            
            .grid {
                grid-template-columns: 1fr 1fr;
                gap: 12px;
                margin-bottom: 20px;
            }
            
            /* Chart grid (second .grid) should stack vertically */
            .grid ~ .grid {
                grid-template-columns: 1fr;
            }
            
            .card {
                padding: 16px;
                min-width: 0;
                overflow: hidden;
            }
            
            .card h3 {
                font-size: 0.75rem;
                margin-bottom: 10px;
            }
            
            .stat-value {
                font-size: 1.75rem;
            }
            
            .stat-label {
                font-size: 0.75rem;
            }
            
            .chart-container {
                height: 200px;
                max-width: 100%;
                overflow: hidden;
            }
            
            /* Full width for chart and activity - stack vertically */
            .grid > .card[style*="span 2"],
            .grid > .card[style*="span 1"] {
                grid-column: span 1 !important;
            }
            
            .grid > .card {
                min-width: 0;
                overflow: hidden;
            }
            
            .grid canvas {
                max-width: 100% !important;
                width: 100% !important;
            }
            
            .activity-log {
                max-height: 250px;
            }
            
            .activity-item {
                font-size: 0.85rem;
                padding: 8px;
            }
        }
        
        @media (max-width: 480px) {
            .grid {
                grid-template-columns: 1fr;
            }
            
            .grid > .card[style*="span 2"],
            .grid > .card[style*="span 1"] {
                grid-column: span 1 !important;
            }
            
            .stat-value {
                font-size: 2rem;
            }
        }
        
        /* Safe area support for notched phones */
        @supports (padding: max(0px)) {
            @media (max-width: 768px) {
                body {
                    padding-left: max(12px, env(safe-area-inset-left));
                    padding-right: max(12px, env(safe-area-inset-right));
                    padding-bottom: max(12px, env(safe-area-inset-bottom));
                }
            }
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
      try:
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
        elif self.path == "/api/ai/activity":
            self.serve_ai_activity()
        elif self.path == "/api/journal":
            self.serve_journal()
        elif self.path == "/api/journal/timeline":
            self.serve_journal_timeline()
        elif self.path == "/api/completions":
            self.serve_completions()
        elif self.path == "/api/token-budget":
            self.serve_token_budget()
        elif self.path == "/api/workspace":
            self.serve_workspace_scan()
        elif self.path == "/api/ai/status":
            self.serve_ai_status()
        elif self.path == "/api/memory":
            self.serve_memory()
        elif self.path == "/api/sub-agents":
            self.serve_sub_agents()
        elif self.path == "/api/terminal/history":
            self.serve_terminal_history()
        elif self.path == "/api/settings":
            self.serve_settings()
        else:
            self.send_error(404)
      except Exception as e:
        try:
            self.send_json({"error": str(e)}, 500)
        except Exception:
            pass  # Connection may already be closed
    
    def do_POST(self):
      try:
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
        elif self.path == "/api/go":
            self.handle_go()
        elif self.path == "/api/settings":
            self.save_settings()
        elif self.path == "/api/terminal/run":
            self.run_ai_terminal()
        elif self.path == "/api/memory/store":
            self.store_memory()
        elif self.path == "/api/sub-agents/spawn":
            self.spawn_sub_agent()
        elif self.path == "/api/ai/commit":
            self.ai_git_commit()
        elif self.path == "/api/webhook":
            self.handle_webhook()
        else:
            self.send_error(404)
      except Exception as e:
        try:
            self.send_json({"error": str(e)}, 500)
        except Exception:
            pass
    
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
        """Serve heartbeat info - flexible interval, always reliable"""
        try:
            # Try flexible daemon first
            check_file = f"{AUTONOMY_DIR}/state/last-check.json"
            last_check = None
            interval_minutes = 5
            
            if os.path.exists(check_file):
                try:
                    with open(check_file, 'r') as f:
                        data = json.load(f)
                        last_check = data.get("last_check")
                        interval_minutes = data.get("interval_minutes", 5)
                except:
                    pass
            
            # Fallback to simple daemon
            if not last_check:
                simple_check = f"{AUTONOMY_DIR}/state/last-check.json"
                if os.path.exists(simple_check):
                    try:
                        with open(simple_check, 'r') as f:
                            data = json.load(f)
                            last_check = data.get("last_check")
                            interval_minutes = data.get("interval_minutes", 5)
                    except:
                        pass
            
            # Check if any daemon is running
            daemon_running = False
            if os.path.exists(f"{AUTONOMY_DIR}/state/daemon.pid"):
                try:
                    with open(f"{AUTONOMY_DIR}/state/daemon.pid", 'r') as f:
                        pid = int(f.read().strip())
                        # Check if process exists (signal 0 doesn't kill, just checks)
                        import signal
                        os.kill(pid, 0)
                        daemon_running = True
                except (ProcessLookupError, ValueError, OSError):
                    daemon_running = False
                except:
                    daemon_running = False
            
            # Calculate next check
            next_check = None
            if last_check:
                try:
                    last_time = datetime.fromisoformat(last_check.replace('Z', '+00:00'))
                    next_check = (last_time + timedelta(minutes=interval_minutes)).isoformat()
                except:
                    pass
            
            self.send_json({
                "last_check": last_check,
                "interval_minutes": interval_minutes,
                "daemon_running": daemon_running,
                "next_check": next_check
            })
        except Exception as e:
            self.send_json({"error": str(e)}, 500)
    
    def serve_coordinator_stats(self):
        """Serve coordinator statistics"""
        try:
            stats = {
                "daemon_running": os.path.exists(f"{AUTONOMY_DIR}/state/daemon.pid"),
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

    def serve_ai_activity(self):
        """Serve real-time AI activity status"""
        try:
            # First check if there's a task needing attention (priority)
            needs_attention = f"{AUTONOMY_DIR}/state/needs_attention.json"
            if os.path.exists(needs_attention):
                with open(needs_attention, 'r') as f:
                    attention = json.load(f)
                    self.send_json({
                        "status": "processing",
                        "task": attention.get("task_name"),
                        "description": attention.get("description", "AI is working on a task..."),
                        "started_at": attention.get("timestamp"),
                        "updated_at": datetime.now().isoformat(),
                        "progress": 50,
                        "message": "AI is processing: " + attention.get("task_name", "task"),
                        "logs": ["Task flagged for AI processing", "AI will start working soon..."]
                    })
                return
            
            # Check for active AI activity
            activity_file = f"{AUTONOMY_DIR}/state/ai_activity.json"
            if os.path.exists(activity_file):
                with open(activity_file, 'r') as f:
                    activity = json.load(f)
                    # Only return if actually processing
                    if activity.get("status") in ["processing", "working"]:
                        self.send_json(activity)
                        return
            
            # Default idle state
            self.send_json({
                "status": "idle",
                "task": None,
                "message": "Waiting for heartbeat...",
                "progress": 0,
                "logs": []
            })
        except Exception as e:
            self.send_json({"status": "error", "message": str(e)}, 500)
    
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
            daemon_running = os.path.exists(f"{AUTONOMY_DIR}/state/daemon.pid")
            
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

    # ── New live-progress API endpoints ────────────────────

    def serve_journal(self):
        """Serve raw journal entries (last 20)"""
        try:
            journal_file = f"{AUTONOMY_DIR}/state/journal.jsonl"
            entries = []
            if os.path.exists(journal_file):
                with open(journal_file, 'r') as f:
                    lines = f.readlines()[-20:]
                for line in lines:
                    try:
                        entries.append(json.loads(line.strip()))
                    except:
                        pass
            self.send_json(entries)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def serve_journal_timeline(self):
        """Serve journal as rendered timeline HTML snippet"""
        try:
            journal_file = f"{AUTONOMY_DIR}/state/journal.jsonl"
            entries = []
            if os.path.exists(journal_file):
                with open(journal_file, 'r') as f:
                    lines = f.readlines()[-10:]
                for line in lines:
                    try:
                        entries.append(json.loads(line.strip()))
                    except:
                        pass
            
            if not entries:
                self.send_json({"html": "<p style='color:var(--text-muted)'>No journal entries yet. The AI will log progress here after each heartbeat.</p>"})
                return

            html_parts = []
            for e in reversed(entries):
                status = e.get("status", "unknown")
                color_map = {"completed": "#00d26a", "failed": "#e94560", "blocked": "#ffc107", "in-progress": "#00b4d8", "pivoted": "#ff6b8a"}
                color = color_map.get(status, "#6b6b8a")
                ts = e.get("timestamp", "")[:19].replace("T", " ")
                task = html_module.escape(e.get("task", ""))
                summary = html_module.escape(e.get("summary", ""))
                next_step = html_module.escape(e.get("next_step", ""))
                status_display = html_module.escape(status.upper())

                html_parts.append(f'''
                <div style="border-left:3px solid {color}; padding:8px 12px; margin:8px 0; background:rgba(255,255,255,0.03); border-radius:0 8px 8px 0;">
                    <div style="display:flex; justify-content:space-between; margin-bottom:4px;">
                        <span style="font-weight:600; color:{color};">[{status_display}]</span>
                        <span style="color:var(--text-muted); font-size:12px;">{ts}</span>
                    </div>
                    <div style="font-weight:500; margin-bottom:2px;">{task}</div>
                    <div style="color:var(--text-muted); font-size:13px;">{summary}</div>
                    {"<div style='color:#00b4d8; font-size:12px; margin-top:4px;'>→ Next: " + next_step + "</div>" if next_step and next_step != "null" else ""}
                </div>''')

            self.send_json({"html": "".join(html_parts)})
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def serve_completions(self):
        """Serve completed.md content"""
        try:
            completed_file = f"{AUTONOMY_DIR}/state/completed.md"
            if os.path.exists(completed_file):
                with open(completed_file, 'r') as f:
                    content = f.read()
                self.send_json({"content": content, "exists": True})
            else:
                self.send_json({"content": "", "exists": False})
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def serve_token_budget(self):
        """Serve token budget status"""
        try:
            token_file = f"{AUTONOMY_DIR}/state/token_usage.json"
            budget = 50000
            
            # Get budget from config
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    config = json.load(f)
                budget = config.get("agentic_config", {}).get("hard_limits", {}).get("daily_token_budget", 50000)
            
            state = {"date": datetime.now().strftime("%Y-%m-%d"), "used": 0, "sessions": 0, "budget": budget}
            if os.path.exists(token_file):
                with open(token_file, 'r') as f:
                    state = json.load(f)
                state["budget"] = budget
            
            state["remaining"] = budget - state.get("used", 0)
            pct = int((state.get("used", 0) / budget * 100)) if budget > 0 else 0
            state["percent_used"] = pct
            
            if pct >= 100:
                state["status"] = "exceeded"
            elif pct >= 80:
                state["status"] = "warning"
            else:
                state["status"] = "ok"
            
            self.send_json(state)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def serve_workspace_scan(self):
        """Serve workspace scan results"""
        try:
            scan_file = f"{AUTONOMY_DIR}/state/workspace_scan.json"
            if os.path.exists(scan_file):
                with open(scan_file, 'r') as f:
                    content = f.read()
                    content = ''.join(c for c in content if ord(c) >= 32 or c in '\n\r\t')
                    scan = json.loads(content)
                self.send_json(scan)
            else:
                self.send_json({"error": "No workspace scan yet. Run: autonomy go"}, 404)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def _config_interval(self):
        """Read daemon interval from config.json — same keys as daemon.sh"""
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    cfg = json.load(f)
                return (
                    cfg.get("daemon", {}).get("interval_minutes")
                    or cfg.get("global_config", {}).get("base_interval_minutes")
                    or 5
                )
        except: pass
        return 5

    # ── AI / Settings / Terminal / Memory / Sub-agents ───

    def serve_ai_status(self):
        try:
            result = subprocess.run(["bash", f"{AUTONOMY_DIR}/lib/ai-engine.sh", "status"],
                                    capture_output=True, text=True, timeout=10)
            self.send_json(json.loads(result.stdout.strip()) if result.returncode == 0 else {"configured": False})
        except:
            self.send_json({"configured": False})

    def serve_settings(self):
        try:
            config = {}
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    config = json.load(f)
            ai = config.get("ai", {})
            key = ai.get("api_key", "")
            masked = ("*" * (len(key) - 4) + key[-4:]) if len(key) > 4 else ("*" * len(key) if key else "")
            self.send_json({
                "provider": ai.get("provider", "openai"),
                "api_key_set": bool(key),
                "api_key_masked": masked,
                "api_url": ai.get("api_url", ""),
                "model": ai.get("model", "gpt-4o-mini"),
                "auto_commit": ai.get("auto_commit", False),
                "auto_push": ai.get("auto_push", False),
                "terminal_access": ai.get("terminal_access", True),
                "max_terminal_timeout": ai.get("max_terminal_timeout", 30),
                "interval_minutes": config.get("daemon", {}).get("interval_minutes", 5),
                "daily_token_budget": config.get("agentic_config", {}).get("hard_limits", {}).get("daily_token_budget", 50000),
                "max_sub_agents": config.get("global_config", {}).get("max_sub_agents", 3)
            })
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def save_settings(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            config = {}
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    config = json.load(f)
            if "ai" not in config:
                config["ai"] = {}
            for key in ["provider", "api_key", "api_url", "model", "auto_commit", "auto_push", "terminal_access", "max_terminal_timeout"]:
                if key in body:
                    config["ai"][key] = body[key]
            if "interval_minutes" in body:
                if "daemon" not in config:
                    config["daemon"] = {}
                config["daemon"]["interval_minutes"] = int(body["interval_minutes"])
            if "daily_token_budget" in body:
                if "agentic_config" not in config:
                    config["agentic_config"] = {"hard_limits": {}}
                config["agentic_config"].setdefault("hard_limits", {})["daily_token_budget"] = int(body["daily_token_budget"])
            if "max_sub_agents" in body:
                config.setdefault("global_config", {})["max_sub_agents"] = int(body["max_sub_agents"])
            with open(CONFIG_FILE, 'w') as f:
                json.dump(config, f, indent=2)
            self.send_json({"success": True, "message": "Settings saved"})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def run_ai_terminal(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            command = body.get("command", "")
            timeout_sec = min(body.get("timeout", 30), 60)
            if not command:
                self.send_json({"error": "No command provided"}, 400)
                return
            result = subprocess.run(
                ["bash", f"{AUTONOMY_DIR}/lib/ai-engine.sh", "terminal", command, str(timeout_sec)],
                capture_output=True, text=True, timeout=timeout_sec + 5
            )
            self.send_json({
                "success": result.returncode == 0,
                "output": result.stdout[-4000:] if result.stdout else "",
                "exit_code": result.returncode,
                "command": command
            })
        except subprocess.TimeoutExpired:
            self.send_json({"success": False, "error": "Command timed out", "command": body.get("command", "")})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def serve_terminal_history(self):
        try:
            history_file = f"{AUTONOMY_DIR}/state/terminal_history.jsonl"
            entries = []
            if os.path.exists(history_file):
                with open(history_file, 'r') as f:
                    for line in f.readlines()[-20:]:
                        try: entries.append(json.loads(line.strip()))
                        except: pass
            self.send_json(entries)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def serve_memory(self):
        try:
            result = subprocess.run(["bash", f"{AUTONOMY_DIR}/lib/memory.sh", "show"],
                                    capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                self.send_json(json.loads(result.stdout.strip()))
            else:
                self.send_json({"facts": [], "decisions": [], "patterns": [], "blockers": [], "preferences": []})
        except:
            self.send_json({"facts": [], "decisions": [], "patterns": [], "blockers": [], "preferences": []})

    def store_memory(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            category = body.get("category", "facts")
            content = body.get("content", "")
            source = body.get("source", "web_ui")
            if not content:
                self.send_json({"error": "No content provided"}, 400)
                return
            result = subprocess.run(
                ["bash", f"{AUTONOMY_DIR}/lib/memory.sh", "store", category, content, source],
                capture_output=True, text=True, timeout=10
            )
            self.send_json({"success": result.returncode == 0, "message": result.stdout.strip()})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def serve_sub_agents(self):
        try:
            result = subprocess.run(["bash", f"{AUTONOMY_DIR}/lib/sub-agents.sh", "status"],
                                    capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and result.stdout.strip():
                status = json.loads(result.stdout.strip())
            else:
                status = {"active_agents": 0, "max_agents": 3, "available_slots": 3, "total_spawned": 0, "total_completed": 0}
            list_result = subprocess.run(["bash", f"{AUTONOMY_DIR}/lib/sub-agents.sh", "list", "active"],
                                         capture_output=True, text=True, timeout=10)
            agents = []
            if list_result.returncode == 0 and list_result.stdout.strip():
                try: agents = json.loads(list_result.stdout.strip())
                except: pass
            status["agents"] = agents
            self.send_json(status)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def spawn_sub_agent(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            parent = body.get("parent", "manual")
            name = body.get("name", "")
            desc = body.get("description", "")
            priority = body.get("priority", "normal")
            if not name or not desc:
                self.send_json({"error": "name and description required"}, 400)
                return
            result = subprocess.run(
                ["bash", f"{AUTONOMY_DIR}/lib/sub-agents.sh", "spawn", parent, name, desc, priority],
                capture_output=True, text=True, timeout=10
            )
            self.send_json({"success": result.returncode == 0, "message": result.stdout.strip()})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def ai_git_commit(self):
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            message = body.get("message", "")
            args = ["bash", f"{AUTONOMY_DIR}/lib/ai-engine.sh", "commit"]
            if message:
                args.append(message)
            result = subprocess.run(args, capture_output=True, text=True, timeout=30)
            self.send_json({"success": result.returncode == 0, "output": result.stdout.strip()})
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def handle_webhook(self):
        """Handle incoming webhook to fire event triggers"""
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            trigger_name = body.get("trigger", "")
            event_data = body.get("data", "")
            if not trigger_name:
                self.send_json({"error": "trigger name required"}, 400)
                return
            trigger_script = os.path.join(AUTONOMY_DIR, "lib", "event-triggers.sh")
            if not os.path.exists(trigger_script):
                self.send_json({"error": "event-triggers.sh not found"}, 404)
                return
            result = subprocess.run(
                ["bash", trigger_script, "fire", trigger_name, str(event_data)],
                capture_output=True, text=True, timeout=15
            )
            self.send_json({
                "success": result.returncode == 0,
                "message": result.stdout.strip(),
                "trigger": trigger_name
            })
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def handle_go(self):
        """Handle autonomy go from web UI"""
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            instruction = body.get("instruction", "")
            
            cmd = ["bash", f"{AUTONOMY_DIR}/autonomy", "go"]
            if instruction:
                cmd.append(instruction)
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            self.send_json({
                "success": result.returncode == 0,
                "output": result.stdout[-500:] if result.stdout else "",
                "message": "Autonomy GO activated" + (f": {instruction}" if instruction else "")
            })
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def control_daemon(self):
        """Control daemon start/stop/restart"""
        try:
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}
            action = body.get("action", "status")
            
            result = subprocess.run(
                ["bash", f"{AUTONOMY_DIR}/daemon.sh", action],
                capture_output=True, text=True, timeout=15
            )
            self.send_json({
                "success": result.returncode == 0,
                "output": result.stdout.strip(),
                "action": action
            })
        except Exception as e:
            self.send_json({"success": False, "error": str(e)}, 500)

    def serve_service_worker(self):
        """Serve Service Worker for PWA offline support — v3 network-first"""
        sw_js = '''
const CACHE_NAME = 'autonomy-v3';
const urlsToCache = ['/', '/manifest.json'];

self.addEventListener('install', event => {
    self.skipWaiting();
    event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(urlsToCache)));
});

self.addEventListener('activate', event => {
    event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))));
});

self.addEventListener('fetch', event => {
    event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
});
'''
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript")
        self.send_header("Cache-Control", "max-age=86400")
        self.end_headers()
        self.wfile.write(sw_js.encode())

    def serve_system_stats(self):
        """Serve real-time system statistics"""
        try:
            import subprocess
            
            # CPU usage
            cpu = subprocess.run(["top", "-bn1"], capture_output=True, text=True, timeout=2)
            cpu_line = [l for l in cpu.stdout.split('\n') if 'Cpu(s)' in l]
            cpu_pct = float(cpu_line[0].split('%')[0].split()[-1]) if cpu_line else 0
            
            # Memory
            mem = subprocess.run(["free", "-m"], capture_output=True, text=True, timeout=2)
            mem_lines = mem.stdout.split('\n')
            if len(mem_lines) > 1:
                mem_parts = mem_lines[1].split()
                mem_total = int(mem_parts[1])
                mem_used = int(mem_parts[2])
                mem_pct = (mem_used / mem_total * 100) if mem_total > 0 else 0
            else:
                mem_total = mem_used = mem_pct = 0
            
            # Disk
            disk = subprocess.run(["df", "-h", "/"], capture_output=True, text=True, timeout=2)
            disk_line = disk.stdout.split('\n')[1]
            disk_parts = disk_line.split()
            disk_size = disk_parts[1]
            disk_used = disk_parts[2]
            disk_pct = int(disk_parts[4].rstrip('%'))
            
            # Load
            with open('/proc/loadavg', 'r') as f:
                load = f.read().split()[0]
            
            self.send_json({
                "cpu": {"usage": cpu_pct},
                "memory": {"total": mem_total, "used": mem_used, "percent": mem_pct},
                "disk": {"size": disk_size, "used": disk_used, "percent": disk_pct},
                "load": load,
                "timestamp": datetime.now().isoformat()
            })
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

    def serve_capabilities(self):
        """Serve available capabilities list"""
        try:
            caps = {
                "vm": [
                    "process_list", "process_tree", "top_cpu", "top_memory",
                    "service_list", "service_status", "cpu", "memory", "disk",
                    "docker_ps", "docker_stats", "network_connections"
                ],
                "watcher": ["add", "remove", "list", "check", "daemon_start"],
                "diagnostic": ["health", "repair", "system"],
                "execute": ["retry", "async", "parallel", "timeout"],
                "log": ["query", "tail", "stats", "errors"],
                "plugin": ["list", "load", "create", "discover"]
            }
            self.send_json(caps)
        except Exception as e:
            self.send_json({"error": str(e)}, 500)

if __name__ == "__main__":
    port = int(os.environ.get("AUTONOMY_WEB_PORT", 8767))
    bind_addr = os.environ.get("AUTONOMY_WEB_BIND", "127.0.0.1")
    server = ThreadingHTTPServer((bind_addr, port), Handler)

    # Graceful shutdown on SIGTERM / SIGINT
    def _shutdown(signum, frame):
        print("\nShutting down web UI...")
        threading.Thread(target=server.shutdown).start()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    print(f"rar-file/autonomy dashboard at http://{bind_addr}:{port}")
    try:
        server.serve_forever()
    except Exception as e:
        print(f"Server error: {e}", file=sys.stderr)
    finally:
        server.server_close()
        print("Web UI stopped.")
