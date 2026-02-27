#!/bin/bash
# Workspace Scanner — Auto-detect language, framework, project structure
# Outputs a compact summary for injection into HEARTBEAT.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE="$(dirname "$(dirname "$AUTONOMY_DIR")")"
SCAN_CACHE="$AUTONOMY_DIR/state/workspace_scan.json"

# Cache validity in seconds (rescan only if older)
CACHE_TTL=300

# ── Detect project language(s) ──────────────────────────────

detect_languages() {
    local langs=()

    [[ -f "$WORKSPACE/package.json" || -f "$WORKSPACE/tsconfig.json" ]] && langs+=("javascript/typescript")
    [[ -f "$WORKSPACE/Cargo.toml" ]]        && langs+=("rust")
    [[ -f "$WORKSPACE/go.mod" ]]            && langs+=("go")
    [[ -f "$WORKSPACE/requirements.txt" || -f "$WORKSPACE/pyproject.toml" || -f "$WORKSPACE/setup.py" ]] && langs+=("python")
    [[ -f "$WORKSPACE/Gemfile" ]]           && langs+=("ruby")
    [[ -f "$WORKSPACE/pom.xml" || -f "$WORKSPACE/build.gradle" || -f "$WORKSPACE/build.gradle.kts" ]] && langs+=("java/kotlin")
    [[ -f "$WORKSPACE/composer.json" ]]     && langs+=("php")
    [[ -f "$WORKSPACE/mix.exs" ]]           && langs+=("elixir")
    [[ -f "$WORKSPACE/CMakeLists.txt" || -f "$WORKSPACE/Makefile" ]] && langs+=("c/cpp")
    [[ -f "$WORKSPACE/pubspec.yaml" ]]      && langs+=("dart/flutter")

    # Fallback: count file extensions
    if [[ ${#langs[@]} -eq 0 ]]; then
        local ext
        ext=$(find "$WORKSPACE" -maxdepth 3 -type f \
              \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" \
                 -o -name "*.rs" -o -name "*.rb" -o -name "*.java" -o -name "*.php" \
                 -o -name "*.c" -o -name "*.cpp" -o -name "*.cs" \) \
              2>/dev/null | head -50 | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
        [[ -n "$ext" ]] && langs+=("$ext")
    fi

    [[ ${#langs[@]} -eq 0 ]] && langs+=("unknown")
    echo "${langs[*]}"
}

# ── Detect framework ────────────────────────────────────────

detect_framework() {
    # Node / JS frameworks
    if [[ -f "$WORKSPACE/package.json" ]]; then
        local pkg="$WORKSPACE/package.json"
        grep -q '"next"'    "$pkg" 2>/dev/null && echo "Next.js"    && return
        grep -q '"nuxt"'    "$pkg" 2>/dev/null && echo "Nuxt"       && return
        grep -q '"react"'   "$pkg" 2>/dev/null && echo "React"      && return
        grep -q '"vue"'     "$pkg" 2>/dev/null && echo "Vue"        && return
        grep -q '"svelte"'  "$pkg" 2>/dev/null && echo "Svelte"     && return
        grep -q '"angular"' "$pkg" 2>/dev/null && echo "Angular"    && return
        grep -q '"express"' "$pkg" 2>/dev/null && echo "Express"    && return
        grep -q '"fastify"' "$pkg" 2>/dev/null && echo "Fastify"    && return
        grep -q '"electron"' "$pkg" 2>/dev/null && echo "Electron"  && return
    fi

    # Python frameworks
    if [[ -f "$WORKSPACE/requirements.txt" ]]; then
        local req="$WORKSPACE/requirements.txt"
        grep -qi "django"  "$req" 2>/dev/null && echo "Django"    && return
        grep -qi "flask"   "$req" 2>/dev/null && echo "Flask"     && return
        grep -qi "fastapi" "$req" 2>/dev/null && echo "FastAPI"   && return
    fi
    if [[ -f "$WORKSPACE/pyproject.toml" ]]; then
        local py="$WORKSPACE/pyproject.toml"
        grep -qi "django"  "$py" 2>/dev/null && echo "Django"    && return
        grep -qi "flask"   "$py" 2>/dev/null && echo "Flask"     && return
        grep -qi "fastapi" "$py" 2>/dev/null && echo "FastAPI"   && return
    fi

    # Ruby
    [[ -f "$WORKSPACE/config/routes.rb" ]] && echo "Rails" && return

    # Rust
    if [[ -f "$WORKSPACE/Cargo.toml" ]]; then
        grep -qi "actix"  "$WORKSPACE/Cargo.toml" 2>/dev/null && echo "Actix Web" && return
        grep -qi "rocket" "$WORKSPACE/Cargo.toml" 2>/dev/null && echo "Rocket"    && return
        grep -qi "axum"   "$WORKSPACE/Cargo.toml" 2>/dev/null && echo "Axum"      && return
    fi

    echo "none detected"
}

# ── Count project size ──────────────────────────────────────

count_files() {
    find "$WORKSPACE" -maxdepth 4 -type f \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -path "*/vendor/*" \
        ! -path "*/target/*" \
        ! -path "*/__pycache__/*" \
        ! -path "*/dist/*" \
        ! -path "*/build/*" \
        2>/dev/null | wc -l | tr -d ' '
}

# ── Detect project type ─────────────────────────────────────

detect_project_type() {
    [[ -f "$WORKSPACE/Dockerfile" || -f "$WORKSPACE/docker-compose.yml" ]] && echo -n "containerized "
    [[ -d "$WORKSPACE/.github/workflows" ]] && echo -n "ci/cd "

    if [[ -f "$WORKSPACE/package.json" ]] && grep -q '"start"' "$WORKSPACE/package.json" 2>/dev/null; then
        echo "web-app"
    elif [[ -d "$WORKSPACE/src" && -d "$WORKSPACE/tests" ]]; then
        echo "library"
    elif [[ -f "$WORKSPACE/main.py" || -f "$WORKSPACE/main.go" || -f "$WORKSPACE/src/main.rs" ]]; then
        echo "application"
    elif [[ -f "$WORKSPACE/setup.py" || -f "$WORKSPACE/pyproject.toml" ]]; then
        echo "python-package"
    else
        echo "project"
    fi
}

# ── Key directories ─────────────────────────────────────────

list_key_dirs() {
    local dirs=()
    for d in src lib app pages components api routes tests test spec docs scripts public static assets; do
        [[ -d "$WORKSPACE/$d" ]] && dirs+=("$d/")
    done
    echo "${dirs[*]}"
}

# ── Git info ────────────────────────────────────────────────

git_info() {
    if [[ -d "$WORKSPACE/.git" ]]; then
        local branch modified
        branch=$(git -C "$WORKSPACE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        modified=$(git -C "$WORKSPACE" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        echo "branch=$branch modified_files=$modified"
    else
        echo "no-git"
    fi
}

# ── README summary ──────────────────────────────────────────

readme_summary() {
    local readme=""
    for f in README.md readme.md README README.rst; do
        [[ -f "$WORKSPACE/$f" ]] && readme="$WORKSPACE/$f" && break
    done
    [[ -z "$readme" ]] && echo "" && return

    # First non-empty, non-heading line (usually describes the project)
    head -20 "$readme" 2>/dev/null | grep -v '^#' | grep -v '^$' | head -2 | tr '\n' ' '
}

# ── Main: Generate scan ────────────────────────────────────

generate_scan() {
    local languages framework project_type file_count key_dirs git readme

    languages=$(detect_languages)
    framework=$(detect_framework)
    project_type=$(detect_project_type)
    file_count=$(count_files)
    key_dirs=$(list_key_dirs)
    git=$(git_info)
    readme=$(readme_summary)

    cat <<EOF
{
  "workspace": "$WORKSPACE",
  "languages": "$languages",
  "framework": "$framework",
  "project_type": "$project_type",
  "file_count": $file_count,
  "key_directories": "$key_dirs",
  "git": "$git",
  "readme_summary": "$(echo "$readme" | sed 's/"/\\"/g' | head -c 200)",
  "scanned_at": "$(date -Iseconds)"
}
EOF
}

# Use cache if fresh
scan() {
    if [[ -f "$SCAN_CACHE" ]]; then
        local age
        age=$(( $(date +%s) - $(date -r "$SCAN_CACHE" +%s 2>/dev/null || echo 0) ))
        if [[ $age -lt $CACHE_TTL ]]; then
            cat "$SCAN_CACHE"
            return 0
        fi
    fi

    generate_scan | tee "$SCAN_CACHE"
}

# Human-readable one-liner for HEARTBEAT injection
scan_oneliner() {
    local data
    data=$(scan)
    local lang fw ptype fcount kdirs git_line
    lang=$(echo "$data"   | jq -r '.languages')
    fw=$(echo "$data"     | jq -r '.framework')
    ptype=$(echo "$data"  | jq -r '.project_type')
    fcount=$(echo "$data" | jq -r '.file_count')
    kdirs=$(echo "$data"  | jq -r '.key_directories')
    git_line=$(echo "$data" | jq -r '.git')

    echo "Language: $lang | Framework: $fw | Type: $ptype | Files: $fcount | Dirs: $kdirs | Git: $git_line"
}

# ── CLI ─────────────────────────────────────────────────────

case "${1:-scan}" in
    scan)     scan ;;
    oneliner) scan_oneliner ;;
    refresh)  rm -f "$SCAN_CACHE"; scan ;;
    *)
        echo "Usage: workspace-scanner.sh {scan|oneliner|refresh}"
        ;;
esac
