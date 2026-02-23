#!/bin/bash
# Check: Git Status
# Checks git repository status for uncommitted changes

CONTEXT="${1:-default}"
CTX_PATH=$(jq -r '.path' "/root/.openclaw/workspace/skills/autonomy/contexts/${CONTEXT}.json")

if [[ -d "$CTX_PATH/.git" ]]; then
  cd "$CTX_PATH"
  CHANGES=$(git status --porcelain | wc -l)
  
  if [[ $CHANGES -gt 0 ]]; then
    echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"alert\", \"uncommitted\": $CHANGES, \"timestamp\": \"$(date -Iseconds)\"}"
  else
    echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"pass\", \"timestamp\": \"$(date -Iseconds)\"}"
  fi
else
  echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"skip\", \"reason\": \"no_git_repo\", \"timestamp\": \"$(date -Iseconds)\"}"
fi
