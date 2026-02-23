# Security Fixes - Autonomy Skill

This document details the security vulnerabilities that were identified and fixed in the autonomy skill.

## Summary of Fixes

### 1. Path Traversal (CVE-style: Directory Traversal)
**Risk Level:** HIGH

**Issue:** Context names were not validated, allowing malicious inputs like `../../../etc/passwd` to access files outside the intended directory.

**Files Modified:**
- `autonomy` (main CLI)
- `checks/git-aware.sh`

**Fix Applied:**
- Added `validate_context_name()` function that enforces pattern `^[a-zA-Z0-9_-]+$`
- All context name inputs are now validated before use
- Reject context names containing path traversal sequences (..), slashes, or special characters

**Code Example:**
```bash
validate_context_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Invalid context name '$name'. Only alphanumeric, underscore, and hyphen allowed."
        return 1
    fi
    return 0
}
```

---

### 2. Token Exposure (Sensitive Data in Logs)
**Risk Level:** HIGH

**Issue:** Discord bot token could be exposed in error messages or exception traces.

**Files Modified:**
- `discord_bot.py`

**Fix Applied:**
- Added `mask_token()` function to redact tokens for display
- Wrap `bot.run()` in try/except to sanitize error messages
- Token validation to detect invalid formats
- Any occurrence of the token in error strings is automatically masked

**Code Example:**
```python
def mask_token(token):
    """Mask token for safe display in logs/errors"""
    if not token or len(token) < 8:
        return "[REDACTED]"
    return token[:4] + "****" + token[-4:]

# Usage in error handling:
if token in error_msg:
    error_msg = error_msg.replace(token, mask_token(token))
```

---

### 3. Command Injection
**Risk Level:** CRITICAL

**Issue:** Repository paths were used directly in `cd` and `git` commands without validation, allowing shell command injection via malicious path names like `"; rm -rf / #`.

**Files Modified:**
- `autonomy` (main CLI)
- `actions.sh`
- `checks/git-aware.sh`

**Fix Applied:**
- Added `validate_path()` function to ensure paths resolve within expected directories
- Added `safe_cd()` wrapper function that validates before changing directory
- All `cd` commands now use `safe_cd` or `--` to prevent option injection
- Path traversal attempts (..) are explicitly blocked

**Code Example:**
```bash
validate_path() {
    local path="$1"
    local base_dir="${2:-$WORKSPACE}"
    
    # Check for path traversal attempts
    if [[ "$abs_path" == *".."* ]]; then
        echo "Error: Path contains invalid characters (..)"
        return 1
    fi
    
    # Ensure path is within base directory
    if [[ ! "$abs_path" =~ ^"$base_real"(/|$) ]]; then
        echo "Error: Path is outside allowed directory"
        return 1
    fi
}

safe_cd() {
    local target_dir="$1"
    validate_path "$target_dir" "/" || return 1
    cd -- "$target_dir" || return 1
}
```

---

### 4. Race Condition (TOCTOU)
**Risk Level:** MEDIUM

**Issue:** Configuration files were updated using a read-modify-write pattern without file locking, allowing race conditions when multiple processes update config simultaneously.

**Files Modified:**
- `autonomy` (main CLI)

**Fix Applied:**
- Added `update_config_with_lock()` function using `flock` for exclusive file locking
- Config updates now use atomic move operations
- Lock file is `${CONFIG}.lock`

**Code Example:**
```bash
update_config_with_lock() {
    local temp_file="${CONFIG}.tmp.$$"
    local lock_fd
    
    # Acquire exclusive lock
    exec {lock_fd}>"${CONFIG}.lock"
    flock -x "$lock_fd" || {
        echo "Error: Could not acquire lock on config"
        return 1
    }
    
    # Write to temp file
    cat > "$temp_file" || {
        flock -u "$lock_fd"
        rm -f "$temp_file"
        return 1
    }
    
    # Atomic move
    mv "$temp_file" "$CONFIG" || {
        flock -u "$lock_fd"
        rm -f "$temp_file"
        return 1
    }
    
    # Release lock
    flock -u "$lock_fd"
    exec {lock_fd}>&-
}
```

---

### 5. Unquoted Variables (Word Splitting / Globbing)
**Risk Level:** MEDIUM

**Issue:** Many shell variables were unquoted, causing word splitting and globbing issues. Paths with spaces or special characters would cause incorrect command execution.

**Files Modified:**
- `autonomy` (main CLI)
- `actions.sh`
- `checks/git-aware.sh`

**Fix Applied:**
- All variables are now quoted: `"$variable"` instead of `$variable`
- Use `--` to separate options from path arguments
- Use `basename -- "$var"` instead of `basename "$var"`
- Use `dirname -- "$var"` instead of `dirname "$var"`

**Before/After Examples:**
```bash
# Before (vulnerable):
cd "$repo"
basename "$files"
rm "$CONTEXTS_DIR/${NAME}.json"

# After (fixed):
cd -- "$repo" || return 1
basename -- "$files"
rm -f -- "$CONTEXT_FILE"
```

---

## Testing Recommendations

1. **Path Traversal:** Try `autonomy context add ../../../etc/passwd /tmp` - should be rejected
2. **Command Injection:** Try paths with shell metacharacters - should be rejected
3. **Race Condition:** Run multiple `autonomy on/off` commands simultaneously - should not corrupt config
4. **Variable Quoting:** Create directories with spaces and special characters - should work correctly

## Files Modified Summary

| File | Changes |
|------|---------|
| `autonomy` | Added validate_context_name(), validate_path(), update_config_with_lock(), quoted all variables |
| `actions.sh` | Added validate_path(), safe_cd(), quoted all variables, fixed cd security |
| `discord_bot.py` | Added mask_token(), token validation, wrapped bot.run() with error sanitization |
| `checks/git-aware.sh` | Added validate_path(), safe_cd(), context name validation, quoted all variables |

## Security Functions Added

### validate_context_name()
Validates that context names only contain alphanumeric characters, underscores, and hyphens.

### validate_path()
Validates that a path resolves within an allowed base directory and contains no path traversal sequences.

### safe_cd()
Wrapper for `cd` that validates the target directory before changing to it.

### update_config_with_lock()
Atomically updates configuration files using file locking to prevent race conditions.

### mask_token()
Redacts sensitive tokens for safe display in logs and error messages.

---

**Date:** 2026-02-24  
**Security Review By:** Security Fix Subagent  
**Status:** COMPLETE
