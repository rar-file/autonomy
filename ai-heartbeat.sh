#!/bin/bash
# AI Heartbeat Runner - Handles locking automatically
# Usage: bash ai-heartbeat.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
cd "$AUTONOMY_DIR"

# Source lock manager
source "$AUTONOMY_DIR/lib/heartbeat-lock.sh"

# Try to acquire lock
LOCK_RESULT=$(acquire_lock "ai-heartbeat")

if [[ "$LOCK_RESULT" != "LOCK_ACQUIRED" ]]; then
    echo "LOCKED: $LOCK_RESULT"
    exit 0
fi

# Ensure lock is released on exit
cleanup() {
    release_lock
}
trap cleanup EXIT

# Check if workstation is active
ACTIVE=$(jq -r '.workstation.active // false' config.json)
if [[ "$ACTIVE" != "true" ]]; then
    echo "INACTIVE: Workstation not active"
    exit 0
fi

# Check for flagged work
if [[ -f "state/needs_attention.json" ]]; then
    TASK_NAME=$(jq -r '.task_name // "unknown"' state/needs_attention.json)
    TASK_FILE=$(jq -r '.task_file // ""' state/needs_attention.json)
    
    echo "PROCESSING: $TASK_NAME"
    
    # Validate task file exists
    if [[ -n "$TASK_FILE" && -f "$TASK_FILE" ]]; then
        # Mark as processing
        jq '.status = "ai_processing" | .processing_started = "'$(date -Iseconds)'"' "$TASK_FILE" > "${TASK_FILE}.tmp" && mv "${TASK_FILE}.tmp" "$TASK_FILE"
        
        # Return info for AI to process
        echo "TASK_READY: $TASK_FILE"
        exit 0
    else
        echo "ERROR: Task file not found: $TASK_FILE"
        rm -f state/needs_attention.json
        exit 1
    fi
else
    echo "IDLE: No tasks flagged for processing"
    exit 0
fi
