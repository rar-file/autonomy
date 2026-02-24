#!/bin/bash
# Unified logging utility for autonomy

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
LOG_DIR="$AUTONOMY_DIR/logs"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Main log function
log_activity() {
    local action="$1"
    local message="$2"
    local status="${3:-info}"
    local context="${4:-$(jq -r '.active_context // "unknown"' "$AUTONOMY_DIR/config.json" 2>/dev/null)}"
    
    local log_file="$LOG_DIR/$(date +%Y-%m).jsonl"
    
    jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg action "$action" \
        --arg message "$message" \
        --arg status "$status" \
        --arg context "$context" \
        '{
            timestamp: $timestamp,
            action: $action,
            message: $message,
            status: $status,
            context: $context
        }' >> "$log_file"
}

# Log check results
log_check() {
    local check_name="$1"
    local status="$2"
    local details="${3:-}"
    
    local log_file="$LOG_DIR/checks-$(date +%Y-%m-%d).jsonl"
    
    jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg check "$check_name" \
        --arg status "$status" \
        --arg details "$details" \
        '{
            timestamp: $timestamp,
            type: "check",
            check: $check,
            status: $status,
            details: $details
        }' >> "$log_file"
}

# Log actions taken
log_action() {
    local action_type="$1"
    local target="$2"
    local result="${3:-success}"
    
    local log_file="$LOG_DIR/actions-$(date +%Y-%m-%d).jsonl"
    
    jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --arg type "$action_type" \
        --arg target "$target" \
        --arg result "$result" \
        '{
            timestamp: $timestamp,
            type: "action",
            action: $type,
            target: $target,
            result: $result
        }' >> "$log_file"
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f log_activity log_check log_action
fi
