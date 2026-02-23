#!/bin/bash
# Auto-context detection hook for PROMPT_COMMAND
# Source this in your ~/.bashrc: source /path/to/cd_hook.sh

AUTONOMY_DIR="${AUTONOMY_DIR:-/root/.openclaw/workspace/skills/autonomy}"
CONTEXTS_DIR="$AUTONOMY_DIR/contexts"
CONFIG="$AUTONOMY_DIR/config.json"
LAST_CONTEXT_FILE="$AUTONOMY_DIR/state/last_auto_context"

# Function to check if current directory matches any context
autonomy_check_context() {
    local current_dir
    current_dir="$(pwd)"
    
    # Check each context file for matching path
    for ctx_file in "$CONTEXTS_DIR"/*.json; do
        [[ -f "$ctx_file" ]] || continue
        
        local ctx_name ctx_path
        ctx_name=$(basename "$ctx_file" .json)
        ctx_path=$(jq -r '.path // ""' "$ctx_file" 2>/dev/null)
        
        # Skip example contexts
        [[ "$ctx_name" == example-* ]] && continue
        [[ -z "$ctx_path" ]] && continue
        
        # Expand ~ if present
        ctx_path="${ctx_path/#\~/$HOME}"
        
        # Check if current dir is within the context path
        if [[ "$current_dir" == "$ctx_path"* ]] || [[ "$current_dir" == "$ctx_path" ]]; then
            # Found a match
            local last_ctx
            last_ctx="$(cat "$LAST_CONTEXT_FILE" 2>/dev/null || echo '')"
            
            if [[ "$last_ctx" != "$ctx_name" ]]; then
                # Context changed - show notification
                echo ""
                echo "[autonomy] Entered project context: $ctx_name"
                echo "[autonomy] Run 'autonomy on $ctx_name' to enable monitoring"
                echo ""
                
                # Save current context
                echo "$ctx_name" > "$LAST_CONTEXT_FILE"
            fi
            
            # Optionally auto-enable if configured
            local auto_enable
            auto_enable=$(jq -r '.global_config.auto_enable_context // false' "$CONFIG" 2>/dev/null)
            if [[ "$auto_enable" == "true" ]]; then
                local active_ctx
                active_ctx=$(jq -r '.active_context // ""' "$CONFIG" 2>/dev/null)
                if [[ "$active_ctx" != "$ctx_name" ]]; then
                    autonomy on "$ctx_name" 2>/dev/null
                fi
            fi
            
            return 0
        fi
    done
    
    # No match found - clear last context if we left a project
    if [[ -f "$LAST_CONTEXT_FILE" ]]; then
        rm "$LAST_CONTEXT_FILE" 2>/dev/null
    fi
    
    return 1
}

# Hook function to be called from PROMPT_COMMAND
autonomy_cd_hook() {
    # Only run if autonomy is installed
    [[ -d "$AUTONOMY_DIR" ]] || return
    
    # Check if we've changed directories
    if [[ "$PWD" != "$AUTONOMY_LAST_PWD" ]]; then
        AUTONOMY_LAST_PWD="$PWD"
        autonomy_check_context
    fi
}

# Setup function for easy installation
autonomy_setup_cd_hook() {
    local shell_rc=""
    
    # Detect shell
    if [[ -n "$BASH_VERSION" ]]; then
        shell_rc="$HOME/.bashrc"
    elif [[ -n "$ZSH_VERSION" ]]; then
        shell_rc="$HOME/.zshrc"
    else
        echo "Unknown shell. Please add manually to your shell's rc file:"
        echo "  source $AUTONOMY_DIR/cd_hook.sh"
        return 1
    fi
    
    # Check if already installed
    if grep -q "cd_hook.sh" "$shell_rc" 2>/dev/null; then
        echo "cd_hook.sh is already sourced in $shell_rc"
        return 0
    fi
    
    echo "" >> "$shell_rc"
    echo "# Auto-context detection for autonomy" >> "$shell_rc"
    echo "export AUTONOMY_DIR=\"$AUTONOMY_DIR\"" >> "$shell_rc"
    echo "source \$AUTONOMY_DIR/cd_hook.sh" >> "$shell_rc"
    echo "PROMPT_COMMAND=\"autonomy_cd_hook; \${PROMPT_COMMAND}\"" >> "$shell_rc"
    
    echo "✓ Added cd_hook to $shell_rc"
    echo "  Run 'source $shell_rc' to enable immediately"
}

# Manual context check command
autonomy_detect_context() {
    if autonomy_check_context; then
        return 0
    else
        echo "[autonomy] No project context detected for: $(pwd)"
        echo "[autonomy] Run 'autonomy context add <name> $(pwd)' to create one"
        return 1
    fi
}
