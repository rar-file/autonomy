#!/bin/bash
# Skill Acquisition & Tool Creation
# Meta-capability that allows the system to create new tools dynamically,
# register them via the plugin system, and expand its own capabilities.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
TOOLS_DIR="$AUTONOMY_DIR/tools"
PLUGINS_DIR="$AUTONOMY_DIR/plugins"
SKILLS_FILE="$STATE_DIR/skills.json"
SKILLS_LOG="$AUTONOMY_DIR/logs/skills.log"

mkdir -p "$STATE_DIR" "$TOOLS_DIR" "$PLUGINS_DIR" "$AUTONOMY_DIR/logs"

_skill_log() {
    echo "$(date -Iseconds) [$1] $2" >> "$SKILLS_LOG"
}

# ── Skills Registry ─────────────────────────────────────────

init_skills() {
    [[ -f "$SKILLS_FILE" ]] || echo '{
        "skills": [],
        "tool_templates": {},
        "stats": {
            "tools_created": 0,
            "skills_learned": 0,
            "skills_used": 0
        }
    }' > "$SKILLS_FILE"
}

# ── Learn a New Skill ──────────────────────────────────────

# learn <name> <description> <category> [example_usage]
learn_skill() {
    local name="$1"
    local desc="$2"
    local category="${3:-general}"
    local example="${4:-}"

    [[ -z "$name" || -z "$desc" ]] && {
        echo "Usage: skill-acquisition.sh learn <name> <description> <category> [example]"
        return 1
    }

    init_skills

    # Check for duplicate
    local existing
    existing=$(jq -r --arg n "$name" '[.skills[] | select(.name == $n)] | length' "$SKILLS_FILE")
    if [[ "$existing" -gt 0 ]]; then
        echo "Skill already exists: $name"
        return 1
    fi

    local tmp="${SKILLS_FILE}.tmp.$$"
    jq --arg name "$name" --arg desc "$desc" --arg cat "$category" \
       --arg example "$example" --arg ts "$(date -Iseconds)" \
        '.skills += [{
            name: $name,
            description: $desc,
            category: $cat,
            example: $example,
            source_task: (if ($example | startswith("source_task:")) then ($example | ltrimstr("source_task:")) else null end),
            learned_at: $ts,
            use_count: 0,
            has_tool: false,
            tool_name: null
        }] | .stats.skills_learned += 1' \
        "$SKILLS_FILE" > "$tmp" && mv "$tmp" "$SKILLS_FILE"

    # Also store in persistent memory
    if [[ -f "$AUTONOMY_DIR/lib/memory.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/memory.sh" store facts \
            "SKILL[$category]: $name — $desc" 2>/dev/null
    fi

    _skill_log INFO "Learned skill: $name ($category)"
    echo "Learned skill: $name"
}

# ── Create a Tool ──────────────────────────────────────────

# create_tool <name> <description> <commands...>
# Generates a bash tool script in the tools/ directory
create_tool() {
    local name="$1"
    local desc="$2"
    shift 2
    local commands=("$@")

    [[ -z "$name" || -z "$desc" ]] && {
        echo "Usage: skill-acquisition.sh create_tool <name> <description> <cmd1> [cmd2] ..."
        return 1
    }

    local tool_file="$TOOLS_DIR/$name"

    # Don't overwrite existing tools
    if [[ -f "$tool_file" ]]; then
        echo "Tool already exists: $tool_file"
        return 1
    fi

    # Generate tool script
    cat > "$tool_file" << TOOL_HEADER
#!/bin/bash
# Tool: $name
# Description: $desc
# Created: $(date -Iseconds)
# Source: skill-acquisition (auto-generated)

TOOL_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="\$(dirname "\$TOOL_DIR")"

TOOL_HEADER

    # Add command functions
    if [[ ${#commands[@]} -gt 0 ]]; then
        cat >> "$tool_file" << 'TOOL_MAIN'
# ── Tool Functions ──────────────────────────────────────────

run() {
TOOL_MAIN

        for cmd in "${commands[@]}"; do
            echo "    $cmd" >> "$tool_file"
        done

        cat >> "$tool_file" << 'TOOL_END'
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-run}" in
    run)   shift; run "$@" ;;
    help)  echo "Usage: $0 {run|help}" ;;
    *)     run "$@" ;;
esac
TOOL_END
    else
        # Create a template tool
        cat >> "$tool_file" << 'TOOL_TEMPLATE'
# ── Tool Logic ──────────────────────────────────────────────

run() {
    echo "Tool: TOOL_NAME"
    echo "Implement your tool logic here"
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-run}" in
    run)   shift; run "$@" ;;
    help)  echo "Usage: $0 {run|help}" ;;
    *)     run "$@" ;;
esac
TOOL_TEMPLATE
        sed -i "s/TOOL_NAME/$name/g" "$tool_file"
    fi

    chmod +x "$tool_file"

    # Register in skills
    init_skills
    local tmp="${SKILLS_FILE}.tmp.$$"
    jq --arg name "$name" --arg desc "$desc" --arg ts "$(date -Iseconds)" \
        '.stats.tools_created += 1 |
         if ([.skills[] | select(.name == $name)] | length) > 0 then
            (.skills[] | select(.name == $name)) |= (.has_tool = true | .tool_name = $name)
         else
            .skills += [{name: $name, description: $desc, category: "tool", learned_at: $ts, use_count: 0, has_tool: true, tool_name: $name}]
         end' \
        "$SKILLS_FILE" > "$tmp" && mv "$tmp" "$SKILLS_FILE"

    # Register capability in plugin system
    if [[ -f "$AUTONOMY_DIR/capabilities/plugin-system.sh" ]]; then
        source "$AUTONOMY_DIR/capabilities/plugin-system.sh" > /dev/null 2>&1 || true
        register_capability "$name" "bash $tool_file run" "$desc" 2>/dev/null
    fi

    _skill_log INFO "Created tool: $name ($tool_file)"
    echo "Created tool: $name ($tool_file)"
}

# ── Create a Plugin ────────────────────────────────────────

# create_plugin <name> <description> <functions_json>
# functions_json: [{"name":"func1","body":"echo hello"},{"name":"func2","body":"ls -la"}]
create_plugin() {
    local name="$1"
    local desc="$2"
    local functions_json="${3:-[]}"

    [[ -z "$name" || -z "$desc" ]] && {
        echo "Usage: skill-acquisition.sh create_plugin <name> <description> [functions_json]"
        return 1
    }

    local plugin_file="$PLUGINS_DIR/${name}.sh"

    cat > "$plugin_file" << PLUGIN_EOF
#!/bin/bash
# Plugin: $name
# Description: $desc
# Version: 1.0.0
# Author: skill-acquisition (auto-generated)
# Dependencies: none

# ── Plugin Initialization ───────────────────────────────────

${name}_init() {
    echo "$name plugin initialized"
}

PLUGIN_EOF

    # Add functions from JSON
    if [[ "$functions_json" != "[]" ]] && echo "$functions_json" | jq empty 2>/dev/null; then
        local func_count
        func_count=$(echo "$functions_json" | jq 'length')

        for ((i = 0; i < func_count; i++)); do
            local func_name func_body
            func_name=$(echo "$functions_json" | jq -r ".[$i].name")
            func_body=$(echo "$functions_json" | jq -r ".[$i].body")

            cat >> "$plugin_file" << FUNC_EOF
${name}_${func_name}() {
    $func_body
}

FUNC_EOF
        done
    fi

    # Add CLI
    cat >> "$plugin_file" << CLI_EOF
# ── CLI ─────────────────────────────────────────────────────

case "\${1:-}" in
    init) ${name}_init ;;
    *) echo "Usage: \$0 {init|<function_name>}" ;;
esac
CLI_EOF

    chmod +x "$plugin_file"

    # Load the plugin
    if [[ -f "$AUTONOMY_DIR/capabilities/plugin-system.sh" ]]; then
        bash "$AUTONOMY_DIR/capabilities/plugin-system.sh" load "$name" 2>/dev/null
    fi

    _skill_log INFO "Created plugin: $name ($plugin_file)"
    echo "Created plugin: $name"
}

# ── AI-Powered Tool Generation ─────────────────────────────

# Asks AI to generate a tool for a given need
generate_tool() {
    local need="$1"

    [[ -z "$need" ]] && {
        echo "Usage: skill-acquisition.sh generate <description of what the tool should do>"
        return 1
    }

    if [[ ! -f "$AUTONOMY_DIR/lib/ai-engine.sh" ]]; then
        echo "AI engine not available"
        return 1
    fi

    local prompt="Create a bash tool for this purpose: $need

Requirements:
1. Must be a self-contained bash script
2. Include a run() function with the main logic
3. Include a CLI case statement at the bottom
4. Use proper error handling
5. Be concise and functional

Respond with ONLY:
Line 1: TOOL_NAME (one word, lowercase, no spaces)
Line 2: DESCRIPTION (one sentence)
Line 3+: The bash commands for the run() function body (one per line, no function wrapper)"

    local result
    result=$(bash "$AUTONOMY_DIR/lib/ai-engine.sh" call "Generate a tool" "$prompt" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo "AI failed to generate tool"
        return 1
    fi

    local tool_name tool_desc
    tool_name=$(echo "$result" | head -1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')
    tool_desc=$(echo "$result" | sed -n '2p')
    local commands
    commands=$(echo "$result" | tail -n +3)

    if [[ -z "$tool_name" || -z "$tool_desc" ]]; then
        echo "Could not parse AI response"
        return 1
    fi

    # Create the tool with extracted commands
    local cmd_array=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^#|^\`|^---$ ]] && continue
        cmd_array+=("$line")
    done <<< "$commands"

    create_tool "$tool_name" "$tool_desc" "${cmd_array[@]}"
}

# ── Use a skill (increment counter) ───────────────────────

use_skill() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    init_skills

    # Only update if skill actually exists
    local exists
    exists=$(jq --arg n "$name" '[.skills[] | select(.name == $n)] | length' "$SKILLS_FILE")
    [[ "$exists" -eq 0 ]] && return 1

    local tmp="${SKILLS_FILE}.tmp.$$"
    jq --arg n "$name" \
        '(.skills[] | select(.name == $n)) |= (.use_count += 1) | .stats.skills_used += 1' \
        "$SKILLS_FILE" > "$tmp" && mv "$tmp" "$SKILLS_FILE"
}

# ── List Skills ────────────────────────────────────────────

list_skills() {
    init_skills
    echo "Learned Skills:"
    jq -r '.skills[] | "  \(if .has_tool then "🔧" else "📝" end) \(.name) [\(.category)] — \(.description) (used \(.use_count)x)"' \
        "$SKILLS_FILE" 2>/dev/null

    echo ""
    echo "Available Tools:"
    for f in "$TOOLS_DIR"/*; do
        [[ -f "$f" && -x "$f" ]] || continue
        local tool_name tool_desc
        tool_name=$(basename "$f")
        tool_desc=$(grep "^# Description:" "$f" 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "no description")
        echo "  • $tool_name — $tool_desc"
    done
}

# ── Status ──────────────────────────────────────────────────

skill_status() {
    init_skills
    jq '{
        stats,
        total_skills: (.skills | length),
        skills_with_tools: ([.skills[] | select(.has_tool == true)] | length),
        categories: ([.skills[].category] | group_by(.) | map({category: .[0], count: length})),
        top_used: (.skills | sort_by(-.use_count) | .[:5] | map({name, use_count, category, description})),
        recent: (.skills | .[-5:] | map({name, category, description, learned_at, source_task})),
        tools: [.skills[] | select(.has_tool == true) | {name, tool_name, description}]
    }' "$SKILLS_FILE"
}

# Oneliner for HEARTBEAT — surfaces actual skill data for AI
skill_oneliner() {
    init_skills
    local learned tools used
    learned=$(jq '.stats.skills_learned // 0' "$SKILLS_FILE")
    tools=$(jq '.stats.tools_created // 0' "$SKILLS_FILE")
    used=$(jq '.stats.skills_used // 0' "$SKILLS_FILE")

    echo "Skills: $learned learned, $tools tools created, $used total uses"

    # Show categories breakdown
    local categories
    categories=$(jq -r '[.skills[].category] | group_by(.) | map("\(length)x \(.[0])") | join(", ")' "$SKILLS_FILE" 2>/dev/null)
    [[ -n "$categories" && "$categories" != "" ]] && echo "Categories: $categories"

    # Show recent skills (last 5) with descriptions
    local recent_count
    recent_count=$(jq '.skills | length' "$SKILLS_FILE")
    if [[ "$recent_count" -gt 0 ]]; then
        echo "Recent skills:"
        jq -r '.skills | .[-5:] | reverse | .[] | "- \(.name) [\(.category)]: \(.description)"' "$SKILLS_FILE" 2>/dev/null
    fi

    # Show tools if any exist
    local tool_count
    tool_count=$(jq '[.skills[] | select(.has_tool == true)] | length' "$SKILLS_FILE")
    if [[ "$tool_count" -gt 0 ]]; then
        echo "Available tools:"
        jq -r '[.skills[] | select(.has_tool == true)] | .[] | "- \(.tool_name): \(.description)"' "$SKILLS_FILE" 2>/dev/null
    fi
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    learn)          shift; learn_skill "$@" ;;
    create_tool)    shift; create_tool "$@" ;;
    create_plugin)  shift; create_plugin "$@" ;;
    generate)       shift; generate_tool "$*" ;;
    use)            shift; use_skill "$1" ;;
    list)           list_skills ;;
    status)         skill_status ;;
    oneliner)       skill_oneliner ;;
    *)
        echo "Skill Acquisition & Tool Creation"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  learn <name> <desc> <category> [example]  Learn a new skill"
        echo "  create_tool <name> <desc> <cmds...>       Create a tool script"
        echo "  create_plugin <name> <desc> [funcs_json]  Create a plugin"
        echo "  generate <description>                     AI-generate a tool"
        echo "  use <name>                                 Track skill usage"
        echo "  list                                       List skills & tools"
        echo "  status                                     Full status JSON"
        echo "  oneliner                                   Summary for HEARTBEAT"
        ;;
esac
