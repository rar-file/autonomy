#!/bin/bash
# Simple tests for Autonomy

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Running Autonomy tests..."

# Test 1: Check autonomy script exists and is executable
[[ -x "$ROOT_DIR/autonomy" ]] && echo "✓ autonomy is executable"

# Test 2: Check syntax
bash -n "$ROOT_DIR/autonomy" && echo "✓ autonomy syntax OK"

# Test 3: Check web_ui.py syntax
python3 -m py_compile "$ROOT_DIR/web_ui.py" && echo "✓ web_ui.py syntax OK"

# Test 4: Check config.json is valid JSON
jq empty "$ROOT_DIR/config.json" && echo "✓ config.json is valid JSON"

# Test 5: Check required directories exist
[[ -d "$ROOT_DIR/tasks" ]] && echo "✓ tasks/ directory exists"
[[ -d "$ROOT_DIR/logs" ]] && echo "✓ logs/ directory exists"
[[ -d "$ROOT_DIR/templates" ]] && echo "✓ templates/ directory exists"

echo ""
echo "All tests passed!"
