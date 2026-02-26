#!/bin/bash
# Heartbeat Coordinator - Actually triggers AI processing
# This script coordinates between the daemon and the AI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
LOG_FILE="$AUTONOMY_DIR/logs/coordinator.log"
HEARTBEAT_LOG="$AUTONOMY_DIR/logs/heartbeat_history.jsonl"

mkdir -p "$AUTONOMY_DIR/logs"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

# Record heartbeat attempt
record_heartbeat() {
    local status="$1"
    local details="$2"
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"status\":\"$status\",\"details\":\"$details\"}" >> "$HEARTBEAT_LOG"
}

# Check for flagged tasks
process_flagged_tasks() {
    log "Checking for flagged tasks..."
    
    if [[ ! -f "$AUTONOMY_DIR/state/needs_attention.json" ]]; then
        log "No flagged tasks found"
        return 1
    fi
    
    task_name=$(jq -r '.task_name' "$AUTONOMY_DIR/state/needs_attention.json")
    task_file=$(jq -r '.task_file' "$AUTONOMY_DIR/state/needs_attention.json")
    
    if [[ ! -f "$task_file" ]]; then
        log "ERROR: Task file not found: $task_file"
        rm -f "$AUTONOMY_DIR/state/needs_attention.json"
        return 1
    fi
    
    # Check if already being processed
    current_status=$(jq -r '.status' "$task_file")
    if [[ "$current_status" == "ai_processing" ]]; then
        log "Task already being processed: $task_name"
        return 1
    fi
    
    # Mark as being processed
    log "Processing task: $task_name"
    jq '.status = "ai_processing" | .processing_started = "'$(date -Iseconds)'"' "$task_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
    
    # Generate processing notification
    cat > "$AUTONOMY_DIR/state/currently_processing.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "task_name": "$task_name",
  "task_file": "$task_file",
  "status": "ai_processing",
  "message": "AI is currently processing this task"
}
EOF
    
    # Log to agentic
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"ai_started_processing\",\"task\":\"$task_name\"}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"
    
    # The actual processing happens via OpenClaw heartbeat
    # This just flags it - the AI will see it in HEARTBEAT.md
    log "Task flagged for AI: $task_name"
    
    return 0
}

# Run health checks
run_health_checks() {
    log "Running health checks..."
    
    issues=0
    
    # Check daemon
    if [[ -f "$AUTONOMY_DIR/state/heartbeat-daemon.pid" ]]; then
        pid=$(cat "$AUTONOMY_DIR/state/heartbeat-daemon.pid")
        if ! ps -p "$pid" > /dev/null 2>&1; then
            log "WARNING: Daemon PID file exists but process not running"
            rm -f "$AUTONOMY_DIR/state/heartbeat-daemon.pid"
            issues=$((issues + 1))
        fi
    fi
    
    # Check web UI
    if ! pgrep -f "web_ui.py" > /dev/null; then
        log "WARNING: Web UI not running"
        issues=$((issues + 1))
    fi
    
    # Check for stuck tasks
    for task_file in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$task_file" ]] || continue
        status=$(jq -r '.status // "pending"' "$task_file")
        if [[ "$status" == "ai_processing" ]]; then
            # Check if processing for too long
            started=$(jq -r '.processing_started // empty' "$task_file")
            if [[ -n "$started" ]]; then
                started_epoch=$(date -d "$started" +%s 2>/dev/null || echo 0)
                now_epoch=$(date +%s)
                diff=$((now_epoch - started_epoch))
                if [[ $diff -gt 3600 ]]; then  # 1 hour
                    log "WARNING: Task stuck in ai_processing for ${diff}s: $(basename "$task_file" .json)"
                    jq '.status = "pending" | del(.processing_started)' "$task_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
                    issues=$((issues + 1))
                fi
            fi
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log "Health checks passed"
        return 0
    else
        log "Health checks found $issues issue(s)"
        return 1
    fi
}

# Main coordinator cycle
coordinator_cycle() {
    log "=== Coordinator Cycle Started ==="
    record_heartbeat "started" "Cycle initiated"
    
    # Step 1: Health checks
    if ! run_health_checks; then
        log "Health issues detected, attempting recovery..."
    fi
    
    # Step 2: Process flagged tasks
    if process_flagged_tasks; then
        record_heartbeat "task_found" "Flagged task being processed"
    else
        record_heartbeat "no_tasks" "No flagged tasks to process"
    fi
    
    # Step 3: Update statistics
    total_tasks=$(ls -1 "$AUTONOMY_DIR"/tasks/*.json 2>/dev/null | wc -l)
    pending_tasks=$(for f in "$AUTONOMY_DIR"/tasks/*.json; do [[ -f "$f" ]] || continue; jq -e '(.completed != true) and (.status != "completed")' "$f" >/dev/null 2>&1 && echo 1; done | wc -l)
    completed_tasks=$(for f in "$AUTONOMY_DIR"/tasks/*.json; do [[ -f "$f" ]] || continue; jq -e '(.completed == true) or (.status == "completed")' "$f" >/dev/null 2>&1 && echo 1; done | wc -l)
    
    log "Statistics: Total=$total_tasks, Pending=$pending_tasks, Completed=$completed_tasks"
    
    # Update stats file
    cat > "$AUTONOMY_DIR/state/coordinator_stats.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_tasks": $total_tasks,
  "pending_tasks": $pending_tasks,
  "completed_tasks": $completed_tasks,
  "cycle_number": $(cat "$AUTONOMY_DIR/state/cycle_count" 2>/dev/null || echo 0)
}
EOF
    
    # Increment cycle count
    count=$(cat "$AUTONOMY_DIR/state/cycle_count" 2>/dev/null || echo 0)
    echo $((count + 1)) > "$AUTONOMY_DIR/state/cycle_count"
    
    log "=== Coordinator Cycle Complete ==="
    record_heartbeat "completed" "Cycle finished successfully"
}

# Command dispatcher
case "${1:-cycle}" in
    cycle)
        coordinator_cycle
        ;;
    health)
        run_health_checks
        ;;
    process)
        process_flagged_tasks
        ;;
    stats)
        cat "$AUTONOMY_DIR/state/coordinator_stats.json" 2>/dev/null | jq . || echo "No stats yet"
        ;;
    history)
        tail -20 "$HEARTBEAT_LOG" 2>/dev/null | jq -r '[.timestamp, .status, .details] | @tsv' || echo "No history"
        ;;
    logs)
        tail -30 "$LOG_FILE" 2>/dev/null || echo "No logs"
        ;;
    *)
        echo "Usage: $0 {cycle|health|process|stats|history|logs}"
        echo ""
        echo "Commands:"
        echo "  cycle   - Run full coordinator cycle"
        echo "  health  - Run health checks only"
        echo "  process - Process flagged tasks"
        echo "  stats   - Show coordinator statistics"
        echo "  history - Show heartbeat history"
        echo "  logs    - Show recent logs"
        ;;
esac
