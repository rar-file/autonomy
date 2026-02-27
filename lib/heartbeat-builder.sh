#!/bin/bash
# Dynamic HEARTBEAT.md Builder
# Regenerates HEARTBEAT.md on every daemon cycle with:
#   - Current flagged task + subtask plan
#   - Last journal entry (session continuity)
#   - Workspace scan (language, framework, structure)
#   - Remaining token budget
#   - Hard limits
#   - Task-decomposition instructions
#
# This replaces the static HEARTBEAT.md.template — the AI always sees
# a fresh, context-rich prompt every heartbeat.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
HEARTBEAT_FILE="$AUTONOMY_DIR/HEARTBEAT.md"
TASKS_DIR="$AUTONOMY_DIR/tasks"

get_config() {
    jq -r "$1" "$CONFIG_FILE" 2>/dev/null
}

# ── Gather live context ─────────────────────────────────────

get_current_task() {
    # Priority: needs_ai_attention > ai_processing > highest priority pending
    local attention_file="$AUTONOMY_DIR/state/needs_attention.json"
    if [[ -f "$attention_file" ]]; then
        local name desc
        name=$(jq -r '.task_name // ""' "$attention_file" 2>/dev/null)
        desc=$(jq -r '.description // ""' "$attention_file" 2>/dev/null)
        if [[ -n "$name" ]]; then
            echo "$name|$desc"
            return
        fi
    fi

    # Check task files - prioritize by priority field (critical > high > normal > low)
    local best_task=""
    local best_desc=""
    local best_priority=-1
    
    for task_file in "$TASKS_DIR"/*.json; do
        [[ -f "$task_file" ]] || continue
        local status completed name desc priority priority_value
        status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        completed=$(jq -r '.completed // false' "$task_file" 2>/dev/null)
        [[ "$completed" == "true" ]] && continue

        if [[ "$status" == "needs_ai_attention" || "$status" == "ai_processing" || "$status" == "pending" ]]; then
            name=$(jq -r '.name // ""' "$task_file" 2>/dev/null)
            desc=$(jq -r '.description // ""' "$task_file" 2>/dev/null)
            priority=$(jq -r '.priority // "normal"' "$task_file" 2>/dev/null)
            
            # Convert priority to numeric value
            case "$priority" in
                critical) priority_value=100 ;;
                high) priority_value=50 ;;
                normal) priority_value=25 ;;
                low) priority_value=10 ;;
                *) priority_value=25 ;;
            esac
            
            # Select highest priority task
            if [[ $priority_value -gt $best_priority ]]; then
                best_priority=$priority_value
                best_task="$name"
                best_desc="$desc"
            fi
        fi
    done
    
    if [[ -n "$best_task" ]]; then
        echo "$best_task|$best_desc"
        return
    fi
    
    echo "|"
}

get_task_subtasks() {
    local task_name="$1"
    [[ -z "$task_name" ]] && return
    local task_file="$TASKS_DIR/${task_name}.json"
    [[ ! -f "$task_file" ]] && return

    local subtasks
    subtasks=$(jq -r '.subtasks // [] | .[]' "$task_file" 2>/dev/null)
    [[ -n "$subtasks" ]] && echo "$subtasks"
}

get_task_attempts() {
    local task_name="$1"
    [[ -z "$task_name" ]] && echo "0" && return
    local task_file="$TASKS_DIR/${task_name}.json"
    [[ ! -f "$task_file" ]] && echo "0" && return
    jq -r '.attempts // 0' "$task_file" 2>/dev/null
}

get_pending_count() {
    local count=0
    for task_file in "$TASKS_DIR"/*.json; do
        [[ -f "$task_file" ]] || continue
        local completed status
        completed=$(jq -r '.completed // false' "$task_file" 2>/dev/null)
        status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        [[ "$completed" == "true" || "$status" == "completed" ]] && continue
        count=$((count + 1))
    done
    echo "$count"
}

# ── Build HEARTBEAT.md ──────────────────────────────────────

build() {
    # Collect all live data
    local task_info current_task current_desc
    task_info=$(get_current_task)
    current_task=$(echo "$task_info" | cut -d'|' -f1)
    current_desc=$(echo "$task_info" | cut -d'|' -f2-)

    local attempts subtasks pending_count
    attempts=$(get_task_attempts "$current_task")
    subtasks=$(get_task_subtasks "$current_task")
    pending_count=$(get_pending_count)

    # Get workspace scan
    local workspace_line=""
    if [[ -f "$AUTONOMY_DIR/lib/workspace-scanner.sh" ]]; then
        workspace_line=$(bash "$AUTONOMY_DIR/lib/workspace-scanner.sh" oneliner 2>/dev/null)
    fi

    # Get journal
    local journal_summary=""
    if [[ -f "$AUTONOMY_DIR/lib/journal.sh" ]]; then
        journal_summary=$(bash "$AUTONOMY_DIR/lib/journal.sh" summary 2>/dev/null)
    fi

    # Get token budget
    local budget_line=""
    if [[ -f "$AUTONOMY_DIR/lib/token-budget.sh" ]]; then
        budget_line=$(bash "$AUTONOMY_DIR/lib/token-budget.sh" summary 2>/dev/null)
    fi

    # Get persistent memory
    local memory_summary=""
    if [[ -f "$AUTONOMY_DIR/lib/memory.sh" ]]; then
        memory_summary=$(bash "$AUTONOMY_DIR/lib/memory.sh" summary 2>/dev/null)
    fi

    # Get sub-agent status
    local agents_summary=""
    if [[ -f "$AUTONOMY_DIR/lib/sub-agents.sh" ]]; then
        agents_summary=$(bash "$AUTONOMY_DIR/lib/sub-agents.sh" summary 2>/dev/null)
    fi

    # Get AI engine status
    local ai_configured="false"
    if [[ -f "$AUTONOMY_DIR/lib/ai-engine.sh" ]]; then
        local ai_status_json
        ai_status_json=$(bash "$AUTONOMY_DIR/lib/ai-engine.sh" status 2>/dev/null)
        ai_configured=$(echo "$ai_status_json" | jq -r '.configured // false' 2>/dev/null)
    fi

    # Hard limits
    local max_tasks max_edits max_searches max_iterations daily_budget
    max_tasks=$(get_config '.agentic_config.hard_limits.max_concurrent_tasks // 5')
    max_edits=$(get_config '.agentic_config.hard_limits.max_file_edits_per_session // 50')
    max_searches=$(get_config '.agentic_config.hard_limits.max_web_searches // 10')
    max_iterations=$(get_config '.agentic_config.hard_limits.max_iterations_per_task // 5')
    daily_budget=$(get_config '.agentic_config.hard_limits.daily_token_budget // 50000')

    # Autonomy level
    local level
    level=$(get_config '.agentic_config.autonomy_level // "semi-autonomous"')

    # ── Write HEARTBEAT.md ──────────────────────────────────

    cat > "$HEARTBEAT_FILE" << HEARTBEAT_EOF
# HEARTBEAT.md — Agentic Autonomy System v2.1

> **Generated:** $(date -Iseconds)
> **Autonomy Level:** $level
> **Pending Tasks:** $pending_count

---

## Your Current Assignment

HEARTBEAT_EOF

    # Task section — adapt based on whether there IS a task
    if [[ -n "$current_task" ]]; then
        cat >> "$HEARTBEAT_FILE" << TASK_EOF

**Task:** \`$current_task\`
**Description:** $current_desc
**Attempt:** $attempts / $max_iterations

TASK_EOF

        # Subtask plan if any
        if [[ -n "$subtasks" ]]; then
            echo "### Subtask Plan" >> "$HEARTBEAT_FILE"
            echo '```' >> "$HEARTBEAT_FILE"
            echo "$subtasks" >> "$HEARTBEAT_FILE"
            echo '```' >> "$HEARTBEAT_FILE"
            echo "" >> "$HEARTBEAT_FILE"
            echo "Work through these subtasks in order. Check off each one as you complete it." >> "$HEARTBEAT_FILE"
        else
            # Task decomposition instructions
            cat >> "$HEARTBEAT_FILE" << DECOMPOSE_EOF
### Step 1: Plan Before You Build

**Before writing any code**, break this task into 2-5 concrete subtasks.
Write them into the task file:
\`\`\`bash
# Update the task with your plan:
jq '.subtasks = ["step1: ...", "step2: ...", "step3: ..."]' "$TASKS_DIR/${current_task}.json" > /tmp/t.json && mv /tmp/t.json "$TASKS_DIR/${current_task}.json"
\`\`\`

Then work through each subtask. This prevents scope creep and endless building.

DECOMPOSE_EOF
        fi
    else
        cat >> "$HEARTBEAT_FILE" << NOTASK_EOF

**No task assigned.** Nothing in the queue needs attention.

If you think something valuable should be done, create a task:
\`\`\`bash
bash $AUTONOMY_DIR/autonomy task create "task-name" "description of what to do"
\`\`\`

Otherwise: **HEARTBEAT_OK** — nothing to do.

NOTASK_EOF
    fi

    # Session history
    cat >> "$HEARTBEAT_FILE" << JOURNAL_EOF

---

## Session History

$journal_summary

JOURNAL_EOF

    # Workspace context
    if [[ -n "$workspace_line" ]]; then
        cat >> "$HEARTBEAT_FILE" << WS_EOF
## Workspace Context

$workspace_line

WS_EOF
    fi

    # Token budget
    cat >> "$HEARTBEAT_FILE" << BUDGET_EOF
## Token Budget

$budget_line

BUDGET_EOF

    # Cross-repository context
    if [[ -f "$AUTONOMY_DIR/lib/repos.sh" ]]; then
        local repo_line
        repo_line=$(bash "$AUTONOMY_DIR/lib/repos.sh" oneliner 2>/dev/null)
        if [[ -n "$repo_line" && "$repo_line" != *"no cross-repo"* ]]; then
            cat >> "$HEARTBEAT_FILE" << REPO_EOF
## Cross-Repository

$repo_line

To switch repos: \`bash $AUTONOMY_DIR/lib/repos.sh switch <name>\`
To rotate: \`bash $AUTONOMY_DIR/lib/repos.sh rotate\`

REPO_EOF
        fi
    fi

    # Persistent memory
    if [[ -n "$memory_summary" && "$memory_summary" != "No persistent memories yet." ]]; then
        cat >> "$HEARTBEAT_FILE" << MEMORY_EOF
## Persistent Memory

$memory_summary

To store new knowledge: \`bash $AUTONOMY_DIR/lib/memory.sh store <category> "content"\`
Categories: facts, decisions, patterns, blockers, preferences

MEMORY_EOF
    fi

    # Sub-agents
    cat >> "$HEARTBEAT_FILE" << AGENTS_EOF
## Sub-Agents

$agents_summary

To spawn a sub-agent: \`bash $AUTONOMY_DIR/lib/sub-agents.sh spawn "$current_task" "sub-task-name" "description"\`
To spawn a parallel sub-agent: \`bash $AUTONOMY_DIR/lib/sub-agents.sh spawn_parallel "$current_task" "sub-task-name" "description"\`

AGENTS_EOF

    # Prompt evolution performance
    if [[ -f "$AUTONOMY_DIR/lib/prompt-evolution.sh" ]]; then
        local perf_line
        perf_line=$(bash "$AUTONOMY_DIR/lib/prompt-evolution.sh" oneliner 2>/dev/null)
        if [[ -n "$perf_line" && "$perf_line" != *"0/100"* ]]; then
            cat >> "$HEARTBEAT_FILE" << PERF_EOF
## Performance Tracking

$perf_line

PERF_EOF
        fi
    fi

    # AI capabilities
    if [[ "$ai_configured" == "true" ]]; then
        cat >> "$HEARTBEAT_FILE" << AI_EOF
## AI Capabilities (Active)

You have access to these AI-powered tools:
- **Terminal:** \`bash $AUTONOMY_DIR/lib/ai-engine.sh terminal "command"\` — Run shell commands
- **Git Commit:** \`bash $AUTONOMY_DIR/lib/ai-engine.sh commit\` — AI-generated commit message
- **Evidence:** \`bash $AUTONOMY_DIR/lib/ai-engine.sh evidence "$current_task" "test command"\`
- **Analysis:** \`bash $AUTONOMY_DIR/lib/ai-engine.sh analyze <task.json>\`
- **Memory:** \`bash $AUTONOMY_DIR/lib/memory.sh store facts "learned something"\`

Use these to verify work, gather evidence, and maintain context.

AI_EOF
    fi

    # New Capabilities
    cat >> "$HEARTBEAT_FILE" << CAPABILITIES_EOF
## System Capabilities

### VM Integration (Full System Access)
- Process management: \`autonomy vm process_list\`, \`autonomy vm top_cpu\`
- Service control: \`autonomy vm service_list\`, \`autonomy vm service_status <svc>\`
- Docker control: \`autonomy vm docker_ps\`, \`autonomy vm docker_logs <c>\`
- Resources: \`autonomy vm cpu\`, \`autonomy vm memory\`, \`autonomy vm disk\`
- Network: \`autonomy vm network_connections\`, \`autonomy vm ping <host>\`
- Storage: \`autonomy vm storage_df\`, \`autonomy vm storage_du <path>\`

### File Watching
- Add watcher: \`autonomy watcher add <path> <action> [name]\`
- List watchers: \`autonomy watcher list\`
- Check changes: \`autonomy watcher check\`
- Daemon: \`autonomy watcher daemon_start\`

### Diagnostics
- Health check: \`autonomy diagnostic health\`
- Auto-repair: \`autonomy diagnostic repair\`
- System info: \`autonomy diagnostic system\`

### Enhanced Execution
- With retry: \`autonomy execute retry "<cmd>" [max] [delay]\`
- Async: \`autonomy execute async "<cmd>" [name]\`
- Parallel: \`autonomy execute parallel "cmd1" "cmd2" ...\`
- Timeout: \`autonomy execute timeout <secs> "<cmd>"\`

### Verification-Driven Development
- Ensure criteria: \`bash $AUTONOMY_DIR/lib/verification-driven.sh ensure <task_id>\`
- Verify task: \`bash $AUTONOMY_DIR/lib/verification-driven.sh verify <task_id>\`
- Fix subtasks: \`bash $AUTONOMY_DIR/lib/verification-driven.sh fix_subtasks <task_id>\`

### Closed-Loop Execution
- Execute task: \`bash $AUTONOMY_DIR/lib/execution-engine.sh execute <task_id>\`
- Check status: \`bash $AUTONOMY_DIR/lib/execution-engine.sh status <task_id>\`

### Intelligent Logging
- Query logs: \`autonomy log query --level INFO --last 20\`
- Tail: \`autonomy log tail [n]\`
- Stats: \`autonomy log stats\`
- Errors: \`autonomy log errors [n]\`

### Plugins
- List: \`autonomy plugin list\`
- Load: \`autonomy plugin load <name>\`
- Create: \`autonomy plugin create <name>\`
- Discover: \`autonomy plugin discover\`

### Skill Acquisition & Tool Creation
- Learn skill: \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh learn <name> <desc> <category>\`
- Create tool: \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh create_tool <name> <desc> <cmds...>\`
- Create plugin: \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh create_plugin <name> <desc> [funcs_json]\`
- AI-generate tool: \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh generate "<description>"\`
- List skills: \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh list\`
- Status: \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh status\`

CAPABILITIES_EOF

    # Skill acquisition stats — expose full skill data to AI
    if [[ -f "$AUTONOMY_DIR/lib/skill-acquisition.sh" ]]; then
        local skill_count
        skill_count=$(jq '.skills | length' "$AUTONOMY_DIR/state/skills.json" 2>/dev/null || echo 0)
        if [[ "$skill_count" -gt 0 ]]; then
            local skill_summary
            skill_summary=$(bash "$AUTONOMY_DIR/lib/skill-acquisition.sh" oneliner 2>/dev/null)
            cat >> "$HEARTBEAT_FILE" << SKILL_EOF
## Learned Skills & Capabilities
$skill_summary

Use \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh generate "<description>"\` to create a new tool for any capability gap.
Use \`bash $AUTONOMY_DIR/lib/skill-acquisition.sh list\` to see full skill inventory.

SKILL_EOF
        fi
    fi

    # Hard limits & rules
    cat >> "$HEARTBEAT_FILE" << RULES_EOF
---

## Hard Limits (Always Respect)

| Limit | Value |
|-------|-------|
| Max concurrent tasks | $max_tasks |
| Max file edits / session | $max_edits |
| Max web searches | $max_searches |
| Max iterations / task | $max_iterations |
| Daily token budget | $daily_budget |

## Execution Rules

1. **Check** — Read this HEARTBEAT.md. What's assigned? What's the history?
2. **Plan** — Break the task into subtasks if you haven't already.
3. **Execute** — Work through one subtask at a time. Stay focused.
4. **Verify** — Test your work. Use \`ai-engine.sh terminal\` to run tests. Gather evidence.
5. **Evidence** — After work, run verification and attach proof:
   \`\`\`bash
   bash $AUTONOMY_DIR/lib/ai-engine.sh evidence "$current_task" "test_command_1" "test_command_2"
   \`\`\`
6. **Journal** — After finishing, log what you did:
   \`\`\`bash
   bash $AUTONOMY_DIR/lib/journal.sh append "$current_task" "summary of what I did" "status" "next step"
   \`\`\`
7. **Memory** — Store any important discoveries or decisions:
   \`\`\`bash
   bash $AUTONOMY_DIR/lib/memory.sh store decisions "Chose X approach because Y"
   \`\`\`
8. **Complete or Continue** — Mark the task done if finished, or let the next heartbeat pick up where you left off.

## Anti-Hallucination Rules (CRITICAL)

- **Verify files exist** — Use \`ai-engine.sh terminal "ls -la file"\` to check.
- **Test your work** — Run the code/tool. Use terminal access to verify.
- **Require evidence** — Use \`ai-engine.sh evidence\` to gather proof. Don't say "it works" without it.
- **Check for existing solutions** — Don't rebuild what exists.
- **Max $max_iterations attempts** — If stuck after $max_iterations tries, report failure.
- **Store learnings** — Use \`memory.sh store patterns "what I learned"\` to remember.

## Completion

A task is **DONE** when:
- It works (you tested it)
- It solves the original problem
- You verified it (anti-hallucination check)
- You logged a journal entry

Mark complete:
\`\`\`bash
bash $AUTONOMY_DIR/autonomy task complete "$current_task" "Tested: [describe what was tested and proven]"
\`\`\`

## If Nothing To Do

Respond with: **HEARTBEAT_OK**

Do NOT invent work. Do NOT build things nobody asked for. Wait for the next task.

RULES_EOF

    echo "$HEARTBEAT_FILE"
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-build}" in
    build)  build ;;
    show)   build > /dev/null; cat "$HEARTBEAT_FILE" ;;
    *)
        echo "Usage: heartbeat-builder.sh {build|show}"
        ;;
esac
