#!/bin/bash
# Test utilities shared across test suites

# Note: We don't use set -e here because it interferes with test assertions
# that need to check for failure cases

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$TEST_DIR")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters per suite
SUITE_PASSED=0
SUITE_FAILED=0

# Test assertion helper
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $test_name"
        ((SUITE_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗ FAIL:${NC} $test_name"
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        ((SUITE_FAILED++))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $test_name"
        ((SUITE_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗ FAIL:${NC} $test_name"
        echo "    Expected to contain: '$needle'"
        echo "    Actual: '$haystack'"
        ((SUITE_FAILED++))
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $test_name"
        ((SUITE_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗ FAIL:${NC} $test_name"
        echo "    Expected NOT to contain: '$needle'"
        echo "    Actual: '$haystack'"
        ((SUITE_FAILED++))
        return 1
    fi
}

assert_true() {
    local result="$1"
    local test_name="$2"
    
    if [[ "$result" == "true" || "$result" == "0" || "$result" == "success" ]]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $test_name"
        ((SUITE_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗ FAIL:${NC} $test_name"
        echo "    Expected: true/0/success"
        echo "    Actual:   '$result'"
        ((SUITE_FAILED++))
        return 1
    fi
}

assert_false() {
    local result="$1"
    local test_name="$2"
    
    if [[ "$result" == "false" || "$result" == "1" || -z "$result" ]]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $test_name"
        ((SUITE_PASSED++))
        return 0
    else
        echo -e "${RED}  ✗ FAIL:${NC} $test_name"
        echo "    Expected: false/1/empty"
        echo "    Actual:   '$result'"
        ((SUITE_FAILED++))
        return 1
    fi
}

# Skip a test
skip_test() {
    local test_name="$1"
    local reason="${2:-not implemented}"
    echo -e "${YELLOW}  ⊘ SKIP:${NC} $test_name ($reason)"
}

# Report suite results
report_suite_results() {
    local suite_name="$1"
    echo ""
    echo "  ------------------------------"
    echo "  Results: $SUITE_PASSED passed, $SUITE_FAILED failed"
    echo ""
    
    if [[ $SUITE_FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Create a temporary test file
create_temp_file() {
    local content="$1"
    local temp_file=$(mktemp)
    echo "$content" > "$temp_file"
    echo "$temp_file"
}

# Create a temporary test directory
create_temp_dir() {
    mktemp -d
}

# Cleanup function
cleanup() {
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

trap cleanup EXIT
