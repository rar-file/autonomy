#!/bin/bash
# Master Control for Autonomy System
# Prevents multiple instances from running

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"

# Count running daemons (exclude grep and this script)
count_daemons() {
    pgrep -f "daemon.sh" 2>/dev/null | while read pid; do
        if ps -p "$pid" -o comm= 2>/dev/null | grep -q "bash"; then
            echo 1
        fi
    done | wc -l
}

# Count web UI processes (exclude grep)
count_webui() {
    pgrep -f "web_ui.py" 2>/dev/null | wc -l
}

# Count processor processes (exclude grep)  
count_processor() {
    pgrep -f "processor.sh" 2>/dev/null | while read pid; do
        if ps -p "$pid" -o comm= 2>/dev/null | grep -q "bash"; then
            echo 1
        fi
    done | wc -l
}

# Main command dispatcher
case "${1:-status}" in
    start)
        echo "Starting Autonomy System..."
        echo ""
        
        # Check for existing daemons
        daemon_count=$(count_daemons)
        if [[ $daemon_count -gt 0 ]]; then
            echo "⚠️  WARNING: $daemon_count daemon(s) already running!"
            echo "   Use './control.sh restart' instead of start."
            echo ""
            read -p "Force kill existing and start fresh? (y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                echo "   Stopping existing daemons..."
                pkill -9 -f "daemon.sh" 2>/dev/null
                rm -f "$AUTONOMY_DIR/state/heartbeat-daemon.pid"
                sleep 1
            else
                echo "Cancelled."
                exit 1
            fi
        fi
        
        # Start daemon
        echo "Starting daemon..."
        "$AUTONOMY_DIR/daemon.sh" start 2>/dev/null
        
        # Start web UI with guardian (always runs)
        webui_count=$(count_webui)
        if [[ $webui_count -eq 0 ]]; then
            echo "Starting Web UI guardian..."
            nohup bash "$AUTONOMY_DIR/webui_guardian.sh" > /tmp/guardian.log 2>&1 &
            echo "   Guardian PID: $!"
            sleep 2
        else
            echo "Web UI already running ($webui_count process(es))"
        fi
        
        # Start continuous processor
        proc_count=$(count_processor)
        if [[ $proc_count -eq 0 ]]; then
            echo "Starting processor..."
            nohup bash "$AUTONOMY_DIR/processor.sh" continuous > /tmp/processor.log 2>&1 &
            echo "   Processor PID: $!"
        else
            echo "Processor already running ($proc_count process(es))"
        fi
        
        echo ""
        echo "✅ System started"
        echo ""
        echo "Services:"
        echo "   Daemon: $(count_daemons) process(es)"
        echo "   Web UI: $(count_webui) process(es) - http://localhost:8767"
        echo "   Processor: $(count_processor) process(es)"
        echo ""
        echo "Logs:"
        echo "   Web UI: tail -f /tmp/webui.log"
        echo "   Processor: tail -f /tmp/processor.log"
        ;;
        
    stop)
        echo "Stopping Autonomy System..."
        
        daemon_count=$(count_daemons)
        webui_count=$(count_webui)
        proc_count=$(count_processor)
        
        echo "   Stopping $daemon_count daemon(s)..."
        pkill -9 -f "daemon.sh" 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/heartbeat-daemon.pid" 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/daemon.lock" 2>/dev/null
        
        echo "   Stopping $webui_count web UI process(es)..."
        pkill -9 -f "webui_guardian.sh" 2>/dev/null
        pkill -9 -f "web_ui.py" 2>/dev/null
        
        echo "   Stopping $proc_count processor(s)..."
        pkill -9 -f "processor.sh" 2>/dev/null
        
        echo ""
        echo "✅ System stopped"
        ;;
        
    status)
        echo "=== AUTONOMY SYSTEM STATUS ==="
        echo ""
        
        # Daemon status
        daemon_count=$(count_daemons)
        if [[ $daemon_count -eq 1 ]]; then
            echo "✅ Daemon: Running (1 process)"
            "$AUTONOMY_DIR/daemon.sh" status 2>/dev/null | head -2
        elif [[ $daemon_count -gt 1 ]]; then
            echo "🔴 ERROR: $daemon_count daemons running (should be 1!)"
            echo "   Run './control.sh restart' to fix"
        else
            echo "❌ Daemon: Not running"
        fi
        
        # Web UI status
        webui_count=$(count_webui)
        if [[ $webui_count -ge 1 ]]; then
            echo "✅ Web UI: Running ($webui_count process(es)) - http://localhost:8767"
        else
            echo "❌ Web UI: Not running"
        fi
        
        # Processor status
        proc_count=$(count_processor)
        if [[ $proc_count -ge 1 ]]; then
            echo "✅ Processor: Running ($proc_count process(es))"
        else
            echo "❌ Processor: Not running"
        fi
        
        # Task stats
        if [[ -f "$AUTONOMY_DIR/state/processor_stats.json" ]]; then
            echo ""
            echo "Task Stats:"
            jq -r '"  Total: \(.total_tasks), Pending: \(.pending), Completed: \(.completed)"' "$AUTONOMY_DIR/state/processor_stats.json" 2>/dev/null || echo "  Stats unavailable"
        fi
        ;;
        
    restart)
        echo "Restarting Autonomy System..."
        $0 stop
        sleep 2
        $0 start
        ;;
        
    webui)
        # Just restart web UI
        echo "Restarting Web UI..."
        pkill -9 -f "webui_guardian.sh" 2>/dev/null
        pkill -9 -f "web_ui.py" 2>/dev/null
        sleep 1
        nohup bash "$AUTONOMY_DIR/webui_guardian.sh" > /tmp/guardian.log 2>&1 &
        echo "✅ Web UI guardian started"
        ;;
        
    process)
        # Run processor once
        bash "$AUTONOMY_DIR/processor.sh" cycle
        ;;
        
    generate)
        # Generate improvements
        bash "$AUTONOMY_DIR/processor.sh" generate
        ;;
        
    fix)
        # Emergency fix - kill everything and start fresh
        echo "🔧 EMERGENCY FIX - Stopping all processes..."
        pkill -9 -f "daemon.sh" 2>/dev/null
        pkill -9 -f "webui_guardian.sh" 2>/dev/null
        pkill -9 -f "web_ui.py" 2>/dev/null
        pkill -9 -f "processor.sh" 2>/dev/null
        pkill -9 -f "auto_reload_server.py" 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/"*.pid 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/"*.lock 2>/dev/null
        echo "   All processes killed"
        echo "   Run './control.sh start' to start fresh"
        ;;
        
    daemon)
        shift
        "$AUTONOMY_DIR/daemon.sh" "$@"
        ;;
        
    workflow|coordinator|processor)
        shift
        "$AUTONOMY_DIR/${1}.sh" "${@:2}"
        ;;
        
    *)
        echo "Usage: $0 {start|stop|restart|status|fix|webui|process|generate}"
        echo ""
        echo "Commands:"
        echo "  start     - Start all services (prevents multiples)"
        echo "  stop      - Stop all services"
        echo "  restart   - Restart all services cleanly"
        echo "  status    - Show system status with process counts"
        echo "  fix       - Emergency: kill all processes"
        echo "  webui     - Restart just the web UI"
        echo "  process   - Run processor cycle once"
        echo "  generate  - Generate improvement tasks"
        ;;
esac
