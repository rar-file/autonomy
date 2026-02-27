#!/bin/bash
# Token Budget Guard Rails
# Tracks daily token usage and enforces budget limits.
# The AI sees remaining budget in HEARTBEAT.md and self-regulates.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
TOKEN_FILE="$STATE_DIR/token_usage.json"

mkdir -p "$STATE_DIR"

get_config() {
    jq -r "$1" "$CONFIG_FILE" 2>/dev/null
}

# ── Read / write token state ────────────────────────────────

today_key() {
    date +%Y-%m-%d
}

load_state() {
    if [[ -f "$TOKEN_FILE" ]]; then
        cat "$TOKEN_FILE"
    else
        echo '{"date":"'"$(today_key)"'","used":0,"sessions":0,"last_reset":"'"$(date -Iseconds)"'"}'
    fi
}

save_state() {
    echo "$1" > "$TOKEN_FILE"
}

# Auto-reset at midnight (new day)
maybe_reset() {
    local state today day_in_state
    state=$(load_state)
    today=$(today_key)
    day_in_state=$(echo "$state" | jq -r '.date // ""')

    if [[ "$day_in_state" != "$today" ]]; then
        local fresh='{"date":"'"$today"'","used":0,"sessions":0,"last_reset":"'"$(date -Iseconds)"'"}'
        save_state "$fresh"
        echo "$fresh"
    else
        echo "$state"
    fi
}

# ── Public API ──────────────────────────────────────────────

# Record tokens used (called after each AI heartbeat)
record_usage() {
    local tokens="${1:-0}"
    [[ "$tokens" =~ ^[0-9]+$ ]] || tokens=0

    local state
    state=$(maybe_reset)
    local new_used new_sessions
    new_used=$(echo "$state" | jq -r ".used + $tokens")
    new_sessions=$(echo "$state" | jq -r ".sessions + 1")

    state=$(echo "$state" | jq --argjson u "$new_used" --argjson s "$new_sessions" \
        '.used = $u | .sessions = $s | .last_activity = "'"$(date -Iseconds)"'"')
    save_state "$state"

    # Also update config.json for backward compat
    local tmp="${CONFIG_FILE}.tmp.$$"
    jq --argjson t "$new_used" '.workstation.token_usage_today = $t' "$CONFIG_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$CONFIG_FILE"

    echo "$new_used"
}

# Get remaining budget
remaining() {
    local state budget used
    state=$(maybe_reset)
    budget=$(get_config '.agentic_config.hard_limits.daily_token_budget // 50000')
    used=$(echo "$state" | jq -r '.used // 0')
    echo $((budget - used))
}

# Check if budget exceeded — returns exit code 1 if over
check_budget() {
    local rem
    rem=$(remaining)
    if [[ "$rem" -le 0 ]]; then
        echo "BUDGET_EXCEEDED"
        return 1
    fi
    echo "OK:$rem"
    return 0
}

# Summary string for HEARTBEAT.md injection
budget_summary() {
    local state budget used rem pct
    state=$(maybe_reset)
    budget=$(get_config '.agentic_config.hard_limits.daily_token_budget // 50000')
    used=$(echo "$state" | jq -r '.used // 0')
    rem=$((budget - used))
    if [[ "$budget" -gt 0 ]]; then
        pct=$(( (used * 100) / budget ))
    else
        pct=0
    fi

    local sessions
    sessions=$(echo "$state" | jq -r '.sessions // 0')

    if [[ "$rem" -le 0 ]]; then
        echo "BUDGET EXCEEDED — ${used}/${budget} tokens used (${pct}%) across ${sessions} sessions. STOP working and notify the user."
    elif [[ "$pct" -ge 80 ]]; then
        echo "WARNING: ${used}/${budget} tokens (${pct}%) — ${rem} remaining across ${sessions} sessions. Conserve tokens, focus on high-value work only."
    else
        echo "${used}/${budget} tokens (${pct}%) — ${rem} remaining across ${sessions} sessions."
    fi
}

# Full JSON state
show_state() {
    local state budget
    state=$(maybe_reset)
    budget=$(get_config '.agentic_config.hard_limits.daily_token_budget // 50000')
    echo "$state" | jq --argjson b "$budget" '. + {budget: $b, remaining: ($b - .used)}'
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-summary}" in
    record)   record_usage "$2" ;;
    remaining) remaining ;;
    check)    check_budget ;;
    summary)  budget_summary ;;
    state)    show_state ;;
    reset)
        save_state '{"date":"'"$(today_key)"'","used":0,"sessions":0,"last_reset":"'"$(date -Iseconds)"'"}'
        echo "Token budget reset for today"
        ;;
    *)
        echo "Usage: token-budget.sh {record <n>|remaining|check|summary|state|reset}"
        ;;
esac
