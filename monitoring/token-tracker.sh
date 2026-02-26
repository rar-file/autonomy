#!/bin/bash
# Token Usage Tracker for Autonomy
# Tracks daily/weekly/monthly token consumption

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
CONFIG="$AUTONOMY_DIR/config.json"
METRICS_DIR="$AUTONOMY_DIR/monitoring/metrics"
mkdir -p "$METRICS_DIR"

TODAY=$(date +%Y-%m-%d)
WEEK=$(date +%Y-W%V)
MONTH=$(date +%Y-%m)

# Get current token usage from config
get_current_usage() {
    jq -r '.workstation.token_usage_today // 0' "$CONFIG"
}

# Get daily budget
get_budget() {
    jq -r '.agentic_config.hard_limits.daily_token_budget // 50000' "$CONFIG"
}

# Record token usage
record_usage() {
    local amount="${1:-0}"
    local source="${2:-unknown}"
    local timestamp=$(date -Iseconds)
    
    # Update daily log
    local daily_file="$METRICS_DIR/tokens-${TODAY}.jsonl"
    jq -n \
        --arg ts "$timestamp" \
        --argjson amount "$amount" \
        --arg source "$source" \
        '{timestamp: $ts, amount: $amount, source: $source}' >> "$daily_file"
    
    # Update config
    local current=$(get_current_usage)
    local new_total=$((current + amount))
    jq --argjson new_total "$new_total" '.workstation.token_usage_today = $new_total' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    
    echo "Recorded $amount tokens from $source"
}

# Get today's usage summary
daily_summary() {
    local daily_file="$METRICS_DIR/tokens-${TODAY}.jsonl"
    local budget=$(get_budget)
    
    if [[ ! -f "$daily_file" ]]; then
        echo "No token usage recorded today"
        return
    fi
    
    local total=$(jq -s 'map(.amount) | add' "$daily_file" 2>/dev/null || echo 0)
    local count=$(wc -l < "$daily_file" 2>/dev/null || echo 0)
    local pct=$(echo "scale=1; $total * 100 / $budget" | bc 2>/dev/null || echo 0)
    
    echo "═══════════════════════════════════════"
    echo "  TOKEN USAGE - TODAY ($TODAY)"
    echo "═══════════════════════════════════════"
    echo "  Total Used:  $total tokens"
    echo "  Budget:      $budget tokens"
    echo "  Usage:       ${pct}%"
    echo "  Requests:    $count"
    echo ""
    
    # Warning if over 80%
    if (( $(echo "$pct > 80" | bc -l) )); then
        echo "  ⚠️  WARNING: Approaching daily budget limit!"
    fi
    
    # Show by source
    echo "  Usage by source:"
    jq -s 'group_by(.source) | map({source: .[0].source, total: map(.amount) | add}) | .[] | "    \(.source): \(.total)"' "$daily_file" 2>/dev/null
}

# Weekly summary
weekly_summary() {
    local week_files="$METRICS_DIR/tokens-*.jsonl"
    local total=0
    local files=0
    
    echo "═══════════════════════════════════════"
    echo "  TOKEN USAGE - THIS WEEK ($WEEK)"
    echo "═══════════════════════════════════════"
    
    for f in $METRICS_DIR/tokens-*.jsonl; do
        [[ -f "$f" ]] || continue
        local day_total=$(jq -s 'map(.amount) | add' "$f" 2>/dev/null || echo 0)
        total=$((total + day_total))
        files=$((files + 1))
    done
    
    echo "  Total: $total tokens across $files days"
}

# Monthly summary
monthly_summary() {
    local budget=$(get_budget)
    local monthly_budget=$((budget * 30))
    local total=0
    
    for f in $METRICS_DIR/tokens-*.jsonl; do
        [[ -f "$f" ]] || continue
        local day_total=$(jq -s 'map(.amount) | add' "$f" 2>/dev/null || echo 0)
        total=$((total + day_total))
    done
    
    local pct=$(echo "scale=1; $total * 100 / $monthly_budget" | bc 2>/dev/null || echo 0)
    
    echo "═══════════════════════════════════════"
    echo "  TOKEN USAGE - THIS MONTH ($MONTH)"
    echo "═══════════════════════════════════════"
    echo "  Total Used:  $total tokens"
    echo "  Budget:      $monthly_budget tokens"
    echo "  Usage:       ${pct}%"
}

# Check if budget exceeded
check_budget() {
    local budget=$(get_budget)
    local current=$(get_current_usage)
    local pct=$(echo "scale=0; $current * 100 / $budget" | bc)
    
    if [[ $pct -ge 100 ]]; then
        echo "EXCEEDED:$current/$budget"
        return 1
    elif [[ $pct -ge 90 ]]; then
        echo "WARNING:$current/$budget"
        return 0
    else
        echo "OK:$current/$budget"
        return 0
    fi
}

# Reset daily counter
reset_daily() {
    jq '.workstation.token_usage_today = 0' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    echo "Daily token counter reset"
}

# Main
case "${1:-summary}" in
    record)
        record_usage "${2:-0}" "${3:-manual}"
        ;;
    summary|daily)
        daily_summary
        ;;
    weekly)
        weekly_summary
        ;;
    monthly)
        monthly_summary
        ;;
    check)
        check_budget
        ;;
    reset)
        reset_daily
        ;;
    *)
        echo "Usage: $0 {record <amount> [source]|summary|weekly|monthly|check|reset}"
        exit 1
        ;;
esac
