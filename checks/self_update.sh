#!/bin/bash
# Autonomy Self-Update System
# Checks GitHub repo for updates and applies them

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$SCRIPT_DIR/.."
WORKSPACE="${OPENCLAW_HOME:-$HOME/.openclaw}/workspace"
REPO="rar-file/autonomy"
INSTALL_DIR="$WORKSPACE/skills/autonomy"
VERSION_FILE="$AUTONOMY_DIR/.version"
LAST_CHECK_FILE="$AUTONOMY_DIR/.last_update_check"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get current version (from git or file)
get_current_version() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR" && git rev-parse --short HEAD 2>/dev/null
    elif [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "unknown"
    fi
}

# Get latest version from GitHub
get_latest_version() {
    # Try master branch first (this repo uses master)
    local latest_commit=$(gh api repos/$REPO/commits/master --jq '.sha[0:7]' 2>/dev/null)
    if [[ -z "$latest_commit" || "$latest_commit" == "null" ]]; then
        # Fallback to main branch
        latest_commit=$(gh api repos/$REPO/commits/main --jq '.sha[0:7]' 2>/dev/null)
    fi
    echo "$latest_commit"
}

# Get latest release info
get_latest_release() {
    gh api repos/$REPO/releases/latest --jq '.tag_name, .published_at, .body' 2>/dev/null | head -3
}

# Check if update is needed
check_update() {
    local current=$(get_current_version)
    local latest=$(get_latest_version)
    
    echo "{\"current\": \"$current\", \"latest\": \"$latest\", \"repo\": \"$REPO\"}"
    
    if [[ "$current" == "$latest" ]]; then
        return 0  # No update needed
    else
        return 1  # Update available
    fi
}

# Perform the update
perform_update() {
    local current=$(get_current_version)
    local latest=$(get_latest_version)
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  AUTONOMY SELF-UPDATE${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Repository: $REPO"
    echo "  Current: $current"
    echo "  Latest:  $latest"
    echo ""
    
    # Backup current installation
    echo "  Creating backup..."
    local backup_dir="$AUTONOMY_DIR/backups/autonomy-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$INSTALL_DIR"/* "$backup_dir/" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Backup saved to: $backup_dir"
    echo ""
    
    # Clone latest version
    echo "  Downloading latest version..."
    local temp_dir=$(mktemp -d)
    
    if ! gh repo clone "$REPO" "$temp_dir" -- --depth 1 2>/dev/null; then
        # Fallback: download tarball
        echo "  Trying tarball download..."
        curl -sL "https://github.com/$REPO/archive/refs/heads/master.tar.gz" | tar -xz -C "$temp_dir" --strip-components=1 2>/dev/null || {
            # Try main as fallback
            curl -sL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$temp_dir" --strip-components=1 2>/dev/null || {
                echo -e "  ${RED}✗${NC} Failed to download update"
                rm -rf "$temp_dir"
                return 1
            }
        }
    fi
    
    # Preserve local configs and state
    echo "  Preserving local configuration..."
    cp "$AUTONOMY_DIR/config.json" "$temp_dir/" 2>/dev/null || true
    cp -r "$AUTONOMY_DIR/contexts" "$temp_dir/" 2>/dev/null || true
    cp -r "$AUTONOMY_DIR/state" "$temp_dir/" 2>/dev/null || true
    cp -r "$AUTONOMY_DIR/logs" "$temp_dir/" 2>/dev/null || true
    
    # Apply update
    echo "  Applying update..."
    rsync -a --delete "$temp_dir/" "$INSTALL_DIR/" 2>/dev/null || {
        # Fallback to cp
        rm -rf "$INSTALL_DIR"
        cp -r "$temp_dir" "$INSTALL_DIR"
    }
    
    # Update version file
    echo "$latest" > "$VERSION_FILE"
    date -Iseconds > "$LAST_CHECK_FILE"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo ""
    echo -e "  ${GREEN}✓ Update complete!${NC}"
    echo "  Version: $current → $latest"
    echo ""
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo "  Run 'autonomy --version' to verify"
    echo "  Backup available at: $backup_dir"
    echo -e "${BLUE}───────────────────────────────────────────────────────────${NC}"
    echo ""
    
    return 0
}

# Auto-check on heartbeat (if enabled)
auto_check() {
    local auto_update=$(jq -r '.config.auto_update // false' "$AUTONOMY_DIR/config.json" 2>/dev/null)
    
    if [[ "$auto_update" != "true" ]]; then
        return 0  # Auto-update disabled
    fi
    
    # Check if we've checked recently (within 24 hours)
    if [[ -f "$LAST_CHECK_FILE" ]]; then
        local last_check=$(cat "$LAST_CHECK_FILE")
        local last_epoch=$(date -d "$last_check" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
        local hours_since=$(( (now_epoch - last_epoch) / 3600 ))
        
        if [[ "$hours_since" -lt 24 ]]; then
            return 0  # Checked recently
        fi
    fi
    
    # Check for updates
    if ! check_update >/dev/null 2>&1; then
        # Update available - could notify here
        echo "Update available for autonomy" >> "$AUTONOMY_DIR/logs/updates.jsonl"
        date -Iseconds > "$LAST_CHECK_FILE"
    fi
}

# Show version info
show_version() {
    local version=$(get_current_version)
    echo "Autonomy Skill v$version"
    echo "Repository: https://github.com/$REPO"
    echo "Install: $INSTALL_DIR"
}

# Command dispatcher
case "${1:-check}" in
    check)
        current=$(get_current_version)
        latest=$(get_latest_version)
        
        if [[ "$current" == "$latest" ]]; then
            echo -e "${GREEN}✓${NC} Autonomy is up to date"
            echo "  Current: $current"
        else
            echo -e "${YELLOW}⬆${NC} Update available!"
            echo "  Current: $current"
            echo "  Latest:  $latest"
            echo ""
            echo "  Run 'autonomy update' to install"
        fi
        ;;
        
    apply|install|run)
        perform_update
        ;;
        
    auto)
        auto_check
        ;;
        
    version|--version|-v)
        show_version
        ;;
        
    *)
        echo "Usage: $0 {check|apply|auto|version}"
        echo ""
        echo "  check    - Check if update is available"
        echo "  apply    - Apply the update"
        echo "  auto     - Auto-check (for heartbeat)"
        echo "  version  - Show current version"
        exit 1
        ;;
esac
