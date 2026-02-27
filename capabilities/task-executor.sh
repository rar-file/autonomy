#!/bin/bash
# Enhanced Task Executor — Better error handling, retries, and async execution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_DIR="$AUTONOMY_DIR/tasks"
EXECUTION_LOG="$AUTONOMY_DIR/logs/execution.jsonl"

mkdir -p "$TASKS_DIR"

# ── Task Execution with Retry Logic ─────────────────────────

execute_with_retry() {
    local cmd="$1"
    local max_retries="${2:-3}"
    local delay="${3:-2}"
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        echo "{\"timestamp\": \"$(date -Iseconds)\", \"attempt\": $attempt, \"command\": \"$cmd\", \"status\": \"running\"}" >> "$EXECUTION_LOG"
        
        if eval "$cmd" 2>&1; then
            echo "{\"timestamp\": \"$(date -Iseconds)\", \"attempt\": $attempt, \"command\": \"$cmd\", \"status\": \"success\"}" >> "$EXECUTION_LOG"
            return 0
        fi
        
        local exit_code=$?
        echo "{\"timestamp\": \"$(date -Iseconds)\", \"attempt\": $attempt, \"command\": \"$cmd\", \"status\": \"failed\", \"exit_code\": $exit_code}" >> "$EXECUTION_LOG"
        
        if [[ $attempt -lt $max_retries ]]; then
            echo "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    echo "Command failed after $max_retries attempts"
    return 1
}

# ── Async Task Execution ───────────────────────────────────

execute_async() {
    local cmd="$1"
    local task_name="${2:-async-task-$(date +%s)}"
    local output_file="$AUTONOMY_DIR/state/${task_name}.output"
    local pid_file="$AUTONOMY_DIR/state/${task_name}.pid"
    
    (
        echo "{\"timestamp\": \"$(date -Iseconds)\", \"task\": \"$task_name\", \"status\": \"started\"}" > "$output_file"
        if eval "$cmd" >> "$output_file" 2>&1; then
            echo "{\"timestamp\": \"$(date -Iseconds)\", \"task\": \"$task_name\", \"status\": \"completed\"}" >> "$output_file"
        else
            echo "{\"timestamp\": \"$(date -Iseconds)\", \"task\": \"$task_name\", \"status\": \"failed\", \"exit_code\": $?}" >> "$output_file"
        fi
    ) &
    
    local pid=$!
    echo $pid > "$pid_file"
    
    echo "✓ Async task '$task_name' started (PID: $pid)"
    echo "Output: $output_file"
}

execute_async_status() {
    local task_name="$1"
    local pid_file="$AUTONOMY_DIR/state/${task_name}.pid"
    local output_file="$AUTONOMY_DIR/state/${task_name}.output"
    
    [[ -f "$pid_file" ]] || { echo "Task '$task_name' not found"; return 1; }
    
    local pid
    pid=$(cat "$pid_file")
    
    if kill -0 "$pid" 2>/dev/null; then
        echo "Task '$task_name': RUNNING (PID: $pid)"
    else
        echo "Task '$task_name': COMPLETED"
        [[ -f "$output_file" ]] && tail -5 "$output_file"
    fi
}

execute_async_wait() {
    local task_name="$1"
    local pid_file="$AUTONOMY_DIR/state/${task_name}.pid"
    
    [[ -f "$pid_file" ]] || { echo "Task '$task_name' not found"; return 1; }
    
    local pid
    pid=$(cat "$pid_file")
    wait "$pid" 2>/dev/null
    
    echo "Task '$task_name' finished"
    execute_async_status "$task_name"
}

# ── Parallel Execution ─────────────────────────────────────

execute_parallel() {
    local pids=()
    local names=()
    
    # Read commands from arguments or stdin
    if [[ $# -gt 0 ]]; then
        local i=1
        for cmd in "$@"; do
            local name="parallel-$i"
            execute_async "$cmd" "$name"
            names+=("$name")
            ((i++))
        done
    else
        local i=1
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            local name="parallel-$i"
            execute_async "$cmd" "$name"
            names+=("$name")
            ((i++))
        done
    fi
    
    echo ""
    echo "Waiting for all parallel tasks to complete..."
    for name in "${names[@]}"; do
        local pid_file="$AUTONOMY_DIR/state/${name}.pid"
        [[ -f "$pid_file" ]] && wait "$(cat "$pid_file")" 2>/dev/null
    done
    
    echo "All parallel tasks completed"
}

# ── Timeout Wrapper ────────────────────────────────────────

execute_with_timeout() {
    local timeout="$1"
    shift
    local cmd="$*"
    
    timeout "$timeout" bash -c "$cmd" 2>&1
    local exit_code=$?
    
    if [[ $exit_code -eq 124 ]]; then
        echo "Command timed out after ${timeout}s"
        return 124
    fi
    
    return $exit_code
}

# ── Conditional Execution ───────────────────────────────────

execute_if() {
    local condition="$1"
    local then_cmd="$2"
    local else_cmd="${3:-}"
    
    if eval "$condition" >/dev/null 2>&1; then
        eval "$then_cmd"
    elif [[ -n "$else_cmd" ]]; then
        eval "$else_cmd"
    fi
}

execute_unless() {
    local condition="$1"
    local cmd="$2"
    
    if ! eval "$condition" >/dev/null 2>&1; then
        eval "$cmd"
    fi
}

# ── Pipeline with Error Handling ───────────────────────────

execute_pipeline() {
    local -a cmds=("$@")
    local output=""
    local i=0
    
    for cmd in "${cmds[@]}"; do
        ((i++))
        if [[ $i -eq 1 ]]; then
            output=$(eval "$cmd" 2>&1)
        else
            output=$(echo "$output" | eval "$cmd" 2>&1)
        fi
        
        if [[ $? -ne 0 ]]; then
            echo "Pipeline failed at step $i: $cmd"
            return 1
        fi
    done
    
    echo "$output"
}

# ── Task Progress Tracking ──────────────────────────────────

task_progress_start() {
    local task_name="$1"
    local total_steps="${2:-1}"
    
    local progress_file="$AUTONOMY_DIR/state/${task_name}.progress"
    echo "{\"task\": \"$task_name\", \"total\": $total_steps, \"current\": 0, \"started\": \"$(date -Iseconds)\"}" > "$progress_file"
}

task_progress_update() {
    local task_name="$1"
    local step="$2"
    local message="${3:-}"
    
    local progress_file="$AUTONOMY_DIR/state/${task_name}.progress"
    [[ -f "$progress_file" ]] || return 1
    
    local current total
    current=$(jq -r '.current' "$progress_file")
    total=$(jq -r '.total' "$progress_file")
    ((current++))
    
    local pct=$((current * 100 / total))
    
    jq --arg current "$current" --arg pct "$pct" --arg msg "$message" --arg updated "$(date -Iseconds)" \
        '.current = ($current | tonumber) | .percent = $pct | .message = $msg | .updated = $updated' \
        "$progress_file" > "${progress_file}.tmp" && mv "${progress_file}.tmp" "$progress_file"
    
    echo "[$task_name] Step $current/$total ($pct%)${message:+: $message}"
}

task_progress_complete() {
    local task_name="$1"
    local progress_file="$AUTONOMY_DIR/state/${task_name}.progress"
    
    [[ -f "$progress_file" ]] || return 1
    
    jq --arg completed "$(date -Iseconds)" '.current = .total | .percent = 100 | .status = "completed" | .completed = $completed' \
        "$progress_file" > "${progress_file}.tmp" && mv "${progress_file}.tmp" "$progress_file"
    
    echo "[$task_name] Complete ✓"
}

# ── Command Router ──────────────────────────────────────────

case "${1:-}" in
    retry) shift; execute_with_retry "$@" ;;
    async) shift; execute_async "$@" ;;
    async_status) execute_async_status "$2" ;;
    async_wait) execute_async_wait "$2" ;;
    parallel) shift; execute_parallel "$@" ;;
    timeout) shift; execute_with_timeout "$@" ;;
    if) execute_if "$2" "$3" "$4" ;;
    unless) execute_unless "$2" "$3" ;;
    pipeline) shift; execute_pipeline "$@" ;;
    progress_start) task_progress_start "$2" "$3" ;;
    progress_update) task_progress_update "$2" "$3" "$4" ;;
    progress_complete) task_progress_complete "$2" ;;
    *)
        echo "Enhanced Task Executor"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  retry <cmd> [max_retries] [delay]      - Execute with retry logic"
        echo "  async <cmd> [name]                    - Execute asynchronously"
        echo "  async_status <name>                   - Check async task status"
        echo "  async_wait <name>                     - Wait for async task"
        echo "  parallel <cmd1> <cmd2> ...            - Execute commands in parallel"
        echo "  timeout <seconds> <cmd>               - Execute with timeout"
        echo "  if <condition> <then_cmd> [else_cmd]  - Conditional execution"
        echo "  unless <condition> <cmd>              - Execute unless condition true"
        echo "  pipeline <cmd1> <cmd2> ...            - Execute pipeline with error handling"
        echo "  progress_start <task> <steps>         - Start progress tracking"
        echo "  progress_update <task> <step> [msg]   - Update progress"
        echo "  progress_complete <task>               - Mark progress complete"
        ;;
esac
