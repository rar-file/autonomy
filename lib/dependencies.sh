#!/bin/bash
# Task Dependency Management System
# Allows tasks to depend on other tasks completing first

AUTONOMY_DIR="${AUTONOMY_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/autonomy}"
TASKS_DIR="$AUTONOMY_DIR/tasks"

# Add a dependency to a task
add_dependency() {
    local task_name="$1"
    local dependency_name="$2"
    
    local task_file="$TASKS_DIR/${task_name}.json"
    
    if [[ ! -f "$task_file" ]]; then
        echo "Error: Task '$task_name' not found"
        return 1
    fi
    
    if [[ ! -f "$TASKS_DIR/${dependency_name}.json" ]]; then
        echo "Error: Dependency task '$dependency_name' not found"
        return 1
    fi
    
    # Add dependency to task
    local tmp_file="${task_file}.tmp"
    jq --arg dep "$dependency_name" '
        .dependencies = (.dependencies // []) |
        if (.dependencies | index($dep)) then
            .
        else
            .dependencies += [$dep]
        end
    ' "$task_file" > "$tmp_file" && mv "$tmp_file" "$task_file"
    
    echo "Added dependency: $task_name now depends on $dependency_name"
}

# Remove a dependency from a task
remove_dependency() {
    local task_name="$1"
    local dependency_name="$2"
    
    local task_file="$TASKS_DIR/${task_name}.json"
    
    if [[ ! -f "$task_file" ]]; then
        echo "Error: Task '$task_name' not found"
        return 1
    fi
    
    local tmp_file="${task_file}.tmp"
    jq --arg dep "$dependency_name" '
        .dependencies = (.dependencies // []) | 
        .dependencies = (.dependencies - [$dep])
    ' "$task_file" > "$tmp_file" && mv "$tmp_file" "$task_file"
    
    echo "Removed dependency: $task_name no longer depends on $dependency_name"
}

# Check if a task can be started (all dependencies satisfied)
can_start() {
    local task_name="$1"
    
    local task_file="$TASKS_DIR/${task_name}.json"
    
    if [[ ! -f "$task_file" ]]; then
        echo '{"can_start": false, "error": "Task not found"}'
        return 1
    fi
    
    local dependencies=$(jq -r '.dependencies // [] | .[]' "$task_file" 2>/dev/null)
    
    if [[ -z "$dependencies" ]]; then
        echo '{"can_start": true, "dependencies": [], "pending": []}'
        return 0
    fi
    
    local pending_deps=()
    for dep in $dependencies; do
        local dep_file="$TASKS_DIR/${dep}.json"
        if [[ -f "$dep_file" ]]; then
            local completed=$(jq -r '.completed // false' "$dep_file")
            if [[ "$completed" != "true" ]]; then
                pending_deps+=("$dep")
            fi
        fi
    done
    
    if [[ ${#pending_deps[@]} -eq 0 ]]; then
        echo "{\"can_start\": true, \"dependencies\": [$([ ${#dependencies[@]} -gt 0 ] && echo "\"$(echo $dependencies | sed 's/ /\",\"/g')\"" || echo "")], \"pending\": []}"
        return 0
    else
        local pending_json=$(printf '"%s",' "${pending_deps[@]}" | sed 's/,$//')
        echo "{\"can_start\": false, \"dependencies\": [$([ ${#dependencies[@]} -gt 0 ] && echo "\"$(echo $dependencies | sed 's/ /\",\"/g')\"" || echo "")], \"pending\": [$pending_json]}"
        return 1
    fi
}

# List all dependencies for a task
list_dependencies() {
    local task_name="$1"
    
    local task_file="$TASKS_DIR/${task_name}.json"
    
    if [[ ! -f "$task_file" ]]; then
        echo "Error: Task '$task_name' not found"
        return 1
    fi
    
    echo "Dependencies for '$task_name':"
    local deps=$(jq -r '.dependencies // [] | .[]' "$task_file" 2>/dev/null)
    
    if [[ -z "$deps" ]]; then
        echo "  (none)"
        return 0
    fi
    
    for dep in $deps; do
        local dep_file="$TASKS_DIR/${dep}.json"
        if [[ -f "$dep_file" ]]; then
            local status=$(jq -r '.status // "unknown"' "$dep_file")
            local completed=$(jq -r '.completed // false' "$dep_file")
            local icon="⏳"
            [[ "$completed" == "true" ]] && icon="✅"
            echo "  $icon $dep (status: $status)"
        else
            echo "  ❓ $dep (task not found)"
        fi
    done
}

# Find all tasks that depend on a given task
find_dependents() {
    local dependency_name="$1"
    
    echo "Tasks that depend on '$dependency_name':"
    local found=0
    
    for task_file in "$TASKS_DIR"/*.json; do
        [[ -f "$task_file" ]] || continue
        
        local task_name=$(basename "$task_file" .json)
        local deps=$(jq -r '.dependencies // [] | .[]' "$task_file" 2>/dev/null)
        
        for dep in $deps; do
            if [[ "$dep" == "$dependency_name" ]]; then
                local status=$(jq -r '.status // "unknown"' "$task_file")
                echo "  • $task_name (status: $status)"
                found=1
                break
            fi
        done
    done
    
    if [[ $found -eq 0 ]]; then
        echo "  (none)"
    fi
}

# Get all tasks ready to start (dependencies satisfied)
get_ready_tasks() {
    echo "Tasks ready to start (all dependencies satisfied):"
    local found=0
    
    for task_file in "$TASKS_DIR"/*.json; do
        [[ -f "$task_file" ]] || continue
        
        local task_name=$(basename "$task_file" .json)
        local status=$(jq -r '.status // "pending"' "$task_file")
        local completed=$(jq -r '.completed // false' "$task_file")
        
        # Skip completed tasks
        [[ "$completed" == "true" ]] && continue
        
        # Skip already processing tasks
        [[ "$status" == "ai_processing" ]] && continue
        
        # Check if can start
        local result=$(can_start "$task_name")
        if echo "$result" | jq -e '.can_start' >/dev/null 2>&1; then
            echo "  • $task_name"
            found=1
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo "  (none - all tasks have pending dependencies or are completed)"
    fi
}

# Visualize dependency graph
show_graph() {
    echo "Task Dependency Graph:"
    echo ""
    
    for task_file in "$TASKS_DIR"/*.json; do
        [[ -f "$task_file" ]] || continue
        
        local task_name=$(basename "$task_file" .json)
        local deps=$(jq -r '.dependencies // [] | .[]' "$task_file" 2>/dev/null)
        local completed=$(jq -r '.completed // false' "$task_file")
        
        local icon="⏳"
        [[ "$completed" == "true" ]] && icon="✅"
        
        if [[ -n "$deps" ]]; then
            echo "$icon $task_name"
            for dep in $deps; do
                local dep_file="$TASKS_DIR/${dep}.json"
                local dep_icon="⏳"
                if [[ -f "$dep_file" ]]; then
                    local dep_completed=$(jq -r '.completed // false' "$dep_file")
                    [[ "$dep_completed" == "true" ]] && dep_icon="✅"
                fi
                echo "  └─> $dep_icon $dep"
            done
            echo ""
        fi
    done
}

# Setup wizard for creating a task with dependencies
setup_wizard() {
    echo "═══════════════════════════════════════════════════════"
    echo "  Task Dependency Setup"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    
    read -p "Task name: " task_name
    read -p "Task description: " description
    
    # Check if task exists
    if [[ -f "$TASKS_DIR/${task_name}.json" ]]; then
        echo "Task already exists. Adding dependencies to existing task."
    else
        # Create the task
        cat > "$TASKS_DIR/${task_name}.json" << EOF
{
  "name": "$task_name",
  "description": "$description",
  "status": "pending",
  "priority": "normal",
  "created": "$(date -Iseconds)",
  "assignee": "self",
  "subtasks": [],
  "completed": false,
  "attempts": 0,
  "max_attempts": 3,
  "dependencies": [],
  "verification": null,
  "evidence": []
}
EOF
        echo "Created task: $task_name"
    fi
    
    echo ""
    echo "Available tasks to depend on:"
    for f in "$TASKS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local name=$(basename "$f" .json)
        [[ "$name" == "$task_name" ]] && continue
        echo "  • $name"
    done
    
    echo ""
    read -p "Add dependency (task name, or empty to finish): " dep_name
    
    while [[ -n "$dep_name" ]]; do
        if [[ -f "$TASKS_DIR/${dep_name}.json" ]]; then
            add_dependency "$task_name" "$dep_name"
        else
            echo "Task '$dep_name' not found"
        fi
        read -p "Add another dependency (or empty to finish): " dep_name
    done
    
    echo ""
    echo "Task '$task_name' configured with dependencies"
    list_dependencies "$task_name"
}

# Command dispatch
case "${1:-status}" in
    add)
        add_dependency "$2" "$3"
        ;;
    remove)
        remove_dependency "$2" "$3"
        ;;
    check)
        can_start "$2"
        ;;
    list)
        list_dependencies "$2"
        ;;
    dependents)
        find_dependents "$2"
        ;;
    ready)
        get_ready_tasks
        ;;
    graph)
        show_graph
        ;;
    setup)
        setup_wizard
        ;;
    *)
        echo "Usage: $0 {add|remove|check|list|dependents|ready|graph|setup}"
        echo ""
        echo "Commands:"
        echo "  add <task> <dependency>    - Add dependency to task"
        echo "  remove <task> <dependency> - Remove dependency from task"
        echo "  check <task>               - Check if task can start"
        echo "  list <task>                - List task dependencies"
        echo "  dependents <task>          - Find tasks that depend on this"
        echo "  ready                      - List all tasks ready to start"
        echo "  graph                      - Show dependency graph"
        echo "  setup                      - Interactive setup wizard"
        exit 1
        ;;
esac
