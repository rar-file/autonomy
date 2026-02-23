#!/bin/bash
# Check: File Integrity
# Verifies critical files exist and are valid

CONTEXT="${1:-default}"

# Validate context name - prevent path traversal
if [[ ! "$CONTEXT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "{"
    echo "  \"check\": \"file_integrity\","
    echo "  \"context\": \"$CONTEXT\","
    echo "  \"status\": \"error\","
    echo "  \"error\": \"invalid_context_name\","
    echo "  \"timestamp\": \"$(date -Iseconds)\""
    echo "}"
    exit 1
fi

CONTEXT_FILE="/root/.openclaw/workspace/skills/autonomy/contexts/${CONTEXT}.json"

# Verify context file exists
if [[ ! -f "$CONTEXT_FILE" ]]; then
    echo "{"
    echo "  \"check\": \"file_integrity\","
    echo "  \"context\": \"$CONTEXT\","
    echo "  \"status\": \"skip\","
    echo "  \"reason\": \"context_not_found\","
    echo "  \"timestamp\": \"$(date -Iseconds)\""
    echo "}"
    exit 0
fi

# Check required files exist
STATUS="pass"
ISSUES=()

if [[ ! -f "/root/.openclaw/workspace/skills/autonomy/config.json" ]]; then
    STATUS="fail"
    ISSUES+=("missing_config")
fi

if [[ ! -f "/root/.openclaw/workspace/SOUL.md" ]]; then
    STATUS="warn"
    ISSUES+=("missing_soul_md")
fi

if [[ ! -f "/root/.openclaw/workspace/IDENTITY.md" ]]; then
    STATUS="warn"
    ISSUES+=("missing_identity_md")
fi

echo "{"
echo "  \"check\": \"file_integrity\","
echo "  \"context\": \"$CONTEXT\","
echo "  \"status\": \"$STATUS\","
if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo "  \"issues\": $(printf '%s\n' "${ISSUES[@]}" | jq -R . | jq -s .),"
fi
echo "  \"timestamp\": \"$(date -Iseconds)\""
echo "}"
