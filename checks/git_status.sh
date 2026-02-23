#!/bin/bash
# Check: Git Status
# Checks git repository status for uncommitted changes

CONTEXT="${1:-default}"

# Validate context name - prevent path traversal
if [[ ! "$CONTEXT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"error\", \"error\": \"invalid_context_name\", \"timestamp\": \"$(date -Iseconds)\"}"
    exit 1
fi

CONTEXT_FILE="/root/.openclaw/workspace/skills/autonomy/contexts/${CONTEXT}.json"

# Verify context file exists and is within allowed directory
if [[ ! -f "$CONTEXT_FILE" ]]; then
    echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"skip\", \"reason\": \"context_not_found\", \"timestamp\": \"$(date -Iseconds)\"}"
    exit 0
fi

CTX_PATH=$(jq -r '.path' "$CONTEXT_FILE")

# Validate path is within workspace
WORKSPACE="/root/.openclaw/workspace"
if [[ ! "$CTX_PATH" =~ ^$WORKSPACE ]]; then
    echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"error\", \"error\": \"path_outside_workspace\", \"timestamp\": \"$(date -Iseconds)\"}"
    exit 1
fi

if [[ -d "$CTX_PATH/.git" ]]; then
  cd "$CTX_PATH" || exit 1
  CHANGES=$(git status --porcelain | wc -l)
  
  if [[ $CHANGES -gt 0 ]]; then
    echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"alert\", \"uncommitted\": $CHANGES, \"timestamp\": \"$(date -Iseconds)\"}"
  else
    echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"pass\", \"timestamp\": \"$(date -Iseconds)\"}"
  fi
else
  echo "{\"check\": \"git_status\", \"context\": \"$CONTEXT\", \"status\": \"skip\", \"reason\": \"no_git_repo\", \"timestamp\": \"$(date -Iseconds)\"}"
fi
