#!/bin/bash
# Adaptive Heartbeat Frequency
# Dynamically adjusts daemon cycle interval based on:
# - Momentum (recent task activity)
# - Queue pressure (pending tasks)
# - Time of day
# - Error rate
# Returns an optimal interval in seconds.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
ADAPTIVE_STATE="$STATE_DIR/adaptive_heartbeat.json"
TASKS_DIR="$AUTONOMY_DIR/tasks"

mkdir -p "$STATE_DIR"

# ── Configuration ───────────────────────────────────────────

# Min/max intervals in seconds
MIN_INTERVAL=30    # 30 seconds minimum (hot)
MAX_INTERVAL=600   # 10 minutes maximum (cold)
BASE_INTERVAL=300  # 5 minutes default

# ── State ───────────────────────────────────────────────────

load_state() {
    if [[ -f "$ADAPTIVE_STATE" ]]; then
        cat "$ADAPTIVE_STATE"
    else
        jq -n '{
            momentum: 50,
            last_interval: 300,
            consecutive_idle: 0,
            consecutive_active: 0,
            task_completed_recently: false,
            error_streak: 0,
            history: []
        }'
    fi
}

save_state() {
    echo "$1" | jq . > "$ADAPTIVE_STATE"
}

# ── Momentum Scoring ───────────────────────────────────────
# 0-100 scale: 0 = completely idle, 100 = very active

calculate_momentum() {
    local state
    state=$(load_state)

    local momentum=50  # Start neutral

    # Factor 1: Pending tasks in queue
    local pending=0
    local in_progress=0
    for f in "$TASKS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local s
        s=$(jq -r '.status // ""' "$f" 2>/dev/null)
        case "$s" in
            pending|needs_ai_attention) pending=$((pending + 1)) ;;
            ai_processing|in-progress)  in_progress=$((in_progress + 1)) ;;
        esac
    done

    # More pending tasks = higher momentum
    [[ $pending -gt 0 ]] && momentum=$((momentum + 10))
    [[ $pending -gt 3 ]] && momentum=$((momentum + 10))
    [[ $pending -gt 5 ]] && momentum=$((momentum + 10))

    # Active processing = very high momentum
    [[ $in_progress -gt 0 ]] && momentum=$((momentum + 20))

    # Factor 2: Recent completions boost
    local task_completed_recently
    task_completed_recently=$(echo "$state" | jq -r '.task_completed_recently // false')
    [[ "$task_completed_recently" == "true" ]] && momentum=$((momentum + 15))

    # Factor 3: Error streak reduces momentum (avoid thrashing)
    local error_streak
    error_streak=$(echo "$state" | jq '.error_streak // 0')
    [[ $error_streak -gt 2 ]] && momentum=$((momentum - 20))

    # Factor 4: Consecutive idle cycles reduce momentum
    local idle_count
    idle_count=$(echo "$state" | jq '.consecutive_idle // 0')
    if [[ $idle_count -gt 3 ]]; then
        momentum=$((momentum - (idle_count * 5)))
    fi

    # Factor 5: Time of day awareness
    local hour
    hour=$(date +%H)
    hour=$((10#$hour))  # Force base-10

    # Off-hours (midnight to 6am): reduce frequency
    if [[ $hour -ge 0 && $hour -lt 6 ]]; then
        momentum=$((momentum - 15))
    fi
    # Peak hours (9am-6pm): slight boost
    if [[ $hour -ge 9 && $hour -lt 18 ]]; then
        momentum=$((momentum + 5))
    fi

    # Clamp to 0-100
    [[ $momentum -gt 100 ]] && momentum=100
    [[ $momentum -lt 0 ]] && momentum=0

    echo "$momentum"
}

# ── Convert Momentum to Interval ───────────────────────────

momentum_to_interval() {
    local momentum="$1"

    # Linear interpolation: high momentum = short interval
    # momentum 100 → MIN_INTERVAL (30s)
    # momentum 0   → MAX_INTERVAL (600s)
    local range=$((MAX_INTERVAL - MIN_INTERVAL))
    local interval=$(( MAX_INTERVAL - (momentum * range / 100) ))

    # Clamp
    [[ $interval -lt $MIN_INTERVAL ]] && interval=$MIN_INTERVAL
    [[ $interval -gt $MAX_INTERVAL ]] && interval=$MAX_INTERVAL

    echo "$interval"
}

# ── Main: Get Adaptive Interval ────────────────────────────

get_adaptive_interval() {
    local momentum
    momentum=$(calculate_momentum)

    local interval
    interval=$(momentum_to_interval "$momentum")

    # Update state
    local state
    state=$(load_state)
    state=$(echo "$state" | jq \
        --argjson m "$momentum" \
        --argjson i "$interval" \
        --arg ts "$(date -Iseconds)" \
        '.momentum = $m | .last_interval = $i |
         .history += [{"at": $ts, "momentum": $m, "interval": $i}] |
         .history = (.history | .[-50:])')
    save_state "$state"

    echo "$interval"
}

# ── Event Signals ───────────────────────────────────────────
# Called by other components to influence momentum

signal_task_completed() {
    local state
    state=$(load_state)
    state=$(echo "$state" | jq '
        .task_completed_recently = true |
        .consecutive_idle = 0 |
        .consecutive_active += 1 |
        .error_streak = 0
    ')
    save_state "$state"
}

signal_task_failed() {
    local state
    state=$(load_state)
    state=$(echo "$state" | jq '.error_streak += 1')
    save_state "$state"
}

signal_idle_cycle() {
    local state
    state=$(load_state)
    state=$(echo "$state" | jq '
        .task_completed_recently = false |
        .consecutive_idle += 1 |
        .consecutive_active = 0
    ')
    save_state "$state"
}

signal_immediate() {
    # Force minimum interval for next cycle
    local state
    state=$(load_state)
    state=$(echo "$state" | jq '.momentum = 100')
    save_state "$state"
    echo "Next cycle will use minimum interval (${MIN_INTERVAL}s)"
}

# ── Status ──────────────────────────────────────────────────

adaptive_status() {
    local momentum
    momentum=$(calculate_momentum)
    local interval
    interval=$(momentum_to_interval "$momentum")

    local state
    state=$(load_state)

    echo "$state" | jq --argjson m "$momentum" --argjson i "$interval" \
        '{
            current_momentum: $m,
            current_interval_seconds: $i,
            current_interval_human: (if $i < 60 then "\($i)s" elif $i < 3600 then "\($i / 60 | floor)m \($i % 60)s" else "\($i / 3600 | floor)h" end),
            consecutive_idle,
            consecutive_active,
            error_streak,
            recent_history: (.history | .[-5:])
        }'
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-interval}" in
    interval)          get_adaptive_interval ;;
    momentum)          calculate_momentum ;;
    status)            adaptive_status ;;
    signal_completed)  signal_task_completed ;;
    signal_failed)     signal_task_failed ;;
    signal_idle)       signal_idle_cycle ;;
    signal_immediate)  signal_immediate ;;
    *)
        echo "Adaptive Heartbeat Frequency"
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  interval           Get current adaptive interval (seconds)"
        echo "  momentum           Calculate current momentum score (0-100)"
        echo "  status             Full adaptive status JSON"
        echo "  signal_completed   Signal a task was completed"
        echo "  signal_failed      Signal a task failed"
        echo "  signal_idle        Signal an idle cycle"
        echo "  signal_immediate   Force minimum interval for next cycle"
        ;;
esac
