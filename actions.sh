#!/bin/bash
# Smart Action System
# Takes actions based on check results, not just alerts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR"
WORKSPACE="$(dirname "$(dirname "$AUTONOMY_DIR")")"
ACTION_LOG="$AUTONOMY_DIR/logs/actions.jsonl"
LAST_ACTION_FILE="$AUTONOMY_DIR/state/last_action.json"

# Colors
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Security: Validate path resolves within expected directories
validate_path() {
    local path="$1"
    local base_dir="${2:-$WORKSPACE}"
    
    if [[ -z "$path" ]]; then
        echo "Error: Path cannot be empty" >&2
        return 1
    fi
    
    # Get absolute path
    local abs_path
    abs_path="$(cd "$base_dir" 2>/dev/null && realpath -m "$path" 2>/dev/null)" || \
    abs_path="$(realpath -m "$path" 2>/dev/null)" || \
    abs_path="$path"
    
    # Check for path traversal attempts
    if [[ "$abs_path" == *".."* ]]; then
        echo "Error: Path contains invalid characters (..): $path" >&2
        return 1
    fi
    
    # Ensure path is within base directory
    local base_real
    base_real="$(realpath -m "$base_dir" 2>/dev/null)" || base_real="$base_dir"
    
    if [[ ! "$abs_path" =~ ^"$base_real"(/|$) ]]; then
        echo "Error: Path is outside allowed directory: $path" >&2
        return 1
    fi
    
    return 0
}

# Security: Safe cd that validates path before changing directory
safe_cd() {
    local target_dir="$1"
    
    # Validate the path
    validate_path "$target_dir" "/" || return 1
    
    # Check if it's a directory
    if [[ ! -d "$target_dir" ]]; then
        echo "Error: Not a directory: $target_dir" >&2
        return 1
    fi
    
    # Safe to cd
    cd -- "$target_dir" || return 1
    
    return 0
}

# Parse arguments for --dry-run flag
DRY_RUN=false
REPO=""
ACTION=""
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            *)
                if [[ -z "$ACTION" ]]; then
                    ACTION="$1"
                elif [[ -z "$REPO" ]]; then
                    REPO="$1"
                fi
                shift
                ;;
        esac
    done
}

# Record action for undo system
record_action() {
    local action="$1"
    local target="$2"
    local details="$3"
    
    cat > "$LAST_ACTION_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "action": "$action",
  "target": "$target",
  "details": "$details",
  "undoable": true
}
EOF
}

# Mark last action as undoable=false (for actions that can't be undone)
mark_not_undoable() {
    if [[ -f "$LAST_ACTION_FILE" ]]; then
        jq '.undoable = false' "$LAST_ACTION_FILE" > "${LAST_ACTION_FILE}.tmp"
        mv "${LAST_ACTION_FILE}.tmp" "$LAST_ACTION_FILE"
    fi
}

# Print dry-run message
print_dry_run() {
    echo -e "${YELLOW}[DRY RUN]${NC} Would execute: $1"
}

# Action: Suggest commit message based on diff
action_suggest_commit_message() {
    local repo="$1"
    safe_cd "$repo" || return 1
    
    # Get changed files
    local files
    files="$(git diff --name-only 2>/dev/null | head -5)"
    local file_count
    file_count="$(git diff --name-only 2>/dev/null | wc -l)"
    
    # Analyze diff for patterns
    local added deleted
    added="$(git diff --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertions' | grep -oE '[0-9]+' || echo "0")"
    deleted="$(git diff --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ deletions' | grep -oE '[0-9]+' || echo "0")"
    
    # Generate suggestions based on patterns
    local suggestions=()
    
    if echo "$files" | grep -q "test"; then
        suggestions+=("Add tests")
    fi
    
    if echo "$files" | grep -qE "fix|bug|patch"; then
        suggestions+=("Fix: resolve issue")
    fi
    
    if [[ "$file_count" -gt 5 ]]; then
        suggestions+=("Update $file_count files")
    elif [[ "$file_count" -eq 1 ]]; then
        local filename
        filename="$(basename -- "$files")"
        suggestions+=("Update $filename")
    fi
    
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        suggestions+=("Update files")
    fi
    
    echo "${suggestions[0]}"
}

# Action: Auto-stash changes when context switching
action_auto_stash() {
    local repo="$1"
    local reason="${2:-Context switch}"
    
    safe_cd "$repo" || return 1
    
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        local stash_name
        stash_name="autonomy-$(date +%Y%m%d-%H%M%S)"
        
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "git stash push -m \"$stash_name\""
            echo "  Stash name would be: $stash_name"
            return 0
        fi
        
        git stash push -m "$stash_name" >/dev/null 2>&1
        
        log_action "auto_stash" "$repo" "Stashed changes as $stash_name"
        record_action "stash" "$repo" "$stash_name"
        echo "Stashed changes in $(basename -- "$repo"): $stash_name"
        return 0
    fi
    
    return 1
}

# Action: Quick commit with generated message
action_quick_commit() {
    local repo="$1"
    safe_cd "$repo" || return 1
    
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        local message
        message="$(action_suggest_commit_message "$repo")"
        
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "git add -A && git commit -m \"$message\""
            echo "  Files to be committed:"
            git status --short
            return 0
        fi
        
        git add -A
        git commit -m "$message" >/dev/null 2>&1
        
        log_action "quick_commit" "$repo" "Auto-committed: $message"
        record_action "commit" "$repo" "$message"
        echo "Committed in $(basename -- "$repo"): $message"
        return 0
    fi
    
    return 1
}

# Action: Push current branch
action_push_branch() {
    local repo="$1"
    safe_cd "$repo" || return 1
    
    local branch unpushed
    branch="$(git branch --show-current)"
    unpushed="$(git log '@{u}'.. 2>/dev/null | wc -l)"
    
    if [[ "$unpushed" -gt 0 ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_dry_run "git push origin \"$branch\""
            echo "  Branch: $branch"
            echo "  Unpushed commits: $unpushed"
            return 0
        fi
        
        git push origin "$branch" >/dev/null 2>&1
        
        log_action "push_branch" "$repo" "Pushed $branch with $unpushed commits"
        mark_not_undoable  # Push cannot be undone
        echo "Pushed $branch: $unpushed commits"
        return 0
    fi
    
    return 1
}

# Action: Sync with remote
action_sync_remote() {
    local repo="$1"
    safe_cd "$repo" || return 1
    
    git fetch origin >/dev/null 2>&1
    local branch behind
    branch="$(git branch --show-current)"
    behind="$(git rev-list HEAD..origin/"$branch" --count 2>/dev/null || echo "0")"
    
    if [[ "$behind" -gt 0 ]]; then
        # Only fast-forward, don't auto-merge
        if git merge-base --is-ancestor HEAD origin/"$branch" 2>/dev/null; then
            if [[ "$DRY_RUN" == true ]]; then
                print_dry_run "git merge --ff-only origin/\"$branch\""
                echo "  Fast-forward $behind commits from origin/$branch"
                return 0
            fi
            
            git merge --ff-only origin/"$branch" >/dev/null 2>&1
            log_action "sync_remote" "$repo" "Fast-forwarded $behind commits"
            record_action "sync" "$repo" "fast-forwarded $behind commits"
            echo "Synced $(basename -- "$repo"): fast-forwarded $behind commits"
            return 0
        else
            log_action "sync_remote" "$repo" "Behind by $behind commits - manual merge needed"
            echo "$(basename -- "$repo") behind by $behind commits - manual merge needed"
            return 1
        fi
    fi
    
    return 0
}

# Log action for learning
log_action() {
    local action="$1"
    local target="$2"
    local message="$3"
    
    mkdir -p "$(dirname -- "$ACTION_LOG")"
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"$action\",\"target\":\"$target\",\"message\":\"$message\"}" >> "$ACTION_LOG"
}

# Main entry point - parse args first
parse_args "$@"

# If action and repo were parsed, use them; otherwise fall back to positional
if [[ -n "$ACTION" && -n "$REPO" ]]; then
    case "$ACTION" in
        suggest-message)
            action_suggest_commit_message "$REPO"
            ;;
        auto-stash|stash)
            action_auto_stash "$REPO" "$3"
            ;;
        quick-commit|commit)
            action_quick_commit "$REPO"
            ;;
        push)
            action_push_branch "$REPO"
            ;;
        sync)
            action_sync_remote "$REPO"
            ;;
        *)
            echo "Usage: $0 {suggest-message|auto-stash|quick-commit|push|sync} [--dry-run] [args...]"
            exit 1
            ;;
    esac
else
    # Original positional argument handling for backward compatibility
    case "$1" in
        suggest-message)
            action_suggest_commit_message "$2"
            ;;
        auto-stash|stash)
            action_auto_stash "$2" "$3"
            ;;
        quick-commit|commit)
            action_quick_commit "$2"
            ;;
        push)
            action_push_branch "$2"
            ;;
        sync)
            action_sync_remote "$2"
            ;;
        *)
            echo "Usage: $0 {suggest-message|auto-stash|quick-commit|push|sync} [--dry-run] [args...]"
            exit 1
            ;;
    esac
fi
