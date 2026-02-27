#!/bin/bash
# Session Journal — Persistent memory across heartbeats
# The AI appends an entry after each heartbeat so the *next* heartbeat
# has context about what was done, what's left, and any blockers.
#
# HEARTBEAT.md tells the AI: "After finishing, append to the journal."
# The heartbeat-builder injects the last N entries so the AI has continuity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="$AUTONOMY_DIR/state"
JOURNAL_FILE="$STATE_DIR/journal.jsonl"
JOURNAL_MD="$STATE_DIR/journal.md"

mkdir -p "$STATE_DIR"

# ── Append a journal entry ──────────────────────────────────

append() {
    local task="${1:-}"
    local summary="${2:-}"
    local status="${3:-in-progress}"   # in-progress | completed | blocked | failed | pivoted
    local next_step="${4:-}"

    [[ -z "$summary" ]] && {
        echo "Usage: journal.sh append <task> <summary> [status] [next_step]"
        return 1
    }

    local entry
    entry=$(jq -n \
        --arg ts   "$(date -Iseconds)" \
        --arg task "$task" \
        --arg sum  "$summary" \
        --arg st   "$status" \
        --arg next "$next_step" \
        '{timestamp: $ts, task: $task, summary: $sum, status: $st, next_step: $next}')

    echo "$entry" >> "$JOURNAL_FILE"

    # Also maintain a human-readable markdown version
    {
        echo ""
        echo "### $(date '+%Y-%m-%d %H:%M') — $task [$status]"
        echo "$summary"
        [[ -n "$next_step" ]] && echo "**Next:** $next_step"
    } >> "$JOURNAL_MD"

    echo "Logged journal entry for: $task"
}

# ── Read last N entries ─────────────────────────────────────

last() {
    local n="${1:-3}"
    if [[ ! -f "$JOURNAL_FILE" ]]; then
        echo "[]"
        return
    fi
    tail -"$n" "$JOURNAL_FILE" | jq -s '.'
}

# ── Last entry as one-liner for HEARTBEAT.md ────────────────

last_summary() {
    if [[ ! -f "$JOURNAL_FILE" ]]; then
        echo "No previous session history."
        return
    fi

    local entry
    entry=$(tail -1 "$JOURNAL_FILE")
    local ts task sum st next_step
    ts=$(echo "$entry"   | jq -r '.timestamp // ""')
    task=$(echo "$entry" | jq -r '.task // ""')
    sum=$(echo "$entry"  | jq -r '.summary // ""')
    st=$(echo "$entry"   | jq -r '.status // ""')
    next_step=$(echo "$entry" | jq -r '.next_step // ""')

    echo "Last session ($ts): Task=$task Status=$st — $sum"
    [[ -n "$next_step" && "$next_step" != "null" ]] && echo "Planned next step: $next_step"
}

# ── Recent timeline for Web UI / HEARTBEAT ──────────────────

timeline() {
    local n="${1:-5}"
    if [[ ! -f "$JOURNAL_FILE" ]]; then
        echo "No journal entries yet."
        return
    fi

    echo "## Recent Session Timeline"
    echo ""
    tail -"$n" "$JOURNAL_FILE" | while IFS= read -r line; do
        local ts task sum st next_step
        ts=$(echo "$line"   | jq -r '.timestamp // ""')
        task=$(echo "$line" | jq -r '.task // ""')
        sum=$(echo "$line"  | jq -r '.summary // ""')
        st=$(echo "$line"   | jq -r '.status // ""')
        next_step=$(echo "$line" | jq -r '.next_step // ""')
        echo "- **$(echo "$ts" | cut -dT -f2 | cut -d+ -f1)** [$st] $task — $sum"
        [[ -n "$next_step" && "$next_step" != "null" ]] && echo "  → Next: $next_step"
    done
}

# ── Count entries by status ─────────────────────────────────

stats() {
    if [[ ! -f "$JOURNAL_FILE" ]]; then
        echo '{"total":0}'
        return
    fi

    local total completed failed blocked
    total=$(wc -l < "$JOURNAL_FILE" | tr -d ' ')
    completed=$(grep -c '"completed"' "$JOURNAL_FILE" 2>/dev/null || echo 0)
    failed=$(grep -c '"failed"' "$JOURNAL_FILE" 2>/dev/null || echo 0)
    blocked=$(grep -c '"blocked"' "$JOURNAL_FILE" 2>/dev/null || echo 0)

    jq -n --argjson t "$total" --argjson c "$completed" --argjson f "$failed" --argjson b "$blocked" \
        '{total: $t, completed: $c, failed: $f, blocked: $b, in_progress: ($t - $c - $f - $b)}'
}

# ── Clear journal ───────────────────────────────────────────

clear_journal() {
    rm -f "$JOURNAL_FILE" "$JOURNAL_MD"
    echo "Journal cleared."
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-last}" in
    append)   shift; append "$@" ;;
    last)     shift; last "${1:-3}" ;;
    summary)  last_summary ;;
    timeline) shift; timeline "${1:-5}" ;;
    stats)    stats ;;
    clear)    clear_journal ;;
    md)
        if [[ -f "$JOURNAL_MD" ]]; then
            cat "$JOURNAL_MD"
        else
            echo "No journal entries yet."
        fi
        ;;
    *)
        echo "Usage: journal.sh {append <task> <summary> [status] [next]|last [n]|summary|timeline [n]|stats|clear|md}"
        ;;
esac
