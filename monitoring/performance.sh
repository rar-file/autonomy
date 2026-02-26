#!/bin/bash
# Performance Metrics Collector
# Tracks execution times, command success rates, and system health

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
METRICS_DIR="$AUTONOMY_DIR/monitoring/metrics"
mkdir -p "$METRICS_DIR"

TODAY=$(date +%Y-%m-%d)

# Record a metric
record_metric() {
    local metric_type="$1"
    local value="$2"
    local unit="${3:-count}"
    local label="${4:-}"
    local timestamp=$(date -Iseconds)
    
    local metric_file="$METRICS_DIR/performance-${TODAY}.jsonl"
    
    jq -n \
        --arg ts "$timestamp" \
        --arg type "$metric_type" \
        --arg value "$value" \
        --arg unit "$unit" \
        --arg label "$label" \
        '{
            timestamp: $ts,
            type: $type,
            value: $value,
            unit: $unit,
            label: $label
        }' >> "$metric_file"
}

# Time a command and record it
time_command() {
    local cmd="$1"
    local label="${2:-$cmd}"
    
    local start=$(date +%s%N)
    eval "$cmd"
    local exit_code=$?
    local end=$(date +%s%N)
    
    # Calculate duration in ms
    local duration_ms=$(( (end - start) / 1000000 ))
    
    # Record success/failure
    if [[ $exit_code -eq 0 ]]; then
        record_metric "command_time" "$duration_ms" "ms" "$label"
        record_metric "command_success" "1" "count" "$label"
    else
        record_metric "command_time" "$duration_ms" "ms" "$label"
        record_metric "command_failure" "1" "count" "$label"
    fi
    
    return $exit_code
}

# Record system metrics
record_system_metrics() {
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo 0)
    record_metric "cpu_usage" "$cpu_usage" "%" "system"
    
    # Memory usage
    local mem_info=$(free | grep Mem)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    local mem_pct=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc 2>/dev/null || echo 0)
    record_metric "memory_usage" "$mem_pct" "%" "system"
    
    # Disk usage
    local disk_pct=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    record_metric "disk_usage" "$disk_pct" "%" "system"
    
    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    record_metric "load_average" "$load_avg" "load" "system"
}

# Generate performance report
performance_report() {
    local days="${1:-1}"
    local metric_file="$METRICS_DIR/performance-${TODAY}.jsonl"
    
    echo "═══════════════════════════════════════"
    echo "  PERFORMANCE REPORT - $TODAY"
    echo "═══════════════════════════════════════"
    
    if [[ ! -f "$metric_file" ]]; then
        echo "No metrics recorded today"
        return
    fi
    
    # Command stats
    echo ""
    echo "  Command Performance:"
    local total_commands=$(jq -s 'map(select(.type == "command_time")) | length' "$metric_file")
    local success_count=$(jq -s 'map(select(.type == "command_success")) | map(.value | tonumber) | add' "$metric_file")
    local failure_count=$(jq -s 'map(select(.type == "command_failure")) | map(.value | tonumber) | add' "$metric_file")
    
    success_count=${success_count:-0}
    failure_count=${failure_count:-0}
    local total=$((success_count + failure_count))
    
    if [[ $total -gt 0 ]]; then
        local success_rate=$(echo "scale=1; $success_count * 100 / $total" | bc)
        echo "    Total: $total_commands commands"
        echo "    Success: $success_count ($success_rate%)"
        echo "    Failed: $failure_count"
    fi
    
    # System metrics (latest values)
    echo ""
    echo "  System Metrics (Latest):"
    local cpu=$(jq -s 'map(select(.type == "cpu_usage")) | last | .value' "$metric_file")
    local mem=$(jq -s 'map(select(.type == "memory_usage")) | last | .value' "$metric_file")
    local disk=$(jq -s 'map(select(.type == "disk_usage")) | last | .value' "$metric_file")
    
    echo "    CPU: ${cpu}%"
    echo "    Memory: ${mem}%"
    echo "    Disk: ${disk}%"
    
    # Average execution times
    echo ""
    echo "  Average Execution Times:"
    jq -s '
        map(select(.type == "command_time")) |
        group_by(.label) |
        map({
            label: .[0].label,
            avg: (map(.value | tonumber) | add / length),
            count: length
        }) |
        sort_by(.avg) |
        .[] |
        "    \(.label): \(.avg | floor)ms (\(.count) calls)"
    ' "$metric_file" 2>/dev/null
}

# Get metric value for alerting
get_metric() {
    local metric_type="$1"
    local metric_file="$METRICS_DIR/performance-${TODAY}.jsonl"
    
    if [[ ! -f "$metric_file" ]]; then
        echo "null"
        return
    fi
    
    jq -s "map(select(.type == \"$metric_type\")) | last | .value" "$metric_file"
}

# Export metrics in Prometheus format
export_prometheus() {
    local metric_file="$METRICS_DIR/performance-${TODAY}.jsonl"
    
    if [[ ! -f "$metric_file" ]]; then
        return
    fi
    
    echo "# HELP autonomy_cpu_usage CPU usage percentage"
    echo "# TYPE autonomy_cpu_usage gauge"
    local cpu=$(jq -s 'map(select(.type == "cpu_usage")) | last | .value' "$metric_file")
    echo "autonomy_cpu_usage $cpu"
    
    echo "# HELP autonomy_memory_usage Memory usage percentage"
    echo "# TYPE autonomy_memory_usage gauge"
    local mem=$(jq -s 'map(select(.type == "memory_usage")) | last | .value' "$metric_file")
    echo "autonomy_memory_usage $mem"
    
    echo "# HELP autonomy_disk_usage Disk usage percentage"
    echo "# TYPE autonomy_disk_usage gauge"
    local disk=$(jq -s 'map(select(.type == "disk_usage")) | last | .value' "$metric_file")
    echo "autonomy_disk_usage $disk"
}

# Main
case "${1:-report}" in
    record)
        record_metric "$2" "$3" "$4" "$5"
        ;;
    time)
        time_command "$2" "$3"
        ;;
    system)
        record_system_metrics
        ;;
    report)
        performance_report
        ;;
    get)
        get_metric "$2"
        ;;
    prometheus)
        export_prometheus
        ;;
    *)
        echo "Usage: $0 {record <type> <value> [unit] [label]|time <command> [label]|system|report|get <metric>|prometheus}"
        exit 1
        ;;
esac
