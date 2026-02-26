#!/bin/bash
# Improvement Generator
# Generates self-improvement tasks when no real work is pending.
# Task flagging is handled exclusively by daemon.sh — this script
# is only invoked for on-demand improvement generation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
LOG_FILE="$AUTONOMY_DIR/logs/processor.log"

mkdir -p "$AUTONOMY_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Generate new improvement tasks (only when no real tasks left)
generate_improvements() {
    log "=== CHECKING IF IMPROVEMENTS NEEDED ==="

    # Count pending REAL tasks (not improvements)
    local real_pending=0
    for f in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$f" ]] || continue
        [[ "$f" == *improvement* ]] && continue
        local status completed
        status=$(jq -r '.status // "pending"' "$f")
        completed=$(jq -r '.completed // false' "$f")
        if [[ "$completed" != "true" && "$status" != "completed" ]]; then
            real_pending=$((real_pending + 1))
        fi
    done

    log "Real pending tasks: $real_pending"

    # Only generate improvements if NO real tasks are pending
    if [[ $real_pending -gt 0 ]]; then
        log "Skipping — $real_pending real tasks still pending"
        return 0
    fi

    # Count existing improvement tasks
    local improvement_count
    improvement_count=$(ls -1 "$AUTONOMY_DIR"/tasks/improvement-*.json 2>/dev/null | wc -l)
    if [[ $improvement_count -ge 2 ]]; then
        log "Already have $improvement_count improvement tasks"
        return 0
    fi

    # Short list; AI will organically create better ones
    local improvements=(
        "Add real-time metrics dashboard with graphs and charts"
        "Implement task dependency management"
    )

    local created=0
    for desc in "${improvements[@]}"; do
        # Skip if this improvement already exists
        if grep -ql "$desc" "$AUTONOMY_DIR"/tasks/*.json 2>/dev/null; then
            log "Improvement already exists: $desc"
            continue
        fi

        local task_name="improvement-$(date +%s)-$created"
        local task_file="$AUTONOMY_DIR/tasks/${task_name}.json"

        cat > "$task_file" <<EOF
{
  "name": "$task_name",
  "description": "$desc",
  "status": "pending",
  "priority": "low",
  "created": "$(date -Iseconds)",
  "assignee": "self",
  "subtasks": [],
  "completed": false,
  "attempts": 0,
  "max_attempts": 3,
  "verification": null,
  "evidence": [],
  "source": "auto_generated",
  "auto_generated": true
}
EOF

        log "Created: $task_name"
        created=$((created + 1))
    done

    log "Generated $created new improvement tasks"
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"improvements_generated\",\"count\":$created}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"
}

# Show task statistics
show_stats() {
    local total pending completed
    total=$(ls -1 "$AUTONOMY_DIR"/tasks/*.json 2>/dev/null | wc -l)
    pending=0; completed=0
    for f in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$f" ]] || continue
        if jq -e '(.completed == true) or (.status == "completed")' "$f" >/dev/null 2>&1; then
            completed=$((completed + 1))
        else
            pending=$((pending + 1))
        fi
    done
    echo "Total: $total  Pending: $pending  Completed: $completed"
}

# Command dispatcher
case "${1:-generate}" in
    generate)
        generate_improvements
        ;;
    stats)
        show_stats
        ;;
    *)
        echo "Usage: $0 {generate|stats}"
        echo ""
        echo "Commands:"
        echo "  generate - Generate self-improvement tasks"
        echo "  stats    - Show task statistics"
        ;;
esac
