#!/bin/bash
# git-aware-fast.sh - Optimized git-aware checks
# Caches git repo discovery, batches operations

CONTEXT="${1:-git-aware}"
WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
CONTEXT_FILE="/root/.openclaw/workspace/skills/autonomy/contexts/${CONTEXT}.json"

# SECURITY: Validate context name
if [[ ! "$CONTEXT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo '{"error":"invalid_context","timestamp":"'"$(date -Iseconds)"'"}' >&2
    exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"check\":\"$1\",\"status\":\"$2\",\"message\":\"$3\",\"context\":\"$CONTEXT\"}"
}

# OPTIMIZATION 1: Cache git repos (was: called 5 times)
# Single find operation at module load
_GIT_REPOS_CACHE=""
_get_git_repos() {
    if [[ -z "$_GIT_REPOS_CACHE" ]]; then
        _GIT_REPOS_CACHE=$(find "$WORKSPACE" -type d -name ".git" 2>/dev/null | while read -r gitdir; do dirname -- "$gitdir"; done)
    fi
    echo "$_GIT_REPOS_CACHE"
}

# OPTIMIZATION 2: Batch git status operations
# Instead of multiple git calls, get all info at once
_get_repo_status() {
    local repo="$1"
    cd "$repo" 2>/dev/null || return 1
    
    # Single git call gets: porcelain status, branch, commit time
    git status --porcelain --branch --porcelain 2>/dev/null
}

# OPTIMIZATION 3: Combined check - single pass through repos
check_all_git_issues() {
    local alerts=()
    local repos=$(_get_git_repos)
    local dirty_count=0
    local stale_count=0
    local unpushed_count=0
    local stash_count=0
    
    local now=$(date +%s)
    
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        cd "$repo" 2>/dev/null || continue
        
        local repo_name="${repo#$WORKSPACE/}"
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "unknown")
        
        # Check 1: Dirty with age (single git status call)
        local status_output=$(git status --porcelain 2>/dev/null)
        if [[ -n "$status_output" ]]; then
            local last_change=$(git log -1 --format=%ct 2>/dev/null || echo "0")
            local age=$((now - last_change))
            if [[ "$age" -gt 7200 ]]; then
                local age_hours=$((age / 3600))
                alerts+=("dirty:$repo_name:$age_hours hours on $branch")
                ((dirty_count++))
            fi
        fi
        
        # Check 2: Unpushed commits (use cached branch)
        local unpushed=$(git log '@{u}'.. --oneline 2>/dev/null | wc -l)
        if [[ "$unpushed" -gt 0 ]]; then
            local oldest_time=$(git log '@{u}'.. --format=%ct --reverse | head -1)
            local age=$((now - oldest_time))
            if [[ "$age" -gt 3600 ]]; then
                local age_hours=$((age / 3600))
                alerts+=("stale:$repo_name:$unpushed commits unpushed for ${age_hours}h on $branch")
                ((stale_count++))
            fi
        fi
        
        # Check 3: Forgotten stashes
        local stash_list=$(git stash list 2>/dev/null)
        if [[ -n "$stash_list" ]]; then
            local stash_n=$(echo "$stash_list" | wc -l)
            local oldest_stash=$(echo "$stash_list" --format=%ct | tail -1)
            local age=$((now - oldest_stash))
            if [[ "$age" -gt 259200 ]]; then
                local age_days=$((age / 86400))
                alerts+=("stash:$repo_name:$stash_n stashes, oldest ${age_days}d")
                ((stash_count++))
            fi
        fi
        
    done <<< "$repos"
    
    # Output results
    if [[ ${#alerts[@]} -gt 0 ]]; then
        local msg=$(printf '%s;' "${alerts[@]}")
        log "git_combined_check" "alert" "${msg%;}"
        return 1
    fi
    
    log "git_combined_check" "pass" "All git checks passed (dirty: $dirty_count, stale: $stale_count, unpushed: $unpushed_count, stashes: $stash_count)"
    return 0
}

# Main execution
case "${CHECK_NAME:-all}" in
    all|combined)
        check_all_git_issues
        ;;
    *)
        log "unknown_check" "error" "Unknown check: $CHECK_NAME"
        exit 1
        ;;
esac
