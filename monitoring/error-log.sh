#!/bin/bash
# Error Logging and Analysis
# Tracks errors, warnings, and failures across autonomy

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
ERRORS_DIR="$AUTONOMY_DIR/monitoring/errors"
mkdir -p "$ERRORS_DIR"

TODAY=$(date +%Y-%m-%d)

# Log an error
log_error() {
    local source="$1"
    local message="$2"
    local severity="${3:-error}"
    local details="${4:-{}}"
    local timestamp=$(date -Iseconds)
    
    local error_file="$ERRORS_DIR/errors-${TODAY}.jsonl"
    
    jq -n \
        --arg ts "$timestamp" \
        --arg source "$source" \
        --arg message "$message" \
        --arg severity "$severity" \
        --argjson details "$details" \
        '{
            timestamp: $ts,
            source: $source,
            message: $message,
            severity: $severity,
            details: $details
        }' >> "$error_file"
    
    # Also log to stderr if critical
    if [[ "$severity" == "critical" ]]; then
        echo "[CRITICAL] $source: $message" >&2
    fi
}

# Log from a command's stderr
log_command_error() {
    local command="$1"
    local stderr_output="$2"
    local exit_code="${3:-1}"
    
    log_error "$command" "$stderr_output" "error" "{\"exit_code\":$exit_code}"
}

# Get error summary
error_summary() {
    local days="${1:-1}"
    local error_file="$ERRORS_DIR/errors-${TODAY}.jsonl"
    
    echo "═══════════════════════════════════════"
    echo "  ERROR SUMMARY - $TODAY"
    echo "═══════════════════════════════════════"
    
    if [[ ! -f "$error_file" ]] || [[ ! -s "$error_file" ]]; then
        echo "  No errors recorded today ✓"
        return
    fi
    
    local total=$(wc -l < "$error_file")
    local critical=$(jq -s 'map(select(.severity == "critical")) | length' "$error_file")
    local errors=$(jq -s 'map(select(.severity == "error")) | length' "$error_file")
    local warnings=$(jq -s 'map(select(.severity == "warning")) | length' "$error_file")
    
    echo "  Total: $total"
    echo "  Critical: $critical"
    echo "  Errors: $errors"
    echo "  Warnings: $warnings"
    echo ""
    
    echo "  Top Error Sources:"
    jq -s 'group_by(.source) | map({source: .[0].source, count: length}) | sort_by(.count) | reverse | .[:5] | .[] | "    \(.source): \(.count)"' "$error_file"
    
    echo ""
    echo "  Recent Errors:"
    tail -5 "$error_file" | jq -r '"    [\(.severity)] \(.source): \(.message)"'
}

# Get errors by source
errors_by_source() {
    local source="$1"
    local error_file="$ERRORS_DIR/errors-${TODAY}.jsonl"
    
    if [[ ! -f "$error_file" ]]; then
        echo "[]"
        return
    fi
    
    jq -s "map(select(.source == \"$source\"))" "$error_file"
}

# Clear old errors (keep last N days)
cleanup_errors() {
    local keep_days="${1:-7}"
    local cutoff=$(date -d "$keep_days days ago" +%Y-%m-%d)
    
    find "$ERRORS_DIR" -name "errors-*.jsonl" -type f | while read -r f; do
        local file_date=$(basename "$f" | sed 's/errors-//; s/.jsonl//')
        if [[ "$file_date" < "$cutoff" ]]; then
            rm "$f"
            echo "Removed old error log: $f"
        fi
    done
}

# Watch for errors in real-time
watch_errors() {
    local error_file="$ERRORS_DIR/errors-${TODAY}.jsonl"
    
    if [[ ! -f "$error_file" ]]; then
        touch "$error_file"
    fi
    
    echo "Watching for new errors... (Ctrl+C to stop)"
    tail -f "$error_file" | jq -r '"[\(.timestamp)] [\(.severity)] \(.source): \(.message)"'
}

# Export errors for analysis
export_errors() {
    local format="${1:-json}"
    local error_file="$ERRORS_DIR/errors-${TODAY}.jsonl"
    
    if [[ ! -f "$error_file" ]]; then
        echo "No errors to export"
        return
    fi
    
    case "$format" in
        json)
            jq -s '.' "$error_file"
            ;;
        csv)
            jq -r '. | ["\(.timestamp)", "\(.severity)", "\(.source)", "\(.message)"] | @csv' "$error_file"
            ;;
        *)
            echo "Unknown format: $format"
            ;;
    esac
}

# Main
case "${1:-summary}" in
    log)
        log_error "$2" "$3" "$4" "${5:-{}}"
        ;;
    cmd-error)
        log_command_error "$2" "$3" "${4:-1}"
        ;;
    summary)
        error_summary
        ;;
    source)
        errors_by_source "$2"
        ;;
    cleanup)
        cleanup_errors "$2"
        ;;
    watch)
        watch_errors
        ;;
    export)
        export_errors "$2"
        ;;
    *)
        echo "Usage: $0 {log <source> <message> [severity] [details]|cmd-error <cmd> <stderr> [exit_code]|summary|source <name>|cleanup [days]|watch|export [format]}"
        exit 1
        ;;
esac
