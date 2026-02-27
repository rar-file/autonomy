#!/bin/bash
# File Watcher Module — Auto-trigger on file changes
# Watches files and directories, triggers actions on change

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="$AUTONOMY_DIR/state"
WATCHERS_FILE="$STATE_DIR/watchers.json"

mkdir -p "$STATE_DIR"

# ── Watcher State Management ────────────────────────────────

init_watchers() {
    [[ -f "$WATCHERS_FILE" ]] || echo "[]" > "$WATCHERS_FILE"
}

get_watchers() {
    init_watchers
    cat "$WATCHERS_FILE"
}

save_watchers() {
    echo "$1" | jq . > "$WATCHERS_FILE"
}

# ── Core Watcher Operations ─────────────────────────────────

watcher_add() {
    local path="$1"
    local action="$2"
    local name="${3:-watcher-$(date +%s)}"
    
    [[ -z "$path" || -z "$action" ]] && {
        echo "Usage: watcher_add <path> <action> [name]"
        return 1
    }
    
    [[ -e "$path" ]] || {
        echo "Error: Path '$path' does not exist"
        return 1
    }
    
    local watchers
    watchers=$(get_watchers)
    
    # Check if watcher already exists for this path
    local existing
    existing=$(echo "$watchers" | jq -r "map(select(.path == \"$path\")) | length")
    
    if [[ "$existing" -gt 0 ]]; then
        echo "Watcher already exists for $path"
        return 1
    fi
    
    # Get initial checksum
    local checksum
    if [[ -d "$path" ]]; then
        checksum=$(find "$path" -type f -exec md5sum {} + 2>/dev/null | md5sum | cut -d' ' -f1)
    else
        checksum=$(md5sum "$path" 2>/dev/null | cut -d' ' -f1)
    fi
    
    local new_watcher
    new_watcher=$(jq -n \
        --arg name "$name" \
        --arg path "$path" \
        --arg action "$action" \
        --arg checksum "$checksum" \
        --arg created "$(date -Iseconds)" \
        '{name: $name, path: $path, action: $action, checksum: $checksum, created: $created, enabled: true, last_triggered: null}')
    
    watchers=$(echo "$watchers" | jq ". + [$new_watcher]")
    save_watchers "$watchers"
    
    echo "✓ Watcher '$name' added for $path"
}

watcher_remove() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: watcher_remove <name>"; return 1; }
    
    local watchers
    watchers=$(get_watchers)
    watchers=$(echo "$watchers" | jq "map(select(.name != \"$name\"))")
    save_watchers "$watchers"
    
    echo "✓ Watcher '$name' removed"
}

watcher_list() {
    local watchers
    watchers=$(get_watchers)
    
    echo "Active File Watchers:"
    echo "$watchers" | jq -r '.[] | "  • \(.name): \(.path) [\(.enabled | if . then "enabled" else "disabled" end)]"'
}

watcher_enable() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: watcher_enable <name>"; return 1; }
    
    local watchers
    watchers=$(get_watchers)
    watchers=$(echo "$watchers" | jq "map(if .name == \"$name\" then .enabled = true else . end)")
    save_watchers "$watchers"
    
    echo "✓ Watcher '$name' enabled"
}

watcher_disable() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: watcher_disable <name>"; return 1; }
    
    local watchers
    watchers=$(get_watchers)
    watchers=$(echo "$watchers" | jq "map(if .name == \"$name\" then .enabled = false else . end)")
    save_watchers "$watchers"
    
    echo "✓ Watcher '$name' disabled"
}

# ── Check for Changes ───────────────────────────────────────

watcher_check() {
    local name="${1:-}"
    local triggered=()
    
    local watchers
    watchers=$(get_watchers)
    
    # Get list of watchers to check
    local to_check
    if [[ -n "$name" ]]; then
        to_check=$(echo "$watchers" | jq -r "map(select(.name == \"$name\" and .enabled == true))")
    else
        to_check=$(echo "$watchers" | jq -r 'map(select(.enabled == true))')
    fi
    
    local count
    count=$(echo "$to_check" | jq 'length')
    [[ "$count" -eq 0 ]] && { echo "No watchers to check"; return 0; }
    
    # Check each watcher
    for ((i=0; i<count; i++)); do
        local w_path w_action w_name w_checksum new_checksum
        
        w_path=$(echo "$to_check" | jq -r ".[$i].path")
        w_action=$(echo "$to_check" | jq -r ".[$i].action")
        w_name=$(echo "$to_check" | jq -r ".[$i].name")
        w_checksum=$(echo "$to_check" | jq -r ".[$i].checksum")
        
        # Calculate new checksum
        if [[ -d "$w_path" ]]; then
            new_checksum=$(find "$w_path" -type f -exec md5sum {} + 2>/dev/null | md5sum | cut -d' ' -f1)
        else
            new_checksum=$(md5sum "$w_path" 2>/dev/null | cut -d' ' -f1)
        fi
        
        if [[ "$new_checksum" != "$w_checksum" ]]; then
            # Change detected!
            triggered+=("$w_name")
            
            # Update checksum
            watchers=$(echo "$watchers" | jq \
                "map(if .name == \"$w_name\" then .checksum = \"$new_checksum\" | .last_triggered = \"$(date -Iseconds)\" else . end)")
            
            # Log the trigger
            echo "$(date -Iseconds) WATCHER_TRIGGERED name=$w_name path=$w_path" >> "$AUTONOMY_DIR/logs/watchers.log"
            
            # Execute action
            echo "[$w_name] Change detected in $w_path"
            echo "[$w_name] Executing: $w_action"
            eval "$w_action" 2>&1 | while read line; do echo "[$w_name] $line"; done
            echo ""
        fi
    done
    
    # Save updated watchers
    save_watchers "$watchers"
    
    if [[ ${#triggered[@]} -eq 0 ]]; then
        echo "No changes detected"
    else
        echo "Triggered watchers: ${triggered[*]}"
    fi
}

# ── Auto-watch Common Patterns ──────────────────────────────

watcher_setup_git() {
    local repo_path="${1:-.}"
    watcher_add "$repo_path/.git" "autonomy work 'Git changes detected in $repo_path'" "git-$repo_path"
}

watcher_setup_config() {
    local config_path="${1:-$AUTONOMY_DIR/config.json}"
    watcher_add "$config_path" "echo 'Config file changed - reloading'" "config-watcher"
}

watcher_setup_logs() {
    local log_path="${1:-$AUTONOMY_DIR/logs}"
    watcher_add "$log_path" "autonomy work 'New log activity detected - analyze'" "log-watcher"
}

# ── Watch Daemon ────────────────────────────────────────────

watcher_daemon_start() {
    local interval="${1:-30}"
    
    # Check if already running
    if [[ -f "$STATE_DIR/watcher-daemon.pid" ]]; then
        local pid
        pid=$(cat "$STATE_DIR/watcher-daemon.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Watcher daemon already running (PID: $pid)"
            return 1
        fi
    fi
    
    # Start daemon
    (
        while true; do
            watcher_check >/dev/null 2>&1
            sleep "$interval"
        done
    ) &
    
    echo $! > "$STATE_DIR/watcher-daemon.pid"
    echo "✓ Watcher daemon started (PID: $!, interval: ${interval}s)"
}

watcher_daemon_stop() {
    if [[ -f "$STATE_DIR/watcher-daemon.pid" ]]; then
        local pid
        pid=$(cat "$STATE_DIR/watcher-daemon.pid")
        kill "$pid" 2>/dev/null && echo "✓ Watcher daemon stopped" || echo "Daemon not running"
        rm -f "$STATE_DIR/watcher-daemon.pid"
    else
        echo "No watcher daemon running"
    fi
}

watcher_daemon_status() {
    if [[ -f "$STATE_DIR/watcher-daemon.pid" ]]; then
        local pid
        pid=$(cat "$STATE_DIR/watcher-daemon.pid")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Watcher daemon: RUNNING (PID: $pid)"
        else
            echo "Watcher daemon: STOPPED (stale PID file)"
            rm -f "$STATE_DIR/watcher-daemon.pid"
        fi
    else
        echo "Watcher daemon: STOPPED"
    fi
}

# ── Command Router ──────────────────────────────────────────

case "${1:-}" in
    add) watcher_add "$2" "$3" "$4" ;;
    remove) watcher_remove "$2" ;;
    list) watcher_list ;;
    enable) watcher_enable "$2" ;;
    disable) watcher_disable "$2" ;;
    check) watcher_check "$2" ;;
    setup_git) watcher_setup_git "$2" ;;
    setup_config) watcher_setup_config "$2" ;;
    daemon_start) watcher_daemon_start "$2" ;;
    daemon_stop) watcher_daemon_stop ;;
    daemon_status) watcher_daemon_status ;;
    *)
        echo "File Watcher Module"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  add <path> <action> [name]     - Add a file watcher"
        echo "  remove <name>                  - Remove a watcher"
        echo "  list                           - List all watchers"
        echo "  enable <name>                  - Enable a watcher"
        echo "  disable <name>                 - Disable a watcher"
        echo "  check [name]                   - Check for changes (all or specific)"
        echo "  setup_git [repo_path]          - Auto-watch git repo"
        echo "  setup_config [config_path]     - Auto-watch config file"
        echo "  daemon_start [interval]        - Start background watcher (default 30s)"
        echo "  daemon_stop                    - Stop background watcher"
        echo "  daemon_status                  - Check daemon status"
        ;;
esac
