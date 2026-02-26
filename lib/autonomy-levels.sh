#!/bin/bash
# Autonomy Levels Manager
# Implements supervised, semi-autonomous, and fully autonomous modes

AUTONOMY_DIR="${AUTONOMY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG="$AUTONOMY_DIR/config.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Level definitions
SUPERVISED_DESC="All actions require explicit approval. AI suggests but never executes without confirmation."
SEMI_AUTO_DESC="AI executes low-risk actions automatically, asks for approval on medium/high risk."
FULL_AUTO_DESC="AI makes all decisions within hard limits. Only critical safety issues require approval."

# Get current level
get_level() {
    jq -r '.agentic_config.autonomy_level // "semi-autonomous"' "$CONFIG"
}

# Set autonomy level
set_level() {
    local level="$1"
    
    case "$level" in
        supervised|semi-autonomous|fully-autonomous)
            jq --arg level "$level" '
                .agentic_config.autonomy_level = $level |
                .agentic_config.requires_approval = 
                    if $level == "supervised" then
                        ["all_actions", "external_api_calls", "sending_messages", "file_deletion", 
                         "public_posts", "git_push", "installing_packages", "file_modification"]
                    elif $level == "semi-autonomous" then
                        ["external_api_calls", "sending_messages", "file_deletion", 
                         "public_posts", "git_push", "installing_packages"]
                    else
                        ["public_posts", "git_push", "destructive_commands"]
                    end |
                .agentic_config.auto_approve =
                    if $level == "supervised" then
                        ["reading_files", "memory_search", "web_search"]
                    elif $level == "semi-autonomous" then
                        ["reading_files", "writing_workspace_files", "local_commands", 
                         "web_search", "memory_search", "creating_tasks"]
                    else
                        ["reading_files", "writing_workspace_files", "local_commands", 
                         "web_search", "memory_search", "creating_tasks", "file_deletion",
                         "external_api_calls", "sending_messages", "installing_packages"]
                    end
            ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
            
            echo -e "${GREEN}✓${NC} Autonomy level set to: ${CYAN}$level${NC}"
            ;;
        *)
            echo -e "${RED}✗${NC} Invalid level. Use: supervised, semi-autonomous, or fully-autonomous"
            return 1
            ;;
    esac
}

# Show current level details
show_level() {
    local level=$(get_level)
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  AUTONOMY LEVEL"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    case "$level" in
        supervised)
            echo -e "  Current: ${YELLOW}SUPERVISED${NC} 🔍"
            echo ""
            echo "  Description:"
            echo "    $SUPERVISED_DESC"
            echo ""
            echo "  Auto-approved:"
            echo "    ✓ Reading files"
            echo "    ✓ Memory search"
            echo "    ✓ Web search"
            echo ""
            echo "  Requires approval:"
            echo "    ✗ All file modifications"
            echo "    ✗ External API calls"
            echo "    ✗ Sending messages"
            echo "    ✗ Running commands"
            echo "    ✗ Creating tasks"
            ;;
        semi-autonomous)
            echo -e "  Current: ${CYAN}SEMI-AUTONOMOUS${NC} ⚡"
            echo ""
            echo "  Description:"
            echo "    $SEMI_AUTO_DESC"
            echo ""
            echo "  Auto-approved:"
            echo "    ✓ Reading files"
            echo "    ✓ Writing workspace files"
            echo "    ✓ Local commands"
            echo "    ✓ Web search"
            echo "    ✓ Memory search"
            echo "    ✓ Creating tasks"
            echo ""
            echo "  Requires approval:"
            echo "    ✗ External API calls"
            echo "    ✗ Sending messages"
            echo "    ✗ File deletion"
            echo "    ✗ Public posts"
            echo "    ✗ Git push"
            echo "    ✗ Installing packages"
            ;;
        fully-autonomous)
            echo -e "  Current: ${GREEN}FULLY AUTONOMOUS${NC} 🚀"
            echo ""
            echo "  Description:"
            echo "    $FULL_AUTO_DESC"
            echo ""
            echo "  Auto-approved:"
            echo "    ✓ Reading files"
            echo "    ✓ Writing workspace files"
            echo "    ✓ Local commands"
            echo "    ✓ Web search"
            echo "    ✓ Memory search"
            echo "    ✓ Creating tasks"
            echo "    ✓ File deletion"
            echo "    ✓ External API calls"
            echo "    ✓ Sending messages"
            echo "    ✓ Installing packages"
            echo ""
            echo "  Requires approval:"
            echo "    ✗ Public posts"
            echo "    ✗ Git push (main branch)"
            echo "    ✗ Destructive system commands"
            ;;
    esac
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# List all levels
list_levels() {
    echo ""
    echo "Available Autonomy Levels:"
    echo ""
    echo -e "  ${YELLOW}supervised${NC}       - All actions require approval"
    echo "                   Best for: Learning, sensitive work, debugging"
    echo ""
    echo -e "  ${CYAN}semi-autonomous${NC}  - Balanced automation with safety checks"
    echo "                   Best for: Daily development, trusted environments"
    echo ""
    echo -e "  ${GREEN}fully-autonomous${NC} - Maximum automation within hard limits"
    echo "                   Best for: Well-tested workflows, automation tasks"
    echo ""
}

# Check if action requires approval
requires_approval() {
    local action="$1"
    local level=$(get_level)
    
    # Get requires_approval list from config
    local needs_approval=$(jq -r ".agentic_config.requires_approval | contains([\"$action\"])" "$CONFIG")
    
    if [[ "$needs_approval" == "true" ]]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# Get approval list for current level
get_approval_list() {
    jq -r '.agentic_config.requires_approval | join(", ")' "$CONFIG"
}

# Get auto-approve list for current level
get_auto_approve_list() {
    jq -r '.agentic_config.auto_approve | join(", ")' "$CONFIG"
}

# Initialize default level in config if not present
init_config() {
    if ! jq -e '.agentic_config.autonomy_level' "$CONFIG" > /dev/null 2>&1; then
        jq '.agentic_config.autonomy_level = "semi-autonomous"' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
    fi
}

# Main command handler
case "${1:-show}" in
    show|status)
        init_config
        show_level
        ;;
    set)
        init_config
        if [[ -z "$2" ]]; then
            echo "Usage: $0 set {supervised|semi-autonomous|fully-autonomous}"
            list_levels
            exit 1
        fi
        set_level "$2"
        ;;
    list)
        list_levels
        ;;
    get)
        get_level
        ;;
    check)
        requires_approval "$2"
        ;;
    *)
        echo "Usage: $0 {show|set <level>|list|get|check <action>}"
        echo ""
        list_levels
        exit 1
        ;;
esac
