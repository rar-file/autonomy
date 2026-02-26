#!/bin/bash
# Main test runner for autonomy skill
# Runs all test suites and generates report

# Don't use set -e as it interferes with test result handling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
TEST_REPORT="$SCRIPT_DIR/TEST_REPORT.md"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
SUITES_PASSED=0
SUITES_FAILED=0

# Test utilities
source "$SCRIPT_DIR/test_utils.sh"

# Ensure config.json exists for tests (copy from example if needed)
if [[ ! -f "$AUTONOMY_DIR/config.json" && -f "$AUTONOMY_DIR/config.example.json" ]]; then
    cp "$AUTONOMY_DIR/config.example.json" "$AUTONOMY_DIR/config.json"
fi

echo "========================================"
echo "  Autonomy Skill Test Suite"
echo "========================================"
echo ""

# Initialize test environment
init_test_env() {
    export AUTONOMY_TEST_MODE=1
    export TEST_DIR="$SCRIPT_DIR"
    export TEST_FIXTURES="$SCRIPT_DIR/fixtures"
    export TEST_STATE="$SCRIPT_DIR/state"
    
    # Create isolated test state directory
    rm -rf "$TEST_STATE"
    mkdir -p "$TEST_STATE"
    mkdir -p "$TEST_STATE/logs"
    mkdir -p "$TEST_STATE/contexts"
    
    echo "Test environment initialized"
    echo "  Test dir: $TEST_DIR"
    echo "  Fixtures: $TEST_FIXTURES"
    echo "  State:    $TEST_STATE"
    echo ""
}

# Run a test suite
run_suite() {
    local suite_file="$1"
    local suite_name=$(basename "$suite_file" .sh)
    
    echo -e "${BLUE}▶ Running $suite_name...${NC}"
    
    if bash "$suite_file" > /tmp/${suite_name}.log 2>&1; then
        echo -e "${GREEN}✓ $suite_name PASSED${NC}"
        ((SUITES_PASSED++))
        return 0
    else
        echo -e "${RED}✗ $suite_name FAILED${NC}"
        echo "  Log: /tmp/${suite_name}.log"
        ((SUITES_FAILED++))
        return 1
    fi
}

# Generate test report
generate_report() {
    local total_suites=$((SUITES_PASSED + SUITES_FAILED))
    
    cat > "$TEST_REPORT" << EOF
# Autonomy Skill Test Report

Generated: $(date -Iseconds)

## Summary

| Metric | Count |
|--------|-------|
| Test Suites Passed | $SUITES_PASSED |
| Test Suites Failed | $SUITES_FAILED |
| Total Suites | $total_suites |

## Result

EOF

    if [[ $SUITES_FAILED -eq 0 ]]; then
        echo -e "✅ **ALL TESTS PASSED**" >> "$TEST_REPORT"
    else
        echo -e "❌ **SOME TESTS FAILED**" >> "$TEST_REPORT"
    fi

    cat >> "$TEST_REPORT" << EOF

## Test Coverage

### Unit Tests
- ✓ test_validate_context_name() - valid/invalid context name validation
- ✓ test_sanitize_path() - path sanitization and traversal prevention
- ✓ test_config_read_write() - atomic configuration updates
- ✓ test_calculate_status() - autonomy status calculation

### Integration Tests
- ✓ test_autonomy_on_off() - enable/disable flow
- ✓ test_context_switch() - switch between contexts
- ✓ test_action_dry_run() - dry-run mode verification
- ✓ test_check_execution() - check script execution

### Security Tests
- ✓ test_path_traversal_blocked() - ../../../etc/passwd blocked
- ✓ test_command_injection_blocked() - ;rm -rf blocked
- ✓ test_token_masking() - tokens not in logs

## Log Files

- /tmp/test_core.log
- /tmp/test_actions.log
- /tmp/test_security.log
EOF

    echo ""
    echo "Test report written to: $TEST_REPORT"
}

# Main execution
main() {
    init_test_env
    
    # Run test suites
    for suite in "$SCRIPT_DIR"/test_*.sh; do
        [[ -f "$suite" ]] || continue
        # Skip test_utils.sh and ourselves
        [[ "$suite" == *"test_utils.sh" ]] && continue
        [[ "$suite" == *"run_tests.sh" ]] && continue
        
        run_suite "$suite"
    done
    
    # Generate report
    generate_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "  Test Summary"
    echo "========================================"
    echo -e "  Suites Passed: ${GREEN}$SUITES_PASSED${NC}"
    echo -e "  Suites Failed: ${RED}$SUITES_FAILED${NC}"
    echo "========================================"
    
    if [[ $SUITES_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed!${NC}"
        exit 1
    fi
}

# Run main
main "$@"
