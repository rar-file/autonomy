#!/bin/bash
# Health Check - Comprehensive diagnostic tool

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"
WORKSPACE="/root/.openclaw/workspace"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════"
}

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        echo -e "$PASS $1 installed"
        return 0
    else
        echo -e "$FAIL $1 not installed"
        return 1
    fi
}

check_file() {
    if [[ -f "$1" ]]; then
        echo -e "$PASS $(basename $1) exists"
        return 0
    else
        echo -e "$FAIL $(basename $1) missing"
        return 1
    fi
}

check_dir() {
    if [[ -d "$1" ]]; then
        echo -e "$PASS $(basename $1)/ exists"
        return 0
    else
        echo -e "$FAIL $(basename $1)/ missing"
        return 1
    fi
}

header "🤖 Autonomy Health Check"
echo "Running at: $(date)"
echo ""

# System Dependencies
header "System Dependencies"
DEPS_PASS=0
DEPS_FAIL=0

for cmd in git jq python3 bash; do
    if check_command $cmd; then
        ((DEPS_PASS++))
    else
        ((DEPS_FAIL++))
    fi
done

echo ""
echo "Dependencies: $DEPS_PASS pass, $DEPS_FAIL fail"

# Core Files
header "Core Files"
FILES_PASS=0
FILES_FAIL=0

for file in "$AUTONOMY_DIR/autonomy" "$AUTONOMY_DIR/config.json" "$AUTONOMY_DIR/actions.sh"; do
    if check_file "$file"; then
        ((FILES_PASS++))
    else
        ((FILES_FAIL++))
    fi
done

echo ""
echo "Core files: $FILES_PASS pass, $FILES_FAIL fail"

# Directory Structure
header "Directory Structure"
check_dir "$AUTONOMY_DIR/contexts"
check_dir "$AUTONOMY_DIR/checks"
check_dir "$AUTONOMY_DIR/scripts"
check_dir "$AUTONOMY_DIR/logs"

# Configuration
header "Configuration"
if [[ -f "$AUTONOMY_DIR/config.json" ]]; then
    if jq empty "$AUTONOMY_DIR/config.json" 2>/dev/null; then
        echo -e "$PASS config.json is valid JSON"
        ACTIVE=$(jq -r '.active_context // "none"' "$AUTONOMY_DIR/config.json")
        echo "  Active context: $ACTIVE"
    else
        echo -e "$FAIL config.json is invalid JSON"
    fi
else
    echo -e "$FAIL config.json not found"
fi

# Test Suite
header "Test Suite"
if [[ -f "$AUTONOMY_DIR/tests/run_tests.sh" ]]; then
    echo -e "$PASS Test suite exists"
    echo "  Run: cd tests && bash run_tests.sh"
else
    echo -e "$WARN Test suite not found"
fi

# Discord Bot
header "Discord Integration"
if pgrep -f "discord_bot.py" >/dev/null; then
    PID=$(pgrep -f "discord_bot.py" | head -1)
    echo -e "$PASS Discord bot running (PID: $PID)"
    
    # Check if token is configured
    if jq -e '.channels.discord' "/root/.openclaw/openclaw.json" >/dev/null 2>&1; then
        echo -e "$PASS Discord token configured"
    else
        echo -e "$WARN Discord token not configured"
    fi
else
    echo -e "$WARN Discord bot not running"
    echo "  Start: ./scripts/start-discord-bot.sh"
fi

# Recent Activity
header "Recent Activity"
if [[ -d "$AUTONOMY_DIR/logs" ]]; then
    LOG_COUNT=$(find "$AUTONOMY_DIR/logs" -name "*.jsonl" -type f 2>/dev/null | wc -l)
    if [[ $LOG_COUNT -gt 0 ]]; then
        LATEST=$(find "$AUTONOMY_DIR/logs" -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        echo -e "$PASS $LOG_COUNT log files found"
        echo "  Latest: $(basename "$LATEST")"
        
        # Last activity
        LAST_ACTIVITY=$(find "$AUTONOMY_DIR/logs" -name "*.jsonl" -exec tail -1 {} \; 2>/dev/null | jq -r '.timestamp' 2>/dev/null | sort | tail -1)
        if [[ -n "$LAST_ACTIVITY" ]]; then
            echo "  Last activity: $LAST_ACTIVITY"
        fi
    else
        echo -e "$WARN No activity logs found"
    fi
else
    echo -e "$WARN Logs directory not found"
fi

# Git Status
header "Git Repository"
cd "$AUTONOMY_DIR"
if [[ -d ".git" ]]; then
    echo -e "$PASS Git repository initialized"
    BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "  Branch: $BRANCH"
    
    # Check for uncommitted changes
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        echo -e "$WARN Uncommitted changes present"
        echo "  Run: git status"
    else
        echo -e "$PASS Working directory clean"
    fi
    
    # Last commit
    LAST_COMMIT=$(git log -1 --format="%h - %s" 2>/dev/null)
    if [[ -n "$LAST_COMMIT" ]]; then
        echo "  Last commit: $LAST_COMMIT"
    fi
else
    echo -e "$FAIL Not a git repository"
fi

# Summary
header "Health Summary"
TOTAL_CHECKS=$((DEPS_PASS + DEPS_FAIL + FILES_PASS + FILES_FAIL))
PASSED=$((DEPS_PASS + FILES_PASS))
FAILED=$((DEPS_FAIL + FILES_FAIL))

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed!${NC} Autonomy is healthy."
elif [[ $FAILED -lt 3 ]]; then
    echo -e "${YELLOW}⚠ Mostly healthy${NC} - $FAILED minor issues found"
else
    echo -e "${RED}✗ Health issues detected${NC} - $FAILED problems need attention"
fi

echo ""
echo "Quick fixes:"
echo "  Run tests:     cd tests && bash run_tests.sh"
echo "  View activity: ./autonomy activity --recent"
echo "  Start Discord: ./scripts/start-discord-bot.sh"
echo "  Get help:      ./autonomy help"
