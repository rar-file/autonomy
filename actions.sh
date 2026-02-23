#!/bin/bash
# Smart Action System
# Takes actions based on check results, not just alerts

WORKSPACE="/root/.openclaw/workspace"
AUTONOMY_DIR="$WORKSPACE/skills/autonomy"
ACTION_LOG="$AUTONOMY_DIR/logs/actions.jsonl"

# Action: Suggest commit message based on diff
action_suggest_commit_message() {
    local repo="$1"
    cd "$repo" || return 1
    
    # Get changed files
    local files
    files=$(git diff --name-only 2>/dev/null | head -5)
    local file_count
    file_count=$(git diff --name-only 2>/dev/null | wc -l)
    
    # Analyze diff for patterns
    local added deleted
    added=$(git diff --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertions' | grep -oE '[0-9]+' || echo "0")
    deleted=$(git diff --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ deletions' | grep -oE '[0-9]+' || echo "0")
    
    # Generate suggestions based on patterns
    local suggestions=()
    
    if echo "$files" | grep -q "test"; then
        suggestions+=("Add tests")
    fi
    
    if echo "$files" | grep -qE "fix|bug|patch"; then
        suggestions+=("Fix: resolve issue")
    fi
    
    if [[ $file_count -gt 5 ]]; then
        suggestions+=("Update $file_count files")
    elif [[ $file_count -eq 1 ]]; then
        local filename
        filename=$(basename "$files")
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
    
    cd "$repo" || return 1
    
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        local stash_name
        stash_name="autonomy-$(date +%Y%m%d-%H%M%S)"
        git stash push -m "$stash_name" >/dev/null 2>&1
        
        log_action "auto_stash" "$repo" "Stashed changes as $stash_name"
        echo "Stashed changes in $(basename "$repo"): $stash_name"
        return 0
    fi
    
    return 1
}

# Action: Quick commit with generated message
action_quick_commit() {
    local repo="$1"
    cd "$repo" || return 1
    
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        local message
        message=$(action_suggest_commit_message "$repo")
        
        git add -A
        git commit -m "$message" >/dev/null 2>&1
        
        log_action "quick_commit" "$repo" "Auto-committed: $message"
        echo "Committed in $(basename "$repo"): $message"
        return 0
    fi
    
    return 1
}

# Action: Push current branch
action_push_branch() {
    local repo="$1"
    cd "$repo" || return 1
    
    local branch unpushed
    branch=$(git branch --show-current)
    unpushed=$(git log @{u}.. 2>/dev/null | wc -l)
    
    if [[ $unpushed -gt 0 ]]; then
        git push origin "$branch" >/dev/null 2>&1
        
        log_action "push_branch" "$repo" "Pushed $branch with $unpushed commits"
        echo "Pushed $branch: $unpushed commits"
        return 0
    fi
    
    return 1
}

# Action: Sync with remote
action_sync_remote() {
    local repo="$1"
    cd "$repo" || return 1
    
    git fetch origin >/dev/null 2>&1
    local branch behind
    branch=$(git branch --show-current)
    behind=$(git rev-list HEAD..origin/$branch --count 2>/dev/null || echo "0")
    
    if [[ $behind -gt 0 ]]; then
        # Only fast-forward, don't auto-merge
        if git merge-base --is-ancestor HEAD origin/$branch 2>/dev/null; then
            git merge --ff-only origin/$branch >/dev/null 2>&1
            log_action "sync_remote" "$repo" "Fast-forwarded $behind commits"
            echo "Synced $(basename "$repo"): fast-forwarded $behind commits"
            return 0
        else
            log_action "sync_remote" "$repo" "Behind by $behind commits - manual merge needed"
            echo "$(basename "$repo") behind by $behind commits - manual merge needed"
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
    
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"action\":\"$action\",\"target\":\"$target\",\"message\":\"$message\"}" >> "$ACTION_LOG"
}

# Main entry point
case "$1" in
    suggest-message)
        action_suggest_commit_message "$2"
        ;;
    auto-stash)
        action_auto_stash "$2" "$3"
        ;;
    quick-commit)
        action_quick_commit "$2"
        ;;
    push)
        action_push_branch "$2"
        ;;
    sync)
        action_sync_remote "$2"
        ;;
    *)
        echo "Usage: $0 {suggest-message|auto-stash|quick-commit|push|sync} [args...]"
        exit 1
        ;;
esac
