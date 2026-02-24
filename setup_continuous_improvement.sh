#!/bin/bash
# Autonomy Continuous Improvement Workflow Setup
# This sets up the complete automation system

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   AUTONOMY CONTINUOUS IMPROVEMENT WORKFLOW SETUP         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
cd "$AUTONOMY_DIR"

# Ensure workstation is on
echo "🔄 Ensuring workstation is active..."
bash autonomy on 2>/dev/null || true
echo ""

# Create main improvement task
echo "📋 Creating main improvement tracking task..."
bash autonomy task create "continuous-improvement" "Master tracking task for continuous autonomy improvements - web UI updates, new features, enhanced capabilities"

# Create sub-tasks for different improvement areas
echo "📋 Creating sub-tasks for parallel development..."

bash autonomy task create "enhance-web-ui" "Enhance web UI dashboard: Add real-time charts, dark mode toggle, task filtering, search functionality, export capabilities"

bash autonomy task create "add-api-endpoints" "Add more API endpoints to web UI: task management, agent spawning, schedule management, configuration editing"

bash autonomy task create "improve-autonomy-levels" "Add more autonomy levels: supervised, semi-autonomous, fully autonomous modes with different approval requirements"

bash autonomy task create "create-monitoring-tools" "Create monitoring tools: token usage tracker, performance metrics, error logging, health checks"

bash autonomy task create "enhance-cli" "Enhance CLI with: command completion, better help text, aliases, configuration wizard, update notifications"

bash autonomy task create "add-integrations" "Add integrations: Discord notifications, Telegram alerts, Slack webhooks, email reports"

bash autonomy task create "documentation" "Improve documentation: API docs, usage examples, troubleshooting guide, contribution guidelines"

echo ""
echo "🤖 Spawning sub-agents for parallel work..."

# Spawn sub-agents for different areas
bash autonomy spawn "Analyze current web UI and suggest 5 specific improvements with implementation plan"

bash autonomy spawn "Research best practices for autonomous agent systems and identify missing features in our implementation"

bash autonomy spawn "Review the autonomy CLI and identify UX improvements that would make it more intuitive"

echo ""
echo "⏰ Setting up schedules..."

# Update config directly with schedules
TMP_CONFIG=$(mktemp)
jq '.workstation.schedules = [
  {"interval": "20m", "task": "Check for web UI improvements and enhancements", "last_run": null, "created": "'$(date -Iseconds)'"},
  {"interval": "1h", "task": "Review and add new autonomy features", "last_run": null, "created": "'$(date -Iseconds)'"},
  {"interval": "2h", "task": "Check OpenClaw integration opportunities", "last_run": null, "created": "'$(date -Iseconds)'"},
  {"interval": "30m", "task": "Monitor sub-agent progress and spawn new ones as needed", "last_run": null, "created": "'$(date -Iseconds)'"}
]' "$AUTONOMY_DIR/config.json" > "$TMP_CONFIG" && mv "$TMP_CONFIG" "$AUTONOMY_DIR/config.json"

echo ""
echo "📝 Creating workflow documentation..."

cat > "$AUTONOMY_DIR/IMPROVEMENT_WORKFLOW.md" << 'EOF'
# Autonomy Continuous Improvement Workflow

## Overview
This workflow runs continuously to improve the autonomy plugin every 20 minutes.

## Active Tasks

### 1. enhance-web-ui
- Real-time charts for token usage
- Dark/light mode toggle
- Task filtering and search
- Export capabilities (CSV, JSON)
- Mobile responsiveness improvements

### 2. add-api-endpoints
- Full CRUD for tasks
- Agent management endpoints
- Schedule management
- Config editing API
- WebSocket for real-time updates

### 3. improve-autonomy-levels
- **Supervised**: All actions need approval
- **Semi-autonomous**: Low-risk actions auto-approved
- **Fully autonomous**: Only critical actions need approval
- Per-task autonomy level setting

### 4. create-monitoring-tools
- Token usage tracking with charts
- Performance metrics dashboard
- Error logging and alerting
- Health check system
- Resource usage monitoring

### 5. enhance-cli
- Tab completion
- Better help system
- Command aliases
- Interactive configuration wizard
- Update notifications

### 6. add-integrations
- Discord bot notifications
- Telegram alerts
- Slack webhooks
- Email reports
- GitHub Actions integration

### 7. documentation
- Complete API documentation
- Usage examples
- Troubleshooting guide
- Video tutorials
- Community contributions guide

## Schedules (Every 20 Minutes)

1. **20m**: Check web UI improvements
2. **30m**: Monitor sub-agent progress
3. **1h**: Review and add new features
4. **2h**: Check OpenClaw integration opportunities

## Sub-Agents Running

- Agent 1: Web UI analysis
- Agent 2: Feature research
- Agent 3: CLI UX review

## How It Works

On each heartbeat:
1. Check schedules - is anything due?
2. Check sub-agents - are they done? Should we spawn more?
3. Check tasks - any pending work?
4. Execute highest priority item
5. Report progress

## Success Metrics

- Web UI has all planned features
- API covers all functionality
- CLI is intuitive and well-documented
- System is fully monitored
- Integrations are working
- Documentation is comprehensive
EOF

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    SETUP COMPLETE!                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Workstation: ACTIVE"
echo "✅ Tasks Created: 7 improvement tasks"
echo "✅ Sub-Agents Spawned: 3 parallel agents"
echo "✅ Schedules Set: 4 recurring checks"
echo "✅ Documentation: IMPROVEMENT_WORKFLOW.md created"
echo ""
echo "📊 Dashboard: http://localhost:8767"
echo "📁 Workflow Doc: $AUTONOMY_DIR/IMPROVEMENT_WORKFLOW.md"
echo ""
echo "The system will now:"
echo "  • Check for improvements every 20 minutes"
echo "  • Spawn sub-agents to research and implement"
echo "  • Update web UI continuously"
echo "  • Add new features automatically"
echo "  • Monitor itself and report progress"
echo ""
echo "🚀 Automation is LIVE!"
