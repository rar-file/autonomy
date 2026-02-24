#!/bin/bash
# git-aware-optimized.sh - Optimized git-aware checks
# Main optimization: Cache git repo discovery

CONTEXT="${1:-git-aware}"
WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"

# SECURITY: Validate context name
if [[ ! "$CONTEXT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo '{"error":"invalid_context","timestamp":"'"$(date -Iseconds)"'"}' >&2
    exit 1
fi

# Colors (disable for JSON output)
NC=''

log() {
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"check\":\"$1\",\"status\":\"$2\",\"message\":\"$3\",\"context\":\"$CONTEXT\"}"
}

# OPTIMIZATION: Single find operation shared by all checks
# Cache repos in a variable to avoid 5 separate find operations
_declare_repos() {
    if [[ -z "${_GIT_REPOS_CACHED:-}" ]]; then
        _GIT_REPOS_CACHED=$(find "$WORKSPACE" -type d -name ".git" 2>/dev/null | sed 's/\.git$//' | sort -u)
        export _GIT_REPOS_CACHED
    fi
    printf '%s\n' "$_GIT_REPOS_CACHED"
}

# OPTIMIZATION: Single check_all function does all checks in one pass
# Avoids repeated cd/git operations to the same repos
check_all() {
    local alerts_dirty=()
    local alerts_stale=()
    local alerts_unpushed=()
    local alerts_stash=()
    
    local now=$(date +%s)
    local repo_count=0
    
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        ((repo_count++))
        
        # Quick check if it's a valid git repo
        [[ -d "$repo/.git" ]] || continue
        
        cd "$repo" 2>/dev/null || continue
        local repo_name="${repo#$WORKSPACE/}"
        
        # Get branch once (faster than git branch --show-current)
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "unknown")
        
        # Check 1: Dirty with age
        if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
            local last_change=$(git log -1 --format=%ct 2>/dev/null || echo "$now")
            local age=$((now - last_change))
            if [[ "$age" -gt 7200 ]]; then
                local age_hours=$((age / 3600))
                alerts_dirty+=("$repo_name: ${age_hours}h of uncommitted changes on $branch")
            fi
        fi
        
        # Check 2: Stale commits
        local unpushed=$(git log '@{u}'.. --oneline 2>/dev/null | wc -l)
        if [[ "$unpushed" -gt 0 ]]; then
            local oldest_time=$(git log '@{u}'.. --format=%ct --reverse 2>/dev/null | head -1)
            if [[ -n "$oldest_time" ]]; then
                local age=$((now - oldest_time))
                if [[ "$age" -gt 3600 ]]; then
                    local age_hours=$((age / 3600))
                    alerts_stale+=("$repo_name: $unpushed commits unpushed for ${age_hours}h on $branch")
                fi
            fi
        fi
        
        # Check 3: Unpushed branches
        for b in $(git branch --format='%(refname:short)' 2>/dev/null); do
            [[ "$b" == "main" || "$b" == "master" ]] && continue
            local branch_unpushed=$(git log origin/"$b".."$b" --oneline 2>/dev/null | wc -l)
            if [[ "$branch_unpushed" -gt 0 ]]; then
                local last_push=$(git log origin/"$b" -1 --format=%ct 2>/dev/null || echo "0")
                local age=$((now - last_push))
                if [[ "$age" -gt 86400 ]]; then
                    local age_days=$((age / 86400))
                    alerts_unpushed+=("$repo_name/$b: $branch_unpushed commits, last push ${age_days}d ago")
                fi
            fi
        done
        
        # Check 4: Forgotten stashes
        local stash_list=$(git stash list 2>/dev/null)
        if [[ -n "$stash_list" ]]; then
            local stash_n=$(echo "$stash_list" | wc -l)
            local oldest_stash=$(git stash list --format=%ct 2>/dev/null | tail -1)
            if [[ -n "$oldest_stash" ]]; then
                local age=$((now - oldest_stash))
                if [[ "$age" -gt 259200 ]]; then
                    local age_days=$((age / 86400))
                    alerts_stash+=("$repo_name: $stash_n forgotten stashes, oldest ${age_days}d")
                fi
            fi
        fi
        
    done <<< "$(_declare_repos)"
    
    # Output results
    local all_alerts="${alerts_dirty[*]};${alerts_stale[*]};${alerts_unpushed[*]};${alerts_stash[*]}"
    all_alerts=$(echo "$all_alerts" | sed 's/;\s*;/;/g' | sed 's/^;*//' | sed 's/;*$//')
    
    if [[ -n "$all_alerts" && "$all_alerts" != ";" ]]; then
        log "git_aware" "alert" "$all_alerts"
        return 1
    fi
    
    log "git_aware" "pass" "All repos clean (scanned $repo_count)"
    return 0
}

# Main
check_all
