#!/bin/bash
# lib/security.sh - Centralized security and validation functions

# Validate context name - prevents path traversal and injection
validate_context_name() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        echo "Error: Context name cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Context name must be alphanumeric with dashes/underscores only" >&2
        return 1
    fi
    
    # Check reserved names
    case "$name" in
        test|help|list|add|remove|on|off|config|status|check|action)
            echo "Error: '$name' is a reserved keyword" >&2
            return 1
            ;;
    esac
    
    return 0
}

# Validate path - ensures it stays within allowed directory
validate_path() {
    local path="$1"
    local base="${2:-$WORKSPACE}"
    
    if [[ -z "$path" ]]; then
        echo "Error: Path cannot be empty" >&2
        return 1
    fi
    
    # Resolve to absolute paths
    local abs_path
    local abs_base
    abs_path="$(cd "$base" 2>/dev/null && readlink -f "$path" 2>/dev/null)" || abs_path="$path"
    abs_base="$(readlink -f "$base" 2>/dev/null)" || abs_base="$base"
    
    # Check if path is within base directory (safer string prefix check)
    if [[ ! "$abs_path" == "$abs_base"* ]]; then
        echo "Error: Path escapes allowed directory" >&2
        return 1
    fi
    
    return 0
}

# Safely change directory with validation
safe_cd() {
    local target="$1"
    
    if [[ ! -d "$target" ]]; then
        echo "Error: Directory does not exist: $target" >&2
        return 1
    fi
    
    if [[ ! -r "$target" ]]; then
        echo "Error: Cannot read directory: $target" >&2
        return 1
    fi
    
    cd "$target" || {
        echo "Error: Failed to enter directory: $target" >&2
        return 1
    }
}

# Atomic config update with proper error handling
atomic_update_config() {
    local config_file="$1"
    local jq_filter="$2"
    local tmp_file="${config_file}.tmp.$$"
    
    # Cleanup function
    cleanup() {
        rm -f "$tmp_file" 2>/dev/null
    }
    trap cleanup EXIT INT TERM
    
    # Validate config file exists
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config file not found: $config_file" >&2
        return 1
    fi
    
    # Write to temp file
    if ! jq "$jq_filter" "$config_file" > "$tmp_file"; then
        echo "Error: Failed to update config (jq error)" >&2
        return 1
    fi
    
    # Validate temp file
    if ! jq empty "$tmp_file" 2>/dev/null; then
        echo "Error: Generated invalid JSON" >&2
        return 1
    fi
    
    # Atomic move
    if ! mv "$tmp_file" "$config_file"; then
        echo "Error: Failed to save config" >&2
        return 1
    fi
    
    # Success - clear trap
    trap - EXIT INT TERM
    return 0
}

# Check if required dependencies are installed
check_dependencies() {
    local deps=("jq" "git" "date" "basename" "dirname")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required commands: ${missing[*]}" >&2
        echo "Install with: apt-get install jq git coreutils" >&2
        return 1
    fi
    
    return 0
}

# Mask sensitive tokens in output
mask_token() {
    local input="$1"
    # Mask common token patterns
    echo "$input" | sed -E \
        -e 's/ghp_[a-zA-Z0-9]{36}/[MASKED_GITHUB_TOKEN]/g' \
        -e 's/sk-[a-zA-Z0-9]{48}/[MASKED_API_KEY]/g' \
        -e 's/[a-zA-Z0-9_-]{20,}\.([a-zA-Z0-9_-]{10,})\.([a-zA-Z0-9_-]{10,})/[MASKED_JWT]/g'
}

# Export functions
export -f validate_context_name validate_path safe_cd atomic_update_config check_dependencies mask_token
