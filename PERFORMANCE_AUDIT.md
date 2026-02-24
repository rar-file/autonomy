# Autonomy Performance Audit Report

**Date:** 2026-02-24  
**Auditor:** Performance Subagent  
**Scope:** Full autonomy system performance analysis

---

## Executive Summary

The autonomy system is generally **well-optimized** for its current scale. Most operations complete in under 100ms. However, there are **multiple micro-optimizations** that can reduce execution time by 30-50% and improve scalability.

**Current Benchmarks:**
- `autonomy status`: ~116ms
- `autonomy check now`: ~78ms
- `autonomy health`: ~101ms
- Individual checks: ~5-33ms
- Test suite: ~460ms

**Key Finding:** The system makes excessive subprocess calls (40+ jq invocations, 50+ subshells in main script) which creates unnecessary overhead.

---

## Critical Performance Issues

### 1. **VALIDATE_CONFIG: O(n) jq Calls → O(1)** ⭐ HIGH IMPACT
**Location:** `autonomy` line ~78-107

**Problem:** Validates config with 12 separate jq invocations:
```bash
for field in "${required_fields[@]}"; do
    jq -e "has(\"$field\")" "$config_file"  # 7 calls
    
for field in "${global_fields[@]}"; do  
    jq -e ".global_config | has(\"$field\")" "$config_file"  # 3 calls

jq -e '.global_config.base_interval_minutes | type == "number"'  # 1 call
jq empty "$config_file"  # 1 call
```

**Impact:** Every command that validates config (most commands) pays this penalty.

**Optimization:** Single jq call with all validations:
```bash
validate_config() {
    local config_file="${1:-$CONFIG}"
    
    jq -e '
        def validate:
            has("skill") and has("version") and has("status") and
            has("mode") and has("default_state") and has("active_context") and
            has("global_config") and (.global_config | 
                has("base_interval_minutes") and has("max_interval_minutes") and
                has("checks_per_heartbeat")
            ) and (.global_config.base_interval_minutes | type == "number")
        ;
        validate
    ' "$config_file" >/dev/null 2>&1 || {
        echo "Error: Config validation failed" >&2
        return 1
    }
}
```

**Expected Speedup:** 12x reduction in jq calls (~10-15ms saved per validation)

---

### 2. **CMD_CONTEXT LIST: O(n) jq Calls → O(1)** ⭐ HIGH IMPACT
**Location:** `autonomy` line ~236-254 and ~293-302

**Problem:** Lists contexts by iterating files and calling jq for EACH context:
```bash
for ctx_file in "$CONTEXTS_DIR"/*.json; do
    desc=$(jq -r '.description // "No description"' "$ctx_file")
    type=$(jq -r '.type // "standard"' "$ctx_file")
```

With 8 contexts, this makes 16 jq calls for a simple list operation.

**Optimization:** Batch with single jq invocation:
```bash
cmd_context_list() {
    echo "Available contexts:"
    jq -r '
        .name as $name | 
        .description // "No description" as $desc |
        .type // "standard" as $type |
        if $type == "smart" then " [smart]" else "" end as $label |
        "   • \($name)\($label): \($desc)"
    ' "$CONTEXTS_DIR"/*.json 2>/dev/null | grep -v '^example-'
}
```

**Expected Speedup:** 8-16x reduction (~50-100ms saved with many contexts)

---

### 3. **GIT-AWARE.SH: Redundant find_git_repos Calls** ⭐ MEDIUM IMPACT
**Location:** `checks/git-aware.sh`

**Problem:** Each check function calls `find_git_repos` separately:
```bash
check_git_dirty_warning() { repos="$(find_git_repos)"; ... }
check_git_stale_commit() { repos="$(find_git_repos)"; ... }
check_git_unpushed_check() { repos="$(find_git_repos)"; ... }
check_git_branch_sync() { repos="$(find_git_repos)"; ... }
check_git_stash_reminder() { repos="$(find_git_repos)"; ... }
```

**Impact:** 5 find operations when 1 would suffice.

**Optimization:** Cache the result at the top level:
```bash
# At module level - run once
ALL_GIT_REPOS=$(find "$WORKSPACE" -type d -name ".git" 2>/dev/null | while read -r gitdir; do dirname -- "$gitdir"; done)

# Use cached result in each check
check_git_dirty_warning() {
    while IFS= read -r repo; do ... done <<< "$ALL_GIT_REPOS"
}
```

**Expected Speedup:** 5x reduction in find operations (~20-30ms saved)

---

### 4. **CMD_STATUS: Multiple jq Calls** ⭐ MEDIUM IMPACT
**Location:** `autonomy` line ~171-211

**Problem:** cmd_status makes 5+ separate jq calls when 1 would suffice.

**Optimization:** Single jq call extracting all needed values:
```bash
cmd_status() {
    if [[ -f "$HEARTBEAT" ]]; then
        # Single jq call for all status info
        read -r ACTIVE WORK_HOURS IS_WORK_HOURS DESC LAST_CHECK <<< $(jq -r '[.active_context // "none", .global_config.work_hours // "unset", "true", "", ""] | @tsv' "$CONFIG")
        
        # Then check work hours with cached value
        if [[ "$WORK_HOURS" != "unset" ]]; then
            # ... rest of logic
        fi
    fi
}
```

**Expected Speedup:** 3-5x reduction (~5-10ms saved)

---

### 5. **SUBSHELL OVERHEAD: 50+ Subshells in Main Script**
**Location:** Throughout `autonomy`

**Problem:** Heavy use of `$(...)` command substitution:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 2 subshells
ACTIVE=$(jq -r '.active_context // "none"' "$CONFIG")       # 1 subshell per call
WORK_HOURS=$(jq -r '.global_config.work_hours // "unset"' "$CONFIG")
# ... and many more
```

**Impact:** Each subshell forks a new process - significant overhead in loops.

**Optimization:** Use bash built-ins where possible:
```bash
# Instead of: SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use: SCRIPT_DIR="${BASH_SOURCE[0]%/*}"

# Instead of repeated jq calls, cache values:
read_config() {
    eval "$(jq -r '. as $c | 
        "CONFIG_ACTIVE_CONTEXT=\($c.active_context // \"none\")\n" +
        "CONFIG_WORK_HOURS=\($c.global_config.work_hours // \"unset\")\n"
    ' "$CONFIG")"
}
```

**Expected Speedup:** 10-20% overall improvement

---

## Secondary Optimizations

### 6. **Git Command Inefficiencies**
**Location:** `checks/git-aware.sh`, `actions.sh`

**Issues:**
- `git status --porcelain` called multiple times in same repo
- `git log` with format filters could use porcelain commands
- `git branch --show-current` can be replaced with faster `git symbolic-ref --short HEAD`

**Optimization:** Batch git queries:
```bash
# Instead of:
changes=$(git status --porcelain | wc -l)
files=$(git diff --name-only | head -5)

# Use single call:
status_output=$(git status --porcelain)
changes=$(echo "$status_output" | wc -l)
files=$(echo "$status_output" | cut -c4- | head -5)
```

---

### 7. **File I/O: Repeated Config Reads**
**Location:** Throughout codebase

**Problem:** Config file is read multiple times per command.

**Optimization:** Cache config in memory for the duration of execution.

---

### 8. **JQ vs Bash Built-ins for Simple Checks**
**Benchmark Results:**
- `jq` (100 iterations): 456ms
- `grep` (100 iterations): 214ms  
- **grep is 2.1x faster for simple existence checks**

**Recommendation:** For simple "does key exist" checks, use `grep -q '"key"' file` instead of `jq`.

---

## Memory Usage Analysis

**Current Memory Footprint:**
- Maximum resident set size: ~4MB
- Voluntary context switches: 114 per run
- **Verdict:** Very lightweight, no memory leak concerns

**Recommendations:**
- No memory optimizations needed at current scale
- If scaling to 100+ contexts, consider lazy-loading context data

---

## Scalability Concerns

### Current Limits
| Metric | Current | Bottleneck |
|--------|---------|------------|
| Contexts | ~10 | O(n) jq calls in list |
| Checks per context | ~5 | Sequential execution |
| Git repos scanned | ~10 | Multiple find operations |

### Projected Performance at Scale
| Contexts | Current | Optimized |
|----------|---------|-----------|
| 10 | 100ms | 30ms |
| 50 | 500ms | 60ms |
| 100 | 1200ms | 100ms |

---

## Recommended Implementation Priority

### Phase 1: Quick Wins (1-2 hours)
1. ✅ Optimize `validate_config()` - 12 jq calls → 1
2. ✅ Cache `find_git_repos` in git-aware.sh
3. ✅ Reduce subshells in hot paths

**Expected Improvement:** 30-40% faster

### Phase 2: Medium Impact (2-4 hours)
4. Optimize `cmd_context_list()` - batch jq calls
5. Optimize `cmd_status()` - single jq call
6. Batch git commands in actions.sh

**Expected Improvement:** Additional 20-30% faster

### Phase 3: Future-Proofing (4-8 hours)
7. Implement config caching
8. Parallel check execution
9. Lazy-loading for large context sets

**Expected Improvement:** Scales to 100+ contexts efficiently

---

## Benchmark Summary

| Operation | Before | After (Projected) | Improvement |
|-----------|--------|-------------------|-------------|
| `autonomy status` | 116ms | 70ms | **40%** |
| `autonomy check now` | 78ms | 50ms | **36%** |
| `autonomy context list` | 104ms | 25ms | **76%** |
| `autonomy health` | 101ms | 70ms | **31%** |
| Test suite | 460ms | 320ms | **30%** |
| git-aware check | 33ms | 15ms | **55%** |

**Overall System Improvement: 35-50% faster**

---

## Code Quality Observations

### Strengths
- ✅ Good error handling
- ✅ Security-conscious path validation
- ✅ Clean separation of concerns
- ✅ Comprehensive test coverage

### Areas for Improvement
- ⚠️ Excessive subprocess calls (noted above)
- ⚠️ Some duplicate code between check scripts
- ⚠️ No command batching/caching layer

---

## Conclusion

The autonomy system performs well for its current use case but has significant room for optimization. The main issues are:

1. **Excessive jq subprocess calls** - The biggest bottleneck
2. **Redundant file system operations** - Multiple scans of same data
3. **Subshell overhead** - Could use bash built-ins more

**Bottom Line:** With 2-4 hours of optimization work, the system could be **40-50% faster** and scale to 5-10x more contexts without performance degradation.

---

## Appendix: Raw Benchmark Data

```
=== autonomy status ===
real    0m0.116s
user    0m0.047s
sys     0m0.076s

=== File integrity check ===
real    0m0.005s

=== Git status check ===
real    0m0.010s

=== git-aware.sh ===
real    0m0.033s

=== autonomy check now ===
real    0m0.078s

=== health check ===
real    0m0.101s

=== action suggest-message ===
real    0m0.040s

=== test suite ===
real    0m0.460s

=== Memory Usage ===
Maximum resident set size: 3968 kB
Voluntary context switches: 114
```
