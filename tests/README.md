# Autonomy Skill Tests

Comprehensive test suite for the autonomy skill.

## Structure

```
tests/
├── run_tests.sh      # Main test runner - execute this to run all tests
├── test_utils.sh     # Shared test utilities and assertion helpers
├── test_core.sh      # Unit tests for core functions
├── test_actions.sh   # Integration tests for actions
├── test_security.sh  # Security tests (path traversal, injection, etc.)
├── fixtures/         # Sample configuration files for testing
│   ├── test-context.json
│   ├── minimal.json
│   └── test-config.json
└── TEST_REPORT.md    # Generated test report
```

## Running Tests

### Run all tests:
```bash
cd "${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/autonomy/tests"
bash run_tests.sh
```

### Run individual test suites:
```bash
bash test_core.sh      # Unit tests only
bash test_actions.sh   # Action tests only
bash test_security.sh  # Security tests only
```

## Test Coverage

### Unit Tests (test_core.sh)
- `test_validate_context_name()` - Validates context name constraints
- `test_sanitize_path()` - Tests path traversal prevention
- `test_config_read_write()` - Tests atomic config updates
- `test_calculate_status()` - Tests status calculation logic

### Integration Tests (test_actions.sh)
- `test_autonomy_on_off()` - Enable/disable flow
- `test_context_switch()` - Context switching
- `test_action_dry_run()` - Dry-run mode
- `test_check_execution()` - Check script execution

### Security Tests (test_security.sh)
- `test_path_traversal_blocked()` - Blocks ../../../etc/passwd
- `test_command_injection_blocked()` - Blocks ;rm -rf / 
- `test_token_masking()` - Masks tokens in logs
- `test_null_byte_injection()` - Removes null bytes
- `test_unicode_normalization()` - Unicode safety

## Test Pattern

Tests use a simple bash pattern:

```bash
test_name() {
    result=$(function_under_test)
    if [[ "$result" == "expected" ]]; then
        echo "✓ PASS: test_name"
    else
        echo "✗ FAIL: test_name - got '$result', expected 'expected'"
        exit 1
    fi
}
```

Assertion helpers from `test_utils.sh`:
- `assert_equals expected actual test_name`
- `assert_contains haystack needle test_name`
- `assert_not_contains haystack needle test_name`
- `assert_true value test_name`
- `assert_false value test_name`

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed
