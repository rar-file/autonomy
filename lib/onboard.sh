#!/bin/bash
# Onboarding Wizard for Autonomy
# Multi-channel: CLI, Web, Chat

AUTONOMY_DIR="${AUTONOMY_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/autonomy}"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
ONBOARDING_FILE="$AUTONOMY_DIR/state/onboarding.json"

mkdir -p "$AUTONOMY_DIR/state"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if onboarding is complete
is_onboarded() {
    if [[ -f "$ONBOARDING_FILE" ]]; then
        local completed=$(jq -r '.completed // false' "$ONBOARDING_FILE" 2>/dev/null)
        [[ "$completed" == "true" ]] && return 0
    fi
    return 1
}

# Mark onboarding complete
mark_complete() {
    cat > "$ONBOARDING_FILE" << EOF
{
  "completed": true,
  "completed_at": "$(date -Iseconds)",
  "version": "2.0.0"
}
EOF
}

# Reset onboarding
reset_onboarding() {
    rm -f "$ONBOARDING_FILE"
    echo "Onboarding reset. Run 'autonomy onboard' to start again."
}

# Show welcome banner
show_welcome() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo -e "  ${CYAN}👋 Welcome to rar-file/autonomy${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  This is your agentic self-improvement system."
    echo "  The AI decides what to work on and executes autonomously."
    echo ""
    echo "  Let's get you set up in the next 2 minutes..."
    echo ""
}

# Step 1: Overview
step_overview() {
    echo ""
    echo -e "${BLUE}📚 What Autonomy Can Do:${NC}"
    echo ""
    echo "  1. 🤖 AGENTIC MODE - AI decides what to work on"
    echo "  2. 📋 Task Management - Create, track, complete tasks"
    echo "  3. ⏰ Scheduled Work - Recurring automated checks"
    echo "  4. 📧 Notifications - Email alerts on completions"
    echo "  5. 🔐 API Security - Rate limiting & authentication"
    echo "  6. 📊 Metrics Dashboard - Visualize activity"
    echo "  7. 🔗 Dependencies - Task chaining"
    echo "  8. 📝 Templates - Reusable task patterns"
    echo ""
    read -p "Press Enter to continue..."
}

# Step 2: Workstation Setup
step_workstation() {
    echo ""
    echo -e "${BLUE}⚡ Step 1: Activate Your Workstation${NC}"
    echo ""
    
    local active=$(jq -r '.workstation.active // false' "$CONFIG_FILE")
    
    if [[ "$active" == "true" ]]; then
        echo -e "  ${GREEN}✅ Workstation is already active!${NC}"
    else
        echo "  The workstation is the heart of autonomy."
        echo "  When active, the AI will process tasks automatically."
        echo ""
        read -p "  Activate workstation now? (y/n): " activate
        
        if [[ "$activate" == "y" ]]; then
            bash "$AUTONOMY_DIR/autonomy" on
            echo ""
            echo -e "  ${GREEN}✅ Workstation activated!${NC}"
        fi
    fi
    echo ""
}

# Step 3: Scheduler Setup
step_scheduler() {
    echo ""
    echo -e "${BLUE}⏰ Step 2: Set Up Scheduler${NC}"
    echo ""
    
    local scheduler_type=$(jq -r '.scheduler.type // "daemon"' "$CONFIG_FILE")
    local daemon_running=$(pgrep -f "daemon.sh" >/dev/null 2>&1 && echo "true" || echo "false")
    
    echo "  Scheduler type: $scheduler_type"
    
    if [[ "$daemon_running" == "true" ]]; then
        echo -e "  ${GREEN}✅ Daemon is running${NC}"
    else
        echo "  The daemon runs every 10 minutes to flag tasks for AI processing."
        echo ""
        read -p "  Start the daemon now? (y/n): " start_daemon
        
        if [[ "$start_daemon" == "y" ]]; then
            bash "$AUTONOMY_DIR/daemon.sh" start
        fi
    fi
    echo ""
}

# Step 4: Web UI Setup
step_webui() {
    echo ""
    echo -e "${BLUE}🌐 Step 3: Web Dashboard${NC}"
    echo ""
    
    echo "  The web UI provides a visual interface at:"
    echo -e "  ${CYAN}http://localhost:8767${NC}"
    echo ""
    echo "  Features:"
    echo "    • Real-time task monitoring"
    echo "    • Metrics dashboard with charts"
    echo "    • Mobile-responsive PWA"
    echo "    • Dark/light theme"
    echo ""
    
    read -p "  Would you like to start the web UI? (y/n): " start_web
    
    if [[ "$start_web" == "y" ]]; then
        cd "$AUTONOMY_DIR"
        nohup python3 web_ui.py > /tmp/webui.log 2>&1 &
        sleep 2
        echo ""
        echo -e "  ${GREEN}✅ Web UI started at http://localhost:8767${NC}"
        echo ""
    fi
}

# Step 5: Optional Features
step_optional() {
    echo ""
    echo -e "${BLUE}🔧 Step 4: Optional Features${NC}"
    echo ""
    
    echo "  These features enhance your experience:"
    echo ""
    
    # Email notifications
    read -p "  1. Set up email notifications? (y/n): " setup_email
    if [[ "$setup_email" == "y" ]]; then
        bash "$AUTONOMY_DIR/lib/notify.sh" setup
    fi
    
    echo ""
    
    # API tokens
    read -p "  2. Create API token for integrations? (y/n): " setup_api
    if [[ "$setup_api" == "y" ]]; then
        bash "$AUTONOMY_DIR/lib/api-auth.sh" setup
    fi
    
    echo ""
}

# Step 6: Quick Tutorial
step_tutorial() {
    echo ""
    echo -e "${BLUE}🎓 Quick Tutorial${NC}"
    echo ""
    
    echo "  Essential commands:"
    echo ""
    echo -e "  ${CYAN}autonomy status${NC}      - Check system status"
    echo -e "  ${CYAN}autonomy work "..."${NC}  - Give the AI a task"
    echo -e "  ${CYAN}autonomy task list${NC}   - View all tasks"
    echo -e "  ${CYAN}autonomy template list${NC} - View task templates"
    echo -e "  ${CYAN}autonomy daemon status${NC} - Check heartbeat daemon"
    echo ""
    
    echo "  Example - Create your first task:"
    echo -e "  ${YELLOW}autonomy work "Organize my project files"${NC}"
    echo ""
    
    read -p "Press Enter to finish setup..."
}

# Complete onboarding
step_complete() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo -e "  ${GREEN}🎉 Setup Complete!${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  Your autonomy system is ready to use."
    echo ""
    echo "  Next steps:"
    echo "    1. Visit http://localhost:8767 for the dashboard"
    echo "    2. Run 'autonomy work \"your task\"' to get started"
    echo "    3. The AI will process tasks automatically every 10 min"
    echo ""
    echo "  Need help? Run: autonomy help"
    echo ""
    
    mark_complete
}

# Run full onboarding
run_onboarding() {
    if is_onboarded; then
        echo ""
        echo "✅ Onboarding already completed!"
        echo ""
        read -p "Run onboarding again? (y/n): " rerun
        [[ "$rerun" != "y" ]] && return 0
    fi
    
    show_welcome
    step_overview
    step_workstation
    step_scheduler
    step_webui
    step_optional
    step_tutorial
    step_complete
}

# Quick setup - non-interactive
quick_setup() {
    echo "Running quick setup..."
    
    # Activate workstation
    local active=$(jq -r '.workstation.active // false' "$CONFIG_FILE")
    if [[ "$active" != "true" ]]; then
        tmp_file="${CONFIG_FILE}.tmp"
        jq '.workstation.active = true' "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"
        echo "✅ Workstation activated"
    fi
    
    # Start daemon if not running
    if ! pgrep -f "daemon.sh" >/dev/null 2>&1; then
        bash "$AUTONOMY_DIR/daemon.sh" start >/dev/null 2>&1
        echo "✅ Daemon started"
    fi
    
    mark_complete
    echo "✅ Quick setup complete!"
}

# Show onboarding status
status() {
    if is_onboarded; then
        echo "✅ Onboarding completed"
        cat "$ONBOARDING_FILE"
    else
        echo "❌ Onboarding not completed"
        echo "Run 'autonomy onboard' to get started"
    fi
}

# Command dispatch
case "${1:-run}" in
    run|start)
        run_onboarding
        ;;
    quick)
        quick_setup
        ;;
    reset)
        reset_onboarding
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {run|quick|reset|status}"
        echo ""
        echo "Commands:"
        echo "  run    - Interactive onboarding wizard"
        echo "  quick  - Non-interactive quick setup"
        echo "  reset  - Reset onboarding (start over)"
        echo "  status - Check onboarding status"
        exit 1
        ;;
esac
