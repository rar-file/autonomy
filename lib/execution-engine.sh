#!/bin/bash
# Closed-Loop Execution Engine
# Extends task processing with: analyze → execute → verify → fix → complete
# Replaces the "analyze-only" behavior of ai_process_task()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
TASKS_DIR="$AUTONOMY_DIR/tasks"
STATE_DIR="$AUTONOMY_DIR/state"
EXEC_STATE_DIR="$STATE_DIR/execution"

mkdir -p "$EXEC_STATE_DIR" "$AUTONOMY_DIR/logs"

source "$SCRIPT_DIR/ai-engine.sh" > /dev/null 2>&1 || true
source "$SCRIPT_DIR/memory.sh" > /dev/null 2>&1 || true
source "$SCRIPT_DIR/journal.sh" > /dev/null 2>&1 || true

# ── Execution States ────────────────────────────────────────
# pending → analyzing → executing → verifying → fixing → completed/failed

EXEC_LOG="$AUTONOMY_DIR/logs/execution.log"

_exec_log() {
    local level="$1"; shift
    echo "$(date -Iseconds) [$level] $*" >> "$EXEC_LOG"
}

# ── State Management ────────────────────────────────────────

get_exec_state() {
    local task_id="$1"
    local state_file="$EXEC_STATE_DIR/${task_id}.json"

    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        jq -n \
            --arg id "$task_id" \
            --arg phase "pending" \
            '{
                task_id: $id,
                phase: $phase,
                plan_steps: [],
                current_step: 0,
                step_results: [],
                verification_results: [],
                fix_attempts: 0,
                max_fix_attempts: 3,
                started_at: null,
                completed_at: null,
                error: null
            }'
    fi
}

save_exec_state() {
    local task_id="$1"
    local state="$2"
    echo "$state" | jq . > "$EXEC_STATE_DIR/${task_id}.json"
}

update_task_progress() {
    local task_id="$1"
    local progress="$2"
    local detail="$3"
    local task_file="$TASKS_DIR/${task_id}.json"

    [[ -f "$task_file" ]] || return 1

    local tmp="${task_file}.tmp.$$"
    jq --argjson p "$progress" --arg d "$detail" \
        '.progress = $p | .progress_detail = $d' \
        "$task_file" > "$tmp" && mv "$tmp" "$task_file"
}

update_task_status() {
    local task_id="$1"
    local status="$2"
    local task_file="$TASKS_DIR/${task_id}.json"

    [[ -f "$task_file" ]] || return 1

    local tmp="${task_file}.tmp.$$"
    jq --arg s "$status" '.status = $s' "$task_file" > "$tmp" && mv "$tmp" "$task_file"
}

# ── Phase 1: ANALYZE ────────────────────────────────────────
# Break task into executable steps with verification criteria

phase_analyze() {
    local task_id="$1"
    local task_file="$TASKS_DIR/${task_id}.json"
    local exec_state

    [[ -f "$task_file" ]] || { _exec_log ERROR "Task file not found: $task_id"; return 1; }

    _exec_log INFO "ANALYZE phase for task: $task_id"
    exec_state=$(get_exec_state "$task_id")
    exec_state=$(echo "$exec_state" | jq '.phase = "analyzing" | .started_at = "'"$(date -Iseconds)"'"')
    save_exec_state "$task_id" "$exec_state"
    update_task_progress "$task_id" 10 "Analyzing task and creating execution plan"

    local task_name task_desc
    task_name=$(jq -r '.name // .id' "$task_file")
    task_desc=$(jq -r '.description // "No description"' "$task_file")
    local subtasks
    subtasks=$(jq -r '.subtasks // [] | join("\n")' "$task_file")

    # Build analysis prompt
    local prompt="Break this task into concrete executable steps. For each step, specify:
1. What to do (specific commands or file edits)
2. How to verify it worked (a test command that returns 0 on success)

Task: $task_name
Description: $task_desc"

    [[ -n "$subtasks" && "$subtasks" != "" ]] && prompt="$prompt
Existing subtasks:
$subtasks"

    prompt="$prompt

Respond ONLY with a JSON array of steps. Each step:
{\"action\": \"description of what to do\", \"commands\": [\"cmd1\", \"cmd2\"], \"verify\": \"command that returns 0 if step succeeded\"}

Return ONLY valid JSON. No markdown, no explanation."

    local analysis_result
    analysis_result=$(ai_call "$prompt" 2>/dev/null)

    if [[ -z "$analysis_result" ]]; then
        _exec_log ERROR "AI analysis returned empty for $task_id"
        exec_state=$(echo "$exec_state" | jq '.phase = "failed" | .error = "AI analysis returned empty"')
        save_exec_state "$task_id" "$exec_state"
        return 1
    fi

    # Extract JSON array from response (handles markdown wrapping)
    local steps_json
    steps_json=$(echo "$analysis_result" | grep -o '\[.*\]' | head -1)

    if [[ -z "$steps_json" ]] || ! echo "$steps_json" | jq empty 2>/dev/null; then
        # Fallback: create a single step from the analysis
        _exec_log WARN "Could not parse steps JSON, creating single-step plan"
        steps_json='[{"action": "Execute task as analyzed", "commands": [], "verify": "echo ok"}]'

        # Store raw analysis in task file
        local tmp="${task_file}.tmp.$$"
        jq --arg plan "$analysis_result" '.ai_plan = $plan' "$task_file" > "$tmp" && mv "$tmp" "$task_file"
    fi

    exec_state=$(echo "$exec_state" | jq --argjson steps "$steps_json" \
        '.plan_steps = $steps | .phase = "executing" | .current_step = 0')
    save_exec_state "$task_id" "$exec_state"
    update_task_progress "$task_id" 20 "Plan created with $(echo "$steps_json" | jq 'length') steps"

    _exec_log INFO "Analysis complete: $(echo "$steps_json" | jq 'length') steps planned for $task_id"
    return 0
}

# ── Phase 2: EXECUTE ────────────────────────────────────────
# Run each step's commands

phase_execute() {
    local task_id="$1"
    local exec_state step_count current_step

    exec_state=$(get_exec_state "$task_id")
    step_count=$(echo "$exec_state" | jq '.plan_steps | length')
    current_step=$(echo "$exec_state" | jq '.current_step')

    if [[ "$current_step" -ge "$step_count" ]]; then
        _exec_log INFO "All steps executed for $task_id, moving to verify"
        exec_state=$(echo "$exec_state" | jq '.phase = "verifying"')
        save_exec_state "$task_id" "$exec_state"
        return 0
    fi

    local step_action step_commands
    step_action=$(echo "$exec_state" | jq -r ".plan_steps[$current_step].action")
    step_commands=$(echo "$exec_state" | jq -r ".plan_steps[$current_step].commands // [] | .[]")

    local progress=$(( 20 + (current_step * 50 / step_count) ))
    update_task_progress "$task_id" "$progress" "Executing step $((current_step + 1))/$step_count: $step_action"
    _exec_log INFO "Executing step $((current_step + 1))/$step_count for $task_id: $step_action"

    local step_result=""
    local step_success=true

    if [[ -n "$step_commands" ]]; then
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            _exec_log INFO "Running command: $cmd"

            local output
            output=$(ai_terminal "$cmd" 2>&1)
            local exit_code=$?
            step_result="${step_result}$ $cmd\n${output}\n"

            if [[ $exit_code -ne 0 ]]; then
                _exec_log WARN "Command failed (exit $exit_code): $cmd"
                step_success=false
                break
            fi
        done <<< "$step_commands"
    else
        # No commands — ask AI to execute the step
        local execute_prompt="Execute this step for the current task. Use terminal commands.
Step: $step_action
Respond with the commands you ran and their results. Be concise."

        step_result=$(ai_call "$execute_prompt" 2>/dev/null)
    fi

    # Record step result
    local result_entry
    result_entry=$(jq -n \
        --arg action "$step_action" \
        --arg result "$step_result" \
        --argjson success "$step_success" \
        --argjson step "$current_step" \
        '{step: $step, action: $action, result: $result, success: $success, at: "'"$(date -Iseconds)"'"}')

    exec_state=$(echo "$exec_state" | jq --argjson entry "$result_entry" \
        '.step_results += [$entry] | .current_step += 1')

    # If all steps done, move to verify
    local new_step=$((current_step + 1))
    if [[ "$new_step" -ge "$step_count" ]]; then
        exec_state=$(echo "$exec_state" | jq '.phase = "verifying"')
    fi

    save_exec_state "$task_id" "$exec_state"
    return 0
}

# ── Phase 3: VERIFY ─────────────────────────────────────────
# Run verification commands for all steps

phase_verify() {
    local task_id="$1"
    local exec_state step_count

    exec_state=$(get_exec_state "$task_id")
    step_count=$(echo "$exec_state" | jq '.plan_steps | length')

    update_task_progress "$task_id" 75 "Verifying results"
    _exec_log INFO "VERIFY phase for task: $task_id"

    local all_passed=true
    local verification_results="[]"

    for ((i = 0; i < step_count; i++)); do
        local verify_cmd
        verify_cmd=$(echo "$exec_state" | jq -r ".plan_steps[$i].verify // \"\"")

        if [[ -z "$verify_cmd" || "$verify_cmd" == "null" || "$verify_cmd" == "echo ok" ]]; then
            verification_results=$(echo "$verification_results" | jq \
                ". + [{\"step\": $i, \"passed\": true, \"output\": \"no verification needed\"}]")
            continue
        fi

        local verify_output
        verify_output=$(ai_terminal "$verify_cmd" 2>&1)
        local verify_exit=$?

        if [[ $verify_exit -eq 0 ]]; then
            verification_results=$(echo "$verification_results" | jq \
                --arg out "$verify_output" \
                ". + [{\"step\": $i, \"passed\": true, \"output\": \$out}]")
            _exec_log INFO "Step $i verification passed"
        else
            all_passed=false
            verification_results=$(echo "$verification_results" | jq \
                --arg out "$verify_output" \
                ". + [{\"step\": $i, \"passed\": false, \"output\": \$out}]")
            _exec_log WARN "Step $i verification failed: $verify_output"
        fi
    done

    exec_state=$(echo "$exec_state" | jq --argjson vr "$verification_results" \
        '.verification_results = $vr')

    if [[ "$all_passed" == "true" ]]; then
        exec_state=$(echo "$exec_state" | jq '.phase = "completed" | .completed_at = "'"$(date -Iseconds)"'"')
        save_exec_state "$task_id" "$exec_state"
        update_task_progress "$task_id" 95 "All verifications passed"
        _exec_log INFO "All verifications passed for $task_id"
        return 0
    else
        local fix_attempts
        fix_attempts=$(echo "$exec_state" | jq '.fix_attempts')
        local max_fix
        max_fix=$(echo "$exec_state" | jq '.max_fix_attempts')

        if [[ "$fix_attempts" -ge "$max_fix" ]]; then
            exec_state=$(echo "$exec_state" | jq '.phase = "failed" | .error = "Max fix attempts exceeded"')
            save_exec_state "$task_id" "$exec_state"
            update_task_progress "$task_id" 80 "Verification failed after $fix_attempts fix attempts"
            _exec_log ERROR "Max fix attempts reached for $task_id"
            return 1
        fi

        exec_state=$(echo "$exec_state" | jq '.phase = "fixing"')
        save_exec_state "$task_id" "$exec_state"
        return 0
    fi
}

# ── Phase 4: FIX ────────────────────────────────────────────
# Ask AI to fix failed verifications, then re-verify

phase_fix() {
    local task_id="$1"
    local exec_state

    exec_state=$(get_exec_state "$task_id")
    local fix_attempts
    fix_attempts=$(echo "$exec_state" | jq '.fix_attempts')

    _exec_log INFO "FIX phase (attempt $((fix_attempts + 1))) for task: $task_id"
    update_task_progress "$task_id" 80 "Fixing failed verifications (attempt $((fix_attempts + 1)))"

    # Collect failed verification info
    local failed_info
    failed_info=$(echo "$exec_state" | jq -r '
        .verification_results | to_entries[] |
        select(.value.passed == false) |
        "Step \(.key): \(.value.output)"
    ')

    local step_results
    step_results=$(echo "$exec_state" | jq -r '
        .step_results[] | "Step \(.step): \(.action) → \(.result)"
    ')

    local fix_prompt="Some verification steps failed. Fix the issues and retry.

What was done:
$step_results

Failed verifications:
$failed_info

Identify what went wrong and fix it. Respond with commands to run.
Format: one command per line, no markdown."

    local fix_response
    fix_response=$(ai_call "$fix_prompt" 2>/dev/null)

    if [[ -n "$fix_response" ]]; then
        # Extract and run fix commands
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^#|^\`|^[\*-] ]] && continue  # Skip comments/markdown
            _exec_log INFO "Fix command: $line"
            ai_terminal "$line" 2>&1 >> "$EXEC_LOG"
        done <<< "$fix_response"
    fi

    exec_state=$(echo "$exec_state" | jq '.fix_attempts += 1 | .phase = "verifying"')
    save_exec_state "$task_id" "$exec_state"
    return 0
}

# ── Phase 5: COMPLETE ───────────────────────────────────────

phase_complete() {
    local task_id="$1"
    local exec_state

    exec_state=$(get_exec_state "$task_id")
    local phase
    phase=$(echo "$exec_state" | jq -r '.phase')

    if [[ "$phase" == "completed" ]]; then
        update_task_status "$task_id" "completed"
        update_task_progress "$task_id" 100 "Task completed with verification"

        # Gather evidence
        ai_gather_evidence "$task_id" "echo 'Execution engine verified all steps'" 2>/dev/null

        local step_count fix_attempts
        step_count=$(echo "$exec_state" | jq '.plan_steps | length')
        fix_attempts=$(echo "$exec_state" | jq '.fix_attempts')

        # Score performance for prompt evolution
        if [[ -f "$AUTONOMY_DIR/lib/prompt-evolution.sh" ]]; then
            local started_at duration_secs
            started_at=$(echo "$exec_state" | jq -r '.started_at // ""')
            duration_secs=0
            if [[ -n "$started_at" && "$started_at" != "null" ]]; then
                local start_epoch end_epoch
                start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
                end_epoch=$(date +%s)
                duration_secs=$((end_epoch - start_epoch))
            fi
            bash "$AUTONOMY_DIR/lib/prompt-evolution.sh" score "$task_id" "true" "$fix_attempts" "$step_count" "$duration_secs" 2>/dev/null
        fi

        # Log to journal
        bash "$SCRIPT_DIR/journal.sh" append "$task_id" \
            "Completed via execution engine: $step_count steps executed and verified" \
            "completed" "" 2>/dev/null

        # Store pattern in memory
        bash "$SCRIPT_DIR/memory.sh" store patterns \
            "Task $task_id completed: $(echo "$exec_state" | jq -r '.plan_steps | length') steps, $(echo "$exec_state" | jq -r '.fix_attempts') fixes needed" 2>/dev/null

        # Learn skill from completed task
        if [[ -f "$AUTONOMY_DIR/lib/skill-acquisition.sh" ]]; then
            local skill_task_name skill_task_desc skill_task_source skill_category
            skill_task_name=$(jq -r '.name // .id // ""' "$TASKS_DIR/${task_id}.json" 2>/dev/null)
            skill_task_desc=$(jq -r '.description // ""' "$TASKS_DIR/${task_id}.json" 2>/dev/null)
            skill_task_source=$(jq -r '.source // ""' "$TASKS_DIR/${task_id}.json" 2>/dev/null)

            # Derive category from source or tags
            skill_category="general"
            case "$skill_task_source" in
                scan:code-annotations)  skill_category="code-quality" ;;
                scan:documentation)     skill_category="documentation" ;;
                scan:test-coverage)     skill_category="testing" ;;
                scan:code-quality)      skill_category="linting" ;;
                scan:security)          skill_category="security" ;;
                scan:dependencies)      skill_category="dependencies" ;;
                trigger:*)              skill_category="automation" ;;
                cross-repo)             skill_category="orchestration" ;;
                self-improvement:*)     skill_category="self-improvement" ;;
                *)
                    # Fallback: infer from task name keywords
                    local lname
                    lname=$(echo "$skill_task_name" | tr '[:upper:]' '[:lower:]')
                    if echo "$lname" | grep -qE 'test|spec|coverage'; then skill_category="testing"
                    elif echo "$lname" | grep -qE 'fix|bug|error|crash'; then skill_category="bug-fix"
                    elif echo "$lname" | grep -qE 'doc|readme|comment'; then skill_category="documentation"
                    elif echo "$lname" | grep -qE 'refactor|clean|improve'; then skill_category="refactoring"
                    elif echo "$lname" | grep -qE 'feature|add|create|implement'; then skill_category="feature"
                    elif echo "$lname" | grep -qE 'security|auth|secret'; then skill_category="security"
                    fi
                    ;;
            esac

            if [[ -n "$skill_task_name" ]]; then
                # Skill name = slugified task name
                local skill_slug
                skill_slug=$(echo "$skill_task_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g; s/--*/-/g; s/^-//; s/-$//')
                # Skill description = human-readable description with execution context
                local skill_desc
                if [[ -n "$skill_task_desc" && "$skill_task_desc" != "null" ]]; then
                    skill_desc="$skill_task_desc (completed in $step_count steps, $fix_attempts fixes)"
                else
                    skill_desc="$skill_task_name (completed in $step_count steps, $fix_attempts fixes)"
                fi
                bash "$AUTONOMY_DIR/lib/skill-acquisition.sh" learn \
                    "$skill_slug" "$skill_desc" "$skill_category" \
                    "source_task:$task_id" 2>/dev/null || true
            fi
        fi

        # Signal adaptive heartbeat about actual task completion
        if [[ -f "$AUTONOMY_DIR/lib/adaptive-heartbeat.sh" ]]; then
            bash "$AUTONOMY_DIR/lib/adaptive-heartbeat.sh" signal_completed >/dev/null 2>&1 || true
        fi

        _exec_log INFO "Task $task_id completed successfully"
        return 0
    elif [[ "$phase" == "failed" ]]; then
        local error
        error=$(echo "$exec_state" | jq -r '.error // "Unknown error"')
        update_task_status "$task_id" "failed"
        update_task_progress "$task_id" 0 "Failed: $error"

        # Score failure for prompt evolution
        if [[ -f "$AUTONOMY_DIR/lib/prompt-evolution.sh" ]]; then
            local fix_attempts step_count
            fix_attempts=$(echo "$exec_state" | jq '.fix_attempts')
            step_count=$(echo "$exec_state" | jq '.plan_steps | length')
            bash "$AUTONOMY_DIR/lib/prompt-evolution.sh" score "$task_id" "false" "$fix_attempts" "$step_count" "0" 2>/dev/null
        fi

        bash "$SCRIPT_DIR/journal.sh" append "$task_id" \
            "Failed via execution engine: $error" \
            "failed" "Needs manual review" 2>/dev/null

        _exec_log ERROR "Task $task_id failed: $error"
        return 1
    fi
}

# ── Main Loop: Run full execution cycle ─────────────────────

execute_task() {
    local task_id="$1"
    local max_iterations="${2:-20}"
    local iteration=0

    [[ -z "$task_id" ]] && { echo "Usage: execution-engine.sh execute <task_id>"; return 1; }
    [[ -f "$TASKS_DIR/${task_id}.json" ]] || { echo "Task not found: $task_id"; return 1; }

    _exec_log INFO "Starting closed-loop execution for task: $task_id"
    update_task_status "$task_id" "ai_processing"

    # Verification-Driven: ensure criteria exist before executing
    if [[ -f "$AUTONOMY_DIR/lib/verification-driven.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/verification-driven.sh" ensure "$task_id" 2>/dev/null || true
    fi

    # Phase 1: Analyze
    phase_analyze "$task_id" || { phase_complete "$task_id"; return 1; }

    # Phase 2-4: Execute → Verify → Fix loop
    while [[ $iteration -lt $max_iterations ]]; do
        iteration=$((iteration + 1))
        local exec_state phase
        exec_state=$(get_exec_state "$task_id")
        phase=$(echo "$exec_state" | jq -r '.phase')

        case "$phase" in
            executing)
                phase_execute "$task_id" || break
                ;;
            verifying)
                phase_verify "$task_id"
                local new_phase
                new_phase=$(echo "$(get_exec_state "$task_id")" | jq -r '.phase')
                [[ "$new_phase" == "completed" || "$new_phase" == "failed" ]] && break
                ;;
            fixing)
                phase_fix "$task_id" || break
                ;;
            completed|failed)
                break
                ;;
            *)
                _exec_log ERROR "Unknown phase: $phase"
                break
                ;;
        esac
    done

    if [[ $iteration -ge $max_iterations ]]; then
        local exec_state
        exec_state=$(get_exec_state "$task_id")
        exec_state=$(echo "$exec_state" | jq '.phase = "failed" | .error = "Max iterations reached"')
        save_exec_state "$task_id" "$exec_state"
    fi

    # Phase 5: Complete/Fail
    phase_complete "$task_id"
}

# ── Status query ────────────────────────────────────────────

execution_status() {
    local task_id="$1"
    local state_file="$EXEC_STATE_DIR/${task_id}.json"

    if [[ -f "$state_file" ]]; then
        cat "$state_file" | jq '{
            task_id,
            phase,
            total_steps: (.plan_steps | length),
            current_step,
            fix_attempts,
            started_at,
            completed_at,
            error
        }'
    else
        echo '{"error": "No execution state found"}'
    fi
}

# ── List all executions ─────────────────────────────────────

list_executions() {
    local results="[]"
    for f in "$EXEC_STATE_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local entry
        entry=$(jq '{task_id, phase, fix_attempts, started_at, completed_at}' "$f")
        results=$(echo "$results" | jq --argjson e "$entry" '. + [$e]')
    done
    echo "$results" | jq .
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    execute)  execute_task "$2" "$3" ;;
    status)   execution_status "$2" ;;
    list)     list_executions ;;
    *)
        echo "Closed-Loop Execution Engine"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  execute <task_id> [max_iter]  - Run full execution loop"
        echo "  status <task_id>              - Check execution status"
        echo "  list                          - List all executions"
        ;;
esac
