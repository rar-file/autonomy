#!/usr/bin/env python3
"""
Autonomy File Watcher
Monitors files/directories and triggers actions on changes.
Uses watchdog library for cross-platform file system events.
"""

import sys
import os
import time
import json
import subprocess
from pathlib import Path
from datetime import datetime

try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
except ImportError:
    print("Error: watchdog not installed. Run: pip install watchdog")
    sys.exit(1)

AUTONOMY_DIR = Path(__file__).parent
WATCHERS_FILE = AUTONOMY_DIR / "watchers.json"
LOGS_DIR = AUTONOMY_DIR / "logs"


class AutonomyEventHandler(FileSystemEventHandler):
    """Handle file system events and trigger configured actions."""

    def __init__(self, watch_path, command, debounce_seconds=2):
        super().__init__()
        self.watch_path = watch_path
        self.command = command
        self.last_trigger = 0
        self.debounce_seconds = debounce_seconds

    def on_modified(self, event):
        if event.is_directory:
            return
        self._handle(event)

    def on_created(self, event):
        if event.is_directory:
            return
        self._handle(event)

    def _handle(self, event):
        """Debounce and handle a file event."""
        now = time.time()
        if now - self.last_trigger < self.debounce_seconds:
            return
        self.last_trigger = now

        self._log_event(event)
        self._execute_command(event)

    def _log_event(self, event):
        """Log the file system event."""
        LOGS_DIR.mkdir(exist_ok=True)
        log_file = LOGS_DIR / "watcher.log"
        entry = {
            "timestamp": datetime.now().isoformat(),
            "event_type": event.event_type,
            "src_path": str(event.src_path),
            "watch_path": str(self.watch_path),
            "command": self.command,
        }
        with open(log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
        print(f"[watcher] {event.event_type}: {event.src_path}")

    def _execute_command(self, event):
        """Execute the configured command with placeholder substitution."""
        cmd = self.command.replace("{file}", str(event.src_path))
        cmd = cmd.replace("{event}", event.event_type)

        try:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, timeout=30
            )
            if result.returncode != 0:
                print(f"[watcher] Command failed: {result.stderr[:200]}")
        except subprocess.TimeoutExpired:
            print(f"[watcher] Command timed out: {cmd}")
        except Exception as e:
            print(f"[watcher] Error: {e}")


def load_watchers():
    """Load watcher configurations from watchers.json."""
    if not WATCHERS_FILE.exists():
        return []
    try:
        with open(WATCHERS_FILE) as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return []


def add_watcher(path, command):
    """Add a new file watcher configuration."""
    watchers = load_watchers()
    resolved = str(Path(path).resolve())
    watchers.append(
        {
            "path": resolved,
            "command": command,
            "created_at": datetime.now().isoformat(),
            "enabled": True,
        }
    )
    with open(WATCHERS_FILE, "w") as f:
        json.dump(watchers, f, indent=2)
    print(f"[watcher] Added: {resolved} → {command}")


def remove_watcher(index):
    """Remove a watcher by index."""
    watchers = load_watchers()
    if 0 <= index < len(watchers):
        removed = watchers.pop(index)
        with open(WATCHERS_FILE, "w") as f:
            json.dump(watchers, f, indent=2)
        print(f"[watcher] Removed: {removed['path']}")
    else:
        print(f"[watcher] Invalid index: {index} (have {len(watchers)} watchers)")


def list_watchers():
    """List all configured watchers."""
    watchers = load_watchers()
    if not watchers:
        print("  No watchers configured")
        return
    for i, w in enumerate(watchers):
        status = "✓" if w.get("enabled", True) else "✗"
        print(f"  [{i}] {status} {w['path']} → {w['command']}")


def start_watchers():
    """Start all enabled watchers (blocking)."""
    # Read debounce from config
    debounce = 2
    config_file = AUTONOMY_DIR / "config.json"
    if config_file.exists():
        try:
            with open(config_file) as f:
                cfg = json.load(f)
            debounce = cfg.get("watcher", {}).get("debounce_seconds", 2)
        except Exception:
            pass

    watchers = load_watchers()
    active = [w for w in watchers if w.get("enabled", True)]

    if not active:
        print("[watcher] No active watchers configured")
        print("  Add one: autonomy watcher add <path> <command>")
        return

    observer = Observer()
    started = 0
    for w in active:
        path = w["path"]
        if not Path(path).exists():
            print(f"[watcher] Warning: {path} does not exist, skipping")
            continue
        handler = AutonomyEventHandler(path, w["command"], debounce)
        observer.schedule(handler, path, recursive=True)
        print(f"[watcher] Watching: {path} → {w['command']}")
        started += 1

    if started == 0:
        print("[watcher] No valid watch paths found")
        return

    observer.start()
    print(f"[watcher] Started {started} watcher(s). Press Ctrl+C to stop.")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        print("\n[watcher] Stopped")
    observer.join()


def main():
    if len(sys.argv) < 2:
        print("Usage: watcher.py {start|add|remove|list}")
        print("")
        print("  start              Start all watchers (foreground)")
        print("  add <path> <cmd>   Add a file watcher")
        print("  remove <index>     Remove watcher by index")
        print("  list               List configured watchers")
        return

    cmd = sys.argv[1]

    if cmd == "start":
        start_watchers()
    elif cmd == "add":
        if len(sys.argv) < 4:
            print("Usage: watcher.py add <path> <command>")
            return
        add_watcher(sys.argv[2], " ".join(sys.argv[3:]))
    elif cmd == "remove":
        if len(sys.argv) < 3:
            print("Usage: watcher.py remove <index>")
            return
        remove_watcher(int(sys.argv[2]))
    elif cmd == "list":
        list_watchers()
    else:
        print(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()
