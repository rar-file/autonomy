#!/bin/bash
# Self-Improving Prompt Evolution System
# Tracks prompt performance, evolves prompts based on results,
# and generates meta-tasks for self-improvement.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
PROMPTS_DIR="$STATE_DIR/prompt_versions"
SCORES_FILE="$STATE_DIR/prompt_scores.json"
EVOLUTION_LOG="$AUTONOMY_DIR/logs/prompt-evolution.log"

mkdir -p "$PROMPTS_DIR" "$STATE_DIR" "$AUTONOMY_DIR/logs"

_evo_log() {
    echo "$(date -Iseconds) [$1] $2" >> "$EVOLUTION_LOG"
}

# ── Score Tracking ──────────────────────────────────────────
# After each task completion, score the effectiveness

init_scores() {
    [[ -f "$SCORES_FILE" ]] || echo '{
        "task_scores": [],
        "aggregate": {
            "total_tasks": 0,
            "avg_score": 0,
            "avg_fix_attempts": 0,
            "avg_steps": 0,
            "success_rate": 0
        },
        "prompt_version": 1,
        "evolution_count": 0
    }' > "$SCORES_FILE"
}

# Record a task score based on execution results
# score_task <task_id> <success:bool> <fix_attempts> <steps_count> <duration_secs>
score_task() {
    local task_id="$1"
    local success="$2"
    local fix_attempts="${3:-0}"
    local step_count="${4:-1}"
    local duration="${5:-0}"

    init_scores

    # Calculate score (0-100)
    local score=0
    if [[ "$success" == "true" ]]; then
        score=70  # Base for success
        # Bonus for fewer fixes needed
        [[ "$fix_attempts" -eq 0 ]] && score=$((score + 20))
        [[ "$fix_attempts" -eq 1 ]] && score=$((score + 10))
        # Bonus for speed (under 5 min)
        [[ "$duration" -lt 300 ]] && score=$((score + 10))
    else
        score=20  # Some credit for trying
        [[ "$fix_attempts" -gt 0 ]] && score=$((score + 10))  # Tried to fix
    fi

    # Clamp to 0-100
    [[ $score -gt 100 ]] && score=100
    [[ $score -lt 0 ]] && score=0

    local entry
    entry=$(jq -n \
        --arg id "$task_id" \
        --argjson score "$score" \
        --argjson success "$success" \
        --argjson fixes "$fix_attempts" \
        --argjson steps "$step_count" \
        --argjson dur "$duration" \
        --arg ts "$(date -Iseconds)" \
        '{task_id: $id, score: $score, success: $success, fix_attempts: $fixes, steps: $steps, duration: $dur, at: $ts}')

    # Add to scores and recalculate aggregate
    local state
    state=$(cat "$SCORES_FILE")
    state=$(echo "$state" | jq --argjson entry "$entry" '
        .task_scores += [$entry] |
        .task_scores = (.task_scores | .[-100:]) |
        .aggregate.total_tasks = (.task_scores | length) |
        .aggregate.avg_score = ((.task_scores | map(.score) | add) / (.task_scores | length) | floor) |
        .aggregate.avg_fix_attempts = ((.task_scores | map(.fix_attempts) | add) / (.task_scores | length) * 10 | floor / 10) |
        .aggregate.avg_steps = ((.task_scores | map(.steps) | add) / (.task_scores | length) * 10 | floor / 10) |
        .aggregate.success_rate = (((.task_scores | map(select(.success == true)) | length) * 100) / (.task_scores | length) | floor)
    ')
    echo "$state" | jq . > "$SCORES_FILE"

    _evo_log INFO "Scored task $task_id: $score/100 (success=$success, fixes=$fix_attempts)"

    # Check if evolution should be triggered
    local total
    total=$(echo "$state" | jq '.aggregate.total_tasks')
    local last_evolution
    last_evolution=$(echo "$state" | jq '.evolution_count')

    # Trigger evolution every 10 tasks or if score drops below 50
    local avg_score
    avg_score=$(echo "$state" | jq '.aggregate.avg_score')
    if [[ $((total % 10)) -eq 0 && $total -gt 0 ]] || [[ $avg_score -lt 50 && $total -ge 5 ]]; then
        evolve_prompts
    fi

    echo "$score"
}

# ── Prompt Version Management ───────────────────────────────

get_current_version() {
    init_scores
    jq -r '.prompt_version // 1' "$SCORES_FILE"
}

# Save the current HEARTBEAT template as a versioned snapshot
snapshot_prompt() {
    local version
    version=$(get_current_version)
    local heartbeat_file="$AUTONOMY_DIR/HEARTBEAT.md"

    if [[ -f "$heartbeat_file" ]]; then
        cp "$heartbeat_file" "$PROMPTS_DIR/heartbeat_v${version}.md"
        _evo_log INFO "Saved prompt snapshot v$version"
        echo "Saved prompt version $version"
    fi
}

# List prompt versions
list_versions() {
    echo "Prompt Versions:"
    for f in "$PROMPTS_DIR"/heartbeat_v*.md; do
        [[ -f "$f" ]] || continue
        local v
        v=$(basename "$f" .md | sed 's/heartbeat_v//')
        local size
        size=$(wc -c < "$f" | tr -d ' ')
        local date_mod
        date_mod=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
        echo "  v$v — ${size} bytes — $date_mod"
    done
}

# ── Prompt Evolution ────────────────────────────────────────
# Analyzes score trends and generates improvements

evolve_prompts() {
    init_scores

    local state
    state=$(cat "$SCORES_FILE")
    local avg_score success_rate avg_fixes
    avg_score=$(echo "$state" | jq '.aggregate.avg_score')
    success_rate=$(echo "$state" | jq '.aggregate.success_rate')
    avg_fixes=$(echo "$state" | jq '.aggregate.avg_fix_attempts')

    _evo_log INFO "Starting prompt evolution (avg_score=$avg_score, success=$success_rate%, fixes=$avg_fixes)"

    # Snapshot current version before evolving
    snapshot_prompt

    # Determine what to improve based on patterns
    local improvements=()

    if [[ $success_rate -lt 70 ]]; then
        improvements+=("Task success rate is ${success_rate}%. Add more explicit step-by-step instructions and error handling guidance.")
    fi

    if [[ $(echo "$avg_fixes" | cut -d. -f1) -gt 1 ]]; then
        improvements+=("Average fix attempts is $avg_fixes. Add pre-execution verification checklist: verify files exist, check syntax, dry-run commands.")
    fi

    # Check for common failure patterns in memory
    if [[ -f "$AUTONOMY_DIR/lib/memory.sh" ]]; then
        local patterns
        patterns=$(bash "$AUTONOMY_DIR/lib/memory.sh" recall patterns 2>/dev/null | head -10)
        if [[ -n "$patterns" ]]; then
            improvements+=("Incorporate learned patterns: $patterns")
        fi

        local blockers
        blockers=$(bash "$AUTONOMY_DIR/lib/memory.sh" recall blockers 2>/dev/null | head -5)
        if [[ -n "$blockers" ]]; then
            improvements+=("Avoid known blockers: $blockers")
        fi
    fi

    if [[ ${#improvements[@]} -eq 0 ]]; then
        _evo_log INFO "No improvements needed (score=$avg_score, rate=$success_rate%)"
        return 0
    fi

    # Store improvements as a decision in memory
    local improvement_text
    improvement_text=$(printf '%s\n' "${improvements[@]}")
    if [[ -f "$AUTONOMY_DIR/lib/memory.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/memory.sh" store decisions \
            "Prompt evolution v$(get_current_version): $improvement_text" 2>/dev/null
    fi

    # Increment version
    state=$(echo "$state" | jq '.prompt_version += 1 | .evolution_count += 1')
    echo "$state" | jq . > "$SCORES_FILE"

    # Generate a meta-task to apply improvements
    if [[ -f "$AUTONOMY_DIR/lib/task-generator.sh" ]]; then
        local version
        version=$(echo "$state" | jq '.prompt_version')
        bash "$AUTONOMY_DIR/lib/task-generator.sh" create \
            "evolve-prompts-v${version}" \
            "Apply prompt evolution v${version}. Improvements needed: ${improvement_text}. Update HEARTBEAT.md template in heartbeat-builder.sh to incorporate these learnings." \
            "medium" \
            "self-improvement:prompt-evolution" 2>/dev/null
    fi

    _evo_log INFO "Prompt evolution complete: v$(get_current_version) with ${#improvements[@]} improvements"
    echo "Evolved to prompt v$(get_current_version) with ${#improvements[@]} improvements"
}

# ── Performance Summary ─────────────────────────────────────

performance_summary() {
    init_scores

    local state
    state=$(cat "$SCORES_FILE")
    echo "$state" | jq '{
        prompt_version,
        evolution_count,
        aggregate,
        recent_scores: (.task_scores | .[-5:] | map({task_id, score, success}))
    }'
}

# One-liner for HEARTBEAT.md injection
performance_oneliner() {
    init_scores

    local state
    state=$(cat "$SCORES_FILE")
    local avg success version
    avg=$(echo "$state" | jq '.aggregate.avg_score // 0')
    success=$(echo "$state" | jq '.aggregate.success_rate // 0')
    version=$(echo "$state" | jq '.prompt_version // 1')

    echo "Prompt v${version} | Avg score: ${avg}/100 | Success rate: ${success}%"
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    score)      shift; score_task "$@" ;;
    evolve)     evolve_prompts ;;
    snapshot)   snapshot_prompt ;;
    versions)   list_versions ;;
    summary)    performance_summary ;;
    oneliner)   performance_oneliner ;;
    *)
        echo "Self-Improving Prompt Evolution"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  score <task_id> <success> <fixes> <steps> <duration>  Record task score"
        echo "  evolve              Trigger prompt evolution"
        echo "  snapshot            Save current prompt version"
        echo "  versions            List saved prompt versions"
        echo "  summary             Performance summary JSON"
        echo "  oneliner            One-line summary for HEARTBEAT"
        ;;
esac
