#!/bin/bash
# Session End Hook — Auto-generates session summaries on session close
# Appends structured summaries to memory/YYYY-MM-DD.md
#
# Usage:
#   session-end.sh                    # Generate and append summary
#   session-end.sh --init             # Initialize a new session (set start time)
#   session-end.sh --dry-run          # Show what would be written without writing
#
# Called by:
#   - Heartbeat lifecycle (end of heartbeat processing)
#   - SIGTERM handler (if session is terminated)
#   - Manual invocation for testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
WORKSPACE_ROOT="$(dirname "$AUTONOMY_DIR")"
STATE_DIR="$AUTONOMY_DIR/state"
MEMORY_DIR="$WORKSPACE_ROOT/memory"

SESSION_FILE="$STATE_DIR/session.json"
JOURNAL_FILE="$STATE_DIR/journal.jsonl"
MEMORY_FILE="$STATE_DIR/memory.json"

mkdir -p "$MEMORY_DIR"

# ── Session Management ───────────────────────────────────────

# Initialize a new session
init_session() {
    local session_id="${OPENCLAW_SESSION_ID:-$(date +%s)-$$}"
    local start_time="$(date -Iseconds)"
    
    local session_data
    session_data=$(jq -n \
        --arg id "$session_id" \
        --arg start "$start_time" \
        --arg workspace "$WORKSPACE_ROOT" \
        '{session_id: $id, start_time: $start, workspace: $workspace, status: "active"}')
    
    echo "$session_data" > "$SESSION_FILE"
    echo "Session initialized: $session_id at $start_time"
}

# Get session info
get_session_info() {
    if [[ -f "$SESSION_FILE" ]]; then
        cat "$SESSION_FILE"
    else
        # Auto-initialize if no session exists
        init_session
        cat "$SESSION_FILE"
    fi
}

# Calculate session duration
calculate_duration() {
    local start_time="$1"
    local end_time="$2"
    
    local start_epoch end_epoch duration
    start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo 0)
    end_epoch=$(date -d "$end_time" +%s 2>/dev/null || echo 0)
    duration=$((end_epoch - start_epoch))
    
    if [[ $duration -lt 60 ]]; then
        echo "${duration}s"
    elif [[ $duration -lt 3600 ]]; then
        echo "$((duration / 60))m $((duration % 60))s"
    else
        local hours=$((duration / 3600))
        local mins=$(((duration % 3600) / 60))
        echo "${hours}h ${mins}m"
    fi
}

# ── Data Collection ─────────────────────────────────────────

# Get recent journal entries for this session
get_session_work() {
    local since="$1"
    
    if [[ ! -f "$JOURNAL_FILE" ]]; then
        echo "No journal entries found."
        return
    fi
    
    # Get entries since session start (last 10 max)
    jq -R 'fromjson? | select(.timestamp >= "'$since'")' "$JOURNAL_FILE" 2>/dev/null | \
        jq -s 'sort_by(.timestamp) | .[-10:] | .[] | "- [\(.status)] \(.task): \(.summary)"' -r 2>/dev/null || \
        echo "No recent work recorded."
}

# Get files changed in git since session start
get_files_changed() {
    local since="$1"
    
    # First try: check git status for modified files
    local modified_files
    modified_files=$(cd "$WORKSPACE_ROOT" && git diff --name-only 2>/dev/null)
    
    # Also get recently modified files (within last hour as fallback)
    local recent_files
    recent_files=$(find "$WORKSPACE_ROOT" -type f -mmin -120 \
        ! -path "*/.git/*" \
        ! -path "*/__pycache__/*" \
        ! -path "*/node_modules/*" \
        ! -path "*/.openclaw/*" \
        2>/dev/null | head -20)
    
    if [[ -n "$modified_files" ]]; then
        echo "$modified_files" | head -10 | while read -r file; do
            echo "- \`$file\`"
        done
    elif [[ -n "$recent_files" ]]; then
        echo "*(Recently touched files)*"
        echo "$recent_files" | head -5 | while read -r file; do
            local rel_path="${file#$WORKSPACE_ROOT/}"
            echo "- \`$rel_path\`"
        done
    else
        echo "- No files changed"
    fi
}

# Get decisions made during session
get_decisions() {
    if [[ ! -f "$MEMORY_FILE" ]]; then
        return
    fi
    
    # Get recent decisions from memory
    jq -r '.decisions // [] | .[-5:] | .[] | "- " + .content' "$MEMORY_FILE" 2>/dev/null || \
        echo "No decisions recorded."
}

# Get session token usage if available
get_token_usage() {
    local usage_file="$AUTONOMY_DIR/logs/usage.jsonl"
    if [[ -f "$usage_file" ]]; then
        local today
        today=$(date +%Y-%m-%d)
        # Sum tokens for today
        jq -R 'fromjson? | select(.timestamp | startswith("'$today'"))' "$usage_file" 2>/dev/null | \
            jq -s 'map(.tokens_in + .tokens_out) | add' 2>/dev/null || echo "0"
    else
        echo "N/A"
    fi
}

# ── Summary Generation ──────────────────────────────────────

generate_summary() {
    local dry_run="${1:-false}"
    
    # Get session info
    local session_info start_time session_id
    session_info=$(get_session_info)
    start_time=$(echo "$session_info" | jq -r '.start_time // empty')
    session_id=$(echo "$session_info" | jq -r '.session_id // empty')
    
    if [[ -z "$start_time" ]]; then
        echo "Error: No session start time found. Run with --init first." >&2
        return 1
    fi
    
    local end_time
    end_time="$(date -Iseconds)"
    
    local duration
    duration=$(calculate_duration "$start_time" "$end_time")
    
    # Collect data
    local work_items files_changed decisions token_usage
    work_items=$(get_session_work "$start_time")
    files_changed=$(get_files_changed "$start_time")
    decisions=$(get_decisions)
    token_usage=$(get_token_usage)
    
    # Format time
    local time_str
    time_str=$(date '+%H:%M' -d "$end_time")
    
    # Build summary
    local summary
    summary="### Session Summary [$time_str] — ${duration}

**Session ID:** \`$session_id\`

#### Work Completed
${work_items}

#### Files Changed
${files_changed}

#### Decisions Made
${decisions}

#### Token Usage
${token_usage} tokens

---
"

    if [[ "$dry_run" == "true" ]]; then
        echo "$summary"
    else
        # Append to daily memory file
        local memory_file
        memory_file="$MEMORY_DIR/$(date +%Y-%m-%d).md"
        
        # Create file with header if it doesn't exist
        if [[ ! -f "$memory_file" ]]; then
            {
                echo "# Memory Log — $(date +%Y-%m-%d)"
                echo ""
                echo "Auto-generated session summaries."
                echo ""
            } > "$memory_file"
        fi
        
        # Append summary
        echo "$summary" >> "$memory_file"
        
        # Mark session as completed
        jq --arg end "$end_time" --arg dur "$duration" \
            '.status = "completed" | .end_time = $end | .duration = $dur' \
            "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
        
        echo "Session summary appended to: $memory_file"
    fi
}

# ── Main ────────────────────────────────────────────────────

case "${1:-generate}" in
    --init|init)
        init_session
        ;;
    --dry-run|dry-run)
        generate_summary true
        ;;
    --generate|generate|"")
        generate_summary false
        ;;
    --status|status)
        if [[ -f "$SESSION_FILE" ]]; then
            get_session_info | jq .
        else
            echo "No active session. Run with --init to start one."
        fi
        ;;
    --help|help)
        echo "Session End Hook — Auto-generates session summaries"
        echo ""
        echo "Usage:"
        echo "  session-end.sh --init       Initialize a new session"
        echo "  session-end.sh              Generate and append summary"
        echo "  session-end.sh --dry-run    Preview summary without writing"
        echo "  session-end.sh --status     Show current session info"
        echo ""
        echo "Environment Variables:"
        echo "  OPENCLAW_SESSION_ID    Override session ID"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run with --help for usage."
        exit 1
        ;;
esac
