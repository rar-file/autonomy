#!/bin/bash
# Learning-From-Failure Feedback Loop
# Analyzes failures, stores patterns, and prevents repeats.
# Integrates with memory.sh for persistent failure knowledge.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
TASKS_DIR="$AUTONOMY_DIR/tasks"
STATE_DIR="$AUTONOMY_DIR/state"
FAILURE_DB="$STATE_DIR/failure_patterns.json"
FAILURE_LOG="$AUTONOMY_DIR/logs/failures.log"

mkdir -p "$STATE_DIR" "$AUTONOMY_DIR/logs"

_fail_log() {
    echo "$(date -Iseconds) [$1] $2" >> "$FAILURE_LOG"
}

# ── Pattern Database ────────────────────────────────────────

init_db() {
    [[ -f "$FAILURE_DB" ]] || echo '{
        "patterns": [],
        "stats": {
            "total_analyzed": 0,
            "unique_patterns": 0,
            "prevented": 0
        }
    }' > "$FAILURE_DB"
}

# ── Analyze a Failed Task ──────────────────────────────────

analyze_failure() {
    local task_id="$1"
    local task_file="$TASKS_DIR/${task_id}.json"

    [[ -f "$task_file" ]] || { echo "Task not found: $task_id"; return 1; }

    init_db

    _fail_log INFO "Analyzing failure for task: $task_id"

    # Gather failure context
    local task_name task_desc status attempts
    task_name=$(jq -r '.name // .id' "$task_file")
    task_desc=$(jq -r '.description // ""' "$task_file")
    status=$(jq -r '.status // "unknown"' "$task_file")
    attempts=$(jq -r '.attempts // 0' "$task_file")
    local ai_analysis
    ai_analysis=$(jq -r '.ai_analysis // ""' "$task_file")
    local exec_error=""

    # Check execution engine state
    local exec_state_file="$STATE_DIR/execution/${task_id}.json"
    if [[ -f "$exec_state_file" ]]; then
        exec_error=$(jq -r '.error // ""' "$exec_state_file")
        local step_results
        step_results=$(jq -r '.step_results[] | select(.success == false) | .result' "$exec_state_file" 2>/dev/null)
        [[ -n "$step_results" ]] && exec_error="$exec_error | Failed steps: $step_results"
    fi

    # Build failure analysis
    local category="unknown"
    local root_cause=""
    local prevention=""

    # Pattern matching for common failures
    local context="$task_desc $ai_analysis $exec_error"

    if echo "$context" | grep -qi 'permission denied\|not executable\|access denied'; then
        category="permissions"
        root_cause="Permission or access issue"
        prevention="Check file permissions before execution. Use 'chmod +x' for scripts."
    elif echo "$context" | grep -qi 'not found\|no such file\|missing\|does not exist'; then
        category="missing-resource"
        root_cause="Required file or resource not found"
        prevention="Verify all required files exist before starting. Use 'test -f' checks."
    elif echo "$context" | grep -qi 'syntax error\|parse error\|invalid json\|unexpected token'; then
        category="syntax"
        root_cause="Syntax or parsing error in code or data"
        prevention="Validate syntax before committing. Use linters and 'jq empty' for JSON."
    elif echo "$context" | grep -qi 'timeout\|exceeded\|too long\|timed out'; then
        category="timeout"
        root_cause="Operation exceeded time limit"
        prevention="Break operation into smaller chunks. Use timeouts with graceful handling."
    elif echo "$context" | grep -qi 'memory\|oom\|killed\|out of memory'; then
        category="resource"
        root_cause="Memory or resource exhaustion"
        prevention="Process data in chunks. Monitor resource usage before heavy operations."
    elif echo "$context" | grep -qi 'network\|connection\|dns\|curl\|api.*fail'; then
        category="network"
        root_cause="Network or API connectivity issue"
        prevention="Add retry logic for network operations. Check connectivity first."
    elif echo "$context" | grep -qi 'merge conflict\|diverged\|push rejected'; then
        category="git"
        root_cause="Git conflict or sync issue"
        prevention="Pull latest changes before working. Resolve conflicts before pushing."
    elif echo "$context" | grep -qi 'test.*fail\|assertion.*fail\|expect.*fail'; then
        category="test-failure"
        root_cause="Tests did not pass"
        prevention="Run tests incrementally. Fix one test at a time. Check test prerequisites."
    fi

    # Use AI for deeper analysis if heuristics are inconclusive
    if [[ "$category" == "unknown" && -f "$AUTONOMY_DIR/lib/ai-engine.sh" ]]; then
        local prompt="Analyze this task failure. What went wrong and how to prevent it?

Task: $task_name
Description: $task_desc
Status: $status
Attempts: $attempts
Error: $exec_error

Respond in 3 lines max:
Line 1: Category (one word: permissions, syntax, timeout, logic, unknown)
Line 2: Root cause (one sentence)
Line 3: Prevention (one sentence)"

        local ai_result
        ai_result=$(bash "$AUTONOMY_DIR/lib/ai-engine.sh" call "Analyze failure" "$prompt" 2>/dev/null)

        if [[ -n "$ai_result" ]]; then
            category=$(echo "$ai_result" | head -1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            root_cause=$(echo "$ai_result" | sed -n '2p')
            prevention=$(echo "$ai_result" | sed -n '3p')
        fi
    fi

    # Store failure pattern
    local pattern
    pattern=$(jq -n \
        --arg task "$task_id" \
        --arg name "$task_name" \
        --arg cat "$category" \
        --arg cause "$root_cause" \
        --arg prev "$prevention" \
        --argjson attempts "$attempts" \
        --arg ts "$(date -Iseconds)" \
        '{task_id: $task, task_name: $name, category: $cat, root_cause: $cause, prevention: $prev, attempts: $attempts, analyzed_at: $ts}')

    local db
    db=$(cat "$FAILURE_DB")

    # Check for duplicate pattern (same category + similar cause)
    local existing
    existing=$(echo "$db" | jq --arg cat "$category" \
        '[.patterns[] | select(.category == $cat)] | length')

    db=$(echo "$db" | jq --argjson p "$pattern" \
        '.patterns += [$p] | .patterns = (.patterns | .[-100:]) |
         .stats.total_analyzed += 1 |
         .stats.unique_patterns = ([.patterns[].category] | unique | length)')
    echo "$db" | jq . > "$FAILURE_DB"

    # Store in persistent memory
    if [[ -f "$AUTONOMY_DIR/lib/memory.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/memory.sh" store patterns \
            "FAILURE[$category]: $task_name — $root_cause. Prevention: $prevention" 2>/dev/null
    fi

    _fail_log INFO "Failure analyzed: $task_id category=$category cause=$root_cause"
    echo "Failure Analysis for $task_id:"
    echo "  Category: $category"
    echo "  Root Cause: $root_cause"
    echo "  Prevention: $prevention"
}

# ── Pre-Task Failure Pattern Matching ──────────────────────
# Check if a task is likely to fail based on known patterns

check_patterns() {
    local task_id="$1"
    local task_file="$TASKS_DIR/${task_id}.json"

    [[ -f "$task_file" ]] || return 0
    init_db

    local task_desc
    task_desc=$(jq -r '.description // ""' "$task_file")

    local warnings="[]"
    local db
    db=$(cat "$FAILURE_DB")
    local pattern_count
    pattern_count=$(echo "$db" | jq '.patterns | length')

    for ((i = 0; i < pattern_count; i++)); do
        local prev_name prev_cat prev_prevention
        prev_name=$(echo "$db" | jq -r ".patterns[$i].task_name")
        prev_cat=$(echo "$db" | jq -r ".patterns[$i].category")
        prev_prevention=$(echo "$db" | jq -r ".patterns[$i].prevention")

        # Simple keyword matching between task descriptions
        local prev_desc_words
        prev_desc_words=$(echo "$prev_name" | tr '-' ' ')

        # Check if any significant words overlap
        local match=false
        for word in $prev_desc_words; do
            [[ ${#word} -lt 4 ]] && continue  # Skip short words
            if echo "$task_desc" | grep -qi "$word"; then
                match=true
                break
            fi
        done

        if [[ "$match" == "true" ]]; then
            warnings=$(echo "$warnings" | jq \
                --arg cat "$prev_cat" \
                --arg prev "$prev_prevention" \
                --arg similar "$prev_name" \
                '. + [{"category": $cat, "prevention": $prev, "similar_task": $similar}]')
        fi
    done

    local warning_count
    warning_count=$(echo "$warnings" | jq 'length')

    if [[ $warning_count -gt 0 ]]; then
        _fail_log WARN "Found $warning_count failure pattern matches for $task_id"
        echo "WARNING: Task $task_id matches $warning_count known failure patterns:"
        echo "$warnings" | jq -r '.[] | "  ⚠ Category: \(.category) | Similar to: \(.similar_task) | Tip: \(.prevention)"'

        # Inject warnings into task file
        local tmp="${task_file}.tmp.$$"
        jq --argjson w "$warnings" '.failure_warnings = $w' "$task_file" > "$tmp" && mv "$tmp" "$task_file"

        # Update prevention stats
        db=$(echo "$db" | jq '.stats.prevented += 1')
        echo "$db" | jq . > "$FAILURE_DB"
    fi

    return 0
}

# ── Failure Summary ─────────────────────────────────────────

failure_summary() {
    init_db
    jq '{
        stats,
        top_categories: ([.patterns[].category] | group_by(.) | map({category: .[0], count: length}) | sort_by(-.count) | .[:5]),
        recent_failures: (.patterns | .[-5:] | map({task_name, category, root_cause, analyzed_at}))
    }' "$FAILURE_DB"
}

# One-liner for HEARTBEAT injection
failure_oneliner() {
    init_db
    local total unique prevented
    total=$(jq '.stats.total_analyzed // 0' "$FAILURE_DB")
    unique=$(jq '.stats.unique_patterns // 0' "$FAILURE_DB")
    prevented=$(jq '.stats.prevented // 0' "$FAILURE_DB")

    if [[ $total -gt 0 ]]; then
        echo "Failure DB: $total analyzed, $unique unique patterns, $prevented prevented"
    else
        echo "No failures analyzed yet"
    fi
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    analyze)       shift; analyze_failure "$1" ;;
    check)         shift; check_patterns "$1" ;;
    summary)       failure_summary ;;
    oneliner)      failure_oneliner ;;
    *)
        echo "Learning-From-Failure Feedback Loop"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  analyze <task_id>   Analyze a failed task"
        echo "  check <task_id>     Pre-check against known failure patterns"
        echo "  summary             Failure pattern summary"
        echo "  oneliner            One-line summary for HEARTBEAT"
        ;;
esac
