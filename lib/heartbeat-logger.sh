#!/bin/bash
# Heartbeat Activity Logger
# Tracks all heartbeat activity for visibility

AUTONOMY_DIR="${AUTONOMY_DIR:-/root/.openclaw/workspace/skills/autonomy}"
LOG_FILE="$AUTONOMY_DIR/logs/heartbeat-activity.jsonl"
STATE_FILE="$AUTONOMY_DIR/state/last-heartbeat.json"

mkdir -p "$AUTONOMY_DIR/logs"

# Log a heartbeat activity
log_heartbeat() {
    local status="$1"      # acquired|skipped|working|completed|failed|idle
    local message="$2"     # Human-readable message
    local details="${3:-{}}"  # JSON details

    local timestamp=$(date -Iseconds)

    # Validate details is valid JSON, fallback to empty object
    if ! echo "$details" | jq empty 2>/dev/null; then
        details="{}"
    fi

    # Build JSON entry
    local entry
    entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg st "$status" \
        --arg msg "$message" \
        --arg det "$details" \
        '{timestamp: $ts, status: $st, message: $msg, details: ($det | fromjson? // {})}')

    # Append to log
    echo "$entry" >> "$LOG_FILE"

    # Update state file (last heartbeat)
    echo "$entry" > "$STATE_FILE"

    # Also echo for immediate visibility
    echo "[$status] $message"
}

# Get last N heartbeats
get_recent() {
    local count="${1:-10}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -$count "$LOG_FILE" | while read line; do
            local ts=$(echo "$line" | jq -r '.timestamp')
            local status=$(echo "$line" | jq -r '.status')
            local msg=$(echo "$line" | jq -r '.message')
            echo "[$ts] [$status] $msg"
        done
    else
        echo "No heartbeat activity logged yet"
    fi
}

# Get last heartbeat info
get_last() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE" | jq -r '.message'
    else
        echo "No heartbeat recorded"
    fi
}

# Get statistics
get_stats() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "No heartbeat activity logged yet"
        return
    fi

    echo "Heartbeat Statistics:"
    echo ""

    # Count by status
    echo "Status Counts:"
    jq -r '.status' "$LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | while read count status; do
        echo "  $status: $count"
    done 2>/dev/null || echo "  (no data)"

    echo ""

    # Time since last heartbeat
    if [[ -f "$STATE_FILE" ]]; then
        local last_ts=$(jq -r '.timestamp' "$STATE_FILE")
        local last_epoch=$(date -d "$last_ts" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
        local diff=$((now_epoch - last_epoch))

        if [[ $diff -lt 60 ]]; then
            echo "Last heartbeat: ${diff}s ago"
        elif [[ $diff -lt 3600 ]]; then
            echo "Last heartbeat: $((diff / 60))m ago"
        else
            echo "Last heartbeat: $((diff / 3600))h ago"
        fi
    fi

    # Total heartbeats
    local total=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "Total heartbeats: $total"
}

# Clear logs
clear_logs() {
    rm -f "$LOG_FILE" "$STATE_FILE"
    echo "Heartbeat logs cleared"
}

# Command dispatch - only run if executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-last}" in
        log)
            log_heartbeat "$2" "$3" "${4:-{}}"
            ;;
        recent|list)
            get_recent "${2:-10}"
            ;;
        last|status)
            get_last
            ;;
        stats)
            get_stats
            ;;
        clear)
            clear_logs
            ;;
        *)
            echo "Usage: $0 {log|recent|last|stats|clear}"
            echo ""
            echo "Commands:"
            echo "  log <status> <message> [details]  - Log a heartbeat activity"
            echo "  recent [count]                       - Show recent heartbeats"
            echo "  last                                 - Show last heartbeat message"
            echo "  stats                                - Show heartbeat statistics"
            echo "  clear                                - Clear all logs"
            exit 1
            ;;
    esac
fi
