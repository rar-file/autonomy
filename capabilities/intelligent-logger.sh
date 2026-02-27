#!/bin/bash
# Intelligent Logger — Structured logging with filtering and analysis

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$AUTONOMY_DIR/logs"

mkdir -p "$LOGS_DIR"

# ── Log Levels ───────────────────────────────────────────────

declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
    [FATAL]=4
)

CURRENT_LOG_LEVEL="${AUTONOMY_LOG_LEVEL:-INFO}"

log_level_numeric() {
    local level="${1^^}"
    echo "${LOG_LEVELS[$level]:-1}"
}

should_log() {
    local msg_level="$1"
    local current_numeric
    local msg_numeric
    
    current_numeric=$(log_level_numeric "$CURRENT_LOG_LEVEL")
    msg_numeric=$(log_level_numeric "$msg_level")
    
    [[ $msg_numeric -ge $current_numeric ]]
}

# ── Structured Logging ──────────────────────────────────────

log_structured() {
    local level="$1"
    local component="$2"
    local message="$3"
    local extra="${4:-{}}"
    
    should_log "$level" || return 0
    
    local log_entry
    log_entry=$(jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg level "$level" \
        --arg component "$component" \
        --arg message "$message" \
        --argjson extra "$extra" \
        '{timestamp: $timestamp, level: $level, component: $component, message: $message, extra: $extra}')
    
    echo "$log_entry" >> "$LOGS_DIR/autonomy.jsonl"
    
    # Also output to console with color
    case "$level" in
        DEBUG) echo -e "\033[90m[DEBUG] $component: $message\033[0m" >&2 ;;
        INFO)  echo -e "\033[32m[INFO]\033[0m $component: $message" >&2 ;;
        WARN)  echo -e "\033[33m[WARN]\033[0m $component: $message" >&2 ;;
        ERROR) echo -e "\033[31m[ERROR]\033[0m $component: $message" >&2 ;;
        FATAL) echo -e "\033[35m[FATAL]\033[0m $component: $message" >&2 ;;
    esac
}

log_debug() { log_structured "DEBUG" "$1" "$2" "${3:-{}}"; }
log_info()  { log_structured "INFO"  "$1" "$2" "${3:-{}}"; }
log_warn()  { log_structured "WARN"  "$1" "$2" "${3:-{}}"; }
log_error() { log_structured "ERROR" "$1" "$2" "${3:-{}}"; }
log_fatal() { log_structured "FATAL" "$1" "$2" "${3:-{}}"; }

# ── Log Querying ────────────────────────────────────────────

log_query() {
    local filters=()
    local log_file="$LOGS_DIR/autonomy.jsonl"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --level)
                filters+=("select(.level == \"$2\")")
                shift 2
                ;;
            --component)
                filters+=("select(.component == \"$2\")")
                shift 2
                ;;
            --since)
                filters+=("select(.timestamp >= \"$2\")")
                shift 2
                ;;
            --until)
                filters+=("select(.timestamp <= \"$2\")")
                shift 2
                ;;
            --contains)
                filters+=("select(.message | contains(\"$2\"))")
                shift 2
                ;;
            --last)
                tail -n "$2" "$log_file" | jq -s '.'
                return
                ;;
            *)
                shift
                ;;
        esac
    done
    
    local query="."
    for filter in "${filters[@]}"; do
        query="$query | $filter"
    done
    
    jq -s "$query" "$log_file"
}

log_tail() {
    local lines="${1:-20}"
    local log_file="$LOGS_DIR/autonomy.jsonl"
    
    [[ -f "$log_file" ]] || { echo "No log file found"; return 1; }
    
    tail -n "$lines" "$log_file" | jq -r '[.timestamp, .level, .component, .message] | @tsv'
}

log_follow() {
    local log_file="$LOGS_DIR/autonomy.jsonl"
    
    [[ -f "$log_file" ]] || { echo "No log file found"; return 1; }
    
    tail -f "$log_file" | jq -r '[.timestamp, .level, .component, .message] | @tsv'
}

# ── Log Analysis ────────────────────────────────────────────

log_stats() {
    local log_file="$LOGS_DIR/autonomy.jsonl"
    
    [[ -f "$log_file" ]] || { echo "No log file found"; return 1; }
    
    echo "Log Statistics:"
    echo ""
    
    # Count by level
    echo "By Level:"
    jq -s 'group_by(.level) | map({level: .[0].level, count: length}) | .[] | "  \(.level): \(.count)"' "$log_file"
    
    echo ""
    echo "By Component:"
    jq -s 'group_by(.component) | map({component: .[0].component, count: length}) | .[] | "  \(.component): \(.count)"' "$log_file"
    
    echo ""
    echo "Time Range:"
    jq -s 'sort_by(.timestamp) | "  First: \(.[0].timestamp)\n  Last:  \(.[-1].timestamp)"' "$log_file"
}

log_errors() {
    local log_file="$LOGS_DIR/autonomy.jsonl"
    local lines="${1:-20}"
    
    [[ -f "$log_file" ]] || { echo "No log file found"; return 1; }
    
    jq -s "map(select(.level == \"ERROR\" or .level == \"FATAL\")) | .[-${lines}:]" "$log_file"
}

# ── Log Rotation ────────────────────────────────────────────

log_rotate() {
    local log_file="$LOGS_DIR/autonomy.jsonl"
    local max_size="${1:-10485760}"  # 10MB default
    
    [[ -f "$log_file" ]] || return 0
    
    local size
    size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null)
    
    if [[ "$size" -gt "$max_size" ]]; then
        mv "$log_file" "${log_file}.$(date +%Y%m%d_%H%M%S)"
        echo "[]" > "$log_file"
        echo "✓ Log rotated"
    fi
}

log_cleanup() {
    local days="${1:-30}"
    
    find "$LOGS_DIR" -name "*.jsonl.*" -mtime +$days -delete
    echo "✓ Old logs cleaned up (older than $days days)"
}

# ── Export/Import ───────────────────────────────────────────

log_export() {
    local output="$1"
    [[ -z "$output" ]] && { echo "Usage: log_export <output_file>"; return 1; }
    
    local log_file="$LOGS_DIR/autonomy.jsonl"
    [[ -f "$log_file" ]] || { echo "No log file found"; return 1; }
    
    jq -s '.' "$log_file" > "$output"
    echo "✓ Logs exported to $output"
}

log_import() {
    local input="$1"
    [[ -z "$input" ]] && { echo "Usage: log_import <input_file>"; return 1; }
    
    [[ -f "$input" ]] || { echo "File not found: $input"; return 1; }
    
    jq -c '.[]' "$input" >> "$LOGS_DIR/autonomy.jsonl"
    echo "✓ Logs imported from $input"
}

# ── Command Router ──────────────────────────────────────────

case "${1:-}" in
    query) shift; log_query "$@" ;;
    tail) log_tail "$2" ;;
    follow) log_follow ;;
    stats) log_stats ;;
    errors) log_errors "$2" ;;
    rotate) log_rotate "$2" ;;
    cleanup) log_cleanup "$2" ;;
    export) log_export "$2" ;;
    import) log_import "$2" ;;
    *)
        echo "Intelligent Logger"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  query [filters...]         - Query logs with filters"
        echo "    --level <level>         - Filter by level (DEBUG, INFO, WARN, ERROR, FATAL)"
        echo "    --component <name>       - Filter by component"
        echo "    --since <iso_date>       - Filter since date"
        echo "    --until <iso_date>       - Filter until date"
        echo "    --contains <string>       - Filter by message content"
        echo "    --last <n>               - Get last N entries"
        echo "  tail [n]                   - Show last N log lines"
        echo "  follow                     - Follow log output (tail -f)"
        echo "  stats                      - Show log statistics"
        echo "  errors [n]                 - Show last N errors"
        echo "  rotate [max_size]          - Rotate logs if too large"
        echo "  cleanup [days]             - Remove old rotated logs"
        echo "  export <file>             - Export logs to JSON file"
        echo "  import <file>             - Import logs from JSON file"
        ;;
esac
