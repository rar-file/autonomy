#!/bin/bash
# Sub-Agent Scheduling System
# Breaks tasks into parallel subtasks and manages their lifecycle.
# Each sub-agent is a lightweight task tracked in state/sub_agents.json.
# Respects the max_sub_agents limit from config.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
TASKS_DIR="$AUTONOMY_DIR/tasks"
AGENTS_FILE="$STATE_DIR/sub_agents.json"
LOGS_DIR="$AUTONOMY_DIR/logs"
AGENT_LOG="$LOGS_DIR/sub-agents.jsonl"

mkdir -p "$STATE_DIR" "$LOGS_DIR" "$TASKS_DIR"

_get_config() {
    jq -r "$1" "$CONFIG_FILE" 2>/dev/null
}

_max_agents() {
    local max
    max=$(_get_config '.global_config.max_sub_agents // .agentic_config.hard_limits.max_sub_agents // 3')
    [[ "$max" =~ ^[0-9]+$ ]] || max=3
    echo "$max"
}

# ── State Management ─────────────────────────────────────────

_ensure_state() {
    if [[ ! -f "$AGENTS_FILE" ]]; then
        echo '{"agents":[],"completed":[],"stats":{"total_spawned":0,"total_completed":0}}' > "$AGENTS_FILE"
    fi
}

_active_count() {
    _ensure_state
    jq '[.agents[] | select(.status == "active" or .status == "pending")] | length' "$AGENTS_FILE" 2>/dev/null || echo 0
}

# ── OpenClaw Sessions Bridge ─────────────────────────────────

# Try to delegate to OpenClaw's native sessions_spawn / sessions_send
# when the OpenClaw CLI is available. Falls back to local-only tracking.
_openclaw_bridge_available() {
    command -v openclaw >/dev/null 2>&1
}

# Attempt to spawn via OpenClaw sessions (cross-session agent)
openclaw_bridge_spawn() {
    local name="$1"
    local desc="$2"
    if _openclaw_bridge_available; then
        openclaw agent --message "Sub-agent task: $name — $desc" 2>/dev/null && return 0
    fi
    return 1  # Bridge not available, caller should fall back to local spawn
}

# Send a message to another OpenClaw session
openclaw_bridge_send() {
    local session_id="$1"
    local message="$2"
    if _openclaw_bridge_available; then
        openclaw sessions send "$session_id" "$message" 2>/dev/null && return 0
    fi
    return 1
}

# List OpenClaw sessions (for coordination)
openclaw_bridge_list() {
    if _openclaw_bridge_available; then
        openclaw sessions list 2>/dev/null && return 0
    fi
    return 1
}

# ── Spawn a Sub-Agent ────────────────────────────────────────

# spawn <parent_task> <agent_name> <description> [priority]
spawn() {
    local parent="$1"
    local name="$2"
    local desc="$3"
    local priority="${4:-normal}"

    [[ -z "$parent" || -z "$name" || -z "$desc" ]] && {
        echo "Usage: sub-agents.sh spawn <parent_task> <agent_name> <description> [priority]"
        return 1
    }

    _ensure_state

    # Check limit
    local active max
    active=$(_active_count)
    max=$(_max_agents)
    if [[ "$active" -ge "$max" ]]; then
        echo "LIMIT_REACHED: $active/$max sub-agents active. Wait for some to complete."
        return 1
    fi

    # Check for duplicate
    local existing
    existing=$(jq -r --arg n "$name" '[.agents[] | select(.name == $n and (.status == "active" or .status == "pending"))] | length' "$AGENTS_FILE" 2>/dev/null)
    if [[ "$existing" -gt 0 ]]; then
        echo "DUPLICATE: Sub-agent '$name' already exists and is active"
        return 1
    fi

    # Create the sub-agent entry
    local agent_id="sa-$(date +%s)-$$"
    local tmp="${AGENTS_FILE}.tmp.$$"
    jq --arg id "$agent_id" --arg parent "$parent" --arg name "$name" \
        --arg desc "$desc" --arg prio "$priority" --arg ts "$(date -Iseconds)" \
        '.agents += [{
            id: $id,
            parent_task: $parent,
            name: $name,
            description: $desc,
            priority: $prio,
            status: "pending",
            created: $ts,
            started: null,
            completed: null,
            result: null,
            evidence: []
        }] | .stats.total_spawned += 1' \
        "$AGENTS_FILE" > "$tmp" && mv "$tmp" "$AGENTS_FILE"

    # Also create a real task file so the daemon can flag it
    local task_file="$TASKS_DIR/${name}.json"
    jq -n --arg name "$name" --arg desc "$desc" --arg prio "$priority" \
        --arg ts "$(date -Iseconds)" --arg parent "$parent" --arg agent_id "$agent_id" \
        '{
            name: $name,
            description: $desc,
            status: "pending",
            priority: $prio,
            created: $ts,
            completed: false,
            attempts: 0,
            max_attempts: 3,
            subtasks: [],
            evidence: [],
            verification: null,
            is_sub_agent: true,
            parent_task: $parent,
            agent_id: $agent_id
        }' > "$task_file"

    # Log
    jq -n --arg ts "$(date -Iseconds)" --arg id "$agent_id" --arg name "$name" --arg parent "$parent" \
        '{timestamp:$ts, action:"agent_spawned", agent_id:$id, name:$name, parent:$parent}' >> "$AGENT_LOG" 2>/dev/null

    echo "Spawned sub-agent: $name (id: $agent_id, $((active+1))/$max slots used)"

    # Attempt to bridge to OpenClaw native session for cross-session visibility
    if _openclaw_bridge_available; then
        openclaw_bridge_spawn "$name" "$desc" && \
            echo "  ↳ Bridged to OpenClaw session" || true
    fi
}

# ── Start / Complete / Fail ──────────────────────────────────

# start <agent_id_or_name>
start_agent() {
    local key="$1"
    _ensure_state
    local tmp="${AGENTS_FILE}.tmp.$$"
    jq --arg k "$key" --arg ts "$(date -Iseconds)" \
        '(.agents[] | select(.id == $k or .name == $k)) |= (.status = "active" | .started = $ts)' \
        "$AGENTS_FILE" > "$tmp" && mv "$tmp" "$AGENTS_FILE"
    echo "Sub-agent started: $key"
}

# complete <agent_id_or_name> <result_summary> [evidence...]
complete_agent() {
    local key="$1"
    local result="$2"
    shift 2
    local evidence_items=("$@")

    _ensure_state

    # Build evidence array
    local ev_json="[]"
    if [[ ${#evidence_items[@]} -gt 0 ]]; then
        ev_json="["
        local first=true
        for item in "${evidence_items[@]}"; do
            $first || ev_json+=","
            ev_json+="$(jq -n --arg e "$item" '$e')"
            first=false
        done
        ev_json+="]"
    fi

    local tmp="${AGENTS_FILE}.tmp.$$"
    jq --arg k "$key" --arg ts "$(date -Iseconds)" --arg res "$result" --argjson ev "$ev_json" \
        '(.agents[] | select(.id == $k or .name == $k)) |=
            (.status = "completed" | .completed = $ts | .result = $res | .evidence = $ev)
        | .stats.total_completed += 1' \
        "$AGENTS_FILE" > "$tmp" && mv "$tmp" "$AGENTS_FILE"

    # Archive to completed array
    jq --arg k "$key" \
        '.completed += [.agents[] | select(.id == $k or .name == $k)] |
         .agents = [.agents[] | select(.id != $k and .name != $k)]' \
        "$AGENTS_FILE" > "$tmp" && mv "$tmp" "$AGENTS_FILE"

    # Log
    jq -n --arg ts "$(date -Iseconds)" --arg key "$key" --arg res "$result" \
        '{timestamp:$ts, action:"agent_completed", agent:$key, result:$res}' >> "$AGENT_LOG" 2>/dev/null

    echo "Sub-agent completed: $key"

    # Check if all sub-agents for parent are done
    _check_parent_completion "$key"
}

# fail <agent_id_or_name> <reason>
fail_agent() {
    local key="$1"
    local reason="$2"
    _ensure_state
    local tmp="${AGENTS_FILE}.tmp.$$"
    jq --arg k "$key" --arg ts "$(date -Iseconds)" --arg r "$reason" \
        '(.agents[] | select(.id == $k or .name == $k)) |=
            (.status = "failed" | .completed = $ts | .result = ("FAILED: " + $r))' \
        "$AGENTS_FILE" > "$tmp" && mv "$tmp" "$AGENTS_FILE"

    jq -n --arg ts "$(date -Iseconds)" --arg key "$key" --arg reason "$reason" \
        '{timestamp:$ts, action:"agent_failed", agent:$key, reason:$reason}' >> "$AGENT_LOG" 2>/dev/null

    echo "Sub-agent failed: $key — $reason"
}

# ── Parent Completion Check ──────────────────────────────────

_check_parent_completion() {
    local key="$1"
    _ensure_state

    # Find parent task from completed list
    local parent
    parent=$(jq -r --arg k "$key" \
        '(.completed[] | select(.id == $k or .name == $k) | .parent_task) // empty' \
        "$AGENTS_FILE" 2>/dev/null)
    [[ -z "$parent" ]] && return

    # Check if any siblings are still active
    local remaining
    remaining=$(jq -r --arg p "$parent" \
        '[.agents[] | select(.parent_task == $p and (.status == "active" or .status == "pending"))] | length' \
        "$AGENTS_FILE" 2>/dev/null)

    if [[ "$remaining" -eq 0 ]]; then
        echo "All sub-agents for '$parent' completed."
        jq -n --arg ts "$(date -Iseconds)" --arg parent "$parent" \
            '{timestamp:$ts, action:"all_agents_done", parent:$parent}' >> "$AGENT_LOG" 2>/dev/null
    fi
}

# ── List / Status ────────────────────────────────────────────

list_agents() {
    _ensure_state
    local filter="${1:-active}"
    case "$filter" in
        active)    jq '[.agents[] | select(.status == "active" or .status == "pending")]' "$AGENTS_FILE" ;;
        all)       jq '.agents' "$AGENTS_FILE" ;;
        completed) jq '.completed // []' "$AGENTS_FILE" ;;
        *)         jq --arg s "$filter" '[.agents[] | select(.status == $s)]' "$AGENTS_FILE" ;;
    esac
}

status() {
    _ensure_state
    local active max
    active=$(_active_count)
    max=$(_max_agents)
    jq --argjson act "$active" --argjson max "$max" \
        '.stats + {active_agents: $act, max_agents: $max, available_slots: ($max - $act)}' \
        "$AGENTS_FILE" 2>/dev/null
}

summary() {
    _ensure_state
    local active max
    active=$(_active_count)
    max=$(_max_agents)
    echo "Sub-agents: $active/$max active"

    # List active agents
    if [[ "$active" -gt 0 ]]; then
        jq -r '.agents[] | select(.status == "active" or .status == "pending") | "  - " + .name + " [" + .status + "] → " + .parent_task' \
            "$AGENTS_FILE" 2>/dev/null
    fi
}

# ── Cleanup stale agents ────────────────────────────────────

cleanup() {
    _ensure_state
    local now
    now=$(date +%s)
    # Agents active for over 2 hours are stale
    local tmp="${AGENTS_FILE}.tmp.$$"
    jq --argjson now "$now" '
        .agents = [.agents[] |
            if (.status == "active" and .started != null) then
                ((.started | sub("\\+.*";"") | strptime("%Y-%m-%dT%H:%M:%S") | mktime) as $start |
                if ($now - $start > 7200) then .status = "failed" | .result = "TIMEOUT: exceeded 2 hour limit"
                else . end)
            else . end
        ]' "$AGENTS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$AGENTS_FILE"
    echo "Cleanup complete"
}

# ── CLI ──────────────────────────────────────────────────────

case "${1:-status}" in
    spawn)     shift; spawn "$@" ;;
    start)     shift; start_agent "$1" ;;
    complete)  shift; complete_agent "$@" ;;
    fail)      shift; fail_agent "$@" ;;
    list)      shift; list_agents "${1:-active}" ;;
    status)    status ;;
    summary)   summary ;;
    cleanup)   cleanup ;;
    *)
        echo "Usage: sub-agents.sh {spawn|start|complete|fail|list|status|summary|cleanup}"
        echo ""
        echo "  spawn <parent> <name> <desc> [priority]  Create a sub-agent"
        echo "  start <id|name>                           Mark agent as active"
        echo "  complete <id|name> <result> [evidence...] Complete with result"
        echo "  fail <id|name> <reason>                   Mark as failed"
        echo "  list [active|all|completed]               List agents"
        echo "  status                                    Sub-agent stats"
        echo "  summary                                   One-liner for HEARTBEAT"
        echo "  cleanup                                   Clean stale agents"
        ;;
esac
