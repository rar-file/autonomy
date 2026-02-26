#!/bin/bash
# Autonomy Heartbeat Daemon v2.1 - Unified Reliable Scheduler
# Single daemon that handles all periodic work:
#   - Task flagging for AI processing
#   - Health checks and auto-recovery
#   - Web UI watchdog
#   - Stuck task recovery

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
PID_FILE="$AUTONOMY_DIR/state/daemon.pid"
LOG_FILE="$AUTONOMY_DIR/logs/daemon.log"
LOCK_FILE="$AUTONOMY_DIR/state/daemon.lock"
CHECK_FILE="$AUTONOMY_DIR/state/last-check.json"

mkdir -p "$AUTONOMY_DIR/state" "$AUTONOMY_DIR/logs" "$AUTONOMY_DIR/tasks"

# Import heartbeat lock manager (optional — gracefully degrade)
source "$AUTONOMY_DIR/lib/heartbeat-lock.sh" 2>/dev/null
source "$AUTONOMY_DIR/lib/heartbeat-logger.sh" 2>/dev/null

# ── Helpers ──────────────────────────────────────────────────

log() {
    echo "[$(date -Iseconds)] $1" >> "$LOG_FILE" 2>/dev/null
}

get_config() {
    jq -r "$1" "$CONFIG_FILE" 2>/dev/null
}

get_interval_seconds() {
    local mins
    mins=$(jq -r '.daemon.interval_minutes // .global_config.base_interval_minutes // 5' "$CONFIG_FILE" 2>/dev/null || echo 5)
    [[ "$mins" =~ ^[0-9]+$ ]] || mins=5
    [[ "$mins" -lt 1 ]] && mins=1
    [[ "$mins" -gt 1440 ]] && mins=1440
    echo $((mins * 60))
}

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        # Stale PID file
        rm -f "$PID_FILE"
    fi
    return 1
}

# ── Core Cycle ───────────────────────────────────────────────

# Flag the next eligible pending task for AI processing
flag_next_task() {
    for task_file in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$task_file" ]] || continue

        local status completed task_name attempts max_attempts
        status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        completed=$(jq -r '.completed // false' "$task_file" 2>/dev/null)
        task_name=$(jq -r '.name // "unknown"' "$task_file" 2>/dev/null)

        # Skip anything not simply pending
        [[ "$completed" == "true" || "$status" == "completed" ]] && continue
        [[ "$status" == "needs_ai_attention" || "$status" == "ai_processing" ]] && continue
        [[ "$task_name" == "continuous-improvement" ]] && continue

        # Skip tasks that exceeded max attempts
        attempts=$(jq -r '.attempts // 0' "$task_file" 2>/dev/null)
        max_attempts=$(jq -r '.max_attempts // 3' "$task_file" 2>/dev/null)
        [[ "$attempts" -ge "$max_attempts" ]] && continue

        # Flag this task
        local tmp="${task_file}.tmp.$$"
        jq --arg ts "$(date -Iseconds)" \
           '.status = "needs_ai_attention" | .flagged_at = $ts | .flagged_by = "daemon"' \
           "$task_file" > "$tmp" && mv "$tmp" "$task_file"

        local desc
        desc=$(jq -r '.description // "No description"' "$task_file" 2>/dev/null)
        cat > "$AUTONOMY_DIR/state/needs_attention.json" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "task_name": "$task_name",
  "task_file": "$task_file",
  "description": "$desc",
  "status": "needs_ai_attention",
  "flagged_by": "daemon"
}
EOF
        echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"task_flagged\",\"task\":\"$task_name\",\"by\":\"daemon\"}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"

        # Log heartbeat activity if available
        if command -v log_heartbeat >/dev/null 2>&1; then
            log_heartbeat "daemon" "Flagged task: $task_name" '{"source":"daemon"}' >/dev/null 2>&1
        fi

        log "Flagged task: $task_name"
        return 0
    done

    log "No eligible tasks to flag"
    return 1
}

# Unstick tasks that have been processing for too long (>1 hour)
recover_stuck_tasks() {
    for task_file in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$task_file" ]] || continue
        local status started
        status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        [[ "$status" != "ai_processing" ]] && continue

        started=$(jq -r '.processing_started // ""' "$task_file" 2>/dev/null)
        [[ -z "$started" ]] && continue

        local started_epoch now_epoch diff
        started_epoch=$(date -d "$started" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        diff=$((now_epoch - started_epoch))

        if [[ $diff -gt 3600 ]]; then
            local name
            name=$(jq -r '.name // "unknown"' "$task_file" 2>/dev/null)
            log "Recovering stuck task: $name (stuck for ${diff}s)"

            # Increment attempts
            local tmp="${task_file}.tmp.$$"
            jq '.attempts = ((.attempts // 0) + 1) | del(.processing_started) | .status = "pending" | .recovery_reason = "stuck_timeout"' \
                "$task_file" > "$tmp" && mv "$tmp" "$task_file"
        fi
    done
}

# Handle tasks that have exceeded max_attempts — pivot or shelve
handle_failed_tasks() {
    for task_file in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$task_file" ]] || continue

        local completed status attempts max_attempts name desc
        completed=$(jq -r '.completed // false' "$task_file" 2>/dev/null)
        [[ "$completed" == "true" ]] && continue

        status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        [[ "$status" == "completed" || "$status" == "shelved" || "$status" == "pivoted" ]] && continue

        attempts=$(jq -r '.attempts // 0' "$task_file" 2>/dev/null)
        max_attempts=$(jq -r '.max_attempts // 3' "$task_file" 2>/dev/null)
        [[ "$attempts" -lt "$max_attempts" ]] && continue

        name=$(jq -r '.name // "unknown"' "$task_file" 2>/dev/null)
        desc=$(jq -r '.description // ""' "$task_file" 2>/dev/null)

        log "Task exceeded max attempts: $name ($attempts/$max_attempts)"

        # Write a failure report
        local report_file="$AUTONOMY_DIR/state/failure_report_${name}.md"
        cat > "$report_file" << REPORT_EOF
# Task Failure Report: $name

**Date:** $(date -Iseconds)
**Attempts:** $attempts / $max_attempts
**Description:** $desc
**Status:** Failed — exceeded maximum attempts

## What Happened
The AI attempted this task $attempts times without completing it successfully.
This likely means the task is too complex, ambiguous, or blocked by an external dependency.

## Recommended Actions
1. Break the task into smaller, more specific subtasks
2. Provide more detailed instructions
3. Check if there are missing dependencies or permissions
4. Consider if the task scope is realistic

---
*Auto-generated by Autonomy failure recovery*
REPORT_EOF

        # Mark original task as shelved
        local tmp="${task_file}.tmp.$$"
        jq --arg ts "$(date -Iseconds)" \
           '.status = "shelved" | .shelved_at = $ts | .shelved_reason = "exceeded_max_attempts"' \
           "$task_file" > "$tmp" && mv "$tmp" "$task_file"

        # Create a simpler pivot task
        local pivot_name="review-${name}"
        cat > "$AUTONOMY_DIR/tasks/${pivot_name}.json" << PIVOT_EOF
{
  "name": "$pivot_name",
  "description": "Review failed task '$name' and decide next steps. Read the failure report at state/failure_report_${name}.md. Either: (1) break it into simpler subtasks, (2) identify what's blocking it, or (3) mark it as not feasible.",
  "status": "pending",
  "priority": "high",
  "created": "$(date -Iseconds)",
  "assignee": "self",
  "subtasks": [],
  "completed": false,
  "attempts": 0,
  "max_attempts": 2,
  "verification": null,
  "evidence": [],
  "pivot_from": "$name",
  "is_pivot": true
}
PIVOT_EOF

        log "Shelved '$name', created pivot task '$pivot_name'"
        echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"task_pivoted\",\"original\":\"$name\",\"pivot\":\"$pivot_name\"}" \
            >> "$AUTONOMY_DIR/logs/agentic.jsonl"

        # Notify if notify.sh is available
        if [[ -f "$AUTONOMY_DIR/lib/notify.sh" ]]; then
            bash "$AUTONOMY_DIR/lib/notify.sh" task-failed "$name" \
                "Exceeded $max_attempts attempts. Shelved and created review task." > /dev/null 2>&1 || true
        fi

        # Journal the failure
        if [[ -f "$AUTONOMY_DIR/lib/journal.sh" ]]; then
            bash "$AUTONOMY_DIR/lib/journal.sh" append "$name" \
                "Task failed after $attempts attempts. Shelved. Pivot task created: $pivot_name" \
                "failed" "AI should review the failure report and decide next steps" > /dev/null 2>&1
        fi
    done
}

# Ensure the web UI is alive (lightweight watchdog)
ensure_webui() {
    if ! pgrep -f "web_ui.py" >/dev/null 2>&1; then
        log "Web UI not running — restarting"
        cd "$AUTONOMY_DIR"
        nohup python3 "$AUTONOMY_DIR/web_ui.py" >> "$AUTONOMY_DIR/logs/webui.log" 2>&1 &
    fi
}

# Release stale heartbeat locks
check_heartbeat_lock() {
    if command -v check_status >/dev/null 2>&1; then
        local lock_status
        lock_status=$(check_status 2>/dev/null)
        if echo "$lock_status" | grep -q "STALE:"; then
            log "Breaking stale heartbeat lock"
            force_release 2>/dev/null
        fi
    fi
}

# Rebuild HEARTBEAT.md with live context (dynamic builder)
rebuild_heartbeat() {
    if [[ -f "$AUTONOMY_DIR/lib/heartbeat-builder.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/heartbeat-builder.sh" build > /dev/null 2>&1
        log "HEARTBEAT.md rebuilt"
    fi
}

# Write last-check state (used by web UI heartbeat timer)
update_check_state() {
    local interval_min
    interval_min=$(jq -r '.daemon.interval_minutes // .global_config.base_interval_minutes // 5' "$CONFIG_FILE" 2>/dev/null || echo 5)
    cat > "$CHECK_FILE" <<EOF
{
  "last_check": "$(date -Iseconds)",
  "interval_minutes": $interval_min
}
EOF
}

# Update coordinator stats (consumed by web UI dashboard)
update_stats() {
    local total pending completed
    total=$(ls -1 "$AUTONOMY_DIR"/tasks/*.json 2>/dev/null | wc -l)
    completed=0; pending=0
    for f in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$f" ]] || continue
        if jq -e '(.completed == true) or (.status == "completed")' "$f" >/dev/null 2>&1; then
            completed=$((completed + 1))
        else
            pending=$((pending + 1))
        fi
    done

    local cycle_num
    cycle_num=$(cat "$AUTONOMY_DIR/state/cycle_count" 2>/dev/null || echo 0)
    cat > "$AUTONOMY_DIR/state/coordinator_stats.json" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_tasks": $total,
  "pending_tasks": $pending,
  "completed_tasks": $completed,
  "cycle_number": $cycle_num
}
EOF
    echo $((cycle_num + 1)) > "$AUTONOMY_DIR/state/cycle_count"
}

# One full daemon cycle
run_cycle() {
    log "=== Daemon cycle started ==="
    update_check_state

    # Only process when workstation is active
    local active
    active=$(jq -r '.workstation.active // false' "$CONFIG_FILE" 2>/dev/null)
    if [[ "$active" != "true" ]]; then
        log "Workstation inactive — skipping task processing"
        # Still keep web UI alive even when inactive
        ensure_webui
        return 0
    fi

    # Check token budget — skip task processing if exceeded
    if [[ -f "$AUTONOMY_DIR/lib/token-budget.sh" ]]; then
        local budget_status
        budget_status=$(bash "$AUTONOMY_DIR/lib/token-budget.sh" check 2>/dev/null)
        if [[ "$budget_status" == "BUDGET_EXCEEDED" ]]; then
            log "Token budget exceeded — skipping task processing (still monitoring)"
            ensure_webui
            rebuild_heartbeat
            update_stats
            return 0
        fi
    fi

    check_heartbeat_lock
    recover_stuck_tasks
    handle_failed_tasks
    flag_next_task
    rebuild_heartbeat
    ensure_webui
    update_stats
    log "=== Daemon cycle complete ==="
}

# ── Daemon Lifecycle ─────────────────────────────────────────

start_daemon() {
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        echo "Daemon already running (PID: $pid). Use 'restart' to restart."
        return 1
    fi

    # Prevent racing starts
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo "Daemon startup in progress (PID: $lock_pid)"
            return 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"

    # Background the main loop
    (
        rm -f "$LOCK_FILE"
        exec >> "$LOG_FILE" 2>&1

        log "Daemon starting (PID: $$)"

        while true; do
            # Graceful stop
            if [[ -f "$AUTONOMY_DIR/state/daemon.stop" ]]; then
                log "Stop signal received — shutting down"
                rm -f "$PID_FILE" "$AUTONOMY_DIR/state/daemon.stop"
                exit 0
            fi

            run_cycle

            # Interruptible sleep (check stop signal every 5 seconds)
            local interval
            interval=$(get_interval_seconds)
            local slept=0
            while [[ $slept -lt $interval ]]; do
                [[ -f "$AUTONOMY_DIR/state/daemon.stop" ]] && break
                sleep 5
                slept=$((slept + 5))
            done
        done
    ) &

    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    sleep 1

    if is_running; then
        local interval_min
        interval_min=$(jq -r '.daemon.interval_minutes // .global_config.base_interval_minutes // 5' "$CONFIG_FILE" 2>/dev/null || echo 5)
        echo "✅ Daemon started (PID: $daemon_pid, interval: ${interval_min}m)"
        log "Daemon started (PID: $daemon_pid)"

        # Update config to reflect running state
        local tmp="${CONFIG_FILE}.tmp.$$"
        jq '.workstation.daemon_running = true | .workstation.daemon_started = "'"$(date -Iseconds)"'"' \
            "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        return 0
    else
        echo "❌ Failed to start daemon"
        rm -f "$PID_FILE"
        return 1
    fi
}

stop_daemon() {
    if ! is_running; then
        echo "Daemon not running"
        rm -f "$PID_FILE" "$LOCK_FILE"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")
    echo "Stopping daemon (PID: $pid)..."
    touch "$AUTONOMY_DIR/state/daemon.stop"
    sleep 3

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        sleep 1
    fi
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$PID_FILE" "$AUTONOMY_DIR/state/daemon.stop" "$LOCK_FILE"

    local tmp="${CONFIG_FILE}.tmp.$$"
    jq '.workstation.daemon_running = false | .workstation.daemon_stopped = "'"$(date -Iseconds)"'"' \
        "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE" 2>/dev/null

    echo "✅ Daemon stopped"
    log "Daemon stopped"
}

show_status() {
    if is_running; then
        local pid uptime
        pid=$(cat "$PID_FILE")
        uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
        echo "✅ Daemon running (PID: $pid, uptime: ${uptime:-unknown})"

        if [[ -f "$CHECK_FILE" ]]; then
            local last_check interval_min
            last_check=$(jq -r '.last_check // "unknown"' "$CHECK_FILE")
            interval_min=$(jq -r '.interval_minutes // 5' "$CHECK_FILE")
            echo "   Last check: $last_check"
            echo "   Interval:   ${interval_min}m"
        fi

        # Show heartbeat lock status if available
        if command -v check_status >/dev/null 2>&1; then
            echo ""
            echo "Heartbeat Lock:"
            check_status 2>&1 | sed 's/^/  /'
        fi

        if [[ -f "$LOG_FILE" ]]; then
            echo ""
            echo "Last 3 log entries:"
            tail -3 "$LOG_FILE" | sed 's/^/  /'
        fi
    else
        echo "❌ Daemon not running"
    fi
}

set_interval() {
    local new="$1"
    if [[ -z "$new" ]] || ! [[ "$new" =~ ^[0-9]+$ ]] || [[ "$new" -lt 1 ]] || [[ "$new" -gt 1440 ]]; then
        echo "Usage: daemon.sh set-interval <minutes>  (1–1440)"
        return 1
    fi
    local tmp="${CONFIG_FILE}.tmp.$$"
    jq --argjson m "$new" '.daemon.interval_minutes = $m' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "✅ Interval set to ${new}m (takes effect next cycle)"
}

# ── Command Dispatch ─────────────────────────────────────────

case "${1:-status}" in
    start)        start_daemon ;;
    stop)         stop_daemon ;;
    restart)      stop_daemon; sleep 1; start_daemon ;;
    status)       show_status ;;
    once|run)     echo "Running single cycle..."; run_cycle; echo "✅ Done" ;;
    set-interval) set_interval "$2" ;;
    logs)         tail -30 "$LOG_FILE" 2>/dev/null || echo "No logs yet" ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|once|set-interval|logs}"
        echo ""
        echo "  start              Start the heartbeat daemon"
        echo "  stop               Stop the daemon"
        echo "  restart            Restart the daemon"
        echo "  status             Show daemon status"
        echo "  once               Run a single cycle now"
        echo "  set-interval <min> Change check interval (1–1440)"
        echo "  logs               Show recent logs"
        exit 1
        ;;
esac
