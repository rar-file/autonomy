#!/bin/bash
# Comprehensive Health Check System
# Monitors all autonomy components and reports status

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
CONFIG="$AUTONOMY_DIR/config.json"
LOGS_DIR="$AUTONOMY_DIR/logs"
STATE_DIR="$AUTONOMY_DIR/state"
METRICS_DIR="$AUTONOMY_DIR/monitoring/metrics"
mkdir -p "$METRICS_DIR"

TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date -Iseconds)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check component health
check_daemon() {
    local pid=$(pgrep -f "autonomy.*daemon" | head -1)
    if [[ -n "$pid" ]]; then
        echo "{\"component\":\"daemon\",\"status\":\"healthy\",\"pid\":$pid}"
    else
        echo "{\"component\":\"daemon\",\"status\":\"unhealthy\",\"error\":\"not running\"}"
    fi
}

check_config() {
    if [[ -f "$CONFIG" ]] && jq empty "$CONFIG" 2>/dev/null; then
        local version=$(jq -r '.version // "unknown"' "$CONFIG")
        echo "{\"component\":\"config\",\"status\":\"healthy\",\"version\":\"$version\"}"
    else
        echo "{\"component\":\"config\",\"status\":\"unhealthy\",\"error\":\"invalid or missing\"}"
    fi
}

check_tasks() {
    local task_count=$(ls -1 "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null | wc -l)
    local pending=$(jq -s 'map(select(.status == "pending" or .status == "needs_ai_attention")) | length' "$AUTONOMY_DIR/tasks"/*.json 2>/dev/null || echo 0)
    
    echo "{\"component\":\"tasks\",\"status\":\"healthy\",\"total\":$task_count,\"pending\":$pending}"
}

check_logs() {
    local log_count=$(ls -1 "$LOGS_DIR"/*.jsonl 2>/dev/null | wc -l)
    local today_log="$LOGS_DIR/autonomy_${TODAY}.jsonl"
    local today_entries=0
    
    if [[ -f "$today_log" ]]; then
        today_entries=$(wc -l < "$today_log")
    fi
    
    echo "{\"component\":\"logs\",\"status\":\"healthy\",\"log_files\":$log_count,\"today_entries\":$today_entries}"
}

check_disk_space() {
    local usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    local status="healthy"
    
    if [[ $usage -gt 90 ]]; then
        status="critical"
    elif [[ $usage -gt 80 ]]; then
        status="warning"
    fi
    
    echo "{\"component\":\"disk\",\"status\":\"$status\",\"usage_percent\":$usage}"
}

check_memory() {
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_pct=$(echo "scale=0; $mem_used * 100 / $mem_total" | bc 2>/dev/null || echo 0)
    local status="healthy"
    
    if [[ $mem_pct -gt 90 ]]; then
        status="critical"
    elif [[ $mem_pct -gt 80 ]]; then
        status="warning"
    fi
    
    echo "{\"component\":\"memory\",\"status\":\"$status\",\"usage_percent\":$mem_pct}"
}

check_integrations() {
    local discord=$(jq -r '.integrations.discord.enabled' "$CONFIG")
    local telegram=$(jq -r '.integrations.telegram.enabled' "$CONFIG")
    local slack=$(jq -r '.integrations.slack.enabled' "$CONFIG")
    
    local enabled_count=0
    [[ "$discord" == "true" ]] && enabled_count=$((enabled_count + 1))
    [[ "$telegram" == "true" ]] && enabled_count=$((enabled_count + 1))
    [[ "$slack" == "true" ]] && enabled_count=$((enabled_count + 1))
    
    echo "{\"component\":\"integrations\",\"status\":\"healthy\",\"enabled\":$enabled_count}"
}

check_token_budget() {
    local budget=$(jq -r '.agentic_config.hard_limits.daily_token_budget // 50000' "$CONFIG")
    local used=$(jq -r '.workstation.token_usage_today // 0' "$CONFIG")
    local pct=$(echo "scale=0; $used * 100 / $budget" | bc 2>/dev/null || echo 0)
    local status="healthy"
    
    if [[ $pct -gt 100 ]]; then
        status="critical"
    elif [[ $pct -gt 80 ]]; then
        status="warning"
    fi
    
    echo "{\"component\":\"token_budget\",\"status\":\"$status\",\"used\":$used,\"budget\":$budget,\"percent\":$pct}"
}

# Run all health checks
run_checks() {
    local results=()
    
    results+=("$(check_daemon)")
    results+=("$(check_config)")
    results+=("$(check_tasks)")
    results+=("$(check_logs)")
    results+=("$(check_disk_space)")
    results+=("$(check_memory)")
    results+=("$(check_integrations)")
    results+=("$(check_token_budget)")
    
    # Combine into array JSON
    printf '%s\n' "${results[@]}" | jq -s '.'
}

# Display health report
health_report() {
    local checks=$(run_checks)
    
    echo "═══════════════════════════════════════"
    echo "  AUTONOMY HEALTH CHECK - $TIMESTAMP"
    echo "═══════════════════════════════════════"
    echo ""
    
    local healthy=$(echo "$checks" | jq '[.[] | select(.status == "healthy")] | length')
    local warning=$(echo "$checks" | jq '[.[] | select(.status == "warning")] | length')
    local critical=$(echo "$checks" | jq '[.[] | select(.status == "critical" or .status == "unhealthy")] | length')
    
    # Overall status
    if [[ $critical -gt 0 ]]; then
        echo -e "  Overall Status: ${RED}CRITICAL${NC}"
    elif [[ $warning -gt 0 ]]; then
        echo -e "  Overall Status: ${YELLOW}WARNING${NC}"
    else
        echo -e "  Overall Status: ${GREEN}HEALTHY${NC}"
    fi
    
    echo "  Components: $healthy healthy, $warning warning, $critical critical"
    echo ""
    
    # Individual components
    echo "  Component Details:"
    echo "$checks" | jq -r '.[] | 
        if .status == "healthy" then "    ✓ \(.component): \(.status)" 
        elif .status == "warning" then "    ⚠ \(.component): \(.status)"
        else "    ✗ \(.component): \(.status)" 
        end'
    
    # Save to metrics
    local health_file="$METRICS_DIR/health-${TODAY}.jsonl"
    jq -n \
        --arg ts "$TIMESTAMP" \
        --argjson healthy "$healthy" \
        --argjson warning "$warning" \
        --argjson critical "$critical" \
        --argjson checks "$checks" \
        '{
            timestamp: $ts,
            healthy: $healthy,
            warning: $warning,
            critical: $critical,
            components: $checks
        }' >> "$health_file"
}

# Check specific component
quick_check() {
    local component="$1"
    case "$component" in
        daemon) check_daemon | jq -r '.status' ;;
        config) check_config | jq -r '.status' ;;
        tasks) check_tasks | jq -r '.status' ;;
        disk) check_disk_space | jq -r '.status' ;;
        memory) check_memory | jq -r '.status' ;;
        tokens) check_token_budget | jq -r '.status' ;;
        *) echo "unknown component" ;;
    esac
}

# Export health in JSON
export_json() {
    run_checks
}

# Main
case "${1:-report}" in
    report)
        health_report
        ;;
    check)
        quick_check "$2"
        ;;
    json)
        export_json
        ;;
    *)
        echo "Usage: $0 {report|check <component>|json}"
        echo "Components: daemon, config, tasks, disk, memory, tokens"
        exit 1
        ;;
esac
