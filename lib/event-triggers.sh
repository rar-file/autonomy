#!/bin/bash
# Event-Driven Task Triggering
# Extends file-watcher.sh with intelligent event→task creation.
# Supports: file changes, git events, cron-like schedules, webhooks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
TASKS_DIR="$AUTONOMY_DIR/tasks"
TRIGGERS_FILE="$STATE_DIR/triggers.json"
TRIGGER_LOG="$AUTONOMY_DIR/logs/triggers.log"

mkdir -p "$STATE_DIR" "$AUTONOMY_DIR/logs" "$TASKS_DIR"

_trigger_log() {
    echo "$(date -Iseconds) [$1] $2" >> "$TRIGGER_LOG"
}

# ── Trigger Registry ───────────────────────────────────────

init_triggers() {
    [[ -f "$TRIGGERS_FILE" ]] || echo '{
        "triggers": [],
        "stats": {
            "total_fired": 0,
            "tasks_created": 0
        }
    }' > "$TRIGGERS_FILE"
}

# Register a trigger
# register <name> <type> <condition> <task_template> [priority]
# Types: file_change, git_push, schedule, webhook, pattern
register_trigger() {
    local name="$1"
    local type="$2"
    local condition="$3"
    local task_template="$4"
    local priority="${5:-medium}"

    [[ -z "$name" || -z "$type" || -z "$condition" || -z "$task_template" ]] && {
        echo "Usage: event-triggers.sh register <name> <type> <condition> <task_template> [priority]"
        return 1
    }

    init_triggers

    # Validate type
    case "$type" in
        file_change|git_push|schedule|webhook|pattern) ;;
        *) echo "Invalid trigger type. Use: file_change, git_push, schedule, webhook, pattern"; return 1 ;;
    esac

    local tmp="${TRIGGERS_FILE}.tmp.$$"
    jq --arg name "$name" --arg type "$type" --arg cond "$condition" \
       --arg tpl "$task_template" --arg pri "$priority" --arg ts "$(date -Iseconds)" \
        '.triggers += [{
            name: $name,
            type: $type,
            condition: $cond,
            task_template: $tpl,
            priority: $pri,
            enabled: true,
            created: $ts,
            last_fired: null,
            fire_count: 0,
            cooldown_seconds: 300
        }]' "$TRIGGERS_FILE" > "$tmp" && mv "$tmp" "$TRIGGERS_FILE"

    _trigger_log INFO "Registered trigger: $name (type=$type)"
    echo "Registered trigger: $name"
}

# Remove a trigger
unregister_trigger() {
    local name="$1"
    init_triggers
    local tmp="${TRIGGERS_FILE}.tmp.$$"
    jq --arg n "$name" '.triggers = [.triggers[] | select(.name != $n)]' \
        "$TRIGGERS_FILE" > "$tmp" && mv "$tmp" "$TRIGGERS_FILE"
    echo "Removed trigger: $name"
}

# List triggers
list_triggers() {
    init_triggers
    echo "Registered Triggers:"
    jq -r '.triggers[] | "  \(if .enabled then "✓" else "✗" end) \(.name) [\(.type)] condition=\(.condition) → \(.task_template) (fired \(.fire_count)x)"' \
        "$TRIGGERS_FILE" 2>/dev/null
}

# ── Fire a trigger (create task) ───────────────────────────

fire_trigger() {
    local trigger_name="$1"
    local event_data="${2:-}"

    init_triggers

    local trigger
    trigger=$(jq --arg n "$trigger_name" '.triggers[] | select(.name == $n and .enabled == true)' "$TRIGGERS_FILE" 2>/dev/null)

    [[ -z "$trigger" ]] && { echo "Trigger not found or disabled: $trigger_name"; return 1; }

    # Check cooldown
    local last_fired cooldown
    last_fired=$(echo "$trigger" | jq -r '.last_fired // ""')
    cooldown=$(echo "$trigger" | jq '.cooldown_seconds // 300')

    if [[ -n "$last_fired" && "$last_fired" != "null" ]]; then
        local last_epoch now_epoch
        last_epoch=$(date -d "$last_fired" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        if [[ $((now_epoch - last_epoch)) -lt $cooldown ]]; then
            _trigger_log INFO "Trigger $trigger_name in cooldown, skipping"
            return 0
        fi
    fi

    # Get task template
    local task_template priority
    task_template=$(echo "$trigger" | jq -r '.task_template')
    priority=$(echo "$trigger" | jq -r '.priority')

    # Create task from trigger
    local task_name="trigger-${trigger_name}-$(date +%s)"
    local task_desc="$task_template"
    [[ -n "$event_data" ]] && task_desc="$task_desc (Event: $event_data)"

    local task_id
    task_id=$(echo "$task_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-60)

    jq -n \
        --arg id "$task_id" \
        --arg name "$task_name" \
        --arg desc "$task_desc" \
        --arg pri "$priority" \
        --arg trigger "$trigger_name" \
        --arg ts "$(date -Iseconds)" \
        '{
            id: $id,
            name: $name,
            description: $desc,
            status: "pending",
            priority: $pri,
            source: ("trigger:" + $trigger),
            created_at: $ts,
            attempts: 0,
            progress: 0,
            subtasks: [],
            tags: ["event-triggered"]
        }' > "$TASKS_DIR/${task_id}.json"

    # Update trigger stats
    local tmp="${TRIGGERS_FILE}.tmp.$$"
    jq --arg n "$trigger_name" --arg ts "$(date -Iseconds)" \
        '(.triggers[] | select(.name == $n)) |= (.last_fired = $ts | .fire_count += 1) |
         .stats.total_fired += 1 | .stats.tasks_created += 1' \
        "$TRIGGERS_FILE" > "$tmp" && mv "$tmp" "$TRIGGERS_FILE"

    # Signal adaptive heartbeat for immediate processing
    if [[ -f "$AUTONOMY_DIR/lib/adaptive-heartbeat.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/adaptive-heartbeat.sh" signal_immediate >/dev/null 2>&1 || true
    fi

    _trigger_log INFO "Fired trigger: $trigger_name → created task $task_id"
    echo "Trigger fired: $trigger_name → $task_id"
}

# ── Event Checkers ─────────────────────────────────────────

# Check all file_change triggers
check_file_triggers() {
    init_triggers
    local triggers
    triggers=$(jq '[.triggers[] | select(.type == "file_change" and .enabled == true)]' "$TRIGGERS_FILE")
    local count
    count=$(echo "$triggers" | jq 'length')

    for ((i = 0; i < count; i++)); do
        local name condition path
        name=$(echo "$triggers" | jq -r ".[$i].name")
        condition=$(echo "$triggers" | jq -r ".[$i].condition")
        path="$condition"

        if [[ -e "$path" ]]; then
            # Use file-watcher checksum comparison
            local checksum_file="$STATE_DIR/trigger_checksums/${name}.sum"
            mkdir -p "$STATE_DIR/trigger_checksums"

            local current_checksum
            if [[ -d "$path" ]]; then
                current_checksum=$(find "$path" -type f -exec md5sum {} + 2>/dev/null | md5sum | cut -d' ' -f1)
            else
                current_checksum=$(md5sum "$path" 2>/dev/null | cut -d' ' -f1)
            fi

            local previous_checksum=""
            [[ -f "$checksum_file" ]] && previous_checksum=$(cat "$checksum_file")

            if [[ "$current_checksum" != "$previous_checksum" ]]; then
                echo "$current_checksum" > "$checksum_file"
                [[ -n "$previous_checksum" ]] && fire_trigger "$name" "File changed: $path"
            fi
        fi
    done
}

# Check git triggers
check_git_triggers() {
    init_triggers
    local triggers
    triggers=$(jq '[.triggers[] | select(.type == "git_push" and .enabled == true)]' "$TRIGGERS_FILE")
    local count
    count=$(echo "$triggers" | jq 'length')

    local workspace
    workspace=$(jq -r '.workstation.workspace // ""' "$CONFIG_FILE" 2>/dev/null)
    [[ -z "$workspace" || ! -d "$workspace/.git" ]] && return

    for ((i = 0; i < count; i++)); do
        local name condition
        name=$(echo "$triggers" | jq -r ".[$i].name")
        condition=$(echo "$triggers" | jq -r ".[$i].condition")  # Branch pattern

        local current_hash
        current_hash=$(git -C "$workspace" rev-parse HEAD 2>/dev/null)

        local hash_file="$STATE_DIR/trigger_checksums/git_${name}.hash"
        local previous_hash=""
        [[ -f "$hash_file" ]] && previous_hash=$(cat "$hash_file")

        if [[ "$current_hash" != "$previous_hash" ]]; then
            echo "$current_hash" > "$hash_file"
            local branch
            branch=$(git -C "$workspace" rev-parse --abbrev-ref HEAD 2>/dev/null)
            if [[ -n "$previous_hash" ]] && echo "$branch" | grep -q "$condition"; then
                fire_trigger "$name" "New commit on $branch: $current_hash"
            fi
        fi
    done
}

# Check schedule triggers (cron-like, simplified)
check_schedule_triggers() {
    init_triggers
    local triggers
    triggers=$(jq '[.triggers[] | select(.type == "schedule" and .enabled == true)]' "$TRIGGERS_FILE")
    local count
    count=$(echo "$triggers" | jq 'length')

    local current_hour current_min
    current_hour=$(date +%H)
    current_min=$(date +%M)

    for ((i = 0; i < count; i++)); do
        local name condition
        name=$(echo "$triggers" | jq -r ".[$i].name")
        condition=$(echo "$triggers" | jq -r ".[$i].condition")  # Format: "HH:MM" or "daily" or "hourly"

        local should_fire=false
        case "$condition" in
            daily)
                [[ "$current_hour" == "09" && "$current_min" -lt 10 ]] && should_fire=true
                ;;
            hourly)
                [[ "$current_min" -lt 10 ]] && should_fire=true
                ;;
            *)
                # HH:MM format
                local target_hour target_min
                target_hour=$(echo "$condition" | cut -d: -f1)
                target_min=$(echo "$condition" | cut -d: -f2)
                [[ "$current_hour" == "$target_hour" && "$current_min" -ge "$target_min" && "$current_min" -lt $((target_min + 10)) ]] && should_fire=true
                ;;
        esac

        [[ "$should_fire" == "true" ]] && fire_trigger "$name" "Schedule: $condition"
    done
}

# Run all trigger checks
check_all() {
    check_file_triggers
    check_git_triggers
    check_schedule_triggers
}

# ── Status ──────────────────────────────────────────────────

trigger_status() {
    init_triggers
    jq '{
        total_triggers: (.triggers | length),
        enabled: ([.triggers[] | select(.enabled == true)] | length),
        by_type: ([.triggers[].type] | group_by(.) | map({type: .[0], count: length})),
        stats,
        triggers: [.triggers[] | {name, type, enabled, fire_count, last_fired}]
    }' "$TRIGGERS_FILE"
}

# ── Setup Common Triggers ──────────────────────────────────

setup_defaults() {
    local workspace
    workspace=$(jq -r '.workstation.workspace // ""' "$CONFIG_FILE" 2>/dev/null)

    # Watch for git changes on main branch
    if [[ -d "$workspace/.git" ]]; then
        register_trigger "git-main-push" "git_push" "main" \
            "New commits on main branch detected. Review changes and create follow-up tasks if needed." \
            "medium" 2>/dev/null
    fi

    # Daily review
    register_trigger "daily-review" "schedule" "daily" \
        "Daily review: Check project health, update documentation, clean up stale tasks." \
        "low" 2>/dev/null

    echo "Default triggers configured"
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    register)     shift; register_trigger "$@" ;;
    unregister)   shift; unregister_trigger "$1" ;;
    list)         list_triggers ;;
    fire)         shift; fire_trigger "$@" ;;
    check)        check_all ;;
    check_files)  check_file_triggers ;;
    check_git)    check_git_triggers ;;
    check_sched)  check_schedule_triggers ;;
    setup)        setup_defaults ;;
    status)       trigger_status ;;
    *)
        echo "Event-Driven Task Triggering"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  register <name> <type> <condition> <template> [priority]"
        echo "  unregister <name>           Remove a trigger"
        echo "  list                        List all triggers"
        echo "  fire <name> [event_data]    Manually fire a trigger"
        echo "  check                       Check all triggers"
        echo "  check_files                 Check file change triggers"
        echo "  check_git                   Check git triggers"
        echo "  check_sched                 Check schedule triggers"
        echo "  setup                       Setup default triggers"
        echo "  status                      Full status JSON"
        echo ""
        echo "Trigger types: file_change, git_push, schedule, webhook, pattern"
        ;;
esac
