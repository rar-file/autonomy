#!/bin/bash
# pre-commit-check.sh
# Run this before every commit to ensure we don't commit restricted files

echo "Checking for files that should NOT be committed..."

# Files that should never be committed
NEVER_COMMIT=(
    ".autonomy/"
    ".autonomy_triggers/"
    ".autonomy_logs/"
    "logs/"
    "tasks/"
    "test_output/"
    "*.tmp"
    "*.log"
    "__pycache__/"
    "*.pyc"
    ".pytest_cache/"
    "venv/"
    ".DS_Store"
    "*.swp"
    "*~"
)

VIOLATIONS=0

for pattern in "${NEVER_COMMIT[@]}"; do
    # Check git staging area
    MATCHES=$(git diff --cached --name-only | grep -E "${pattern//\*/.*}" || true)
    if [ -n "$MATCHES" ]; then
        echo "❌ VIOLATION: Found files matching '$pattern':"
        echo "$MATCHES" | sed 's/^/   /'
        VIOLATIONS=$((VIOLATIONS + 1))
    fi
done

if [ $VIOLATIONS -gt 0 ]; then
    echo ""
    echo "⚠️  COMMIT BLOCKED: Remove these files from staging before committing."
    echo "   To unstage: git reset HEAD <file>"
    echo "   To add to .gitignore: echo '<pattern>' >> .gitignore"
    exit 1
fi

echo "✅ All clear - no restricted files found."
exit 0
