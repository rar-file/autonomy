#!/bin/bash
# Activity - View autonomy activity history

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
LOG_DIR="$AUTONOMY_DIR/logs"

show_help() {
    cat << EOF
Autonomy Activity Log Viewer

Usage: autonomy activity [options]

Options:
  --today, -t          Show today's activity
  --recent, -r N       Show last N entries (default: 20)
  --checks, -c         Show only check results
  --actions, -a        Show only actions taken
  --errors, -e         Show only errors
  --summary, -s        Show daily summary
  --clear, --clean     Clear old logs (>30 days)
  --export FILE        Export to file

Examples:
  autonomy activity --today
  autonomy activity --recent 50
  autonomy activity --checks --errors
  autonomy activity --summary
EOF
}

# Parse arguments
MODE="recent"
LIMIT=20
FILTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --today|-t)
            MODE="today"
            shift
            ;;
        --recent|-r)
            MODE="recent"
            LIMIT="${2:-20}"
            shift 2
            ;;
        --checks|-c)
            FILTER="checks"
            shift
            ;;
        --actions|-a)
            FILTER="actions"
            shift
            ;;
        --errors|-e)
            FILTER="errors"
            shift
            ;;
        --summary|-s)
            MODE="summary"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Header
echo "═══════════════════════════════════════════════════════════"
echo "  🤖 Autonomy Activity Log"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Collect all log files
ALL_LOGS=$(find "$LOG_DIR" -name "*.jsonl" -type f 2>/dev/null | sort -r)

if [[ -z "$ALL_LOGS" ]]; then
    echo "No activity logs found."
    echo "Autonomy may not have run yet, or logs have been cleared."
    exit 0
fi

# Mode: Today
if [[ "$MODE" == "today" ]]; then
    TODAY=$(date +%Y-%m-%d)
    echo "Activity for today ($TODAY):"
    echo ""
    
    for logfile in $ALL_LOGS; do
        grep "^${TODAY}" "$logfile" 2>/dev/null | while read line; do
            timestamp=$(echo "$line" | jq -r '.timestamp // .time // "unknown"' 2>/dev/null)
            action=$(echo "$line" | jq -r '.action // .check // .phase // "activity"' 2>/dev/null)
            message=$(echo "$line" | jq -r '.message // .status // ""' 2>/dev/null)
            
            printf "  %s │ %-20s │ %s\n" "${timestamp:11:8}" "$action" "$message"
        done
    done
fi

# Mode: Recent
if [[ "$MODE" == "recent" ]]; then
    echo "Last $LIMIT activities:"
    echo ""
    
    # Combine and sort all logs, take last N
    cat $ALL_LOGS 2>/dev/null | jq -s 'sort_by(.timestamp) | reverse | .[0:'$LIMIT']' 2>/dev/null | jq -c '.[]' | while read line; do
        timestamp=$(echo "$line" | jq -r '.timestamp // .time // "unknown"' 2>/dev/null)
        action=$(echo "$line" | jq -r '.action // .check // .phase // "activity"' 2>/dev/null)
        message=$(echo "$line" | jq -r '.message // .status // ""' 2>/dev/null | cut -c1-40)
        
        # Color code by type
        icon="📝"
        [[ "$action" =~ check ]] && icon="🔍"
        [[ "$action" =~ action ]] && icon="⚡"
        [[ "$action" =~ error ]] && icon="❌"
        [[ "$action" =~ complete|success ]] && icon="✅"
        
        printf "  %s │ %s %-18s │ %s\n" "${timestamp:0:19}" "$icon" "$action" "$message"
    done
fi

# Mode: Summary
if [[ "$MODE" == "summary" ]]; then
    echo "Activity Summary:"
    echo ""
    
    # Count by day
    echo "By Day:"
    cat $ALL_LOGS 2>/dev/null | jq -r '.timestamp[0:10]' 2>/dev/null | sort | uniq -c | sort -r | while read count date; do
        printf "  %-12s │ %4d entries\n" "$date" "$count"
    done
    
    echo ""
    echo "By Type:"
    cat $ALL_LOGS 2>/dev/null | jq -r '.action // .check // .phase // "other"' 2>/dev/null | sort | uniq -c | sort -r | while read count type; do
        printf "  %-20s │ %4d\n" "$type" "$count"
    done
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Log files: $(echo "$ALL_LOGS" | wc -l) files"
echo "  Location: $LOG_DIR"
echo "═══════════════════════════════════════════════════════════"
