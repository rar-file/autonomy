#!/bin/bash
# Unified Metrics Dashboard
# Aggregates all monitoring data

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
MONITORING_DIR="$AUTONOMY_DIR/monitoring"
METRICS_DIR="$MONITORING_DIR/metrics"
ERRORS_DIR="$MONITORING_DIR/errors"

TODAY=$(date +%Y-%m-%d)

# Display full dashboard
dashboard() {
    clear 2>/dev/null || true
    
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         AUTONOMY MONITORING DASHBOARD - $(date '+%H:%M:%S')          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Health Status
    echo "┌─ HEALTH STATUS ─────────────────────────────────────────────┐"
    if [[ -x "$MONITORING_DIR/health-check.sh" ]]; then
        local health=$($MONITORING_DIR/health-check.sh json 2>/dev/null)
        local healthy=$(echo "$health" | jq '[.[] | select(.status == "healthy")] | length')
        local warning=$(echo "$health" | jq '[.[] | select(.status == "warning")] | length')
        local critical=$(echo "$health" | jq '[.[] | select(.status == "critical" or .status == "unhealthy")] | length')
        
        printf "│  ✓ Healthy: %-3d  ⚠ Warning: %-3d  ✗ Critical: %-3d          │\n" "$healthy" "$warning" "$critical"
        
        # Critical items
        local critical_items=$(echo "$health" | jq -r '.[] | select(.status == "critical" or .status == "unhealthy") | .component' | tr '\n' ', ')
        if [[ -n "$critical_items" ]]; then
            printf "│  Critical: %-50s │\n" "${critical_items:0:50}"
        fi
    else
        echo "│  Health check not available                                  │"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Token Usage
    echo "┌─ TOKEN USAGE ───────────────────────────────────────────────┐"
    if [[ -x "$MONITORING_DIR/token-tracker.sh" ]]; then
        local budget=$(jq -r '.agentic_config.hard_limits.daily_token_budget // 50000' "$AUTONOMY_DIR/config.json")
        local used=$(jq -r '.workstation.token_usage_today // 0' "$AUTONOMY_DIR/config.json")
        local pct=$(echo "scale=1; $used * 100 / $budget" | bc 2>/dev/null || echo 0)
        
        printf "│  Today: %6s / %6s tokens (%5s%%)                    │\n" "$used" "$budget" "$pct"
        
        # Progress bar
        local bar_width=40
        local filled=$(echo "scale=0; $pct * $bar_width / 100" | bc)
        local bar=""
        for ((i=0; i<filled; i++)); do bar="${bar}█"; done
        for ((i=filled; i<bar_width; i++)); do bar="${bar}░"; done
        printf "│  [%s]                         │\n" "$bar"
    else
        echo "│  Token tracker not available                                 │"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Tasks
    echo "┌─ TASKS ─────────────────────────────────────────────────────┐"
    local total_tasks=$(ls -1 "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null | wc -l)
    local pending=$(jq -s 'map(select(.status == "pending")) | length' "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null || echo 0)
    local in_progress=$(jq -s 'map(select(.status == "in_progress")) | length' "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null || echo 0)
    local completed=$(jq -s 'map(select(.status == "completed")) | length' "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null || echo 0)
    local needs_attention=$(jq -s 'map(select(.status == "needs_ai_attention")) | length' "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null || echo 0)
    
    printf "│  Total: %-3d  Pending: %-3d  In Progress: %-3d  Completed: %-3d    │\n" "$total_tasks" "$pending" "$in_progress" "$completed"
    if [[ $needs_attention -gt 0 ]]; then
        printf "│  ⚠ Needs Attention: %-3d                                      │\n" "$needs_attention"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Errors
    echo "┌─ ERRORS TODAY ──────────────────────────────────────────────┐"
    local error_file="$ERRORS_DIR/errors-${TODAY}.jsonl"
    if [[ -f "$error_file" ]] && [[ -s "$error_file" ]]; then
        local total_errors=$(wc -l < "$error_file")
        local critical_errors=$(jq -s 'map(select(.severity == "critical")) | length' "$error_file" 2>/dev/null || echo 0)
        
        if [[ $critical_errors -gt 0 ]]; then
            printf "│  ✗ Critical: %-3d  Total: %-3d                                 │\n" "$critical_errors" "$total_errors"
        elif [[ $total_errors -gt 0 ]]; then
            printf "│  ⚠ Total Errors: %-3d                                         │\n" "$total_errors"
        else
            echo "│  ✓ No errors today                                          │"
        fi
    else
        echo "│  ✓ No errors today                                          │"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Recent Activity
    echo "┌─ RECENT ACTIVITY ───────────────────────────────────────────┐"
    local activity_log="$AUTONOMY_DIR/logs/autonomy_${TODAY}.jsonl"
    if [[ -f "$activity_log" ]]; then
        tail -3 "$activity_log" 2>/dev/null | jq -r '"│  [\(.timestamp[11:16])] \(.action): \(.details.task // .details.message // "activity")"' | while read line; do
            printf "%-62s│\n" "$line"
        done
    else
        echo "│  No activity recorded today                                 │"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
}

# Export all metrics as JSON
export_all() {
    local health='{}'
    local tokens='{}'
    local tasks='{}'
    local errors='{}'
    
    if [[ -x "$MONITORING_DIR/health-check.sh" ]]; then
        health=$($MONITORING_DIR/health-check.sh json 2>/dev/null)
    fi
    
    if [[ -x "$MONITORING_DIR/token-tracker.sh" ]]; then
        local budget=$(jq -r '.agentic_config.hard_limits.daily_token_budget // 50000' "$AUTONOMY_DIR/config.json")
        local used=$(jq -r '.workstation.token_usage_today // 0' "$AUTONOMY_DIR/config.json")
        tokens="{\"budget\":$budget,\"used\":$used,\"percent\":$(echo "scale=1; $used * 100 / $budget" | bc)}"
    fi
    
    local total_tasks=$(ls -1 "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null | wc -l)
    local pending=$(jq -s 'map(select(.status == "pending")) | length' "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null || echo 0)
    tasks="{\"total\":$total_tasks,\"pending\":$pending}"
    
    local error_file="$ERRORS_DIR/errors-${TODAY}.jsonl"
    if [[ -f "$error_file" ]]; then
        local error_count=$(wc -l < "$error_file")
        errors="{\"today\":$error_count}"
    fi
    
    jq -n \
        --arg ts "$(date -Iseconds)" \
        --argjson health "$health" \
        --argjson tokens "$tokens" \
        --argjson tasks "$tasks" \
        --argjson errors "$errors" \
        '{
            timestamp: $ts,
            health: $health,
            tokens: $tokens,
            tasks: $tasks,
            errors: $errors
        }'
}

# Watch mode
watch_mode() {
    while true; do
        dashboard
        sleep 5
    done
}

# Main
case "${1:-dashboard}" in
    dashboard)
        dashboard
        ;;
    json|export)
        export_all
        ;;
    watch)
        watch_mode
        ;;
    *)
        echo "Usage: $0 {dashboard|json|watch}"
        exit 1
        ;;
esac
