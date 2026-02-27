#!/bin/bash
# API Rate Limiting and Token Authentication Library
# Provides rate limiting and token-based authentication for API endpoints

AUTONOMY_DIR="${AUTONOMY_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/autonomy}"
TOKENS_FILE="$AUTONOMY_DIR/state/api-tokens.json"
RATE_LIMITS_FILE="$AUTONOMY_DIR/state/rate-limits.json"

mkdir -p "$AUTONOMY_DIR/state"

# Initialize files if they don't exist
init_files() {
    if [[ ! -f "$TOKENS_FILE" ]]; then
        echo '{"tokens": {}}' > "$TOKENS_FILE"
    fi
    if [[ ! -f "$RATE_LIMITS_FILE" ]]; then
        echo '{"requests": []}' > "$RATE_LIMITS_FILE"
    fi
}

# Generate a new API token
generate_token() {
    local name="${1:-default}"
    local rate_limit="${2:-100}"  # requests per hour
    local scopes="${3:-[\"read\"]}"  # JSON array of scopes

    init_files

    local token="api_$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p)"
    local created=$(date -Iseconds)

    # Add token to file
    local tmp_file="${TOKENS_FILE}.tmp"
    jq --arg name "$name" \
       --arg token "$token" \
       --arg limit "$rate_limit" \
       --arg scopes "$scopes" \
       --arg created "$created" \
       '.tokens[$name] = {
         "token": $token,
         "rate_limit": ($limit | tonumber),
         "scopes": ($scopes | fromjson),
         "created": $created,
         "last_used": null,
         "active": true
       }' "$TOKENS_FILE" > "$tmp_file" && mv "$tmp_file" "$TOKENS_FILE"

    echo "$token"
}

# Validate a token and check rate limit
validate_request() {
    local token="$1"
    local endpoint="${2:-default}"
    local cost="${3:-1}"  # request cost (some endpoints cost more)

    init_files

    # Check if token exists
    local token_name=$(jq -r --arg tok "$token" '.tokens | to_entries[] | select(.value.token == $tok) | .key' "$TOKENS_FILE" 2>/dev/null)

    if [[ -z "$token_name" ]]; then
        echo '{"valid": false, "error": "Invalid token"}'
        return 1
    fi

    # Check if token is active
    local is_active=$(jq -r --arg name "$token_name" '.tokens[$name].active' "$TOKENS_FILE")
    if [[ "$is_active" != "true" ]]; then
        echo '{"valid": false, "error": "Token revoked"}'
        return 1
    fi

    # Get rate limit for this token
    local rate_limit=$(jq -r --arg name "$token_name" '.tokens[$name].rate_limit' "$TOKENS_FILE")

    # Check rate limit
    local now=$(date +%s)
    local hour_ago=$((now - 3600))

    # Count requests in the last hour
    local request_count=$(jq -r --arg tn "$token_name" --arg start "$hour_ago" '
      [.requests[] | select(.token == $tn and (.timestamp | tonumber) > ($start | tonumber))] | length
    ' "$RATE_LIMITS_FILE" 2>/dev/null || echo 0)

    if [[ "$request_count" -ge "$rate_limit" ]]; then
        echo "{\"valid\": false, \"error\": \"Rate limit exceeded ($request_count/$rate_limit per hour)\", \"retry_after\": 3600}"
        return 1
    fi

    # Log this request
    local tmp_file="${RATE_LIMITS_FILE}.tmp"
    jq --arg tn "$token_name" \
       --arg ts "$now" \
       --arg endpoint "$endpoint" \
       --arg cost "$cost" \
       '.requests += [{
         "token": $tn,
         "timestamp": $ts,
         "endpoint": $endpoint,
         "cost": ($cost | tonumber)
       }]' "$RATE_LIMITS_FILE" > "$tmp_file" && mv "$tmp_file" "$RATE_LIMITS_FILE"

    # Update last_used
    local tmp_file2="${TOKENS_FILE}.tmp"
    jq --arg name "$token_name" \
       --arg now "$(date -Iseconds)" \
       '.tokens[$name].last_used = $now' "$TOKENS_FILE" > "$tmp_file2" && mv "$tmp_file2" "$TOKENS_FILE"

    # Get scopes
    local scopes=$(jq -r --arg name "$token_name" '.tokens[$name].scopes' "$TOKENS_FILE")

    echo "{\"valid\": true, \"token_name\": \"$token_name\", \"scopes\": $scopes, \"remaining\": $((rate_limit - request_count - cost))}"
    return 0
}

# Revoke a token
revoke_token() {
    local name="$1"

    init_files

    if jq -e --arg name "$name" '.tokens[$name]' "$TOKENS_FILE" >/dev/null 2>&1; then
        local tmp_file="${TOKENS_FILE}.tmp"
        jq --arg name "$name" '.tokens[$name].active = false' "$TOKENS_FILE" > "$tmp_file" && mv "$tmp_file" "$TOKENS_FILE"
        echo "Token '$name' revoked"
    else
        echo "Token '$name' not found"
        return 1
    fi
}

# List all tokens
list_tokens() {
    init_files

    echo "API Tokens:"
    echo ""
    
    local token_count=$(jq '.tokens | length' "$TOKENS_FILE" 2>/dev/null || echo 0)
    if [[ "$token_count" -eq 0 ]]; then
        echo "  No tokens configured"
        return
    fi
    
    jq -r '.tokens | keys[]' "$TOKENS_FILE" | while read name; do
        local active=$(jq -r --arg n "$name" '.tokens[$n].active' "$TOKENS_FILE")
        local rate_limit=$(jq -r --arg n "$name" '.tokens[$n].rate_limit' "$TOKENS_FILE")
        local scopes=$(jq -r --arg n "$name" '.tokens[$n].scopes | join(", ")' "$TOKENS_FILE")
        local created=$(jq -r --arg n "$name" '.tokens[$n].created' "$TOKENS_FILE")
        local last_used=$(jq -r --arg n "$name" '.tokens[$n].last_used // "never"' "$TOKENS_FILE")
        
        echo "  $name:"
        echo "    Active: $active"
        echo "    Rate limit: $rate_limit/hour"
        echo "    Scopes: $scopes"
        echo "    Created: $created"
        echo "    Last used: $last_used"
        echo ""
    done
}

# Clean old rate limit entries (older than 24 hours)
clean_rate_limits() {
    local now=$(date +%s)
    local day_ago=$((now - 86400))

    local tmp_file="${RATE_LIMITS_FILE}.tmp"
    jq --arg cutoff "$day_ago" '.requests = [.requests[] | select((.timestamp | tonumber) > ($cutoff | tonumber))]' "$RATE_LIMITS_FILE" > "$tmp_file" && mv "$tmp_file" "$RATE_LIMITS_FILE"

    echo "Old rate limit entries cleaned"
}

# Get rate limit status for a token
get_rate_limit_status() {
    local token_name="$1"

    init_files

    local now=$(date +%s)
    local hour_ago=$((now - 3600))

    local rate_limit=$(jq -r --arg name "$token_name" '.tokens[$name].rate_limit' "$TOKENS_FILE" 2>/dev/null || echo 0)
    local request_count=$(jq -r --arg tn "$token_name" --arg start "$hour_ago" '
      [.requests[] | select(.token == $tn and (.timestamp | tonumber) > ($start | tonumber))] | length
    ' "$RATE_LIMITS_FILE" 2>/dev/null || echo 0)

    echo "{\"token\": \"$token_name\", \"limit\": $rate_limit, \"used\": $request_count, \"remaining\": $((rate_limit - request_count))}"
}

# Setup wizard
setup_wizard() {
    echo "═══════════════════════════════════════════════════════"
    echo "  API Token Setup"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "This will create an API token for accessing the autonomy API."
    echo ""

    read -p "Token name (e.g., 'web-ui', 'discord-bot'): " name
    read -p "Rate limit per hour (default: 100): " rate_limit
    rate_limit=${rate_limit:-100}
    read -p "Scopes (comma-separated, default: read,write): " scopes_input
    scopes_input=${scopes_input:-read,write}

    # Convert scopes to JSON array
    local scopes_json="[$(echo "$scopes_input" | tr ',' '\n' | while read s; do echo "\"$(echo $s | xargs)\""; done | tr '\n' ',' | sed 's/,$//')]"

    local token=$(generate_token "$name" "$rate_limit" "$scopes_json")

    echo ""
    echo "✅ Token created: $name"
    echo ""
    echo "Token: $token"
    echo "Rate limit: $rate_limit/hour"
    echo ""
    echo "Store this token securely - it won't be shown again!"
}

# Command dispatch
case "${1:-status}" in
    generate)
        token=$(generate_token "${2:-default}" "${3:-100}" "${4:-[\"read\"]}")
        echo "Token: $token"
        ;;
    validate)
        validate_request "$2" "${3:-default}" "${4:-1}"
        ;;
    revoke)
        revoke_token "$2"
        ;;
    list)
        list_tokens
        ;;
    clean)
        clean_rate_limits
        ;;
    status)
        if [[ -n "$2" ]]; then
            get_rate_limit_status "$2"
        else
            list_tokens
        fi
        ;;
    setup)
        setup_wizard
        ;;
    *)
        echo "Usage: $0 {generate|validate|revoke|list|clean|status|setup}"
        echo ""
        echo "Commands:"
        echo "  generate [name] [limit] [scopes]  - Generate new token"
        echo "  validate <token> [endpoint] [cost] - Validate token request"
        echo "  revoke <name>                    - Revoke a token"
        echo "  list                             - List all tokens"
        echo "  clean                            - Clean old rate limit data"
        echo "  status [token_name]              - Show rate limit status"
        echo "  setup                            - Interactive setup wizard"
        exit 1
        ;;
esac
