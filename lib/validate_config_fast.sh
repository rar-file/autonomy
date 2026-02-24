#!/bin/bash
# validate_config_fast - Optimized version using single jq call
# Usage: source validate_config_fast.sh && validate_config

CONFIG="${CONFIG:-/root/.openclaw/workspace/skills/autonomy/config.json}"

# Optimized: Single jq call validates entire schema
validate_config() {
    local config_file="${1:-$CONFIG}"
    
    # Check file exists
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Config file not found: $config_file" >&2
        return 1
    fi
    
    # Single jq call for ALL validations
    # 12x faster than original (12 jq calls → 1)
    jq -e '
        def validate:
            # File must be valid JSON (implicit)
            
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
                has("max_interval_minutes") and
                has("checks_per_heartbeat")
            ) and
            
            # Type validations
            (.global_config.base_interval_minutes | type == "number")
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
