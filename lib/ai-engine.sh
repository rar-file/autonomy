#!/bin/bash
# AI Engine — OpenClaw API Integration
# Connects to OpenAI-compatible APIs for task analysis, git commits,
# terminal execution, and evidence gathering.
#
# API key is read from config.json (ai.api_key) or env AUTONOMY_AI_KEY.
# Provider can be openai, anthropic, or any OpenAI-compatible endpoint.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
LOGS_DIR="$AUTONOMY_DIR/logs"
AI_LOG="$LOGS_DIR/ai-engine.jsonl"
TERMINAL_LOG="$STATE_DIR/terminal_history.jsonl"

mkdir -p "$STATE_DIR" "$LOGS_DIR"

# ── Configuration ────────────────────────────────────────────

_get_config() {
    jq -r "$1" "$CONFIG_FILE" 2>/dev/null
}

# Read from OpenClaw's centralized config (~/.openclaw/openclaw.json)
_get_openclaw_config() {
    local oc_home="${OPENCLAW_HOME:-$HOME/.openclaw}"
    local oc_config="${OPENCLAW_CONFIG_PATH:-$oc_home/openclaw.json}"
    [[ -f "$oc_config" ]] && jq -r "$1" "$oc_config" 2>/dev/null
}

get_api_key() {
    local key="${AUTONOMY_AI_KEY:-}"
    [[ -n "$key" ]] && { echo "$key"; return 0; }
    key=$(_get_config '.ai.api_key // ""')
    [[ -n "$key" && "$key" != "null" ]] && { echo "$key"; return 0; }
    # Fallback: OpenClaw centralized config
    key=$(_get_openclaw_config '.ai.api_key // .apiKey // ""')
    [[ -n "$key" && "$key" != "null" ]] && { echo "$key"; return 0; }
    return 1
}

get_api_url() {
    local url
    url=$(_get_config '.ai.api_url // ""')
    [[ -n "$url" && "$url" != "null" ]] && { echo "$url"; return; }
    # Fallback: OpenClaw centralized config
    url=$(_get_openclaw_config '.ai.api_url // .apiUrl // ""')
    [[ -n "$url" && "$url" != "null" ]] && { echo "$url"; return; }
    local provider
    provider=$(get_provider)
    case "$provider" in
        anthropic) echo "https://api.anthropic.com/v1/messages" ;;
        *)         echo "https://api.openai.com/v1/chat/completions" ;;
    esac
}

get_model() {
    local model
    model=$(_get_config '.ai.model // ""')
    [[ -n "$model" && "$model" != "null" ]] && { echo "$model"; return; }
    # Fallback: OpenClaw centralized config
    model=$(_get_openclaw_config '.agent.model // .ai.model // ""')
    [[ -n "$model" && "$model" != "null" ]] && { echo "$model"; return; }
    local provider
    provider=$(get_provider)
    case "$provider" in
        anthropic) echo "claude-sonnet-4-20250514" ;;
        *)         echo "gpt-4o-mini" ;;
    esac
}

get_provider() {
    local provider
    provider=$(_get_config '.ai.provider // ""')
    [[ -n "$provider" && "$provider" != "null" ]] && { echo "$provider"; return; }
    # Fallback: OpenClaw centralized config
    provider=$(_get_openclaw_config '.agent.provider // .ai.provider // "openai"')
    echo "${provider:-openai}"
}

# ── Core API Call ────────────────────────────────────────────

# ai_call <system_prompt> <user_prompt> [max_tokens]
# Returns: response text on stdout, logs usage
ai_call() {
    local system_prompt="$1"
    local user_prompt="$2"
    local max_tokens="${3:-1024}"

    local api_key api_url model provider
    api_key=$(get_api_key) || {
        echo "ERROR: No API key configured. Set ai.api_key in config.json or AUTONOMY_AI_KEY env var."
        return 1
    }
    api_url=$(get_api_url)
    model=$(get_model)
    provider=$(get_provider)

    local response=""
    local input_tokens=0 output_tokens=0

    if [[ "$provider" == "anthropic" ]]; then
        response=$(curl -s --max-time 60 "$api_url" \
            -H "x-api-key: $api_key" \
            -H "anthropic-version: 2023-06-01" \
            -H "content-type: application/json" \
            -d "$(jq -n \
                --arg model "$model" \
                --arg sys "$system_prompt" \
                --arg usr "$user_prompt" \
                --argjson mt "$max_tokens" \
                '{model:$model, max_tokens:$mt, system:$sys, messages:[{role:"user",content:$usr}]}'
            )" 2>/dev/null)

        local text
        text=$(echo "$response" | jq -r '.content[0].text // ""' 2>/dev/null)
        input_tokens=$(echo "$response" | jq -r '.usage.input_tokens // 0' 2>/dev/null)
        output_tokens=$(echo "$response" | jq -r '.usage.output_tokens // 0' 2>/dev/null)
        response="$text"
    else
        # OpenAI-compatible (works with OpenAI, local LLMs, OpenRouter, etc.)
        local raw
        raw=$(curl -s --max-time 60 "$api_url" \
            -H "Authorization: Bearer $api_key" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg model "$model" \
                --arg sys "$system_prompt" \
                --arg usr "$user_prompt" \
                --argjson mt "$max_tokens" \
                '{model:$model, max_tokens:$mt, messages:[{role:"system",content:$sys},{role:"user",content:$usr}]}'
            )" 2>/dev/null)

        response=$(echo "$raw" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
        input_tokens=$(echo "$raw" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)
        output_tokens=$(echo "$raw" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
    fi

    # Record token usage
    local total_tokens=$((input_tokens + output_tokens))
    if [[ "$total_tokens" -gt 0 && -f "$AUTONOMY_DIR/lib/token-budget.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/token-budget.sh" record "$total_tokens" >/dev/null 2>&1
    fi

    # Log the call
    jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg model "$model" \
        --argjson in_tok "$input_tokens" \
        --argjson out_tok "$output_tokens" \
        --arg provider "$provider" \
        '{timestamp:$ts, provider:$provider, model:$model, input_tokens:$in_tok, output_tokens:$out_tok, total:($in_tok+$out_tok)}' \
        >> "$AI_LOG" 2>/dev/null

    echo "$response"
}

# ── Task Analysis ────────────────────────────────────────────

# ai_analyze_task <task_json_path>
# Returns: analysis + suggested subtasks as markdown
ai_analyze_task() {
    local task_file="$1"
    [[ ! -f "$task_file" ]] && { echo "ERROR: Task file not found"; return 1; }

    local task_json
    task_json=$(cat "$task_file")
    local task_name desc
    task_name=$(echo "$task_json" | jq -r '.name // "unknown"')
    desc=$(echo "$task_json" | jq -r '.description // "No description"')

    local workspace_context=""
    if [[ -f "$AUTONOMY_DIR/lib/workspace-scanner.sh" ]]; then
        workspace_context=$(bash "$AUTONOMY_DIR/lib/workspace-scanner.sh" oneliner 2>/dev/null)
    fi

    local system="You are an AI task analyst for an autonomous coding agent. Analyze the given task and produce:
1. A brief analysis of what needs to be done (2-3 sentences)
2. 2-5 concrete subtasks in order
3. Any risks or blockers

Be specific and actionable. Use the workspace context to tailor your plan."

    local prompt="Task: $task_name
Description: $desc
Workspace: $workspace_context
Current task JSON: $task_json

Analyze this task and provide a structured plan."

    ai_call "$system" "$prompt" 800
}

# ── Git Commit ───────────────────────────────────────────────

# ai_commit [message_override]
# Analyzes staged changes, generates commit message via AI, commits
ai_commit() {
    local override_msg="$1"

    # Check we're in a git repo
    if ! git -C "$AUTONOMY_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "ERROR: Not a git repository"
        return 1
    fi

    local diff
    diff=$(git -C "$AUTONOMY_DIR" diff --cached --stat 2>/dev/null)
    if [[ -z "$diff" ]]; then
        # Nothing staged — auto-stage tracked changes
        git -C "$AUTONOMY_DIR" add -u 2>/dev/null
        diff=$(git -C "$AUTONOMY_DIR" diff --cached --stat 2>/dev/null)
        [[ -z "$diff" ]] && { echo "Nothing to commit"; return 0; }
    fi

    local diff_content
    diff_content=$(git -C "$AUTONOMY_DIR" diff --cached --no-color 2>/dev/null | head -200)

    local commit_msg="$override_msg"
    if [[ -z "$commit_msg" ]]; then
        local api_key
        api_key=$(get_api_key 2>/dev/null)
        if [[ -n "$api_key" ]]; then
            commit_msg=$(ai_call \
                "Generate a concise, conventional git commit message for the following diff. Use format: type(scope): description. Only output the commit message, nothing else." \
                "Files changed:
$diff

Diff (first 200 lines):
$diff_content" \
                200)
            # Clean up — remove quotes/backticks AI might add
            commit_msg=$(echo "$commit_msg" | sed 's/^["`'\'']*//;s/["`'\'']*$//' | head -1)
        fi
    fi

    # Fallback if AI didn't produce a message
    [[ -z "$commit_msg" || "$commit_msg" == "ERROR:"* ]] && \
        commit_msg="chore(autonomy): automated changes — $(date +%Y-%m-%d)"

    git -C "$AUTONOMY_DIR" commit -m "$commit_msg" 2>&1
    local exit_code=$?

    # Log the commit
    jq -n --arg ts "$(date -Iseconds)" --arg msg "$commit_msg" --argjson ec "$exit_code" \
        '{timestamp:$ts, action:"git_commit", message:$msg, exit_code:$ec}' >> "$AI_LOG" 2>/dev/null

    if [[ $exit_code -eq 0 ]]; then
        echo "Committed: $commit_msg"
    fi
    return $exit_code
}

# ai_push — push to remote
ai_push() {
    local branch
    branch=$(git -C "$AUTONOMY_DIR" branch --show-current 2>/dev/null)
    [[ -z "$branch" ]] && { echo "ERROR: Not on a branch"; return 1; }
    git -C "$AUTONOMY_DIR" push origin "$branch" 2>&1
}

# ── Terminal Access ──────────────────────────────────────────

# ai_terminal <command> [timeout_seconds]
# Executes a command in a sandboxed subprocess, captures output
ai_terminal() {
    local cmd="$1"
    local timeout_sec="${2:-30}"

    # Safety: block obviously dangerous commands
    local blocked_patterns="rm -rf /|mkfs|dd if=|:(){ :|shutdown|reboot|halt|poweroff|format "
    if echo "$cmd" | grep -qiE "$blocked_patterns"; then
        echo "BLOCKED: Command matches dangerous pattern"
        jq -n --arg ts "$(date -Iseconds)" --arg cmd "$cmd" \
            '{timestamp:$ts, action:"terminal_blocked", command:$cmd}' >> "$AI_LOG" 2>/dev/null
        return 1
    fi

    # Execute with timeout
    local output exit_code
    output=$(cd "$AUTONOMY_DIR" && timeout "$timeout_sec" bash -c "$cmd" 2>&1)
    exit_code=$?

    # Truncate output to 4KB for sanity
    if [[ ${#output} -gt 4096 ]]; then
        output="${output:0:4000}
... [truncated — ${#output} bytes total]"
    fi

    # Log
    jq -n --arg ts "$(date -Iseconds)" --arg cmd "$cmd" \
        --argjson ec "$exit_code" --arg out "$output" \
        '{timestamp:$ts, command:$cmd, exit_code:$ec, output:$out}' >> "$TERMINAL_LOG" 2>/dev/null

    jq -n --arg ts "$(date -Iseconds)" --arg cmd "$cmd" --argjson ec "$exit_code" \
        '{timestamp:$ts, action:"terminal_exec", command:$cmd, exit_code:$ec}' >> "$AI_LOG" 2>/dev/null

    echo "$output"
    return $exit_code
}

# ai_terminal_history [count]
ai_terminal_history() {
    local n="${1:-10}"
    if [[ -f "$TERMINAL_LOG" ]]; then
        tail -"$n" "$TERMINAL_LOG" | jq -s '.'
    else
        echo "[]"
    fi
}

# ── Evidence Gathering ───────────────────────────────────────

# ai_gather_evidence <task_name> <verification_commands...>
# Runs verification commands, captures output, attaches to task
ai_gather_evidence() {
    local task_name="$1"
    shift
    local task_file="$AUTONOMY_DIR/tasks/${task_name}.json"
    [[ ! -f "$task_file" ]] && { echo "ERROR: Task not found: $task_name"; return 1; }

    local evidence=()
    for cmd in "$@"; do
        local output
        output=$(ai_terminal "$cmd" 15)
        local exit_code=$?
        evidence+=("$(jq -n \
            --arg cmd "$cmd" \
            --argjson ec "$exit_code" \
            --arg out "$output" \
            --arg ts "$(date -Iseconds)" \
            '{timestamp:$ts, command:$cmd, exit_code:$ec, output:$out, passed:($ec==0)}')")
    done

    # Build JSON array and merge into task
    local evidence_json="["
    local first=true
    for e in "${evidence[@]}"; do
        $first || evidence_json+=","
        evidence_json+="$e"
        first=false
    done
    evidence_json+="]"

    # Merge evidence into the task file
    local tmp="${task_file}.tmp.$$"
    jq --argjson ev "$evidence_json" \
        '.evidence = ((.evidence // []) + $ev) | .last_evidence_at = "'"$(date -Iseconds)"'"' \
        "$task_file" > "$tmp" && mv "$tmp" "$task_file"

    # Count passes
    local passed total
    total=$(echo "$evidence_json" | jq 'length')
    passed=$(echo "$evidence_json" | jq '[.[] | select(.passed == true)] | length')

    echo "Evidence gathered: $passed/$total checks passed"
    jq -n --arg ts "$(date -Iseconds)" --arg task "$task_name" \
        --argjson p "$passed" --argjson t "$total" \
        '{timestamp:$ts, action:"evidence_gathered", task:$task, passed:$p, total:$t}' >> "$AI_LOG" 2>/dev/null
}

# ── AI-Driven Task Completion ────────────────────────────────

# ai_process_task <task_file>
# Full cycle: analyze → plan subtasks → execute → verify → complete
ai_process_task() {
    local task_file="$1"
    [[ ! -f "$task_file" ]] && { echo "ERROR: Task file not found"; return 1; }

    local task_name
    task_name=$(jq -r '.name // "unknown"' "$task_file")

    # Update status to processing
    local tmp="${task_file}.tmp.$$"
    jq --arg ts "$(date -Iseconds)" \
        '.status = "ai_processing" | .processing_started = $ts' \
        "$task_file" > "$tmp" && mv "$tmp" "$task_file"

    # Write activity state for web UI
    jq -n --arg ts "$(date -Iseconds)" --arg task "$task_name" \
        '{status:"processing", task:$task, started_at:$ts, progress:10, message:"Analyzing task..."}' \
        > "$STATE_DIR/ai_activity.json"

    # Step 1: Analyze
    local analysis
    analysis=$(ai_analyze_task "$task_file")
    if [[ -z "$analysis" || "$analysis" == "ERROR:"* ]]; then
        echo "AI analysis failed: $analysis"
        jq '.status = "pending"' "$task_file" > "$tmp" && mv "$tmp" "$task_file"
        return 1
    fi

    # Update progress
    jq -n --arg ts "$(date -Iseconds)" --arg task "$task_name" \
        '{status:"processing", task:$task, started_at:$ts, progress:40, message:"Planning subtasks..."}' \
        > "$STATE_DIR/ai_activity.json"

    # Store analysis in task
    jq --arg analysis "$analysis" '.ai_analysis = $analysis' "$task_file" > "$tmp" && mv "$tmp" "$task_file"

    # Log
    if [[ -f "$AUTONOMY_DIR/lib/journal.sh" ]]; then
        bash "$AUTONOMY_DIR/lib/journal.sh" append "$task_name" \
            "AI analyzed task. Generated plan." "in-progress" "Execute plan" >/dev/null 2>&1
    fi

    # Hand off to closed-loop execution engine if available
    if [[ -f "$AUTONOMY_DIR/lib/execution-engine.sh" ]]; then
        jq -n --arg ts "$(date -Iseconds)" --arg task "$task_name" \
            '{status:"processing", task:$task, started_at:$ts, progress:45, message:"Executing plan via closed-loop engine..."}' \
            > "$STATE_DIR/ai_activity.json"

        bash "$AUTONOMY_DIR/lib/execution-engine.sh" execute "$task_name" 2>/dev/null
        local engine_exit=$?

        if [[ $engine_exit -eq 0 ]]; then
            jq -n --arg ts "$(date -Iseconds)" --arg task "$task_name" \
                '{status:"idle", task:$task, started_at:$ts, progress:100, message:"Task completed via execution engine"}' \
                > "$STATE_DIR/ai_activity.json"
            echo "Task $task_name completed via closed-loop execution engine."
            return 0
        else
            jq -n --arg ts "$(date -Iseconds)" --arg task "$task_name" \
                '{status:"idle", task:$task, started_at:$ts, progress:0, message:"Execution engine failed, task needs review"}' \
                > "$STATE_DIR/ai_activity.json"
            echo "Execution engine failed for $task_name. Manual review needed."
            return 1
        fi
    fi

    echo "Task $task_name analyzed. Plan stored in task file."
    echo "$analysis"
}

# ── Status & Info ────────────────────────────────────────────

ai_status() {
    local api_key
    api_key=$(get_api_key 2>/dev/null)
    local configured="false"
    [[ -n "$api_key" ]] && configured="true"

    local provider model api_url
    provider=$(get_provider)
    model=$(get_model)
    api_url=$(get_api_url)

    local total_calls total_tokens
    if [[ -f "$AI_LOG" ]]; then
        total_calls=$(wc -l < "$AI_LOG" | tr -d ' ')
        total_tokens=$(jq -s '[.[].total // 0] | add // 0' "$AI_LOG" 2>/dev/null)
    else
        total_calls=0
        total_tokens=0
    fi

    jq -n \
        --argjson configured "$configured" \
        --arg provider "$provider" \
        --arg model "$model" \
        --arg api_url "$api_url" \
        --argjson total_calls "$total_calls" \
        --argjson total_tokens "$total_tokens" \
        '{configured:$configured, provider:$provider, model:$model, api_url:$api_url, total_calls:$total_calls, total_tokens:$total_tokens}'
}

# ── CLI ──────────────────────────────────────────────────────

case "${1:-status}" in
    call)       shift; ai_call "$@" ;;
    analyze)    shift; ai_analyze_task "$1" ;;
    commit)     shift; ai_commit "$1" ;;
    push)       ai_push ;;
    terminal)   shift; ai_terminal "$@" ;;
    term-hist)  shift; ai_terminal_history "$@" ;;
    evidence)   shift; ai_gather_evidence "$@" ;;
    process)    shift; ai_process_task "$1" ;;
    status)     ai_status ;;
    *)
        echo "Usage: ai-engine.sh {status|call|analyze|commit|push|terminal|term-hist|evidence|process}"
        echo ""
        echo "  status              Show AI engine configuration"
        echo "  call <sys> <usr>    Raw API call"
        echo "  analyze <task.json> Analyze a task and suggest plan"
        echo "  commit [msg]        AI-generated git commit"
        echo "  push                Push to remote"
        echo "  terminal <cmd>      Execute terminal command (sandboxed)"
        echo "  term-hist [n]       Show terminal history"
        echo "  evidence <task> <cmd...>  Run verification commands"
        echo "  process <task.json> Full AI processing cycle"
        ;;
esac
