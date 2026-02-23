#!/bin/bash
# Git-Aware Development Checks
# Intelligent git monitoring that actually prevents problems

CONTEXT="${1:-git-aware}"
CONTEXT_FILE="/root/.openclaw/workspace/skills/autonomy/contexts/${CONTEXT}.json"
WORKSPACE="/root/.openclaw/workspace"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"check\":\"$1\",\"status\":\"$2\",\"message\":\"$3\",\"context\":\"$CONTEXT\"}"
}

# Find all git repos in workspace
find_git_repos() {
    find "$WORKSPACE" -type d -name ".git" 2>/dev/null | while read gitdir; do
        dirname "$gitdir"
    done
}

# Check 1: Dirty Repository Warning
check_git_dirty_warning() {
    local alerts=()
    
    while read repo; do
        cd "$repo"
        
        # Check if dirty
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            # Get time since last commit or file modification
            local last_change=$(git log -1 --format=%ct 2>/dev/null || echo "0")
            local now=$(date +%s)
            local age=$((now - last_change))
            
            # If changes sitting for >2 hours
            if [[ $age -gt 7200 ]]; then
                local age_hours=$((age / 3600))
                local branch=$(git branch --show-current)
                alerts+=("${repo#$WORKSPACE/}: $age_hours hours of uncommitted changes on $branch")
            fi
        fi
    done <<(find_git_repos)
    
    if [[ ${#alerts[@]} -gt 0 ]]; then
        log "git_dirty_warning" "alert" "${alerts[*]}"
        return 1
    fi
    
    log "git_dirty_warning" "pass" "No stale uncommitted changes"
    return 0
}

# Check 2: Stale Commit Reminder (committed but sitting locally)
check_git_stale_commit() {
    local alerts=()
    
    while read repo; do
        cd "$repo"
        
        # Check for commits not pushed
        local unpushed=$(git log @{u}.. 2>/dev/null | wc -l)
        
        if [[ $unpushed -gt 0 ]]; then
            # Get age of oldest unpushed commit
            local oldest_commit_time=$(git log @{u}.. --format=%ct --reverse | head -1)
            local now=$(date +%s)
            local age=$((now - oldest_commit_time))
            
            # If sitting for >1 hour
            if [[ $age -gt 3600 ]]; then
                local age_hours=$((age / 3600))
                local branch=$(git branch --show-current)
                alerts+=("${repo#$WORKSPACE/}: $unpushed commits unpushed for ${age_hours}h on $branch")
            fi
        fi
    done <<(find_git_repos)
    
    if [[ ${#alerts[@]} -gt 0 ]]; then
        log "git_stale_commit" "alert" "${alerts[*]}"
        return 1
    fi
    
    log "git_stale_commit" "pass" "All commits pushed"
    return 0
}

# Check 3: Unpushed Branch Warning (long-term)
check_git_unpushed_check() {
    local alerts=()
    
    while read repo; do
        cd "$repo"
        
        # Check all branches, not just current
        local branches=$(git branch --format='%(refname:short)' 2>/dev/null)
        
        for branch in $branches; do
            # Skip main/master
            [[ "$branch" == "main" || "$branch" == "master" ]] && continue
            
            local unpushed=$(git log origin/$branch..$branch 2>/dev/null | wc -l)
            
            if [[ $unpushed -gt 0 ]]; then
                local last_push=$(git log origin/$branch -1 --format=%ct 2>/dev/null || echo "0")
                local now=$(date +%s)
                local age=$((now - last_push))
                
                # If branch hasn't been pushed in >24 hours
                if [[ $age -gt 86400 ]]; then
                    local age_days=$((age / 86400))
                    alerts+=("${repo#$WORKSPACE/}/$branch: $unpushed commits, last push ${age_days}d ago")
                fi
            fi
        done
    done <<(find_git_repos)
    
    if [[ ${#alerts[@]} -gt 0 ]]; then
        log "git_unpushed_check" "alert" "${alerts[*]}"
        return 1
    fi
    
    log "git_unpushed_check" "pass" "All branches synced"
    return 0
}

# Check 4: Branch Sync Status
check_git_branch_sync() {
    local alerts=()
    
    while read repo; do
        cd "$repo"
        
        # Check if local main is behind remote
        git fetch origin main 2>/dev/null || git fetch origin master 2>/dev/null
        
        local branch=$(git branch --show-current)
        local behind=$(git rev-list HEAD..origin/$branch --count 2>/dev/null || echo "0")
        
        if [[ $behind -gt 0 ]]; then
            alerts+=("${repo#$WORKSPACE/}: $branch is $behind commits behind origin")
        fi
    done <<(find_git_repos)
    
    if [[ ${#alerts[@]} -gt 0 ]]; then
        log "git_branch_sync" "warn" "${alerts[*]}"
        return 1
    fi
    
    log "git_branch_sync" "pass" "All branches up to date"
    return 0
}

# Check 5: Stash Reminder (forgotten stashes)
check_git_stash_reminder() {
    local alerts=()
    
    while read repo; do
        cd "$repo"
        
        local stash_count=$(git stash list | wc -l)
        
        if [[ $stash_count -gt 0 ]]; then
            # Get age of oldest stash
            local oldest_stash=$(git stash list --format=%ct | tail -1)
            local now=$(date +%s)
            local age=$((now - oldest_stash))
            
            # If stash is >3 days old
            if [[ $age -gt 259200 ]]; then
                local age_days=$((age / 86400))
                alerts+=("${repo#$WORKSPACE/}: $stash_count forgotten stashes, oldest ${age_days}d")
            fi
        fi
    done <<(find_git_repos)
    
    if [[ ${#alerts[@]} -gt 0 ]]; then
        log "git_stash_reminder" "warn" "${alerts[*]}"
        return 1
    fi
    
    log "git_stash_reminder" "pass" "No forgotten stashes"
    return 0
}

# Main execution
case "${CHECK_NAME:-all}" in
    dirty|all)
        check_git_dirty_warning
        ;;
    stale|all)
        check_git_stale_commit
        ;;
    unpushed|all)
        check_git_unpushed_check
        ;;
    sync|all)
        check_git_branch_sync
        ;;
    stash|all)
        check_git_stash_reminder
        ;;
esac
