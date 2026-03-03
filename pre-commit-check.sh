#!/bin/bash
# Pre-commit hook to prevent committing excluded files
# Install: cp pre-commit-check.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

echo "Running pre-commit checks..."

# List of patterns that should never be committed
FORBIDDEN_PATTERNS=(
    ".autonomy/"
    ".autonomy_triggers/"
    ".autonomy_logs/"
    "logs/"
    "tasks/"
    "test_output/"
    "*.log"
    "*.tmp"
    "*.pid"
    "__pycache__/"
    "*.pyc"
    "FILES_NEVER_COMMIT.md"
    "COMMIT_CHECKLIST.md"
    "PRE_COMMIT.md"
    "*.local.md"
    "fix_*.py"
    "test_*.py"
    "notes/"
    "RESEARCH_*.md"
    ".vscode/"
    ".idea/"
    "venv/"
    "env/"
    "ENV/"
)

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only)

VIOLATIONS=()

for file in $STAGED_FILES; do
    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
        # Remove trailing slash for directory check
        clean_pattern="${pattern%/}"
        
        if [[ "$file" == $pattern ]] || [[ "$file" == *"/$pattern" ]] || [[ "$file" == "$pattern"* ]]; then
            VIOLATIONS+=("$file (matches: $pattern)")
        fi
    done
done

if [ ${#VIOLATIONS[@]} -ne 0 ]; then
    echo ""
    echo "❌ COMMIT BLOCKED: Forbidden files detected:"
    echo ""
    for v in "${VIOLATIONS[@]}"; do
        echo "   - $v"
    done
    echo ""
    echo "These files should not be committed to GitHub."
    echo "Add them to .gitignore or remove from staging."
    echo ""
    echo "To unstage: git reset HEAD <file>"
    echo "To add to .gitignore: echo '<pattern>' >> .gitignore"
    echo ""
    exit 1
fi

echo "✅ Pre-commit checks passed"
exit 0
