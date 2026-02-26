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
    # Priority: needs_ai_attention > ai_processing > first pending
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

    # Check task files
    for task_file in "$TASKS_DIR"/*.json; do
        [[ -f "$task_file" ]] || continue
        local status completed name desc
        status=$(jq -r '.status // "pending"' "$task_file" 2>/dev/null)
        completed=$(jq -r '.completed // false' "$task_file" 2>/dev/null)
        [[ "$completed" == "true" ]] && continue

        if [[ "$status" == "needs_ai_attention" || "$status" == "ai_processing" || "$status" == "pending" ]]; then
            name=$(jq -r '.name // ""' "$task_file" 2>/dev/null)
            desc=$(jq -r '.description // ""' "$task_file" 2>/dev/null)
            echo "$name|$desc"
            return
        fi
    done
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
4. **Verify** — Test your work. Does it actually run? Files exist?
5. **Journal** — After finishing, log what you did:
   \`\`\`bash
   bash $AUTONOMY_DIR/lib/journal.sh append "$current_task" "summary of what I did" "status" "next step"
   \`\`\`
6. **Complete or Continue** — Mark the task done if finished, or let the next heartbeat pick up where you left off.

## Anti-Hallucination Rules (CRITICAL)

- **Verify files exist** — Actually check files you created are there.
- **Test your work** — Run the code/tool. Does it work?
- **Require evidence** — Don't say "it works" without proof.
- **Check for existing solutions** — Don't rebuild what exists.
- **Max $max_iterations attempts** — If stuck after $max_iterations tries, report failure.

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
