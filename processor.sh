#!/bin/bash
# Continuous Task Processor
# Runs every 5 minutes: processes tasks, generates new ones

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
LOG_FILE="$AUTONOMY_DIR/logs/processor.log"

mkdir -p "$AUTONOMY_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Process a single task - just flag it, don't mark as processing
process_task() {
    local task_file="$1"
    local task_name=$(jq -r '.name' "$task_file")
    local task_desc=$(jq -r '.description' "$task_file")
    
    log "Flagging task for AI: $task_name"
    
    # Flag as needs_ai_attention (AI will mark as processing when it starts)
    jq '.status = "needs_ai_attention" | .flagged_at = "'$(date -Iseconds)'" | .flagged_by = "processor"' "$task_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
    
    # Create notification for AI
    cat > "$AUTONOMY_DIR/state/needs_attention.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "task_name": "$task_name",
  "task_file": "$task_file",
  "description": "$task_desc",
  "status": "needs_ai_attention",
  "flagged_by": "processor"
}
EOF
    
    # Log to agentic
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"task_flagged\",\"task\":\"$task_name\",\"by\":\"processor\"}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"
    
    log "Task $task_name flagged for AI attention"
    
    return 0
}

# Process all pending tasks (but only 1 at a time to avoid overwhelming)
process_all_tasks() {
    log "=== PROCESSING PENDING TASKS (max 1 per cycle) ==="
    
    local processed=0
    local skipped=0
    local max_to_process=1  # Only process 1 task per cycle
    
    for task_file in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$task_file" ]] || continue
        
        # Stop after processing max tasks
        if [[ $processed -ge $max_to_process ]]; then
            log "Reached max tasks per cycle ($max_to_process), stopping"
            break
        fi
        
        local status=$(jq -r '.status // "pending"' "$task_file")
        local completed=$(jq -r '.completed // false' "$task_file")
        local task_name=$(jq -r '.name' "$task_file")
        
        # Skip completed tasks
        if [[ "$completed" == "true" || "$status" == "completed" ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        
        # Skip already flagged or processing tasks
        if [[ "$status" == "needs_ai_attention" || "$status" == "ai_processing" ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        
        # Skip auto-generated improvement tasks (let daemon handle real tasks first)
        if [[ "$task_name" == improvement-* ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        
        # Skip master tracking tasks
        if [[ "$task_name" == "continuous-improvement" ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        
        # Process this task
        log "Processing: $task_name"
        process_task "$task_file"
        processed=$((processed + 1))
    done
    
    log "Processed: $processed, Skipped: $skipped"
    
    # Log summary
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"processor_batch_complete\",\"processed\":$processed,\"skipped\":$skipped}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"
}
                    skipped=$((skipped + 1))
                    continue
                fi
            else
                skipped=$((skipped + 1))
                continue
            fi
        fi
        
        # Process this task
        process_task "$task_file"
        processed=$((processed + 1))
        
        # Small delay between tasks
        sleep 1
    done
    
    log "Processed: $processed, Skipped: $skipped"
    
    # Log summary
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"processor_batch_complete\",\"processed\":$processed,\"skipped\":$skipped}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"
}

# Generate new improvement tasks (only when no real tasks left)
generate_improvements() {
    log "=== CHECKING IF IMPROVEMENTS NEEDED ==="
    
    # Count pending REAL tasks (not improvements)
    local real_pending=0
    for f in "$AUTONOMY_DIR"/tasks/*.json; do
        [[ -f "$f" ]] || continue
        [[ "$f" == *improvement* ]] && continue
        local status=$(jq -r '.status // "pending"' "$f")
        local completed=$(jq -r '.completed // false' "$f")
        if [[ "$completed" != "true" && "$status" != "completed" ]]; then
            real_pending=$((real_pending + 1))
        fi
    done
    
    log "Real pending tasks: $real_pending"
    
    # Only generate improvements if NO real tasks are pending
    if [[ $real_pending -gt 0 ]]; then
        log "Skipping improvements - $real_pending real tasks still pending"
        return 0
    fi
    
    # Count existing improvement tasks
    local improvement_count=$(ls -1 "$AUTONOMY_DIR"/tasks/improvement-*.json 2>/dev/null | wc -l)
    
    # Don't generate if we already have improvement tasks
    if [[ $improvement_count -ge 2 ]]; then
        log "Already have $improvement_count improvement tasks"
        return 0
    fi
    
    # Generate only 2 improvements per cycle (not 10)
    local improvements=(
        "Add real-time metrics dashboard with graphs and charts"
        "Implement task dependency management"
    )
    
    local created=0
    for desc in "${improvements[@]}"; do
        # Check if this improvement already exists
        if grep -q "$desc" "$AUTONOMY_DIR"/tasks/improvement-*.json 2>/dev/null; then
            log "Improvement already exists: $desc"
            continue
        fi
        
        local task_name="improvement-$(date +%s)-$created"
        local task_file="$AUTONOMY_DIR/tasks/${task_name}.json"
        
        # Skip if too many tasks already
        if [[ $((current_count + created)) -gt 50 ]]; then
            log "Task limit reached, skipping"
            break
        fi
        
        # Check if this improvement already exists
        if grep -q "$desc" "$AUTONOMY_DIR"/tasks/*.json 2>/dev/null; then
            log "Improvement already exists: $desc"
            continue
        fi
        
        cat > "$task_file" << EOF
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
    
    # Log generation
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"improvements_generated\",\"count\":$created}" >> "$AUTONOMY_DIR/logs/agentic.jsonl"
}

# Main processor cycle
processor_cycle() {
    log ""
    log "╔════════════════════════════════════════════════╗"
    log "║     CONTINUOUS TASK PROCESSOR CYCLE            ║"
    log "╚════════════════════════════════════════════════╝"
    log ""
    
    # Phase 1: Process all pending tasks
    process_all_tasks
    
    # Phase 2: Generate new improvement tasks
    generate_improvements
    
    # Phase 3: Update statistics
    local total=$(ls -1 "$AUTONOMY_DIR"/tasks/*.json 2>/dev/null | wc -l)
    local pending=$(for f in "$AUTONOMY_DIR"/tasks/*.json; do [[ -f "$f" ]] && jq -e '(.completed != true) && (.status != "completed")' "$f" >/dev/null 2>&1 && echo 1; done | wc -l)
    local completed=$((total - pending))
    
    log ""
    log "📊 Statistics:"
    log "  Total Tasks: $total"
    log "  Pending: $pending"
    log "  Completed: $completed"
    
    cat > "$AUTONOMY_DIR/state/processor_stats.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_tasks": $total,
  "pending": $pending,
  "completed": $completed
}
EOF
    
    log ""
    log "Next cycle in 5 minutes..."
    log "─────────────────────────────────────────────────"
}

# Command dispatcher
case "${1:-cycle}" in
    cycle)
        processor_cycle
        ;;
    continuous)
        log "Starting continuous processor (every 5 minutes)..."
        while true; do
            processor_cycle
            sleep 300  # 5 minutes
        done
        ;;
    process)
        process_all_tasks
        ;;
    generate)
        generate_improvements
        ;;
    *)
        echo "Usage: $0 {cycle|continuous|process|generate}"
        echo ""
        echo "Commands:"
        echo "  cycle      - Run one processor cycle"
        echo "  continuous - Run continuously every 5 minutes"
        echo "  process    - Process all pending tasks"
        echo "  generate   - Generate improvement tasks"
        ;;
esac
