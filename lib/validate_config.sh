#!/bin/bash
# validate_config - Optimized single-jq-call schema validator
# Usage: source validate_config.sh && validate_config

AUTONOMY_DIR="${AUTONOMY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG="${CONFIG:-$AUTONOMY_DIR/config.json}"

# Optimized: Single jq call validates entire schema
validate_config() {
    local config_file="${1:-$CONFIG}"
    
    # Check file exists
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config file not found: $config_file" >&2
        return 1
    fi
    
    # Single jq call for ALL validations
    jq -e '
        def validate:
            # Required top-level fields
            has("skill") and
            has("version") and
            has("status") and
            has("mode") and
            has("default_state") and
            has("active_context") and
            has("global_config") and
            
            # Required global_config fields
            (.global_config | 
                has("base_interval_minutes") and
                has("max_concurrent_tasks") or has("max_schedules")
            ) and
            
            # Type validations
            (.global_config.base_interval_minutes | type == "number") and
            
            # Agentic config basics
            (has("agentic_config") and (.agentic_config | has("hard_limits")))
        ;
        validate
    ' "$config_file" >/dev/null 2>&1 || {
        echo "Error: Config validation failed" >&2
        return 1
    }
    
    return 0
}

# Export for use in other scripts
export -f validate_config

# If run directly, test it
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Testing optimized validate_config..."
    time validate_config "$CONFIG" && echo "✓ Config valid" || echo "✗ Config invalid"
fi
