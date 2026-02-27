#!/bin/bash
# Continuous Task Generation Pipeline
# Auto-discovers work when task queue is empty: TODOs, FIXMEs, lint issues,
# missing docs, failing tests, stale dependencies, code smells.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
TASKS_DIR="$AUTONOMY_DIR/tasks"
STATE_DIR="$AUTONOMY_DIR/state"
GENERATOR_STATE="$STATE_DIR/task_generator.json"
WORKSPACE="$(jq -r '.workstation.workspace // ""' "$CONFIG_FILE" 2>/dev/null)"

# Fallback workspace detection
if [[ -z "$WORKSPACE" || "$WORKSPACE" == "null" ]]; then
    WORKSPACE="$(dirname "$(dirname "$AUTONOMY_DIR")")"
fi

mkdir -p "$TASKS_DIR" "$STATE_DIR"

GEN_LOG="$AUTONOMY_DIR/logs/task-generator.log"

_gen_log() {
    echo "$(date -Iseconds) [$1] $2" >> "$GEN_LOG"
}

# ── State Management ────────────────────────────────────────

load_generator_state() {
    if [[ -f "$GENERATOR_STATE" ]]; then
        cat "$GENERATOR_STATE"
    else
        echo '{"last_scan":"never","tasks_generated":0,"scan_history":[]}'
    fi
}

save_generator_state() {
    echo "$1" | jq . > "$GENERATOR_STATE"
}

# ── Check if queue is empty ─────────────────────────────────

queue_is_empty() {
    local pending=0
    for f in "$TASKS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local status
        status=$(jq -r '.status // ""' "$f" 2>/dev/null)
        case "$status" in
            pending|needs_ai_attention|ai_processing|in-progress)
                pending=$((pending + 1))
                ;;
        esac
    done
    [[ $pending -eq 0 ]]
}

# ── Task creation helper ────────────────────────────────────

create_generated_task() {
    local name="$1"
    local description="$2"
    local priority="${3:-medium}"
    local source="${4:-auto-generated}"
    local task_id

    # Sanitize name for filename
    task_id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-60)

    # Skip if task already exists
    [[ -f "$TASKS_DIR/${task_id}.json" ]] && return 1

    # Check for duplicates by description similarity (first 40 chars)
    local desc_prefix="${description:0:40}"
    for f in "$TASKS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local existing_desc
        existing_desc=$(jq -r '.description // ""' "$f" 2>/dev/null)
        if [[ "${existing_desc:0:40}" == "$desc_prefix" ]]; then
            return 1
        fi
    done

    jq -n \
        --arg id "$task_id" \
        --arg name "$name" \
        --arg desc "$description" \
        --arg pri "$priority" \
        --arg src "$source" \
        --arg ts "$(date -Iseconds)" \
        '{
            id: $id,
            name: $name,
            description: $desc,
            status: "pending",
            priority: $pri,
            source: $src,
            created_at: $ts,
            attempts: 0,
            progress: 0,
            subtasks: [],
            tags: ["auto-generated"]
        }' > "$TASKS_DIR/${task_id}.json"

    _gen_log INFO "Created task: $task_id ($source)"
    echo "$task_id"
    return 0
}

# ── Scanners ────────────────────────────────────────────────

# Scan for TODO/FIXME/HACK/XXX comments in source code
scan_code_annotations() {
    [[ -d "$WORKSPACE" ]] || return

    local results
    results=$(find "$WORKSPACE" -maxdepth 4 -type f \
        \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" \
           -o -name "*.go" -o -name "*.rs" -o -name "*.rb" -o -name "*.java" \
           -o -name "*.c" -o -name "*.cpp" -o -name "*.php" \) \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -path "*/vendor/*" \
        ! -path "*/__pycache__/*" \
        -exec grep -Hn 'TODO\|FIXME\|HACK\|XXX\|BUG' {} \; 2>/dev/null | head -20)

    [[ -z "$results" ]] && return

    local count
    count=$(echo "$results" | wc -l | tr -d ' ')

    if [[ $count -gt 0 ]]; then
        # Group by type
        local todos fixmes hacks
        todos=$(echo "$results" | grep -c 'TODO' || echo 0)
        fixmes=$(echo "$results" | grep -c 'FIXME' || echo 0)
        hacks=$(echo "$results" | grep -c 'HACK\|XXX\|BUG' || echo 0)

        local top_files
        top_files=$(echo "$results" | cut -d: -f1 | sort | uniq -c | sort -rn | head -3 | awk '{print $2}' | xargs -I{} basename {} | tr '\n' ', ')

        create_generated_task \
            "resolve-code-annotations" \
            "Found $count code annotations ($todos TODOs, $fixmes FIXMEs, $hacks HACKs/XXXs). Top files: $top_files. Review and resolve the most critical ones." \
            "low" \
            "scan:code-annotations"
    fi
}

# Scan for missing or outdated documentation
scan_documentation() {
    [[ -d "$WORKSPACE" ]] || return

    local has_readme=false
    for f in README.md readme.md README README.rst; do
        [[ -f "$WORKSPACE/$f" ]] && has_readme=true && break
    done

    if [[ "$has_readme" == "false" ]]; then
        create_generated_task \
            "create-readme" \
            "Project is missing a README file. Create a comprehensive README.md with project description, setup instructions, usage examples, and contributing guidelines." \
            "medium" \
            "scan:documentation"
        return
    fi

    # Check if README is stale (no update in 30 days)
    local readme_age
    readme_age=$(find "$WORKSPACE" -maxdepth 1 -name "README.md" -mtime +30 2>/dev/null | head -1)
    if [[ -n "$readme_age" ]]; then
        create_generated_task \
            "update-documentation" \
            "README.md hasn't been updated in over 30 days. Review and update it to reflect current state of the project." \
            "low" \
            "scan:documentation"
    fi
}

# Scan for test coverage gaps
scan_test_coverage() {
    [[ -d "$WORKSPACE" ]] || return

    local src_count=0
    local test_count=0

    src_count=$(find "$WORKSPACE" -maxdepth 4 -type f \
        \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) \
        ! -path "*/test*" ! -path "*/node_modules/*" ! -path "*/.git/*" \
        2>/dev/null | wc -l | tr -d ' ')

    test_count=$(find "$WORKSPACE" -maxdepth 4 -type f \
        \( -name "test_*" -o -name "*_test.*" -o -name "*.test.*" -o -name "*.spec.*" \) \
        ! -path "*/node_modules/*" ! -path "*/.git/*" \
        2>/dev/null | wc -l | tr -d ' ')

    if [[ $src_count -gt 5 && $test_count -eq 0 ]]; then
        create_generated_task \
            "add-test-suite" \
            "Project has $src_count source files but no test files detected. Create initial test suite covering core functionality." \
            "high" \
            "scan:test-coverage"
    elif [[ $src_count -gt 0 && $test_count -gt 0 ]]; then
        local ratio
        ratio=$((test_count * 100 / src_count))
        if [[ $ratio -lt 30 ]]; then
            create_generated_task \
                "improve-test-coverage" \
                "Test coverage ratio is low: $test_count test files for $src_count source files ($ratio% ratio). Add tests for uncovered modules." \
                "medium" \
                "scan:test-coverage"
        fi
    fi
}

# Scan for linting/formatting issues
scan_code_quality() {
    [[ -d "$WORKSPACE" ]] || return

    # Check for linting config
    local has_lint=false
    for f in .eslintrc .eslintrc.json .eslintrc.js .pylintrc .flake8 .rustfmt.toml .golangci.yml; do
        [[ -f "$WORKSPACE/$f" ]] && has_lint=true && break
    done

    if [[ "$has_lint" == "false" ]]; then
        # Detect language and suggest linter setup
        local lang=""
        [[ -f "$WORKSPACE/package.json" ]] && lang="JavaScript/TypeScript"
        [[ -f "$WORKSPACE/requirements.txt" || -f "$WORKSPACE/pyproject.toml" ]] && lang="Python"
        [[ -f "$WORKSPACE/Cargo.toml" ]] && lang="Rust"
        [[ -f "$WORKSPACE/go.mod" ]] && lang="Go"

        if [[ -n "$lang" ]]; then
            create_generated_task \
                "setup-linting" \
                "No linting configuration found for $lang project. Set up appropriate linter and formatter configuration." \
                "low" \
                "scan:code-quality"
        fi
    fi
}

# Scan for security issues (basic)
scan_security() {
    [[ -d "$WORKSPACE" ]] || return

    local issues=()

    # Check for hardcoded secrets patterns
    local secret_hits
    secret_hits=$(find "$WORKSPACE" -maxdepth 4 -type f \
        \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" -o -name "*.env" \) \
        ! -path "*/node_modules/*" ! -path "*/.git/*" \
        -exec grep -l 'password\s*=\s*["\x27][^"\x27]\+["\x27]\|api_key\s*=\s*["\x27][^"\x27]\+["\x27]\|secret\s*=\s*["\x27][^"\x27]\+["\x27]' {} \; 2>/dev/null | head -5)

    if [[ -n "$secret_hits" ]]; then
        local count
        count=$(echo "$secret_hits" | wc -l | tr -d ' ')
        create_generated_task \
            "audit-hardcoded-secrets" \
            "Found $count files potentially containing hardcoded secrets/credentials. Audit and move to environment variables or secure config." \
            "high" \
            "scan:security"
    fi

    # Check for .env in git
    if [[ -d "$WORKSPACE/.git" ]] && git -C "$WORKSPACE" ls-files --cached .env 2>/dev/null | grep -q '.env'; then
        create_generated_task \
            "remove-env-from-git" \
            ".env file is tracked by git. Remove from tracking and add to .gitignore to prevent credential leaks." \
            "high" \
            "scan:security"
    fi
}

# Scan for dependency issues
scan_dependencies() {
    [[ -d "$WORKSPACE" ]] || return

    # Node.js: check for outdated lockfile
    if [[ -f "$WORKSPACE/package.json" && ! -f "$WORKSPACE/package-lock.json" && ! -f "$WORKSPACE/yarn.lock" && ! -f "$WORKSPACE/pnpm-lock.yaml" ]]; then
        create_generated_task \
            "add-lockfile" \
            "Project has package.json but no lockfile. Run npm install or equivalent to generate a lockfile for reproducible builds." \
            "medium" \
            "scan:dependencies"
    fi

    # Python: check for pinned versions
    if [[ -f "$WORKSPACE/requirements.txt" ]]; then
        local unpinned
        unpinned=$(grep -c '^[a-zA-Z]' "$WORKSPACE/requirements.txt" 2>/dev/null || echo 0)
        local pinned
        pinned=$(grep -c '==' "$WORKSPACE/requirements.txt" 2>/dev/null || echo 0)

        if [[ $unpinned -gt 0 && $pinned -eq 0 ]]; then
            create_generated_task \
                "pin-dependencies" \
                "Python dependencies are not version-pinned. Pin versions in requirements.txt for reproducible builds." \
                "medium" \
                "scan:dependencies"
        fi
    fi
}

# ── Main scan orchestrator ──────────────────────────────────

run_scan() {
    local force="${1:-false}"

    # Don't generate if queue has work (unless forced)
    if [[ "$force" != "true" ]] && ! queue_is_empty; then
        echo "Queue has active tasks, skipping generation"
        return 0
    fi

    _gen_log INFO "Starting task generation scan"
    local generated_before generated_after
    local state
    state=$(load_generator_state)

    generated_before=$(echo "$state" | jq '.tasks_generated')

    # Run all scanners
    scan_code_annotations
    scan_documentation
    scan_test_coverage
    scan_code_quality
    scan_security
    scan_dependencies

    # Count what we generated
    local new_count=0
    for f in "$TASKS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        local src
        src=$(jq -r '.source // ""' "$f" 2>/dev/null)
        [[ "$src" == scan:* ]] && new_count=$((new_count + 1))
    done

    # Update state
    state=$(echo "$state" | jq \
        --arg ts "$(date -Iseconds)" \
        --argjson count "$new_count" \
        '.last_scan = $ts | .tasks_generated = $count | .scan_history += [{"at": $ts, "found": $count}] | .scan_history = (.scan_history | .[-20:])')
    save_generator_state "$state"

    _gen_log INFO "Scan complete: $new_count auto-generated tasks exist"
    echo "Scan complete: $new_count auto-generated tasks in queue"
}

# ── Status ──────────────────────────────────────────────────

generator_status() {
    local state
    state=$(load_generator_state)
    echo "$state" | jq '.'
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    scan)     run_scan "${2:-false}" ;;
    force)    run_scan "true" ;;
    status)   generator_status ;;
    create)   shift; create_generated_task "$@" ;;
    *)
        echo "Continuous Task Generation Pipeline"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  scan           - Scan for work (only if queue empty)"
        echo "  force          - Force scan even if queue has tasks"
        echo "  status         - Show generator state"
        echo "  create <name> <desc> [priority] [source]  - Create a task"
        ;;
esac
