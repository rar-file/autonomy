#!/usr/bin/env python3
"""
Autonomy Heartbeat System - Phase 1 Implementation
Integrates with OpenClaw's heartbeat to provide true AI autonomy
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
import subprocess

# Paths
AUTONOMY_DIR = Path("/root/.openclaw/workspace/autonomy-merge")
TASKS_DIR = AUTONOMY_DIR / "tasks"
LOGS_DIR = AUTONOMY_DIR / "logs"
MEMORY_DIR = Path("/root/.openclaw/workspace/memory")

def log(message, level="info"):
    """Log to autonomy log file"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] [{level.upper()}] {message}"
    
    # Print for visibility
    print(log_entry)
    
    # Write to log file
    LOGS_DIR.mkdir(exist_ok=True)
    log_file = LOGS_DIR / f"heartbeat-{datetime.now().strftime('%Y%m%d')}.log"
    with open(log_file, 'a') as f:
        f.write(log_entry + "\n")

def get_web_ui_status():
    """Fetch status from autonomy web UI"""
    try:
        result = subprocess.run(
            ["curl", "-s", "http://localhost:8767/api/status"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception as e:
        log(f"Failed to fetch web UI status: {e}", "error")
    return None

def check_system_health():
    """Goal 1: Monitor system health"""
    log("Checking system health...")
    
    status = get_web_ui_status()
    if not status:
        log("Web UI not responding", "warning")
        return []
    
    health = status.get('health', {})
    alerts = []
    
    # Check thresholds
    disk = health.get('disk', '0%').replace('%', '')
    cpu = health.get('cpu', '0%').replace('%', '')
    memory = health.get('memory', '0%').replace('%', '')
    
    try:
        if int(disk) > 85:
            alerts.append({
                'type': 'warning',
                'title': 'Disk Space Low',
                'message': f'Disk usage at {disk}%. Consider cleaning up old files.',
                'action': 'clean_disk'
            })
        
        if int(cpu) > 80:
            alerts.append({
                'type': 'warning',
                'title': 'High CPU Usage',
                'message': f'CPU at {cpu}%. Check running processes.',
                'action': 'check_processes'
            })
            
        if int(memory) > 90:
            alerts.append({
                'type': 'critical',
                'title': 'Memory Critical',
                'message': f'Memory at {memory}%. System may become unstable.',
                'action': 'restart_services'
            })
    except ValueError:
        pass
    
    for alert in alerts:
        log(f"Health alert: {alert['title']} - {alert['message']}", alert['type'])
    
    return alerts

def get_pending_tasks():
    """Get all pending tasks from autonomy"""
    tasks = []
    if TASKS_DIR.exists():
        for task_file in TASKS_DIR.glob("*.json"):
            try:
                with open(task_file) as f:
                    task = json.load(f)
                    task['file'] = task_file.name
                    tasks.append(task)
            except Exception as e:
                log(f"Failed to read task {task_file}: {e}", "error")
    return tasks

def check_stalled_tasks():
    """Find tasks that have been in-progress too long"""
    log("Checking for stalled tasks...")
    
    tasks = get_pending_tasks()
    stalled = []
    
    for task in tasks:
        if task.get('status') == 'in-progress':
            updated = task.get('updated_at', task.get('created_at'))
            if updated:
                try:
                    updated_time = datetime.fromisoformat(updated)
                    if datetime.now() - updated_time > timedelta(hours=24):
                        stalled.append(task)
                except:
                    pass
    
    if stalled:
        log(f"Found {len(stalled)} stalled tasks", "warning")
        for task in stalled:
            log(f"  - {task.get('name', 'unnamed')}: stuck for >24h")
    
    return stalled

def check_github_status():
    """Check GitHub for CI failures, reviews, etc."""
    log("Checking GitHub status...")
    
    alerts = []
    
    try:
        # Check for CI failures
        result = subprocess.run(
            ["gh", "pr", "list", "--state", "open", "--json", "number,title,headRefName"],
            capture_output=True, text=True, timeout=15
        )
        
        if result.returncode == 0:
            prs = json.loads(result.stdout)
            
            # Check each PR's CI status
            for pr in prs[:5]:  # Check first 5
                ci_result = subprocess.run(
                    ["gh", "pr", "checks", str(pr['number']), "--json", "state"],
                    capture_output=True, text=True, timeout=10
                )
                if ci_result.returncode == 0:
                    checks = json.loads(ci_result.stdout)
                    failed = [c for c in checks if c.get('state') == 'FAILURE']
                    if failed:
                        alerts.append({
                            'type': 'error',
                            'title': f"CI Failed on PR #{pr['number']}",
                            'message': f"'{pr['title']}' has failing checks",
                            'action': 'fix_ci'
                        })
    except Exception as e:
        log(f"GitHub check failed: {e}", "error")
    
    return alerts

def self_review_codebase():
    """Every 5th heartbeat: scan for improvements"""
    log("Running self-review...")
    
    findings = []
    
    # Scan for TODO/FIXME
    try:
        result = subprocess.run(
            ["grep", "-r", "-n", "-E", "TODO|FIXME|XXX", 
             str(AUTONOMY_DIR / "web_ui.py"),
             str(AUTONOMY_DIR / "templates"),
             "--include=*.py", "--include=*.html", "--include=*.js"],
            capture_output=True, text=True, timeout=30
        )
        
        if result.stdout:
            lines = result.stdout.strip().split('\n')
            for line in lines[:10]:  # Limit to first 10
                if line:
                    findings.append({
                        'type': 'todo',
                        'content': line.strip()
                    })
    except Exception as e:
        log(f"Self-review failed: {e}", "error")
    
    if findings:
        log(f"Found {len(findings)} TODOs/FIXMEs")
    
    return findings

def should_run_background_work():
    """Check if safe to run background tasks"""
    try:
        # Check if user idle (using xprintidle if available)
        result = subprocess.run(
            ["xprintidle"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            idle_ms = int(result.stdout.strip())
            idle_min = idle_ms / 1000 / 60
            if idle_min > 10:
                return True
    except:
        pass
    
    # Check CPU usage
    try:
        result = subprocess.run(
            ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            cpu = float(result.stdout.strip())
            if cpu < 30:
                return True
    except:
        pass
    
    return False

def run_background_tasks():
    """Run low-priority background work"""
    if not should_run_background_work():
        return
    
    log("Running background tasks...")
    
    # Task 1: Clean old logs
    try:
        logs = list(LOGS_DIR.glob("*.log"))
        old_logs = [l for l in logs if l.stat().st_mtime < (datetime.now() - timedelta(days=7)).timestamp()]
        for log_file in old_logs[:5]:  # Delete max 5 per run
            log_file.unlink()
            log(f"Cleaned old log: {log_file.name}")
    except Exception as e:
        log(f"Log cleanup failed: {e}", "error")
    
    # Task 2: Update file index (placeholder)
    log("File index update would run here")

def create_task(name, description, priority="medium"):
    """Create a new autonomy task"""
    task = {
        "name": name,
        "description": description,
        "status": "pending",
        "priority": priority,
        "created_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
        "attempts": 0
    }
    
    task_file = TASKS_DIR / f"{name.replace(' ', '_').lower()}.json"
    TASKS_DIR.mkdir(exist_ok=True)
    
    with open(task_file, 'w') as f:
        json.dump(task, f, indent=2)
    
    log(f"Created task: {name} ({priority})")
    return task

def is_monday_morning():
    """Check if it's Monday between 9-11am"""
    now = datetime.now()
    return now.weekday() == 0 and 9 <= now.hour <= 11

def check_predictive_tasks():
    """Create predictive tasks based on patterns"""
    log("Checking predictive tasks...")
    
    tasks_created = []
    
    # Monday morning: weekly review
    if is_monday_morning():
        # Check if already exists
        existing = [t for t in get_pending_tasks() if 'weekly review' in t.get('name', '').lower()]
        if not existing:
            task = create_task(
                "Weekly Review",
                "Review priorities for the week, check pending tasks, plan work",
                "medium"
            )
            tasks_created.append(task)
    
    # Check for stale tasks
    stale = check_stalled_tasks()
    for task in stale:
        # Create reminder task
        reminder = create_task(
            f"Resume: {task.get('name', 'stalled task')}",
            f"Task has been in-progress for >24h. Needs attention or should be marked complete.",
            "high" if task.get('priority') == 'critical' else "medium"
        )
        tasks_created.append(reminder)
    
    return tasks_created

def generate_summary():
    """Generate summary of autonomy activity"""
    tasks = get_pending_tasks()
    pending = len([t for t in tasks if t.get('status') == 'pending'])
    in_progress = len([t for t in tasks if t.get('status') == 'in-progress'])
    completed_today = len([
        t for t in tasks 
        if t.get('status') == 'completed' 
        and t.get('updated_at', '').startswith(datetime.now().strftime('%Y-%m-%d'))
    ])
    
    summary = {
        'timestamp': datetime.now().isoformat(),
        'pending_tasks': pending,
        'in_progress_tasks': in_progress,
        'completed_today': completed_today,
        'total_tasks': len(tasks)
    }
    
    return summary

def main():
    """Main heartbeat entry point"""
    log("=" * 50)
    log("AUTONOMY HEARTBEAT - Phase 1")
    log("=" * 50)
    
    heartbeat_count = 0
    
    try:
        # 1. System Health Check
        health_alerts = check_system_health()
        for alert in health_alerts:
            if alert['type'] == 'critical':
                create_task(
                    f"URGENT: {alert['title']}",
                    alert['message'],
                    'critical'
                )
        
        # 2. Review Pending Tasks
        pending = get_pending_tasks()
        log(f"Found {len(pending)} total tasks")
        
        # 3. Check Stalled Tasks
        stalled = check_stalled_tasks()
        
        # 4. GitHub Status
        gh_alerts = check_github_status()
        for alert in gh_alerts:
            create_task(
                alert['title'],
                alert['message'],
                'high' if alert['type'] == 'error' else 'medium'
            )
        
        # 5. Self-Review (every 5th heartbeat)
        heartbeat_count += 1
        if heartbeat_count % 5 == 0:
            findings = self_review_codebase()
            for finding in findings[:3]:  # Max 3 tasks from self-review
                create_task(
                    f"Code Improvement: {finding['content'][:50]}...",
                    f"Self-review found: {finding['content']}",
                    'low'
                )
        
        # 6. Predictive Tasks
        predictive = check_predictive_tasks()
        
        # 7. Background Work (if idle)
        run_background_tasks()
        
        # 8. Generate Summary
        summary = generate_summary()
        log(f"Summary: {summary['pending_tasks']} pending, {summary['in_progress_tasks']} in-progress, {summary['completed_today']} completed today")
        
        log("Heartbeat complete")
        
    except Exception as e:
        log(f"Heartbeat failed: {e}", "error")
        raise

if __name__ == "__main__":
    main()
