#!/bin/bash
# Core function unit tests for autonomy skill

# Don't use set -e here as it interferes with test assertions

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$TEST_DIR")"

# Source utilities
source "$TEST_DIR/test_utils.sh"

echo "Running Core Function Tests"
echo "============================"

# ============================================================
# validate_context_name() - Unit Tests
# ============================================================

validate_context_name() {
    local name="$1"
    
    # Check for valid characters: alphanumeric, dash, underscore only
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "invalid"
        return 1
    fi
    
    # Check length (1-64 chars)
    if [[ ${#name} -lt 1 || ${#name} -gt 64 ]]; then
        echo "invalid"
        return 1
    fi
    
    # Check for reserved names
    local reserved=("help" "status" "on" "off" "config" "test")
    for r in "${reserved[@]}"; do
        if [[ "$name" == "$r" ]]; then
            echo "reserved"
            return 1
        fi
    done
    
    echo "valid"
    return 0
}

test_validate_context_name_valid() {
    assert_equals "valid" "$(validate_context_name "myapp")" "valid simple name"
    assert_equals "valid" "$(validate_context_name "my-app")" "valid name with dash"
    assert_equals "valid" "$(validate_context_name "my_app")" "valid name with underscore"
    assert_equals "valid" "$(validate_context_name "MyApp123")" "valid alphanumeric"
    assert_equals "valid" "$(validate_context_name "a")" "valid single char"
    assert_equals "valid" "$(validate_context_name "app_123_test")" "valid complex name"
}

test_validate_context_name_invalid() {
    assert_equals "invalid" "$(validate_context_name "")" "empty name"
    assert_equals "invalid" "$(validate_context_name "my app")" "space in name"
    assert_equals "invalid" "$(validate_context_name "my/app")" "slash in name"
    assert_equals "invalid" "$(validate_context_name "my.app")" "dot in name"
    assert_equals "invalid" "$(validate_context_name "my@pp")" "special char @"
    assert_equals "invalid" "$(validate_context_name "../../../etc")" "path traversal"
    assert_equals "invalid" "$(validate_context_name ';rm -rf /')" "command injection"
    assert_equals "invalid" "$(validate_context_name '$(whoami)')" "command substitution"
    assert_equals "reserved" "$(validate_context_name 'test')" "reserved name"
    assert_equals "reserved" "$(validate_context_name 'help')" "reserved name help"
}

# ============================================================
# sanitize_path() - Unit Tests
# ============================================================

sanitize_path() {
    local path="$1"
    local base_dir="${2:-/root/.openclaw/workspace}"
    
    # Expand tilde
    path="${path/#\~/$HOME}"
    
    # Remove null bytes
    path="${path//\\x00/}"
    
    # Check for path traversal patterns before normalization
    if [[ "$path" =~ \.\./|\.\.$ ]]; then
        echo "ERROR: path traversal detected"
        return 1
    fi
    
    # Normalize path
    path=$(realpath -m "$path" 2>/dev/null || echo "$path")
    
    # Check for path traversal outside base
    if [[ ! "$path" =~ ^$base_dir ]]; then
        echo "ERROR: path traversal detected"
        return 1
    fi
    
    echo "$path"
    return 0
}

test_sanitize_path_valid() {
    local base="/root/.openclaw/workspace"
    
    assert_equals "$base/projects" "$(sanitize_path "/root/.openclaw/workspace/projects" "$base")" "valid subdir"
    assert_equals "$base" "$(sanitize_path "/root/.openclaw/workspace" "$base")" "exact base path"
}

test_sanitize_path_traversal() {
    local base="/root/.openclaw/workspace"
    
    local result=$(sanitize_path "/root/.openclaw/workspace/../../../etc/passwd" "$base" 2>&1 || true)
    assert_contains "$result" "ERROR" "blocks ../ traversal"
    
    result=$(sanitize_path "../../../etc/passwd" "$base" 2>&1 || true)
    assert_contains "$result" "ERROR" "blocks relative traversal"
    
    result=$(sanitize_path "/root/.openclaw/workspace/sub/../../.." "$base" 2>&1 || true)
    assert_contains "$result" "ERROR" "blocks complex traversal"
}

# ============================================================
# config_read_write() - Unit Tests
# ============================================================

test_config_read_write() {
    local test_config="$TEST_DIR/state/test_config.json"
    
    # Test write
    echo '{"skill": "test", "version": "1.0.0"}' > "$test_config"
    assert_true "$(test -f "$test_config" && echo "true" || echo "false")" "config file created"
    
    # Test read
    local value=$(jq -r '.skill' "$test_config")
    assert_equals "test" "$value" "config read correct value"
    
    # Test atomic update
    jq '.version = "2.0.0"' "$test_config" > "${test_config}.tmp" && mv "${test_config}.tmp" "$test_config"
    value=$(jq -r '.version' "$test_config")
    assert_equals "2.0.0" "$value" "config atomic update works"
    
    # Verify no temp file left
    assert_false "$(test -f "${test_config}.tmp" && echo "true" || echo "false")" "temp file cleaned up"
}

test_config_atomic_update_preserves_data() {
    local test_config="$TEST_DIR/state/test_config2.json"
    
    # Create initial config with multiple fields
    cat > "$test_config" << 'EOF'
{
  "skill": "autonomy",
  "version": "1.0.0",
  "active_context": "git-aware",
  "global_config": {
    "base_interval_minutes": 20,
    "token_target": 800
  }
}
EOF
    
    # Update only one field atomically
    jq '.global_config.token_target = 1000' "$test_config" > "${test_config}.tmp" && mv "${test_config}.tmp" "$test_config"
    
    # Verify other fields preserved
    local interval=$(jq -r '.global_config.base_interval_minutes' "$test_config")
    assert_equals "20" "$interval" "preserved existing nested value"
    
    local context=$(jq -r '.active_context' "$test_config")
    assert_equals "git-aware" "$context" "preserved other top-level values"
    
    local new_target=$(jq -r '.global_config.token_target' "$test_config")
    assert_equals "1000" "$new_target" "updated target value"
}

# ============================================================
# calculate_status() - Unit Tests
# ============================================================

calculate_status() {
    local config_file="$1"
    local heartbeat_file="$2"
    
    # Check if heartbeat exists
    if [[ ! -f "$heartbeat_file" ]]; then
        echo "disabled"
        return 0
    fi
    
    # Get active context
    local context=$(jq -r '.active_context // "none"' "$config_file" 2>/dev/null)
    
    if [[ "$context" == "null" || "$context" == "none" || -z "$context" ]]; then
        echo "enabled_no_context"
        return 0
    fi
    
    echo "enabled:$context"
    return 0
}

test_calculate_status_disabled() {
    local test_config="$TEST_DIR/state/test_status.json"
    local test_heartbeat="$TEST_DIR/state/HEARTBEAT.md"
    
    echo '{"active_context": "test"}' > "$test_config"
    rm -f "$test_heartbeat"
    
    local status=$(calculate_status "$test_config" "$test_heartbeat")
    assert_equals "disabled" "$status" "status when heartbeat missing"
}

test_calculate_status_enabled_no_context() {
    local test_config="$TEST_DIR/state/test_status2.json"
    local test_heartbeat="$TEST_DIR/state/HEARTBEAT2.md"
    
    echo '{"active_context": null}' > "$test_config"
    touch "$test_heartbeat"
    
    local status=$(calculate_status "$test_config" "$test_heartbeat")
    assert_equals "enabled_no_context" "$status" "status enabled but no context"
}

test_calculate_status_enabled_with_context() {
    local test_config="$TEST_DIR/state/test_status3.json"
    local test_heartbeat="$TEST_DIR/state/HEARTBEAT3.md"
    
    echo '{"active_context": "git-aware"}' > "$test_config"
    touch "$test_heartbeat"
    
    local status=$(calculate_status "$test_config" "$test_heartbeat")
    assert_equals "enabled:git-aware" "$status" "status enabled with context"
}

# ============================================================
# Run all tests
# ============================================================

test_validate_context_name_valid
test_validate_context_name_invalid
test_sanitize_path_valid
test_sanitize_path_traversal
test_config_read_write
test_config_atomic_update_preserves_data
test_calculate_status_disabled
test_calculate_status_enabled_no_context
test_calculate_status_enabled_with_context

report_suite_results "Core Tests"
