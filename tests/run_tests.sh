#!/bin/bash
# Simple tests for Autonomy v3

set -e

echo "Running Autonomy v3 tests..."

# Test 1: Check autonomy script exists and is executable
test -x ../autonomy && echo "✓ autonomy is executable"

# Test 2: Check syntax
bash -n ../autonomy && echo "✓ autonomy syntax OK"

# Test 3: Check web_ui.py syntax
python3 -m py_compile ../web_ui.py && echo "✓ web_ui.py syntax OK"

# Test 4: Check config.json is valid JSON
jq empty ../config.json && echo "✓ config.json is valid JSON"

# Test 5: Check required directories exist
test -d ../tasks && echo "✓ tasks/ directory exists"
test -d ../logs && echo "✓ logs/ directory exists"
test -d ../templates && echo "✓ templates/ directory exists"

echo ""
echo "All tests passed!"
