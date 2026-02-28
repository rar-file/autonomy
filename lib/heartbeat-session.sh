#!/bin/bash
# Heartbeat Session Integration
# Hooks session tracking into the heartbeat lifecycle
#
# This script is called by the daemon at the start and end of each heartbeat cycle.
# It ensures session summaries are auto-generated and appended to memory files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$AUTONOMY_DIR/hooks"
SESSION_END="$HOOKS_DIR/session-end.sh"

# ── Heartbeat Lifecycle Hooks ───────────────────────────────

# Called at the start of a heartbeat cycle
heartbeat_start() {
    # Initialize a new session if none exists or if previous was completed
    local session_file="$AUTONOMY_DIR/state/session.json"
    
    if [[ -f "$session_file" ]]; then
        local status
        status=$(jq -r '.status // "completed"' "$session_file" 2>/dev/null)
        if [[ "$status" == "completed" ]]; then
            # Start a new session
            "$SESSION_END" --init >/dev/null 2>&1
        fi
    else
        # No session exists, initialize one
        "$SESSION_END" --init >/dev/null 2>&1
    fi
}

# Called at the end of a heartbeat cycle
heartbeat_end() {
    # Generate session summary
    "$SESSION_END" --generate >/dev/null 2>&1
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    start)
        heartbeat_start
        ;;
    end)
        heartbeat_end
        ;;
    status)
        "$SESSION_END" --status
        ;;
    *)
        echo "Heartbeat Session Integration"
        echo ""
        echo "Usage:"
        echo "  heartbeat-session.sh start   # Initialize session at heartbeat start"
        echo "  heartbeat-session.sh end     # Generate summary at heartbeat end"
        echo "  heartbeat-session.sh status  # Show current session info"
        ;;
esac
