#!/bin/bash
# Heartbeat Lock Functions (Library - no command dispatch)
# Source this file to use the functions

AUTONOMY_DIR="${AUTONOMY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="$AUTONOMY_DIR/state"
LOCK_FILE="$STATE_DIR/heartbeat.lock"
LOCK_TIMEOUT_SECONDS="${LOCK_TIMEOUT_SECONDS:-900}"  # 15 min default — slow tasks need room
LOCK_GRACE_SECONDS=60  # Extra grace after timeout before force-kill

mkdir -p "$STATE_DIR"

# Get current timestamp
_now() {
    date +%s
}

# Check if a lock is stale (older than timeout)
is_lock_stale() {
    if [[ ! -f "$LOCK_FILE" ]]; then
        return 1  # No lock = not stale
    fi
    
    local lock_time=$(jq -r '.timestamp // 0' "$LOCK_FILE" 2>/dev/null)
    local lock_pid=$(jq -r '.pid // 0' "$LOCK_FILE" 2>/dev/null)
    local current_time=$(_now)
    
    # Check if process is still running
    if [[ -n "$lock_pid" && "$lock_pid" != "0" ]]; then
        if ps -p "$lock_pid" >/dev/null 2>&1; then
            # Process still running, check if it's been too long
            local elapsed=$((current_time - lock_time))
            if [[ $elapsed -gt $LOCK_TIMEOUT_SECONDS ]]; then
                echo "Lock is stale (PID $lock_pid running for ${elapsed}s, timeout ${LOCK_TIMEOUT_SECONDS}s)"
                return 0
            fi
            return 1  # Lock valid and process running
        fi
    fi
    
    # Process not running, lock is stale
    echo "Lock is stale (process $lock_pid not running)"
    return 0
}

# Acquire heartbeat lock
acquire_lock() {
    local caller="${1:-unknown}"
    
    # Check if lock exists
    if [[ -f "$LOCK_FILE" ]]; then
        if ! is_lock_stale >/dev/null 2>&1; then
            # Lock is valid, heartbeat in progress
            local lock_pid=$(jq -r '.pid // "unknown"' "$LOCK_FILE" 2>/dev/null)
            local lock_caller=$(jq -r '.caller // "unknown"' "$LOCK_FILE" 2>/dev/null)
            echo "LOCKED: Heartbeat already in progress (PID: $lock_pid, caller: $lock_caller)"
            return 1
        fi
        
        # Lock is stale, break it
        echo "Breaking stale heartbeat lock..."
        rm -f "$LOCK_FILE"
    fi
    
    # Acquire lock
    cat > "$LOCK_FILE" << EOF
{
  "pid": $$,
  "timestamp": $(_now),
  "caller": "$caller",
  "started": "$(date -Iseconds)"
}
EOF
    
    echo "LOCK_ACQUIRED"
    return 0
}

# Release heartbeat lock
release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(jq -r '.pid // 0' "$LOCK_FILE" 2>/dev/null)
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$LOCK_FILE"
            echo "LOCK_RELEASED"
            return 0
        else
            echo "LOCK_NOT_OWNED (owned by PID $lock_pid, we are $$)"
            return 1
        fi
    fi
    echo "NO_LOCK"
    return 0
}

# Force release (for cleanup)
force_release() {
    rm -f "$LOCK_FILE"
    echo "LOCK_FORCE_RELEASED"
}

# Check lock status
check_status() {
    if [[ ! -f "$LOCK_FILE" ]]; then
        echo "UNLOCKED: No heartbeat in progress"
        return 0
    fi
    
    local lock_pid=$(jq -r '.pid // "unknown"' "$LOCK_FILE" 2>/dev/null)
    local lock_caller=$(jq -r '.caller // "unknown"' "$LOCK_FILE" 2>/dev/null)
    local lock_time=$(jq -r '.timestamp // 0' "$LOCK_FILE" 2>/dev/null)
    local current_time=$(_now)
    local elapsed=$((current_time - lock_time))
    
    if ps -p "$lock_pid" >/dev/null 2>&1; then
        echo "LOCKED: Heartbeat in progress (PID: $lock_pid, caller: $lock_caller, elapsed: ${elapsed}s)"
        return 1
    else
        echo "STALE: Lock exists but process dead (PID: $lock_pid, caller: $lock_caller)"
        return 2
    fi
}

# Wait for heartbeat to complete (with timeout)
wait_for_heartbeat() {
    local timeout=${1:-60}
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if ! check_status | grep -q "LOCKED:"; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    
    return 1
}
