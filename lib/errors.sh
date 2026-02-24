#!/bin/bash
# Error handler with smart suggestions

AUTONOMY_DIR="/root/.openclaw/workspace/skills/autonomy"

# Smart error messages with actionable suggestions
suggest_fix() {
    local error_type="$1"
    local context="$2"
    
    case "$error_type" in
        context_not_found)
            echo ""
            echo "💡 Suggestion:"
            echo "   This context doesn't exist yet. Create it with:"
            echo "   autonomy context add $context /path/to/project"
            echo ""
            echo "   Or see available contexts:"
            echo "   autonomy context list"
            ;;
        
        config_corrupted)
            echo ""
            echo "💡 Suggestion:"
            echo "   Your config file appears corrupted. Try:"
            echo "   1. autonomy config restore    # Restore from backup"
            echo "   2. autonomy config validate   # Check for errors"
            echo ""
            echo "   If that fails, delete config.json and restart:"
            echo "   rm ~/.openclaw/workspace/skills/autonomy/config.json"
            ;;
        
        check_not_found)
            echo ""
            echo "💡 Suggestion:"
            echo "   This check doesn't exist. Available checks:"
            ls -1 "$AUTONOMY_DIR/checks/" 2>/dev/null | grep '\.sh$' | sed 's/\.sh$//' | sed 's/^/   - /'
            echo ""
            echo "   Or run all checks: autonomy check now"
            ;;
        
        no_git_repo)
            echo ""
            echo "💡 Suggestion:"
            echo "   This directory isn't a git repository. Either:"
            echo "   1. cd into a git repository"
            echo "   2. Initialize git: git init"
            echo "   3. Use a different context that points to a git repo"
            ;;
        
        discord_not_running)
            echo ""
            echo "💡 Suggestion:"
            echo "   The Discord bot isn't running. Start it with:"
            echo "   ./scripts/start-discord-bot.sh"
            echo ""
            echo "   Or for persistent monitoring:"
            echo "   ./scripts/discord-watchdog.sh &"
            ;;
        
        permission_denied)
            echo ""
            echo "💡 Suggestion:"
            echo "   Permission denied. Try:"
            echo "   chmod +x ~/.openclaw/workspace/skills/autonomy/autonomy"
            echo ""
            echo "   Or run with proper permissions"
            ;;
        
        jq_not_installed)
            echo ""
            echo "💡 Suggestion:"
            echo "   jq is required but not installed. Install it:"
            echo "   Ubuntu/Debian: sudo apt-get install jq"
            echo "   macOS: brew install jq"
            echo "   Other: https://stedolan.github.io/jq/download/"
            ;;
        
        autonomy_not_initialized)
            echo ""
            echo "💡 Suggestion:"
            echo "   Autonomy doesn't appear to be initialized. Run:"
            echo "   cd ~/.openclaw/workspace/skills/autonomy"
            echo "   ./scripts/install.sh"
            ;;
        
        *)
            echo ""
            echo "💡 Run 'autonomy health' for diagnostics"
            ;;
    esac
}

# Export if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f suggest_fix
fi
