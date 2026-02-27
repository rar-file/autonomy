#!/bin/bash
# Database Backend Abstraction Layer
# Supports SQLite (default) and PostgreSQL backends

AUTONOMY_DIR="${AUTONOMY_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}/workspace/skills/autonomy}"
CONFIG_FILE="$AUTONOMY_DIR/config.json"
DB_DIR="$AUTONOMY_DIR/data"
SQLITE_DB="$DB_DIR/autonomy.db"

# Get database configuration
get_db_config() {
    local backend=$(jq -r '.database.backend // "sqlite"' "$CONFIG_FILE" 2>/dev/null || echo "sqlite")
    echo "$backend"
}

# Initialize database
init_db() {
    local backend=$(get_db_config)
    
    mkdir -p "$DB_DIR"
    
    case "$backend" in
        sqlite)
            init_sqlite
            ;;
        postgresql)
            init_postgresql
            ;;
        *)
            echo "Unknown backend: $backend"
            return 1
            ;;
    esac
}

# Initialize SQLite database
init_sqlite() {
    if [[ -f "$SQLITE_DB" ]]; then
        return 0
    fi
    
    sqlite3 "$SQLITE_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending',
    priority TEXT DEFAULT 'normal',
    created_at TEXT,
    completed BOOLEAN DEFAULT 0,
    completed_at TEXT,
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 3,
    verification TEXT,
    dependencies TEXT,
    data TEXT
);

CREATE TABLE IF NOT EXISTS activity_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT,
    action TEXT,
    details TEXT
);

CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_completed ON tasks(completed);
CREATE INDEX IF NOT EXISTS idx_activity_timestamp ON activity_log(timestamp);
EOF

    echo "SQLite database initialized at $SQLITE_DB"
}

# Initialize PostgreSQL (placeholder - requires psql)
init_postgresql() {
    echo "PostgreSQL backend not yet implemented"
    echo "Please use SQLite for now"
    return 1
}

# Insert or update a task
save_task() {
    local task_file="$1"
    
    if [[ ! -f "$task_file" ]]; then
        echo "Task file not found: $task_file"
        return 1
    fi
    
    local backend=$(get_db_config)
    local task_name=$(basename "$task_file" .json)
    local task_data=$(cat "$task_file")
    
    case "$backend" in
        sqlite)
            save_task_sqlite "$task_name" "$task_data"
            ;;
        postgresql)
            echo "PostgreSQL not implemented"
            return 1
            ;;
    esac
}

save_task_sqlite() {
    local name="$1"
    local data="$2"
    
    local description=$(echo "$data" | jq -r '.description // ""')
    local status=$(echo "$data" | jq -r '.status // "pending"')
    local priority=$(echo "$data" | jq -r '.priority // "normal"')
    local created=$(echo "$data" | jq -r '.created // ""')
    local completed=$(echo "$data" | jq -r '.completed // false')
    local completed_at=$(echo "$data" | jq -r '.completed_at // ""')
    local attempts=$(echo "$data" | jq -r '.attempts // 0')
    local max_attempts=$(echo "$data" | jq -r '.max_attempts // 3')
    local verification=$(echo "$data" | jq -r '.verification // ""')
    local dependencies=$(echo "$data" | jq -c '.dependencies // []')
    
    # Convert boolean to integer
    [[ "$completed" == "true" ]] && completed=1 || completed=0
    
    sqlite3 "$SQLITE_DB" << EOF
INSERT OR REPLACE INTO tasks (id, name, description, status, priority, created_at, completed, completed_at, attempts, max_attempts, verification, dependencies, data)
VALUES ('$name', '$name', '$(echo "$description" | sed "s/'/''/g")', '$status', '$priority', '$created', $completed, '$completed_at', $attempts, $max_attempts, '$(echo "$verification" | sed "s/'/''/g")', '$(echo "$dependencies" | sed "s/'/''/g")', '$(echo "$data" | sed "s/'/''/g")');
EOF
}

# Get a task by name
get_task() {
    local name="$1"
    local backend=$(get_db_config)
    
    case "$backend" in
        sqlite)
            sqlite3 "$SQLITE_DB" "SELECT data FROM tasks WHERE id = '$name';"
            ;;
        postgresql)
            echo "PostgreSQL not implemented"
            return 1
            ;;
    esac
}

# Get all tasks
get_all_tasks() {
    local backend=$(get_db_config)
    
    case "$backend" in
        sqlite)
            sqlite3 "$SQLITE_DB" "SELECT data FROM tasks;"
            ;;
        postgresql)
            echo "PostgreSQL not implemented"
            return 1
            ;;
    esac
}

# Get tasks by status
get_tasks_by_status() {
    local status="$1"
    local backend=$(get_db_config)
    
    case "$backend" in
        sqlite)
            sqlite3 "$SQLITE_DB" "SELECT data FROM tasks WHERE status = '$status';"
            ;;
        postgresql)
            echo "PostgreSQL not implemented"
            return 1
            ;;
    esac
}

# Get task counts by status
get_task_counts() {
    local backend=$(get_db_config)
    
    case "$backend" in
        sqlite)
            sqlite3 "$SQLITE_DB" << 'EOF'
SELECT 
    status,
    COUNT(*) as count
FROM tasks
GROUP BY status;
EOF
            ;;
        postgresql)
            echo "PostgreSQL not implemented"
            return 1
            ;;
    esac
}

# Log activity
log_activity() {
    local action="$1"
    local details="${2:-{}}"
    local backend=$(get_db_config)
    local timestamp=$(date -Iseconds)
    
    case "$backend" in
        sqlite)
            sqlite3 "$SQLITE_DB" "INSERT INTO activity_log (timestamp, action, details) VALUES ('$timestamp', '$action', '$(echo "$details" | sed "s/'/''/g")');"
            ;;
        postgresql)
            echo "PostgreSQL not implemented"
            return 1
            ;;
    esac
}

# Get recent activity
get_recent_activity() {
    local limit="${1:-20}"
    local backend=$(get_db_config)
    
    case "$backend" in
        sqlite)
            sqlite3 "$SQLITE_DB" "SELECT json_object('timestamp', timestamp, 'action', action, 'details', details) FROM activity_log ORDER BY timestamp DESC LIMIT $limit;"
            ;;
        postgresql)
            echo "PostgreSQL not implemented"
            return 1
            ;;
    esac
}

# Sync all JSON tasks to database
sync_to_db() {
    local tasks_dir="${1:-$AUTONOMY_DIR/tasks}"
    
    echo "Syncing tasks from $tasks_dir to database..."
    
    local count=0
    for task_file in "$tasks_dir"/*.json; do
        [[ -f "$task_file" ]] || continue
        save_task "$task_file"
        ((count++))
    done
    
    echo "Synced $count tasks to database"
}

# Export database to JSON files
sync_from_db() {
    local tasks_dir="${1:-$AUTONOMY_DIR/tasks}"
    
    echo "Exporting tasks from database to $tasks_dir..."
    
    mkdir -p "$tasks_dir"
    
    local count=0
    sqlite3 "$SQLITE_DB" "SELECT name, data FROM tasks;" | while IFS='|' read -r name data; do
        echo "$data" > "$tasks_dir/${name}.json"
        ((count++))
    done
    
    echo "Exported $count tasks to $tasks_dir"
}

# Show database status
status() {
    local backend=$(get_db_config)
    
    echo "Database Backend: $backend"
    echo ""
    
    case "$backend" in
        sqlite)
            if [[ -f "$SQLITE_DB" ]]; then
                echo "SQLite database: $SQLITE_DB"
                echo ""
                echo "Task counts by status:"
                get_task_counts | while read line; do
                    echo "  $line"
                done
                echo ""
                local total=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM tasks;")
                echo "Total tasks: $total"
            else
                echo "Database not initialized"
                echo "Run: autonomy db init"
            fi
            ;;
        postgresql)
            echo "PostgreSQL configuration:"
            jq '.database.postgresql' "$CONFIG_FILE" 2>/dev/null || echo "  Not configured"
            ;;
    esac
}

# Setup wizard
setup_wizard() {
    echo "═══════════════════════════════════════════════════════"
    echo "  Database Backend Setup"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Choose database backend:"
    echo "  1) SQLite (default, file-based, no setup required)"
    echo "  2) PostgreSQL (requires server setup)"
    echo ""
    read -p "Choice (1/2): " choice
    
    case "$choice" in
        1)
            echo "Using SQLite backend"
            tmp_file="${CONFIG_FILE}.tmp"
            jq '.database = {"backend": "sqlite"}' "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"
            init_sqlite
            ;;
        2)
            echo "PostgreSQL setup not yet implemented"
            echo "Please use SQLite for now"
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

# Command dispatch
case "${1:-status}" in
    init)
        init_db
        ;;
    save)
        save_task "$2"
        ;;
    get)
        get_task "$2"
        ;;
    all)
        get_all_tasks
        ;;
    status)
        status
        ;;
    sync-to-db)
        sync_to_db "$2"
        ;;
    sync-from-db)
        sync_from_db "$2"
        ;;
    setup)
        setup_wizard
        ;;
    *)
        echo "Usage: $0 {init|save|get|all|status|sync-to-db|sync-from-db|setup}"
        echo ""
        echo "Commands:"
        echo "  init              - Initialize database"
        echo "  save <file>       - Save task to database"
        echo "  get <name>        - Get task from database"
        echo "  all               - Get all tasks"
        echo "  status            - Show database status"
        echo "  sync-to-db [dir]  - Sync JSON files to database"
        echo "  sync-from-db [dir] - Export database to JSON files"
        echo "  setup             - Interactive setup wizard"
        exit 1
        ;;
esac
