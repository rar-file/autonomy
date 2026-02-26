#!/bin/bash
# GitHub Actions Integration
# Manage CI/CD workflows and GitHub integration

AUTONOMY_DIR="${AUTONOMY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(dirname "$(dirname "$AUTONOMY_DIR")")}"
WORKFLOWS_DIR="$REPO_DIR/.github/workflows"

# Check if GitHub CLI is installed
check_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "GitHub CLI not installed"
        echo "Install from: https://cli.github.com/"
        return 1
    fi
    return 0
}

# Show workflow status
workflow_status() {
    if [[ ! -d "$WORKFLOWS_DIR" ]]; then
        echo "No workflows directory found"
        return 1
    fi
    
    echo "GitHub Actions Workflows:"
    echo ""
    
    for workflow in "$WORKFLOWS_DIR"/*.yml; do
        [[ -f "$workflow" ]] || continue
        local name=$(basename "$workflow" .yml)
        echo "  • $name"
    done
    
    if check_gh 2>/dev/null; then
        echo ""
        echo "Recent runs:"
        cd "$REPO_DIR" && gh run list --limit 5 2>/dev/null || echo "  No recent runs or not authenticated"
    fi
}

# Trigger a workflow run
trigger_workflow() {
    local workflow="$1"
    local branch="${2:-main}"
    
    if ! check_gh; then
        return 1
    fi
    
    cd "$REPO_DIR"
    gh workflow run "$workflow" --ref "$branch"
    echo "Triggered workflow: $workflow (branch: $branch)"
}

# Watch workflow run
watch_run() {
    local run_id="$1"
    
    if ! check_gh; then
        return 1
    fi
    
    cd "$REPO_DIR"
    gh run watch "$run_id"
}

# View workflow logs
view_logs() {
    local run_id="$1"
    
    if ! check_gh; then
        return 1
    fi
    
    cd "$REPO_DIR"
    gh run view "$run_id" --log
}

# Enable/disable workflow
toggle_workflow() {
    local workflow="$1"
    local action="$2"  # enable or disable
    
    if ! check_gh; then
        return 1
    fi
    
    cd "$REPO_DIR"
    if [[ "$action" == "enable" ]]; then
        gh workflow enable "$workflow"
    else
        gh workflow disable "$workflow"
    fi
}

# Create a new workflow template
create_workflow() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        echo "Usage: create_workflow <name>"
        return 1
    fi
    
    mkdir -p "$WORKFLOWS_DIR"
    
    cat > "$WORKFLOWS_DIR/${name}.yml" << 'EOF'
name: Workflow Name

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  job-name:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Run command
      run: |
        echo "Hello World"
EOF
    
    echo "Created workflow: $WORKFLOWS_DIR/${name}.yml"
}

# Validate workflow syntax
validate_workflow() {
    local workflow="$1"
    
    if ! command -v actionlint >/dev/null 2>&1; then
        echo "actionlint not installed, checking basic syntax..."
        # Basic YAML check
        python3 -c "import yaml; yaml.safe_load(open('$WORKFLOWS_DIR/$workflow.yml'))" 2>&1
        if [[ $? -eq 0 ]]; then
            echo "✅ YAML syntax valid"
        else
            echo "❌ YAML syntax error"
            return 1
        fi
    else
        actionlint "$WORKFLOWS_DIR/$workflow.yml"
    fi
}

# Setup wizard
setup_wizard() {
    echo "═══════════════════════════════════════════════════════"
    echo "  GitHub Actions Setup"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    
    if ! check_gh; then
        echo ""
        echo "GitHub CLI is required. Install it:"
        echo "  https://cli.github.com/"
        return 1
    fi
    
    echo "Checking GitHub authentication..."
    if ! gh auth status >/dev/null 2>&1; then
        echo "Not authenticated. Running 'gh auth login'..."
        gh auth login
    else
        echo "✅ Already authenticated"
    fi
    
    echo ""
    echo "Creating workflows directory..."
    mkdir -p "$WORKFLOWS_DIR"
    
    echo ""
    echo "✅ GitHub Actions setup complete"
    echo ""
    echo "Next steps:"
    echo "  1. Create workflows: autonomy gh create-workflow <name>"
    echo "  2. View status: autonomy gh status"
    echo "  3. Push to GitHub to trigger workflows"
}

# Command dispatch
case "${1:-status}" in
    status)
        workflow_status
        ;;
    trigger)
        trigger_workflow "$2" "$3"
        ;;
    watch)
        watch_run "$2"
        ;;
    logs)
        view_logs "$2"
        ;;
    enable)
        toggle_workflow "$2" "enable"
        ;;
    disable)
        toggle_workflow "$2" "disable"
        ;;
    create-workflow)
        create_workflow "$2"
        ;;
    validate)
        validate_workflow "$2"
        ;;
    setup)
        setup_wizard
        ;;
    *)
        echo "Usage: $0 {status|trigger|watch|logs|enable|disable|create-workflow|validate|setup}"
        echo ""
        echo "Commands:"
        echo "  status                  - Show workflow status"
        echo "  trigger <workflow> [branch] - Trigger workflow run"
        echo "  watch <run-id>         - Watch workflow run"
        echo "  logs <run-id>          - View workflow logs"
        echo "  enable <workflow>      - Enable workflow"
        echo "  disable <workflow>     - Disable workflow"
        echo "  create-workflow <name> - Create new workflow"
        echo "  validate <workflow>    - Validate workflow syntax"
        echo "  setup                   - Interactive setup"
        exit 1
        ;;
esac
