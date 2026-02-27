#!/bin/bash
# Verification-Driven Development
# Ensures every task has explicit verification criteria BEFORE execution.
# Auto-generates verification sub-tasks and enforces test-first workflow.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
TASKS_DIR="$AUTONOMY_DIR/tasks"
STATE_DIR="$AUTONOMY_DIR/state"
VDD_LOG="$AUTONOMY_DIR/logs/verification.log"

mkdir -p "$STATE_DIR" "$AUTONOMY_DIR/logs"

_vdd_log() {
    echo "$(date -Iseconds) [$1] $2" >> "$VDD_LOG"
}

# ── Verification Criteria Management ───────────────────────

# Ensure a task has verification criteria. If not, generate them.
ensure_verification() {
    local task_id="$1"
    local task_file="$TASKS_DIR/${task_id}.json"

    [[ -f "$task_file" ]] || { echo "Task not found: $task_id"; return 1; }

    # Check if verification criteria already exist
    local has_verification
    has_verification=$(jq 'has("verification_criteria") and (.verification_criteria | length > 0)' "$task_file" 2>/dev/null)

    if [[ "$has_verification" == "true" ]]; then
        _vdd_log INFO "Task $task_id already has verification criteria"
        return 0
    fi

    _vdd_log INFO "Generating verification criteria for task: $task_id"

    # Get task details
    local task_name task_desc
    task_name=$(jq -r '.name // .id' "$task_file")
    task_desc=$(jq -r '.description // "No description"' "$task_file")

    # Use AI to generate criteria if available, otherwise use heuristics
    local criteria="[]"

    if [[ -f "$AUTONOMY_DIR/lib/ai-engine.sh" ]]; then
        local prompt="Generate verification criteria for this task. Each criterion should be a specific, testable check.

Task: $task_name
Description: $task_desc

Respond ONLY with a JSON array of strings, each being a verification criterion.
Example: [\"File config.json exists and is valid JSON\", \"Running 'npm test' passes with 0 failures\"]
Return ONLY valid JSON."

        local ai_result
        ai_result=$(bash "$AUTONOMY_DIR/lib/ai-engine.sh" call "Generate verification criteria" "$prompt" 2>/dev/null)

        if [[ -n "$ai_result" ]]; then
            # Extract JSON array
            local extracted
            extracted=$(echo "$ai_result" | grep -o '\[.*\]' | head -1)
            if echo "$extracted" | jq empty 2>/dev/null; then
                criteria="$extracted"
            fi
        fi
    fi

    # If AI failed or not available, use heuristic criteria
    if [[ "$criteria" == "[]" ]]; then
        criteria=$(generate_heuristic_criteria "$task_file")
    fi

    # Store criteria in task file
    local tmp="${task_file}.tmp.$$"
    jq --argjson vc "$criteria" '.verification_criteria = $vc | .verification_status = "pending"' \
        "$task_file" > "$tmp" && mv "$tmp" "$task_file"

    _vdd_log INFO "Added $(echo "$criteria" | jq 'length') verification criteria to $task_id"
    echo "Added verification criteria to $task_id"
}

# Generate heuristic verification criteria based on task keywords
generate_heuristic_criteria() {
    local task_file="$1"
    local name desc
    name=$(jq -r '.name // ""' "$task_file")
    desc=$(jq -r '.description // ""' "$task_file")
    local combined="$name $desc"

    local criteria=()

    # Detect task type from keywords
    if echo "$combined" | grep -qi 'fix\|bug\|error\|crash\|broken'; then
        criteria+=("The previously failing behavior no longer occurs")
        criteria+=("No new errors are introduced (check error logs)")
        criteria+=("Existing tests still pass")
    fi

    if echo "$combined" | grep -qi 'test\|coverage\|spec'; then
        criteria+=("New test files are created and run successfully")
        criteria+=("Test coverage has increased or maintained")
        criteria+=("All tests pass with exit code 0")
    fi

    if echo "$combined" | grep -qi 'feature\|add\|create\|implement'; then
        criteria+=("The new feature is functional and can be demonstrated")
        criteria+=("The implementation follows existing code patterns")
        criteria+=("No existing functionality is broken")
    fi

    if echo "$combined" | grep -qi 'refactor\|clean\|improve\|optimize'; then
        criteria+=("Code functionality is preserved (tests pass)")
        criteria+=("Code is measurably cleaner or faster")
        criteria+=("No regressions in existing behavior")
    fi

    if echo "$combined" | grep -qi 'doc\|readme\|comment'; then
        criteria+=("Documentation is accurate and complete")
        criteria+=("Code examples in documentation actually work")
    fi

    if echo "$combined" | grep -qi 'security\|auth\|secret\|credential'; then
        criteria+=("No credentials are hardcoded or exposed")
        criteria+=("Security improvement is verifiable")
    fi

    # Default criteria if none matched
    if [[ ${#criteria[@]} -eq 0 ]]; then
        criteria+=("The task objective is met as described")
        criteria+=("No errors in logs after change")
        criteria+=("Changes are committed with a descriptive message")
    fi

    # Convert to JSON array
    printf '%s\n' "${criteria[@]}" | jq -R . | jq -s .
}

# ── Run Verification ───────────────────────────────────────

# Verify a task against its criteria
verify_task() {
    local task_id="$1"
    local task_file="$TASKS_DIR/${task_id}.json"

    [[ -f "$task_file" ]] || { echo "Task not found: $task_id"; return 1; }

    local criteria
    criteria=$(jq '.verification_criteria // []' "$task_file")
    local count
    count=$(echo "$criteria" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No verification criteria found. Run ensure_verification first."
        return 1
    fi

    _vdd_log INFO "Verifying task $task_id against $count criteria"

    local results="[]"
    local all_passed=true

    for ((i = 0; i < count; i++)); do
        local criterion
        criterion=$(echo "$criteria" | jq -r ".[$i]")

        # Ask AI to verify this criterion
        local passed=true
        local evidence="Manual check required"

        if [[ -f "$AUTONOMY_DIR/lib/ai-engine.sh" ]]; then
            local check_prompt="Verify this criterion for the task. Check if it's met.
Criterion: $criterion
Task: $(jq -r '.name' "$task_file")

Respond with ONLY: PASS or FAIL followed by a one-line explanation.
Example: PASS — All tests pass with 0 failures"

            local check_result
            check_result=$(bash "$AUTONOMY_DIR/lib/ai-engine.sh" call "Verify criterion" "$check_prompt" 2>/dev/null)

            if echo "$check_result" | grep -qi '^FAIL'; then
                passed=false
                all_passed=false
                evidence="$check_result"
            elif echo "$check_result" | grep -qi '^PASS'; then
                evidence="$check_result"
            fi
        fi

        results=$(echo "$results" | jq \
            --arg criterion "$criterion" \
            --argjson passed "$passed" \
            --arg evidence "$evidence" \
            '. + [{"criterion": $criterion, "passed": $passed, "evidence": $evidence}]')
    done

    # Update task with verification results
    local passed_count
    passed_count=$(echo "$results" | jq '[.[] | select(.passed == true)] | length')

    local tmp="${task_file}.tmp.$$"
    jq --argjson vr "$results" --arg vs "$(if [[ "$all_passed" == "true" ]]; then echo "passed"; else echo "failed"; fi)" \
        --arg vt "$(date -Iseconds)" \
        '.verification_results = $vr | .verification_status = $vs | .verified_at = $vt' \
        "$task_file" > "$tmp" && mv "$tmp" "$task_file"

    _vdd_log INFO "Verification of $task_id: $passed_count/$count passed"

    if [[ "$all_passed" == "true" ]]; then
        echo "VERIFIED: All $count criteria passed for $task_id"
        return 0
    else
        echo "FAILED: $passed_count/$count criteria passed for $task_id"
        return 1
    fi
}

# ── Generate Verification Sub-Tasks ────────────────────────

# Create sub-tasks for each unverified criterion
create_verification_subtasks() {
    local task_id="$1"
    local task_file="$TASKS_DIR/${task_id}.json"

    [[ -f "$task_file" ]] || return 1

    local results
    results=$(jq '.verification_results // []' "$task_file")
    local count
    count=$(echo "$results" | jq 'length')

    [[ $count -eq 0 ]] && { echo "No verification results. Run verify_task first."; return 1; }

    local created=0
    for ((i = 0; i < count; i++)); do
        local passed criterion
        passed=$(echo "$results" | jq -r ".[$i].passed")
        criterion=$(echo "$results" | jq -r ".[$i].criterion")

        if [[ "$passed" == "false" ]]; then
            local sub_name="verify-${task_id}-fix-$((i+1))"
            local sub_desc="Fix failed verification: $criterion (for task $task_id)"

            if [[ -f "$AUTONOMY_DIR/lib/sub-agents.sh" ]]; then
                bash "$AUTONOMY_DIR/lib/sub-agents.sh" spawn "$task_id" "$sub_name" "$sub_desc" "high" 2>/dev/null
                created=$((created + 1))
            fi
        fi
    done

    echo "Created $created verification fix sub-tasks for $task_id"
}

# ── Status ──────────────────────────────────────────────────

vdd_status() {
    local total=0 verified=0 pending=0 failed=0

    for f in "$TASKS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local vs
        vs=$(jq -r '.verification_status // "none"' "$f" 2>/dev/null)
        total=$((total + 1))
        case "$vs" in
            passed)  verified=$((verified + 1)) ;;
            pending) pending=$((pending + 1)) ;;
            failed)  failed=$((failed + 1)) ;;
        esac
    done

    jq -n --argjson t "$total" --argjson v "$verified" --argjson p "$pending" --argjson f "$failed" \
        '{total_tasks: $t, verified: $v, pending_verification: $p, failed_verification: $f}'
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    ensure)        shift; ensure_verification "$1" ;;
    verify)        shift; verify_task "$1" ;;
    fix_subtasks)  shift; create_verification_subtasks "$1" ;;
    status)        vdd_status ;;
    *)
        echo "Verification-Driven Development"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  ensure <task_id>       Generate verification criteria for a task"
        echo "  verify <task_id>       Run verification against criteria"
        echo "  fix_subtasks <task_id> Create sub-tasks for failed verifications"
        echo "  status                 Verification status across all tasks"
        ;;
esac
