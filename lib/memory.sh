#!/bin/bash
# Persistent Memory System — Context that survives across heartbeats
# Stores learned patterns, decisions, preferences, and key facts
# so the AI doesn't repeat mistakes or re-discover the same things.
#
# Memory is injected into HEARTBEAT.md by the heartbeat-builder.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="$AUTONOMY_DIR/state"
MEMORY_FILE="$STATE_DIR/memory.json"
MEMORY_LOG="$STATE_DIR/memory_log.jsonl"

mkdir -p "$STATE_DIR"

# ── Initialize ───────────────────────────────────────────────

_ensure_memory() {
    if [[ ! -f "$MEMORY_FILE" ]]; then
        cat > "$MEMORY_FILE" << 'EOF'
{
  "version": 1,
  "created": null,
  "updated": null,
  "facts": [],
  "decisions": [],
  "patterns": [],
  "blockers": [],
  "preferences": []
}
EOF
        jq --arg ts "$(date -Iseconds)" '.created = $ts | .updated = $ts' "$MEMORY_FILE" > "${MEMORY_FILE}.tmp" \
            && mv "${MEMORY_FILE}.tmp" "$MEMORY_FILE"
    fi
}

# ── Store ────────────────────────────────────────────────────

# store <category> <content> [source]
# Categories: facts, decisions, patterns, blockers, preferences
store() {
    local category="${1:-facts}"
    local content="$2"
    local source="${3:-ai}"

    [[ -z "$content" ]] && {
        echo "Usage: memory.sh store <category> <content> [source]"
        return 1
    }

    _ensure_memory

    # Validate category
    case "$category" in
        facts|decisions|patterns|blockers|preferences) ;;
        *) echo "Invalid category: $category (use: facts, decisions, patterns, blockers, preferences)"; return 1 ;;
    esac

    # Check for duplicate (fuzzy — same first 50 chars)
    local short="${content:0:50}"
    local existing
    existing=$(jq -r --arg cat "$category" --arg s "$short" \
        '.[$cat] // [] | [.[] | select(.content[:50] == $s)] | length' "$MEMORY_FILE" 2>/dev/null)
    if [[ "$existing" -gt 0 ]]; then
        echo "DUPLICATE: Similar memory already exists in $category"
        return 0
    fi

    # Add entry
    local entry
    entry=$(jq -n \
        --arg content "$content" \
        --arg source "$source" \
        --arg ts "$(date -Iseconds)" \
        --arg id "$(date +%s)-$$" \
        '{id:$id, content:$content, source:$source, stored_at:$ts}')

    local tmp="${MEMORY_FILE}.tmp.$$"
    jq --arg cat "$category" --argjson entry "$entry" --arg ts "$(date -Iseconds)" \
        '.[$cat] += [$entry] | .updated = $ts' "$MEMORY_FILE" > "$tmp" && mv "$tmp" "$MEMORY_FILE"

    # Append to log
    jq -n --arg ts "$(date -Iseconds)" --arg cat "$category" --arg content "$content" --arg source "$source" \
        '{timestamp:$ts, action:"store", category:$cat, content:$content, source:$source}' >> "$MEMORY_LOG" 2>/dev/null

    echo "Stored in $category: ${content:0:60}..."
}

# ── Recall ───────────────────────────────────────────────────

# recall [category] — dumps memory as formatted text for HEARTBEAT.md
recall() {
    local category="${1:-all}"
    _ensure_memory

    if [[ "$category" == "all" ]]; then
        local output=""
        for cat in facts decisions patterns blockers preferences; do
            local count
            count=$(jq -r --arg c "$cat" '.[$c] // [] | length' "$MEMORY_FILE" 2>/dev/null)
            [[ "$count" -eq 0 ]] && continue
            output+="### ${cat^}
"
            jq -r --arg c "$cat" '.[$c] // [] | .[-5:] | .[] | "- " + .content' "$MEMORY_FILE" 2>/dev/null
            output+="
"
        done
        if [[ -z "$output" ]]; then
            echo "No memories stored yet."
        else
            echo "$output"
        fi
    else
        jq -r --arg c "$category" '.[$c] // [] | .[] | "- " + .content' "$MEMORY_FILE" 2>/dev/null
    fi
}

# summary — compact one-liner for HEARTBEAT.md
summary() {
    _ensure_memory
    local total facts_n decisions_n blockers_n
    facts_n=$(jq '.facts // [] | length' "$MEMORY_FILE" 2>/dev/null)
    decisions_n=$(jq '.decisions // [] | length' "$MEMORY_FILE" 2>/dev/null)
    blockers_n=$(jq '.blockers // [] | length' "$MEMORY_FILE" 2>/dev/null)
    total=$(jq '[.facts,.decisions,.patterns,.blockers,.preferences] | map(length) | add' "$MEMORY_FILE" 2>/dev/null)

    if [[ "$total" -eq 0 ]]; then
        echo "No persistent memories yet."
        return
    fi

    echo "Memory: $total items ($facts_n facts, $decisions_n decisions, $blockers_n blockers)"

    # Show most recent blocker if any
    local latest_blocker
    latest_blocker=$(jq -r '.blockers // [] | last | .content // empty' "$MEMORY_FILE" 2>/dev/null)
    [[ -n "$latest_blocker" ]] && echo "⚠ Active blocker: $latest_blocker"
}

# ── Remove / Clear ───────────────────────────────────────────

# remove <category> <id>
remove() {
    local category="$1"
    local id="$2"
    [[ -z "$category" || -z "$id" ]] && { echo "Usage: memory.sh remove <category> <id>"; return 1; }
    _ensure_memory

    local tmp="${MEMORY_FILE}.tmp.$$"
    jq --arg cat "$category" --arg id "$id" --arg ts "$(date -Iseconds)" \
        '.[$cat] = [.[$cat][] | select(.id != $id)] | .updated = $ts' \
        "$MEMORY_FILE" > "$tmp" && mv "$tmp" "$MEMORY_FILE"
    echo "Removed $id from $category"
}

# clear [category] — wipe a category or all
clear_memory() {
    local category="${1:-all}"
    _ensure_memory
    local tmp="${MEMORY_FILE}.tmp.$$"

    if [[ "$category" == "all" ]]; then
        jq --arg ts "$(date -Iseconds)" \
            '.facts=[] | .decisions=[] | .patterns=[] | .blockers=[] | .preferences=[] | .updated=$ts' \
            "$MEMORY_FILE" > "$tmp" && mv "$tmp" "$MEMORY_FILE"
        echo "All memory cleared."
    else
        jq --arg cat "$category" --arg ts "$(date -Iseconds)" \
            '.[$cat] = [] | .updated = $ts' \
            "$MEMORY_FILE" > "$tmp" && mv "$tmp" "$MEMORY_FILE"
        echo "Cleared $category."
    fi
}

# ── Stats ────────────────────────────────────────────────────

stats() {
    _ensure_memory
    jq '{
        facts: (.facts // [] | length),
        decisions: (.decisions // [] | length),
        patterns: (.patterns // [] | length),
        blockers: (.blockers // [] | length),
        preferences: (.preferences // [] | length),
        total: ([.facts,.decisions,.patterns,.blockers,.preferences] | map(length) | add),
        updated: .updated
    }' "$MEMORY_FILE" 2>/dev/null
}

# ── Full JSON dump ───────────────────────────────────────────

show() {
    _ensure_memory
    cat "$MEMORY_FILE"
}

# ── CLI ──────────────────────────────────────────────────────

case "${1:-summary}" in
    store)    shift; store "$@" ;;
    recall)   shift; recall "$@" ;;
    summary)  summary ;;
    remove)   shift; remove "$@" ;;
    clear)    shift; clear_memory "$@" ;;
    stats)    stats ;;
    show)     show ;;
    *)
        echo "Usage: memory.sh {store|recall|summary|remove|clear|stats|show}"
        echo ""
        echo "  store <category> <content> [source]  Save a memory"
        echo "  recall [category]                     Recall memories (or all)"
        echo "  summary                               One-liner for HEARTBEAT"
        echo "  remove <category> <id>                Remove a specific memory"
        echo "  clear [category|all]                  Clear memories"
        echo "  stats                                 Memory statistics"
        echo "  show                                  Full JSON dump"
        echo ""
        echo "Categories: facts, decisions, patterns, blockers, preferences"
        ;;
esac
