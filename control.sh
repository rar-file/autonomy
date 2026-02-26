#!/bin/bash
# Master Control for Autonomy System
# Unified process management — daemon handles scheduling + web UI watchdog

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
PID_FILE="$AUTONOMY_DIR/state/daemon.pid"

# Count running daemons (PID-file based — single source of truth)
count_daemons() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "1"
            return
        fi
    fi
    echo "0"
}

# Count web UI processes
count_webui() {
    pgrep -f "web_ui.py" 2>/dev/null | wc -l
}

# Main command dispatcher
case "${1:-status}" in
    start)
        echo "Starting Autonomy System..."
        echo ""

        # Check for existing daemons
        daemon_count=$(count_daemons)
        if [[ $daemon_count -gt 0 ]]; then
            echo "⚠️  Daemon already running."
            echo "   Use './control.sh restart' instead."
            exit 1
        fi

        # Start daemon (daemon auto-starts web UI as watchdog)
        echo "Starting daemon..."
        "$AUTONOMY_DIR/daemon.sh" start

        # Also ensure web UI is up right now
        webui_count=$(count_webui)
        if [[ $webui_count -eq 0 ]]; then
            echo "Starting Web UI..."
            cd "$AUTONOMY_DIR"
            nohup python3 "$AUTONOMY_DIR/web_ui.py" >> "$AUTONOMY_DIR/logs/webui.log" 2>&1 &
            sleep 2
        fi

        echo ""
        echo "✅ System started"
        echo ""
        echo "Services:"
        echo "   Daemon: $(count_daemons) process(es)"
        echo "   Web UI: $(count_webui) process(es) — http://localhost:8767"
        ;;

    stop)
        echo "Stopping Autonomy System..."

        echo "   Stopping daemon..."
        "$AUTONOMY_DIR/daemon.sh" stop 2>/dev/null

        echo "   Stopping web UI..."
        pkill -f "web_ui.py" 2>/dev/null
        pkill -f "webui_guardian.sh" 2>/dev/null

        rm -f "$AUTONOMY_DIR/state/"*.pid 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/"*.lock 2>/dev/null

        echo ""
        echo "✅ System stopped"
        ;;

    status)
        echo "=== AUTONOMY SYSTEM STATUS ==="
        echo ""

        # Daemon status
        daemon_count=$(count_daemons)
        if [[ $daemon_count -eq 1 ]]; then
            echo "✅ Daemon: Running"
            "$AUTONOMY_DIR/daemon.sh" status 2>/dev/null | head -3
        else
            echo "❌ Daemon: Not running"
        fi

        # Web UI status
        webui_count=$(count_webui)
        if [[ $webui_count -ge 1 ]]; then
            echo "✅ Web UI: Running ($webui_count process) — http://localhost:8767"
        else
            echo "❌ Web UI: Not running"
        fi

        # Task stats
        if [[ -f "$AUTONOMY_DIR/state/coordinator_stats.json" ]]; then
            echo ""
            echo "Task Stats:"
            jq -r '"  Total: \(.total_tasks), Pending: \(.pending_tasks), Completed: \(.completed_tasks)"' \
                "$AUTONOMY_DIR/state/coordinator_stats.json" 2>/dev/null || echo "  Stats unavailable"
        fi
        ;;

    restart)
        echo "Restarting Autonomy System..."
        "$0" stop
        sleep 2
        "$0" start
        ;;

    webui)
        echo "Restarting Web UI..."
        pkill -f "webui_guardian.sh" 2>/dev/null
        pkill -f "web_ui.py" 2>/dev/null
        sleep 1
        cd "$AUTONOMY_DIR"
        nohup python3 "$AUTONOMY_DIR/web_ui.py" >> "$AUTONOMY_DIR/logs/webui.log" 2>&1 &
        echo "✅ Web UI started (PID: $!)"
        ;;

    generate)
        bash "$AUTONOMY_DIR/processor.sh" generate
        ;;

    fix)
        echo "🔧 EMERGENCY FIX — Stopping all processes..."
        pkill -f "daemon.sh" 2>/dev/null
        pkill -f "webui_guardian.sh" 2>/dev/null
        pkill -f "web_ui.py" 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/"*.pid 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/"*.lock 2>/dev/null
        rm -f "$AUTONOMY_DIR/state/daemon.stop" 2>/dev/null
        echo "   All processes killed"
        echo "   Run './control.sh start' to start fresh"
        ;;

    daemon)
        shift
        "$AUTONOMY_DIR/daemon.sh" "$@"
        ;;

    coordinator)
        shift
        "$AUTONOMY_DIR/coordinator.sh" "$@"
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|fix|webui|generate|daemon|coordinator}"
        echo ""
        echo "Commands:"
        echo "  start       Start all services (daemon + web UI)"
        echo "  stop        Stop all services"
        echo "  restart     Restart all services cleanly"
        echo "  status      Show system status"
        echo "  fix         Emergency: kill all processes"
        echo "  webui       Restart just the web UI"
        echo "  generate    Generate improvement tasks"
        echo "  daemon      Pass commands to daemon.sh"
        echo "  coordinator Pass commands to coordinator.sh"
        ;;
esac
