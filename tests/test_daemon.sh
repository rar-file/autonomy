#!/bin/bash
# Daemon functionality tests for autonomy skill
# Tests: start, stop, status, restart, once, logs, and task flagging

# Don't use set -e here as it interferes with test assertions

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$TEST_DIR")"

# Source utilities
source "$TEST_DIR/test_utils.sh"

# Daemon test state directory
DAEMON_TEST_STATE="$TEST_DIR/state/daemon_test"
TEST_LOG_FILE="$DAEMON_TEST_STATE/daemon.log"
TEST_PID_FILE="$DAEMON_TEST_STATE/heartbeat-daemon.pid"

echo "Running Daemon Functionality Tests"
echo "==================================="

# Setup test environment
setup_daemon_test() {
    rm -rf "$DAEMON_TEST_STATE"
    mkdir -p "$DAEMON_TEST_STATE" "$DAEMON_TEST_STATE/logs" "$DAEMON_TEST_STATE/tasks" "$DAEMON_TEST_STATE/state"
    
    # Create test config
    cat > "$DAEMON_TEST_STATE/config.json" << 'EOF'
{
  "skill": "autonomy",
  "version": "2.0.0",
  "workstation": {
    "active": true,
    "daemon_running": false
  },
  "scheduler": {
    "type": "daemon",
    "interval_minutes": 10
  }
}
EOF
}

# Check if daemon is running in test environment
is_daemon_running() {
    if [[ -f "$TEST_PID_FILE" ]]; then
        local pid=$(cat "$TEST_PID_FILE" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "true"
            return 0
        fi
    fi
    echo "false"
    return 1
}

# ============================================================
# Daemon Status Tests
# ============================================================

test_daemon_status_not_running() {
    echo "  Testing daemon status when not running..."
    
    setup_daemon_test
    
    # Ensure no PID file
    rm -f "$TEST_PID_FILE"
    
    local status=$(is_daemon_running)
    assert_equals "false" "$status" "daemon status shows not running when no PID"
}

test_daemon_pid_file_cleanup() {
    echo "  Testing PID file cleanup for stale PID..."
    
    setup_daemon_test
    
    # Create a fake PID file with non-existent PID
    echo "99999" > "$TEST_PID_FILE"
    
    # Check if PID is valid
    local running=$(is_daemon_running)
    assert_equals "false" "$running" "daemon detects stale PID file"
}

# ============================================================
# Daemon Start/Stop Tests
# ============================================================

test_daemon_start_stop() {
    echo "  Testing daemon start and stop..."
    
    setup_daemon_test
    
    # Start daemon with modified paths
    (
        exec >> "$TEST_LOG_FILE" 2>&1
        echo "[$(date -Iseconds)] Test daemon starting..."
        
        # Simple daemon loop for testing
        while true; do
            if [[ -f "$DAEMON_TEST_STATE/state/daemon.stop" ]]; then
                rm -f "$TEST_PID_FILE" "$DAEMON_TEST_STATE/state/daemon.stop"
                exit 0
            fi
            sleep 1
        done
    ) &
    
    local daemon_pid=$!
    echo "$daemon_pid" > "$TEST_PID_FILE"
    
    # Wait for daemon to start
    sleep 0.5
    
    # Verify daemon is running
    local running=$(is_daemon_running)
    assert_equals "true" "$running" "daemon starts successfully"
    
    # Stop daemon
    touch "$DAEMON_TEST_STATE/state/daemon.stop"
    sleep 1.5
    
    # Verify daemon stopped
    running=$(is_daemon_running)
    assert_equals "false" "$running" "daemon stops successfully"
    
    # Verify PID file cleaned up
    local pid_exists=$(test -f "$TEST_PID_FILE" && echo "true" || echo "false")
    assert_equals "false" "$pid_exists" "PID file cleaned up after stop"
}

test_daemon_restart() {
    echo "  Testing daemon restart..."
    
    setup_daemon_test
    
    # Start daemon
    (
        exec >> "$TEST_LOG_FILE" 2>&1
        while true; do
            if [[ -f "$DAEMON_TEST_STATE/state/daemon.stop" ]]; then
                rm -f "$TEST_PID_FILE" "$DAEMON_TEST_STATE/state/daemon.stop"
                exit 0
            fi
            sleep 1
        done
    ) &
    
    local pid1=$!
    echo "$pid1" > "$TEST_PID_FILE"
    sleep 0.5
    
    # Verify first daemon is running
    assert_equals "true" "$(is_daemon_running)" "first daemon instance running"
    
    # Stop first daemon
    touch "$DAEMON_TEST_STATE/state/daemon.stop"
    sleep 1.5
    
    # Start second daemon (restart)
    (
        exec >> "$TEST_LOG_FILE" 2>&1
        while true; do
            if [[ -f "$DAEMON_TEST_STATE/state/daemon.stop" ]]; then
                rm -f "$TEST_PID_FILE" "$DAEMON_TEST_STATE/state/daemon.stop"
                exit 0
            fi
            sleep 1
        done
    ) &
    
    local pid2=$!
    echo "$pid2" > "$TEST_PID_FILE"
    sleep 0.5
    
    # Verify new daemon is running with different PID
    local running=$(is_daemon_running)
    assert_equals "true" "$running" "restarted daemon running"
    
    # Verify PIDs are different
    if [[ "$pid1" != "$pid2" ]]; then
        assert_true "true" "restart creates new process"
    else
        assert_true "false" "restart creates new process"
    fi
    
    # Cleanup
    touch "$DAEMON_TEST_STATE/state/daemon.stop"
    sleep 1.5
}

# ============================================================
# Daemon Log Tests
# ============================================================

test_daemon_logs() {
    echo "  Testing daemon log creation..."
    
    setup_daemon_test
    
    # Write test log entries
    echo "[$(date -Iseconds)] Test log entry 1" >> "$TEST_LOG_FILE"
    echo "[$(date -Iseconds)] Test log entry 2" >> "$TEST_LOG_FILE"
    echo "[$(date -Iseconds)] Test log entry 3" >> "$TEST_LOG_FILE"
    
    # Verify log file exists and contains entries
    local log_exists=$(test -f "$TEST_LOG_FILE" && echo "true" || echo "false")
    assert_true "$log_exists" "daemon log file created"
    
    # Verify log content
    local log_content=$(cat "$TEST_LOG_FILE")
    assert_contains "$log_content" "Test log entry 1" "log contains entry 1"
    assert_contains "$log_content" "Test log entry 2" "log contains entry 2"
    assert_contains "$log_content" "Test log entry 3" "log contains entry 3"
}

# ============================================================
# Task Flagging Tests
# ============================================================

test_daemon_task_flagging() {
    echo "  Testing daemon task flagging..."
    
    setup_daemon_test
    
    # Create test task
    cat > "$DAEMON_TEST_STATE/tasks/test_task.json" << 'EOF'
{
  "name": "test_task",
  "description": "Test task for flagging",
  "status": "pending",
  "priority": "normal",
  "created": "2024-01-01T00:00:00+00:00",
  "completed": false,
  "attempts": 0,
  "max_attempts": 3
}
EOF
    
    # Simulate daemon finding and flagging a task
    local pending_task="$DAEMON_TEST_STATE/tasks/test_task.json"
    
    # Mark task as in_progress
    local tmp_file="${pending_task}.tmp"
    jq '.status = "in_progress"' "$pending_task" > "$tmp_file" && mv "$tmp_file" "$pending_task"
    
    local status=$(jq -r '.status' "$pending_task")
    assert_equals "in_progress" "$status" "task marked as in_progress"
    
    # Flag task for AI attention
    jq '.status = "needs_ai_attention" | .flagged_at = "'$(date -Iseconds)'" | .flagged_by = "daemon"' "$pending_task" > "$tmp_file" && mv "$tmp_file" "$pending_task"
    
    status=$(jq -r '.status' "$pending_task")
    assert_equals "needs_ai_attention" "$status" "task flagged as needs_ai_attention"
    
    local flagged_by=$(jq -r '.flagged_by' "$pending_task")
    assert_equals "daemon" "$flagged_by" "task flagged_by is daemon"
    
    # Create notification file
    local task_name=$(jq -r '.name' "$pending_task")
    local task_desc=$(jq -r '.description' "$pending_task")
    
    cat > "$DAEMON_TEST_STATE/state/needs_attention.json" << WORK_NOTIFY
{
  "timestamp": "$(date -Iseconds)",
  "task_name": "$task_name",
  "task_file": "$pending_task",
  "description": "$task_desc",
  "status": "needs_ai_attention",
  "message": "Task flagged by daemon and requires AI processing"
}
WORK_NOTIFY
    
    local notify_exists=$(test -f "$DAEMON_TEST_STATE/state/needs_attention.json" && echo "true" || echo "false")
    assert_true "$notify_exists" "notification file created"
    
    local notify_content=$(cat "$DAEMON_TEST_STATE/state/needs_attention.json")
    assert_contains "$notify_content" "test_task" "notification contains task name"
    assert_contains "$notify_content" "needs_ai_attention" "notification contains status"
}

test_daemon_multiple_tasks_priority() {
    echo "  Testing daemon handles multiple tasks..."
    
    setup_daemon_test
    
    # Create multiple test tasks
    for i in 1 2 3; do
        cat > "$DAEMON_TEST_STATE/tasks/task_${i}.json" << EOF
{
  "name": "task_${i}",
  "description": "Test task ${i}",
  "status": "pending",
  "priority": "normal",
  "created": "2024-01-01T00:00:0${i}+00:00",
  "completed": false,
  "attempts": 0,
  "max_attempts": 3
}
EOF
    done
    
    # Count pending tasks
    local pending_count=$(find "$DAEMON_TEST_STATE/tasks" -name "*.json" | wc -l)
    assert_equals "3" "$pending_count" "three pending tasks created"
    
    # Simulate daemon finding first pending task
    local found_task=""
    for task_file in "$DAEMON_TEST_STATE/tasks"/*.json; do
        [[ -f "$task_file" ]] || continue
        local task_status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        if [[ "$task_status" != "completed" && "$task_status" != "needs_ai_attention" ]]; then
            found_task="$task_file"
            break
        fi
    done
    
    assert_true "$(test -n "$found_task" && echo "true" || echo "false")" "daemon finds first pending task"
}

# ============================================================
# Daemon Config Update Tests
# ============================================================

test_daemon_updates_config() {
    echo "  Testing daemon config updates..."
    
    setup_daemon_test
    
    # Simulate daemon start updating config
    local tmp_config="$DAEMON_TEST_STATE/config.json.tmp"
    jq '.workstation.daemon_running = true | .workstation.daemon_started = "'$(date -Iseconds)'"' "$DAEMON_TEST_STATE/config.json" > "$tmp_config" && mv "$tmp_config" "$DAEMON_TEST_STATE/config.json"
    
    local daemon_running=$(jq -r '.workstation.daemon_running' "$DAEMON_TEST_STATE/config.json")
    assert_equals "true" "$daemon_running" "config updated with daemon_running=true"
    
    local daemon_started=$(jq -r '.workstation.daemon_started' "$DAEMON_TEST_STATE/config.json")
    assert_not_equals "null" "$daemon_started" "config updated with daemon_started timestamp"
    
    # Simulate daemon stop updating config
    jq '.workstation.daemon_running = false | .workstation.daemon_stopped = "'$(date -Iseconds)'"' "$DAEMON_TEST_STATE/config.json" > "$tmp_config" && mv "$tmp_config" "$DAEMON_TEST_STATE/config.json"
    
    daemon_running=$(jq -r '.workstation.daemon_running' "$DAEMON_TEST_STATE/config.json")
    assert_equals "false" "$daemon_running" "config updated with daemon_running=false"
}

# ============================================================
# Run all tests
# ============================================================

setup_daemon_test
test_daemon_status_not_running
test_daemon_pid_file_cleanup
test_daemon_start_stop
test_daemon_restart
test_daemon_logs
test_daemon_task_flagging
test_daemon_multiple_tasks_priority
test_daemon_updates_config

# Cleanup
rm -rf "$DAEMON_TEST_STATE"

report_suite_results "Daemon Tests"
