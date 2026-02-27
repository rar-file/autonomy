#!/bin/bash
# Plugin System — Extensible capability loader
# Loads and manages plugins from the plugins/ directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_DIR="$AUTONOMY_DIR/plugins"
PLUGIN_STATE="$AUTONOMY_DIR/state/plugins.json"

mkdir -p "$PLUGINS_DIR"
[[ -f "$PLUGIN_STATE" ]] || echo "[]" > "$PLUGIN_STATE"

# ── Plugin Discovery ────────────────────────────────────────

plugin_discover() {
    local plugins=()
    
    for plugin_file in "$PLUGINS_DIR"/*.sh; do
        [[ -f "$plugin_file" ]] || continue
        
        local name version description
        name=$(basename "$plugin_file" .sh)
        version=$(grep "^# Version:" "$plugin_file" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "unknown")
        description=$(grep "^# Description:" "$plugin_file" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "No description")
        
        plugins+=("$(jq -n --arg name "$name" --arg version "$version" --arg desc "$description" --arg file "$plugin_file" '{name: $name, version: $version, description: $desc, file: $file, loaded: false}')")
    done
    
    printf '%s\n' "${plugins[@]}" | jq -s '.'
}

plugin_list() {
    local discovered
    discovered=$(plugin_discover)
    local loaded
    loaded=$(cat "$PLUGIN_STATE")
    
    echo "Available Plugins:"
    echo "$discovered" | jq -r '.[] | "  • \(.name) v\(.version): \(.description)"'
    echo ""
    echo "Loaded Plugins:"
    echo "$loaded" | jq -r '.[] | "  • \(.name) v\(.version)"'
}

# ── Plugin Loading ──────────────────────────────────────────

plugin_load() {
    local plugin_name="$1"
    local plugin_file="$PLUGINS_DIR/${plugin_name}.sh"
    
    [[ -f "$plugin_file" ]] || {
        echo "Error: Plugin '$plugin_name' not found"
        return 1
    }
    
    # Check if already loaded
    local loaded
    loaded=$(cat "$PLUGIN_STATE" | jq -r "map(select(.name == \"$plugin_name\")) | length")
    
    if [[ "$loaded" -gt 0 ]]; then
        echo "Plugin '$plugin_name' already loaded"
        return 0
    fi
    
    # Load the plugin
    source "$plugin_file"
    
    # Get metadata
    local version description
    version=$(grep "^# Version:" "$plugin_file" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "unknown")
    description=$(grep "^# Description:" "$plugin_file" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "No description")
    
    # Add to loaded plugins
    local new_plugin
    new_plugin=$(jq -n --arg name "$plugin_name" --arg version "$version" --arg desc "$description" --arg file "$plugin_file" --arg loaded_at "$(date -Iseconds)" '{name: $name, version: $version, description: $desc, file: $file, loaded_at: $loaded_at}')
    
    local current
    current=$(cat "$PLUGIN_STATE")
    echo "$current" | jq ". + [$new_plugin]" > "$PLUGIN_STATE"
    
    echo "✓ Plugin '$plugin_name' v$version loaded"
}

plugin_unload() {
    local plugin_name="$1"
    
    local current
    current=$(cat "$PLUGIN_STATE")
    current=$(echo "$current" | jq "map(select(.name != \"$plugin_name\"))")
    echo "$current" > "$PLUGIN_STATE"
    
    echo "✓ Plugin '$plugin_name' unloaded (restart required for full effect)"
}

plugin_reload() {
    local plugin_name="$1"
    
    plugin_unload "$plugin_name"
    plugin_load "$plugin_name"
}

plugin_reload_all() {
    echo "Reloading all plugins..."
    echo "[]" > "$PLUGIN_STATE"
    
    for plugin_file in "$PLUGINS_DIR"/*.sh; do
        [[ -f "$plugin_file" ]] || continue
        local name
        name=$(basename "$plugin_file" .sh)
        plugin_load "$name"
    done
}

# ── Plugin Execution ───────────────────────────────────────

plugin_call() {
    local plugin_name="$1"
    local function_name="$2"
    shift 2
    
    # Check if loaded
    local loaded
    loaded=$(cat "$PLUGIN_STATE" | jq -r "map(select(.name == \"$plugin_name\")) | length")
    
    if [[ "$loaded" -eq 0 ]]; then
        plugin_load "$plugin_name" || return 1
    fi
    
    # Call function
    if type "${plugin_name}_${function_name}" >/dev/null 2>&1; then
        "${plugin_name}_${function_name}" "$@"
    else
        echo "Error: Function '${plugin_name}_${function_name}' not found"
        return 1
    fi
}

# ── Plugin Template Generator ──────────────────────────────

plugin_create_template() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: plugin_create_template <name>"; return 1; }
    
    local template_file="$PLUGINS_DIR/${name}.sh"
    
    cat > "$template_file" << 'EOF'
#!/bin/bash
# Plugin: PLUGIN_NAME
# Description: Describe what this plugin does
# Version: 0.1.0
# Author: Your name
# Dependencies: none

# ── Plugin Initialization ───────────────────────────────────

PLUGIN_NAME_init() {
    echo "PLUGIN_NAME plugin initialized"
}

# ── Plugin Functions ────────────────────────────────────────

# Call with: plugin_call PLUGIN_NAME example_function arg1 arg2
PLUGIN_NAME_example_function() {
    echo "Example function called with args: $*"
}

# ── Main ────────────────────────────────────────────────────

case "${1:-}" in
    init) PLUGIN_NAME_init ;;
    *) echo "Usage: $0 {init|example_function}" ;;
esac
EOF
    
    sed -i "s/PLUGIN_NAME/$name/g" "$template_file"
    chmod +x "$template_file"
    
    echo "✓ Plugin template created: $template_file"
    echo "Edit it and then run: plugin_load $name"
}

# ── Capability Registration ─────────────────────────────────

register_capability() {
    local name="$1"
    local command="$2"
    local description="$3"
    
    local cap_file="$AUTONOMY_DIR/state/capabilities.json"
    [[ -f "$cap_file" ]] || echo "[]" > "$cap_file"
    
    local current
    current=$(cat "$cap_file")
    
    # Check if already exists
    if echo "$current" | jq -e "map(select(.name == \"$name\")) | length > 0" >/dev/null; then
        return 0
    fi
    
    local new_cap
    new_cap=$(jq -n --arg name "$name" --arg cmd "$command" --arg desc "$description" --arg registered "$(date -Iseconds)" '{name: $name, command: $cmd, description: $desc, registered: $registered}')
    
    echo "$current" | jq ". + [$new_cap]" > "$cap_file"
}

discover_capabilities() {
    echo "Registered Capabilities:"
    
    # Built-in capabilities
    echo "  System:"
    echo "    • vm-process-list — List system processes"
    echo "    • vm-service-status — Check systemd services"
    echo "    • vm-docker-ps — List Docker containers"
    echo "    • vm-resource-usage — Monitor resources"
    
    echo "  File Watching:"
    echo "    • watcher-add — Add file watcher"
    echo "    • watcher-check — Check for changes"
    
    echo "  Diagnostics:"
    echo "    • diagnostic-health — Run health checks"
    echo "    • diagnostic-repair — Auto-repair issues"
    
    echo "  Plugins:"
    echo "    • plugin-list — List available plugins"
    echo "    • plugin-load — Load a plugin"
    
    # Dynamic capabilities
    local cap_file="$AUTONOMY_DIR/state/capabilities.json"
    if [[ -f "$cap_file" ]]; then
        echo "  Custom:"
        cat "$cap_file" | jq -r '.[] | "    • \(.name) — \(.description)"'
    fi
}

# ── Command Router ──────────────────────────────────────────

case "${1:-}" in
    list) plugin_list ;;
    load) plugin_load "$2" ;;
    unload) plugin_unload "$2" ;;
    reload) plugin_reload "$2" ;;
    reload_all) plugin_reload_all ;;
    call) shift; plugin_call "$@" ;;
    create) plugin_create_template "$2" ;;
    discover) discover_capabilities ;;
    *)
        echo "Plugin System"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  list                       - List plugins"
        echo "  load <name>                - Load a plugin"
        echo "  unload <name>              - Unload a plugin"
        echo "  reload <name>              - Reload a plugin"
        echo "  reload_all                 - Reload all plugins"
        echo "  call <plugin> <func> [args] - Call plugin function"
        echo "  create <name>              - Create plugin template"
        echo "  discover                   - Show all capabilities"
        ;;
esac
