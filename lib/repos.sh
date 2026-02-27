#!/bin/bash
# Cross-Repository Orchestration
# Manages multiple repositories, rotates context between them,
# and coordinates tasks across repo boundaries.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
STATE_DIR="$AUTONOMY_DIR/state"
REPOS_FILE="$STATE_DIR/repos.json"
REPOS_LOG="$AUTONOMY_DIR/logs/repos.log"

mkdir -p "$STATE_DIR" "$AUTONOMY_DIR/logs"

_repo_log() {
    echo "$(date -Iseconds) [$1] $2" >> "$REPOS_LOG"
}

# ── Repository Registry ────────────────────────────────────

init_repos() {
    if [[ ! -f "$REPOS_FILE" ]]; then
        jq -n '{
            repos: [],
            active_repo: null,
            rotation_index: 0,
            rotation_strategy: "round-robin",
            last_rotation: null,
            stats: {}
        }' > "$REPOS_FILE"
    fi
}

# Register a repository
# add_repo <path> [name] [priority]
add_repo() {
    local path="$1"
    local name="${2:-$(basename "$path")}"
    local priority="${3:-normal}"

    [[ -z "$path" ]] && { echo "Usage: repos.sh add <path> [name] [priority]"; return 1; }
    [[ -d "$path" ]] || { echo "Error: $path is not a directory"; return 1; }

    init_repos

    # Check for duplicate
    local existing
    existing=$(jq -r --arg p "$path" '[.repos[] | select(.path == $p)] | length' "$REPOS_FILE")
    if [[ "$existing" -gt 0 ]]; then
        echo "Repository already registered: $path"
        return 1
    fi

    # Detect repo info
    local branch="none"
    local lang="unknown"
    if [[ -d "$path/.git" ]]; then
        branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    fi

    # Basic language detection
    [[ -f "$path/package.json" ]] && lang="javascript"
    [[ -f "$path/requirements.txt" || -f "$path/pyproject.toml" ]] && lang="python"
    [[ -f "$path/Cargo.toml" ]] && lang="rust"
    [[ -f "$path/go.mod" ]] && lang="go"

    local tmp="${REPOS_FILE}.tmp.$$"
    jq --arg path "$path" --arg name "$name" --arg pri "$priority" \
       --arg branch "$branch" --arg lang "$lang" --arg ts "$(date -Iseconds)" \
        '.repos += [{
            path: $path,
            name: $name,
            priority: $pri,
            branch: $branch,
            language: $lang,
            added: $ts,
            enabled: true,
            tasks_completed: 0,
            last_active: null
        }]' "$REPOS_FILE" > "$tmp" && mv "$tmp" "$REPOS_FILE"

    _repo_log INFO "Added repository: $name ($path)"
    echo "Added repository: $name ($path)"
}

# Remove a repository
remove_repo() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: repos.sh remove <name>"; return 1; }

    init_repos
    local tmp="${REPOS_FILE}.tmp.$$"
    jq --arg n "$name" '.repos = [.repos[] | select(.name != $n)]' "$REPOS_FILE" > "$tmp" && mv "$tmp" "$REPOS_FILE"
    echo "Removed repository: $name"
}

# List repositories
list_repos() {
    init_repos
    echo "Registered Repositories:"
    jq -r '.repos[] | "  \(if .enabled then "✓" else "✗" end) \(.name) [\(.priority)] — \(.path) (\(.language), branch: \(.branch))"' "$REPOS_FILE"
    echo ""
    local active
    active=$(jq -r '.active_repo // "none"' "$REPOS_FILE")
    echo "Active: $active"
}

# ── Rotation ────────────────────────────────────────────────

# Get the next repository to work on
rotate() {
    init_repos

    local strategy repo_count
    strategy=$(jq -r '.rotation_strategy' "$REPOS_FILE")
    repo_count=$(jq '[.repos[] | select(.enabled == true)] | length' "$REPOS_FILE")

    if [[ "$repo_count" -eq 0 ]]; then
        echo ""
        return 1
    fi

    local next_idx next_repo
    case "$strategy" in
        round-robin)
            local current_idx
            current_idx=$(jq '.rotation_index' "$REPOS_FILE")
            next_idx=$(( (current_idx + 1) % repo_count ))
            ;;
        priority)
            # Pick highest priority that hasn't been active recently
            next_idx=0  # Simplified: just take first enabled by priority
            ;;
        *)
            next_idx=0
            ;;
    esac

    next_repo=$(jq -r --argjson idx "$next_idx" \
        '[.repos[] | select(.enabled == true)][$idx].name // ""' "$REPOS_FILE")

    if [[ -n "$next_repo" ]]; then
        local tmp="${REPOS_FILE}.tmp.$$"
        jq --arg repo "$next_repo" --argjson idx "$next_idx" --arg ts "$(date -Iseconds)" \
            '.active_repo = $repo | .rotation_index = $idx | .last_rotation = $ts |
             (.repos[] | select(.name == $repo)).last_active = $ts' \
            "$REPOS_FILE" > "$tmp" && mv "$tmp" "$REPOS_FILE"
        _repo_log INFO "Rotated to repository: $next_repo"
    fi

    echo "$next_repo"
}

# Get the active repo's path
get_active_path() {
    init_repos
    local active_name
    active_name=$(jq -r '.active_repo // ""' "$REPOS_FILE")
    [[ -z "$active_name" ]] && { echo ""; return 1; }

    jq -r --arg n "$active_name" '.repos[] | select(.name == $n) | .path' "$REPOS_FILE"
}

# ── Workspace Switching ────────────────────────────────────

# Switch working directory context to a specific repo
switch_to() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: repos.sh switch <name>"; return 1; }

    init_repos
    local repo_path
    repo_path=$(jq -r --arg n "$name" '.repos[] | select(.name == $n) | .path // ""' "$REPOS_FILE")

    if [[ -z "$repo_path" || ! -d "$repo_path" ]]; then
        echo "Repository not found or path invalid: $name"
        return 1
    fi

    # Update active repo
    local tmp="${REPOS_FILE}.tmp.$$"
    jq --arg repo "$name" --arg ts "$(date -Iseconds)" \
        '.active_repo = $repo | .last_rotation = $ts |
         (.repos[] | select(.name == $repo)).last_active = $ts' \
        "$REPOS_FILE" > "$tmp" && mv "$tmp" "$REPOS_FILE"

    # Update config.json workspace pointer
    tmp="${CONFIG_FILE}.tmp.$$"
    jq --arg ws "$repo_path" '.workstation.workspace = $ws' "$CONFIG_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$CONFIG_FILE"

    _repo_log INFO "Switched to repository: $name ($repo_path)"
    echo "Switched to: $name ($repo_path)"
}

# ── Cross-Repo Task Creation ───────────────────────────────

# Create a task that spans multiple repos
create_cross_repo_task() {
    local name="$1"
    local desc="$2"
    local repos_csv="$3"  # comma-separated repo names

    [[ -z "$name" || -z "$desc" || -z "$repos_csv" ]] && {
        echo "Usage: repos.sh create_task <name> <description> <repo1,repo2,...>"
        return 1
    }

    local tasks_dir="$AUTONOMY_DIR/tasks"
    local task_id
    task_id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-60)

    jq -n \
        --arg id "$task_id" \
        --arg name "$name" \
        --arg desc "$desc" \
        --arg repos "$repos_csv" \
        --arg ts "$(date -Iseconds)" \
        '{
            id: $id,
            name: $name,
            description: $desc,
            status: "pending",
            priority: "high",
            source: "cross-repo",
            repos: ($repos | split(",")),
            created_at: $ts,
            attempts: 0,
            progress: 0,
            subtasks: [],
            tags: ["cross-repo"]
        }' > "$tasks_dir/${task_id}.json"

    _repo_log INFO "Created cross-repo task: $name across $repos_csv"
    echo "Created cross-repo task: $task_id"
}

# ── Status ──────────────────────────────────────────────────

repo_status() {
    init_repos
    jq '{
        total_repos: (.repos | length),
        enabled: ([.repos[] | select(.enabled == true)] | length),
        active_repo,
        rotation_strategy,
        last_rotation,
        repos: [.repos[] | {name, priority, enabled, language, tasks_completed, last_active}]
    }' "$REPOS_FILE"
}

# One-liner for HEARTBEAT injection
repo_oneliner() {
    init_repos
    local count active
    count=$(jq '[.repos[] | select(.enabled == true)] | length' "$REPOS_FILE")
    active=$(jq -r '.active_repo // "none"' "$REPOS_FILE")

    if [[ "$count" -gt 0 ]]; then
        echo "Cross-repo: $count repos registered, active: $active"
    else
        echo "Single-repo mode (no cross-repo orchestration configured)"
    fi
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-}" in
    add)         shift; add_repo "$@" ;;
    remove)      shift; remove_repo "$1" ;;
    list)        list_repos ;;
    rotate)      rotate ;;
    switch)      shift; switch_to "$1" ;;
    active_path) get_active_path ;;
    create_task) shift; create_cross_repo_task "$@" ;;
    status)      repo_status ;;
    oneliner)    repo_oneliner ;;
    *)
        echo "Cross-Repository Orchestration"
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  add <path> [name] [priority]       Register a repository"
        echo "  remove <name>                       Unregister a repository"
        echo "  list                                List all repositories"
        echo "  rotate                              Rotate to next repository"
        echo "  switch <name>                       Switch active repository"
        echo "  active_path                         Get active repo path"
        echo "  create_task <name> <desc> <repos>   Create cross-repo task"
        echo "  status                              Full status JSON"
        echo "  oneliner                            Summary for HEARTBEAT"
        ;;
esac
