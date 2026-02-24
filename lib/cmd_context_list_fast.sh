#!/bin/bash
# cmd_context_list_fast - Optimized context listing
# Replaces O(n) jq calls with O(1) batch processing

CONTEXTS_DIR="${CONTEXTS_DIR:-/root/.openclaw/workspace/skills/autonomy/contexts}"

cmd_context_list() {
    echo "Available contexts:"
    
    # Single jq invocation processes ALL context files
    # Was: n jq calls (2 per context)
    # Now: 1 jq call total
    jq -rs '
        # Filter out example contexts and format output
        map(select(.name | startswith("example-") | not)) |
        map(
            .name as $name |
            (.type // "standard") as $type |
            (.description // "No description") as $desc |
            if $type == "smart" then 
                "   • \($name) [smart]: \($desc)"
            else 
                "   • \($name): \($desc)"
            end
        ) |
        .[]
    ' "$CONTEXTS_DIR"/*.json 2>/dev/null || echo "   (No contexts found)"
}

# Export for use
export -f cmd_context_list

# If run directly, test it
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Testing optimized cmd_context_list..."
    echo ""
    time cmd_context_list
fi
