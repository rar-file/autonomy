#!/bin/bash
# Task Templates System
# Create tasks from predefined templates

AUTONOMY_DIR="${AUTONOMY_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/autonomy}"
TEMPLATES_DIR="$AUTONOMY_DIR/templates"
TASKS_DIR="$AUTONOMY_DIR/tasks"

mkdir -p "$TEMPLATES_DIR"

# Initialize default templates if none exist
init_templates() {
    if [[ ! -f "$TEMPLATES_DIR/bug-fix.json" ]]; then
        cat > "$TEMPLATES_DIR/bug-fix.json" << 'EOF'
{
  "name": "bug-fix",
  "description": "Fix a bug: investigate, reproduce, fix, test",
  "status": "pending",
  "priority": "high",
  "subtasks": [
    "Investigate the bug and understand root cause",
    "Reproduce the bug locally",
    "Implement the fix",
    "Write/update tests",
    "Verify fix works"
  ],
  "max_attempts": 3
}
EOF
    fi
    
    if [[ ! -f "$TEMPLATES_DIR/feature.json" ]]; then
        cat > "$TEMPLATES_DIR/feature.json" << 'EOF'
{
  "name": "feature",
  "description": "Implement new feature: design, code, test, document",
  "status": "pending",
  "priority": "normal",
  "subtasks": [
    "Design the feature",
    "Implement core functionality",
    "Add tests",
    "Update documentation",
    "Deploy and verify"
  ],
  "max_attempts": 3
}
EOF
    fi
    
    if [[ ! -f "$TEMPLATES_DIR/research.json" ]]; then
        cat > "$TEMPLATES_DIR/research.json" << 'EOF'
{
  "name": "research",
  "description": "Research topic: search, summarize, document findings",
  "status": "pending",
  "priority": "normal",
  "subtasks": [
    "Search for relevant information",
    "Read and analyze sources",
    "Summarize findings",
    "Document conclusions",
    "Create actionable recommendations"
  ],
  "max_attempts": 3
}
EOF
    fi
    
    if [[ ! -f "$TEMPLATES_DIR/refactor.json" ]]; then
        cat > "$TEMPLATES_DIR/refactor.json" << 'EOF'
{
  "name": "refactor",
  "description": "Refactor code: analyze, improve, test, verify",
  "status": "pending",
  "priority": "low",
  "subtasks": [
    "Analyze current code",
    "Identify improvement areas",
    "Refactor with tests passing",
    "Verify no regressions",
    "Update documentation"
  ],
  "max_attempts": 3
}
EOF
    fi
    
    if [[ ! -f "$TEMPLATES_DIR/documentation.json" ]]; then
        cat > "$TEMPLATES_DIR/documentation.json" << 'EOF'
{
  "name": "documentation",
  "description": "Write documentation: outline, draft, review, publish",
  "status": "pending",
  "priority": "normal",
  "subtasks": [
    "Create outline",
    "Write first draft",
    "Review and edit",
    "Add examples",
    "Publish/update"
  ],
  "max_attempts": 3
}
EOF
    fi
    
    echo "Default templates initialized"
}

# List available templates
list_templates() {
    echo "Available templates:"
    echo ""
    for template in "$TEMPLATES_DIR"/*.json; do
        [[ -f "$template" ]] || continue
        local name=$(basename "$template" .json)
        local desc=$(jq -r '.description' "$template" 2>/dev/null || echo "No description")
        local subtasks=$(jq -r '.subtasks | length' "$template" 2>/dev/null || echo 0)
        echo "  • $name"
        echo "    $desc"
        echo "    Subtasks: $subtasks"
        echo ""
    done
}

# Create a task from a template
create_from_template() {
    local template_name="$1"
    local task_name="$2"
    local custom_desc="${3:-}"
    
    local template_file="$TEMPLATES_DIR/${template_name}.json"
    
    if [[ ! -f "$template_file" ]]; then
        echo "Error: Template '$template_name' not found"
        echo "Run 'autonomy template list' to see available templates"
        return 1
    fi
    
    if [[ -z "$task_name" ]]; then
        echo "Usage: autonomy template create <template> <task-name> [description]"
        return 1
    fi
    
    local task_file="$TASKS_DIR/${task_name}.json"
    
    if [[ -f "$task_file" ]]; then
        echo "Error: Task '$task_name' already exists"
        return 1
    fi
    
    # Read template and customize
    local template_data=$(cat "$template_file")
    local description="$custom_desc"
    if [[ -z "$description" ]]; then
        description=$(echo "$template_data" | jq -r '.description')
    fi
    
    # Create task from template
    jq --arg name "$task_name" \
        --arg desc "$description" \
        --arg date "$(date -Iseconds)" \
        --arg tmpl "$template_name" \
        '{
            name: $name,
            description: $desc,
            status: .status,
            priority: .priority,
            created: $date,
            assignee: "self",
            subtasks: .subtasks,
            completed: false,
            attempts: 0,
            max_attempts: .max_attempts,
            verification: null,
            evidence: [],
            template: $tmpl
        }' "$template_file" > "$task_file"
    
    echo "✅ Created task '$task_name' from template '$template_name'"
    echo ""
    echo "Subtasks:"
    echo "$template_data" | jq -r '.subtasks[] | "  • " + .'
}

# Show template details
show_template() {
    local template_name="$1"
    local template_file="$TEMPLATES_DIR/${template_name}.json"
    
    if [[ ! -f "$template_file" ]]; then
        echo "Error: Template '$template_name' not found"
        return 1
    fi
    
    echo "Template: $template_name"
    echo ""
    jq '.' "$template_file"
}

# Create a new template from a task
save_as_template() {
    local task_name="$1"
    local template_name="$2"
    
    local task_file="$TASKS_DIR/${task_name}.json"
    local template_file="$TEMPLATES_DIR/${template_name}.json"
    
    if [[ ! -f "$task_file" ]]; then
        echo "Error: Task '$task_name' not found"
        return 1
    fi
    
    # Extract template fields from task
    jq '{
        name: .name,
        description: .description,
        status: "pending",
        priority: .priority,
        subtasks: .subtasks,
        max_attempts: .max_attempts
    }' "$task_file" > "$template_file"
    
    echo "✅ Saved task '$task_name' as template '$template_name'"
}

# Setup wizard
create_custom_template() {
    echo "═══════════════════════════════════════════════════════"
    echo "  Create Custom Template"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    
    read -p "Template name (e.g., 'security-audit'): " name
    read -p "Description: " description
    read -p "Priority (low/normal/high): " priority
    priority=${priority:-normal}
    
    echo ""
    echo "Enter subtasks (one per line, empty line to finish):"
    local subtasks=()
    while true; do
        read -p "Subtask: " subtask
        [[ -z "$subtask" ]] && break
        subtasks+=("$subtask")
    done
    
    # Build subtasks JSON array
    local subtasks_json="["
    for i in "${!subtasks[@]}"; do
        [[ $i -gt 0 ]] && subtasks_json+=","
        subtasks_json+="\"${subtasks[$i]}\""
    done
    subtasks_json+="]"
    
    cat > "$TEMPLATES_DIR/${name}.json" << EOF
{
  "name": "$name",
  "description": "$description",
  "status": "pending",
  "priority": "$priority",
  "subtasks": $subtasks_json,
  "max_attempts": 3
}
EOF
    
    echo ""
    echo "✅ Template '$name' created"
}

# Command dispatch
case "${1:-list}" in
    init)
        init_templates
        ;;
    list)
        init_templates >/dev/null 2>&1
        list_templates
        ;;
    create)
        shift
        create_from_template "$@"
        ;;
    show)
        show_template "$2"
        ;;
    save)
        save_as_template "$2" "$3"
        ;;
    new)
        create_custom_template
        ;;
    *)
        echo "Usage: $0 {list|create|show|save|new|init}"
        echo ""
        echo "Commands:"
        echo "  list                    - List available templates"
        echo "  create <tmpl> <name>   - Create task from template"
        echo "  show <template>        - Show template details"
        echo "  save <task> <template> - Save task as template"
        echo "  new                     - Create custom template"
        echo "  init                    - Initialize default templates"
        exit 1
        ;;
esac
