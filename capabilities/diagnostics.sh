#!/bin/bash
# Diagnostic & Self-Repair Module
# Self-diagnosis, health checks, and auto-repair capabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
DIAGNOSTICS_DIR="$AUTONOMY_DIR/diagnostics"
HEALTH_LOG="$AUTONOMY_DIR/logs/health.jsonl"

mkdir -p "$DIAGNOSTICS_DIR"

# ── Health Checks ───────────────────────────────────────────

check_dependencies() {
    local missing=()
    local deps=("bash" "jq" "python3" "git" "curl")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo '{"check": "dependencies", "status": "ok", "message": "All dependencies present"}'
    else
        echo "{\"check\": \"dependencies\", \"status\": \"fail\", \"message\": \"Missing: ${missing[*]}\"}"
    fi
}

check_config() {
    local config_file="$AUTONOMY_DIR/config.json"
    
    if [[ ! -f "$config_file" ]]; then
        echo '{"check": "config", "status": "fail", "message": "config.json not found"}'
        return
    fi
    
    if ! jq empty "$config_file" 2>/dev/null; then
        echo '{"check": "config", "status": "fail", "message": "config.json is invalid JSON"}'
        return
    fi
    
    echo '{"check": "config", "status": "ok", "message": "Configuration valid"}'
}

check_directories() {
    local dirs=("tasks" "logs" "state" "agents" "tools")
    local missing=()
    
    for dir in "${dirs[@]}"; do
        [[ -d "$AUTONOMY_DIR/$dir" ]] || missing+=("$dir")
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo '{"check": "directories", "status": "ok", "message": "All required directories present"}'
    else
        echo "{\"check\": \"directories\", \"status\": \"fail\", \"message\": \"Missing directories: ${missing[*]}\"}"
    fi
}

check_permissions() {
    local issues=()
    
    # Check if autonomy script is executable
    [[ -x "$AUTONOMY_DIR/autonomy" ]] || issues+=("autonomy not executable")
    
    # Check if lib files are readable
    for lib in "$AUTONOMY_DIR/lib/"*.sh; do
        [[ -r "$lib" ]] || issues+=("$(basename "$lib") not readable")
    done
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        echo '{"check": "permissions", "status": "ok", "message": "All permissions correct"}'
    else
        echo "{\"check\": \"permissions\", \"status\": \"warn\", \"message\": \"${issues[*]}\"}"
    fi
}

check_disk_space() {
    local usage
    usage=$(df -h "$AUTONOMY_DIR" | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [[ "$usage" -gt 90 ]]; then
        echo "{\"check\": \"disk_space\", \"status\": \"critical\", \"message\": \"Disk usage at ${usage}%\"}"
    elif [[ "$usage" -gt 80 ]]; then
        echo "{\"check\": \"disk_space\", \"status\": \"warn\", \"message\": \"Disk usage at ${usage}%\"}"
    else
        echo "{\"check\": \"disk_space\", \"status\": \"ok\", \"message\": \"Disk usage at ${usage}%\"}"
    fi
}

check_log_size() {
    local log_dir="$AUTONOMY_DIR/logs"
    local size
    
    if [[ -d "$log_dir" ]]; then
        size=$(du -sm "$log_dir" 2>/dev/null | cut -f1)
        if [[ "$size" -gt 100 ]]; then
            echo "{\"check\": \"log_size\", \"status\": \"warn\", \"message\": \"Logs using ${size}MB\"}"
        else
            echo "{\"check\": \"log_size\", \"status\": \"ok\", \"message\": \"Logs using ${size}MB\"}"
        fi
    else
        echo '{"check": "log_size", "status": "ok", "message": "No logs directory"}'
    fi
}

check_daemon() {
    local pid_file="$AUTONOMY_DIR/state/daemon.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "{\"check\": \"daemon\", \"status\": \"ok\", \"message\": \"Daemon running (PID: $pid)\"}"
        else
            echo '{"check": "daemon", "status": "warn", "message": "Stale daemon PID file"}'
        fi
    else
        echo '{"check": "daemon", "status": "ok", "message": "No daemon running"}'
    fi
}

check_web_ui() {
    if curl -s http://localhost:8767/health 2>/dev/null | grep -q "ok"; then
        echo '{"check": "web_ui", "status": "ok", "message": "Web UI responding"}'
    else
        echo '{"check": "web_ui", "status": "warn", "message": "Web UI not responding"}'
    fi
}

check_git_repo() {
    if [[ -d "$AUTONOMY_DIR/.git" ]]; then
        local branch
        branch=$(cd "$AUTONOMY_DIR" && git branch --show-current 2>/dev/null)
        echo "{\"check\": \"git_repo\", \"status\": \"ok\", \"message\": \"Git repo on branch: $branch\"}"
    else
        echo '{"check": "git_repo", "status": "ok", "message": "Not a git repository"}'
    fi
}

# ── Run All Health Checks ───────────────────────────────────

diagnostic_health_check() {
    local results=()
    
    results+=("$(check_dependencies)")
    results+=("$(check_config)")
    results+=("$(check_directories)")
    results+=("$(check_permissions)")
    results+=("$(check_disk_space)")
    results+=("$(check_log_size)")
    results+=("$(check_daemon)")
    results+=("$(check_web_ui)")
    results+=("$(check_git_repo)")
    
    # Convert to JSON array
    local json_output
    json_output=$(printf '%s\n' "${results[@]}" | jq -s '.')
    
    # Log results
    echo "{\"timestamp\": \"$(date -Iseconds)\", \"health_check\": $json_output}" >> "$HEALTH_LOG"
    
    # Output summary
    local ok_count warn_count fail_count
    ok_count=$(echo "$json_output" | jq '[.[] | select(.status == "ok")] | length')
    warn_count=$(echo "$json_output" | jq '[.[] | select(.status == "warn")] | length')
    fail_count=$(echo "$json_output" | jq '[.[] | select(.status == "fail" or .status == "critical")] | length')
    
    echo "Health Check Summary:"
    echo "  ✓ OK: $ok_count"
    echo "  ⚠ Warn: $warn_count"
    echo "  ✗ Fail: $fail_count"
    echo ""
    
    # Show issues
    if [[ "$warn_count" -gt 0 || "$fail_count" -gt 0 ]]; then
        echo "Issues found:"
        echo "$json_output" | jq -r '.[] | select(.status != "ok") | "  [\(.status)] \(.check): \(.message)"'
    fi
    
    # Return overall status
    if [[ "$fail_count" -gt 0 ]]; then
        return 1
    elif [[ "$warn_count" -gt 0 ]]; then
        return 2
    else
        return 0
    fi
}

# ── Self-Repair Functions ───────────────────────────────────

repair_permissions() {
    echo "Repairing permissions..."
    chmod +x "$AUTONOMY_DIR/autonomy"
    chmod +x "$AUTONOMY_DIR/lib/"*.sh 2>/dev/null
    chmod +x "$AUTONOMY_DIR/capabilities/"*.sh 2>/dev/null
    chmod +x "$AUTONOMY_DIR/checks/"*.sh 2>/dev/null
    echo "✓ Permissions repaired"
}

repair_directories() {
    echo "Creating missing directories..."
    mkdir -p "$AUTONOMY_DIR/"{tasks,logs,state,agents,tools,capabilities,integrations,watchers,diagnostics}
    echo "✓ Directories created"
}

repair_config() {
    echo "Restoring config from example..."
    if [[ -f "$AUTONOMY_DIR/config.example.json" ]]; then
        cp "$AUTONOMY_DIR/config.example.json" "$AUTONOMY_DIR/config.json"
        echo "✓ Config restored from example"
    else
        echo "✗ No config.example.json found"
    fi
}

repair_stale_pids() {
    echo "Cleaning stale PID files..."
    local pid_files=("$AUTONOMY_DIR/state/daemon.pid" "$AUTONOMY_DIR/state/watcher-daemon.pid")
    
    for pid_file in "${pid_files[@]}"; do
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            if ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$pid_file"
                echo "  ✓ Removed stale: $pid_file"
            fi
        fi
    done
}

repair_logs() {
    echo "Rotating large logs..."
    local log_dir="$AUTONOMY_DIR/logs"
    
    for log in "$log_dir/"*.jsonl; do
        [[ -f "$log" ]] || continue
        local size
        size=$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null)
        
        if [[ "$size" -gt 10485760 ]]; then  # 10MB
            mv "$log" "${log}.old"
            echo "  ✓ Rotated: $(basename "$log")"
        fi
    done
}

repair_all() {
    echo "Running auto-repair..."
    echo ""
    
    local health_json
    health_json=$(diagnostic_health_check 2>/dev/null)
    
    # Check what needs repairing
    if echo "$health_json" | grep -q "permissions.*warn"; then
        repair_permissions
    fi
    
    if echo "$health_json" | grep -q "directories.*fail"; then
        repair_directories
    fi
    
    if echo "$health_json" | grep -q "config.*fail"; then
        repair_config
    fi
    
    repair_stale_pids
    
    if echo "$health_json" | grep -q "log_size.*warn"; then
        repair_logs
    fi
    
    echo ""
    echo "Auto-repair complete. Re-checking health..."
    diagnostic_health_check
}

# ── System Information ──────────────────────────────────────

diagnostic_system_info() {
    echo "System Information:"
    echo "  OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || uname -o)"
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo "  Hostname: $(hostname)"
    echo ""
    echo "Resource Usage:"
    echo "  CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
    echo "  Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
    echo "  Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
}

# ── Command Router ──────────────────────────────────────────

case "${1:-}" in
    health) diagnostic_health_check ;;
    repair) repair_all ;;
    repair_permissions) repair_permissions ;;
    repair_dirs) repair_directories ;;
    repair_config) repair_config ;;
    repair_logs) repair_logs ;;
    system) diagnostic_system_info ;;
    *)
        echo "Diagnostic & Self-Repair Module"
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  health                    - Run full health check"
        echo "  repair                    - Auto-repair all issues"
        echo "  repair_permissions        - Fix file permissions"
        echo "  repair_dirs               - Create missing directories"
        echo "  repair_config             - Restore config from example"
        echo "  repair_logs               - Rotate large log files"
        echo "  system                    - Show system information"
        ;;
esac
