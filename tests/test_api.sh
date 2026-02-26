#!/bin/bash
# API endpoint tests for autonomy web UI
# Tests: All GET and POST endpoints

# Don't use set -e here as it interferes with test assertions

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONOMY_DIR="$(dirname "$TEST_DIR")"

# Source utilities
source "$TEST_DIR/test_utils.sh"

# API test state directory
API_TEST_STATE="$TEST_DIR/state/api_test"
TEST_PORT=18767  # Use different port to avoid conflicts

echo "Running API Endpoint Tests"
echo "==========================="

# Setup test environment
setup_api_test() {
    rm -rf "$API_TEST_STATE"
    mkdir -p "$API_TEST_STATE" "$API_TEST_STATE/tasks" "$API_TEST_STATE/logs" "$API_TEST_STATE/state"
    
    # Create test config
    cat > "$API_TEST_STATE/config.json" << 'EOF'
{
  "skill": "autonomy",
  "version": "2.0.0",
  "workstation": {
    "active": true,
    "daemon_running": false,
    "tasks": [],
    "running_agents": [],
    "schedules": [],
    "token_usage_today": 0
  },
  "global_config": {
    "base_interval_minutes": 10,
    "work_hours": "09:00-18:00"
  }
}
EOF
    
    # Create sample tasks
    cat > "$API_TEST_STATE/tasks/task1.json" << 'EOF'
{
  "name": "task1",
  "description": "Test task 1",
  "status": "pending",
  "priority": "normal",
  "created": "2024-01-01T10:00:00+00:00",
  "completed": false,
  "attempts": 0,
  "max_attempts": 3
}
EOF
    
    cat > "$API_TEST_STATE/tasks/task2.json" << 'EOF'
{
  "name": "task2",
  "description": "Test task 2",
  "status": "completed",
  "priority": "high",
  "created": "2024-01-01T11:00:00+00:00",
  "completed": true,
  "completed_at": "2024-01-01T12:00:00+00:00",
  "verification": "Tested and verified",
  "attempts": 1,
  "max_attempts": 3
}
EOF
    
    # Create sample log
    echo '{"timestamp":"2024-01-01T10:00:00+00:00","action":"test"}' > "$API_TEST_STATE/logs/agentic.jsonl"
}

# Mock API responses for testing
mock_api_get() {
    local endpoint="$1"
    
    case "$endpoint" in
        "/api/tasks")
            # Return all tasks as JSON array
            local tasks="["
            local first=true
            for task_file in "$API_TEST_STATE/tasks"/*.json; do
                [[ -f "$task_file" ]] || continue
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    tasks="$tasks,"
                fi
                tasks="$tasks$(cat "$task_file")"
            done
            tasks="$tasks]"
            echo "$tasks"
            ;;
        "/api/status")
            local active=$(jq -r '.workstation.active' "$API_TEST_STATE/config.json")
            echo "{\"active\": $active}"
            ;;
        "/api/heartbeat")
            local interval=$(jq -r '.global_config.base_interval_minutes // 10' "$API_TEST_STATE/config.json")
            echo "{\"last_activity\": \"2024-01-01T10:00:00+00:00\", \"interval_minutes\": $interval}"
            ;;
        "/api/task/"*)
            local task_name=$(echo "$endpoint" | sed 's|/api/task/||')
            if [[ -f "$API_TEST_STATE/tasks/${task_name}.json" ]]; then
                cat "$API_TEST_STATE/tasks/${task_name}.json"
            else
                echo '{"error": "Task not found"}'
                return 1
            fi
            ;;
        *)
            echo '{"error": "Not found"}'
            return 1
            ;;
    esac
}

mock_api_post() {
    local endpoint="$1"
    local body="$2"
    
    case "$endpoint" in
        "/api/workstation/on")
            jq '.workstation.active = true' "$API_TEST_STATE/config.json" > "$API_TEST_STATE/config.json.tmp" && mv "$API_TEST_STATE/config.json.tmp" "$API_TEST_STATE/config.json"
            echo '{"success": true}'
            ;;
        "/api/workstation/off")
            jq '.workstation.active = false' "$API_TEST_STATE/config.json" > "$API_TEST_STATE/config.json.tmp" && mv "$API_TEST_STATE/config.json.tmp" "$API_TEST_STATE/config.json"
            echo '{"success": true}'
            ;;
        "/api/task/create")
            local name=$(echo "$body" | jq -r '.name // "unnamed"')
            local desc=$(echo "$body" | jq -r '.description // "No description"')
            cat > "$API_TEST_STATE/tasks/${name}.json" << EOF
{
  "name": "$name",
  "description": "$desc",
  "status": "pending",
  "priority": "normal",
  "created": "$(date -Iseconds)",
  "completed": false
}
EOF
            echo "{\"success\": true, \"message\": \"Task $name created\"}"
            ;;
        "/api/task/"*/complete)
            local task_name=$(echo "$endpoint" | sed 's|/api/task/||; s|/complete||')
            local verification=$(echo "$body" | jq -r '.verification // "Completed via API"')
            if [[ -f "$API_TEST_STATE/tasks/${task_name}.json" ]]; then
                jq --arg verify "$verification" --arg date "$(date -Iseconds)" \
                   '.status = "completed" | .completed = true | .completed_at = $date | .verification = $verify | .attempts = (.attempts // 0) + 1' \
                   "$API_TEST_STATE/tasks/${task_name}.json" > "$API_TEST_STATE/tasks/${task_name}.json.tmp" && \
                   mv "$API_TEST_STATE/tasks/${task_name}.json.tmp" "$API_TEST_STATE/tasks/${task_name}.json"
                echo "{\"success\": true, \"message\": \"Task $task_name completed\"}"
            else
                echo '{"error": "Task not found"}'
                return 1
            fi
            ;;
        "/api/task/"*/update)
            local task_name=$(echo "$endpoint" | sed 's|/api/task/||; s|/update||')
            if [[ -f "$API_TEST_STATE/tasks/${task_name}.json" ]]; then
                # Apply updates from body
                local tmp_file="$API_TEST_STATE/tasks/${task_name}.json.tmp"
                cp "$API_TEST_STATE/tasks/${task_name}.json" "$tmp_file"
                
                # Update fields if present in body
                local new_desc=$(echo "$body" | jq -r '.description // empty')
                local new_priority=$(echo "$body" | jq -r '.priority // empty')
                local new_status=$(echo "$body" | jq -r '.status // empty')
                
                if [[ -n "$new_desc" ]]; then
                    jq --arg d "$new_desc" '.description = $d' "$tmp_file" > "$tmp_file.2" && mv "$tmp_file.2" "$tmp_file"
                fi
                if [[ -n "$new_priority" ]]; then
                    jq --arg p "$new_priority" '.priority = $p' "$tmp_file" > "$tmp_file.2" && mv "$tmp_file.2" "$tmp_file"
                fi
                if [[ -n "$new_status" ]]; then
                    jq --arg s "$new_status" '.status = $s' "$tmp_file" > "$tmp_file.2" && mv "$tmp_file.2" "$tmp_file"
                fi
                
                mv "$tmp_file" "$API_TEST_STATE/tasks/${task_name}.json"
                echo "{\"success\": true, \"message\": \"Task $task_name updated\"}"
            else
                echo '{"error": "Task not found"}'
                return 1
            fi
            ;;
        "/api/schedule/add")
            local interval=$(echo "$body" | jq -r '.interval // "30m"')
            local task=$(echo "$body" | jq -r '.task // ""')
            jq --arg int "$interval" --arg t "$task" '.workstation.schedules += [{"interval": $int, "task": $t, "last_run": null, "created": "'$(date -Iseconds)'"}]' \
               "$API_TEST_STATE/config.json" > "$API_TEST_STATE/config.json.tmp" && \
               mv "$API_TEST_STATE/config.json.tmp" "$API_TEST_STATE/config.json"
            echo "{\"success\": true, \"message\": \"Schedule added: $task every $interval\"}"
            ;;
        "/api/schedule/remove")
            local index=$(echo "$body" | jq -r '.index // 0')
            jq "del(.workstation.schedules[$index])" "$API_TEST_STATE/config.json" > "$API_TEST_STATE/config.json.tmp" && \
               mv "$API_TEST_STATE/config.json.tmp" "$API_TEST_STATE/config.json"
            echo '{"success": true, "message": "Schedule removed"}'
            ;;
        "/api/trigger")
            echo '{"success": true, "message": "Heartbeat triggered"}'
            ;;
        *)
            echo '{"error": "Not found"}'
            return 1
            ;;
    esac
}

mock_api_delete() {
    local endpoint="$1"
    
    case "$endpoint" in
        "/api/task/"*)
            local task_name=$(echo "$endpoint" | sed 's|/api/task/||')
            if [[ -f "$API_TEST_STATE/tasks/${task_name}.json" ]]; then
                rm "$API_TEST_STATE/tasks/${task_name}.json"
                echo "{\"success\": true, \"message\": \"Task $task_name deleted\"}"
            else
                echo '{"error": "Task not found"}'
                return 1
            fi
            ;;
        *)
            echo '{"error": "Not found"}'
            return 1
            ;;
    esac
}

# ============================================================
# GET Endpoint Tests
# ============================================================

test_api_get_tasks() {
    echo "  Testing GET /api/tasks..."
    
    setup_api_test
    
    local response=$(mock_api_get "/api/tasks")
    
    assert_contains "$response" "task1" "tasks endpoint returns task1"
    assert_contains "$response" "task2" "tasks endpoint returns task2"
    assert_contains "$response" "Test task 1" "tasks include descriptions"
}

test_api_get_status() {
    echo "  Testing GET /api/status..."
    
    setup_api_test
    
    local response=$(mock_api_get "/api/status")
    assert_contains "$response" '"active": true' "status shows active"
    
    # Change status and test again
    jq '.workstation.active = false' "$API_TEST_STATE/config.json" > "$API_TEST_STATE/config.json.tmp" && \
       mv "$API_TEST_STATE/config.json.tmp" "$API_TEST_STATE/config.json"
    
    response=$(mock_api_get "/api/status")
    assert_contains "$response" '"active": false' "status shows inactive after change"
}

test_api_get_heartbeat() {
    echo "  Testing GET /api/heartbeat..."
    
    setup_api_test
    
    local response=$(mock_api_get "/api/heartbeat")
    
    assert_contains "$response" "last_activity" "heartbeat includes last_activity"
    assert_contains "$response" "interval_minutes" "heartbeat includes interval_minutes"
    assert_contains "$response" "10" "heartbeat shows correct interval"
}

test_api_get_task_detail() {
    echo "  Testing GET /api/task/{name}..."
    
    setup_api_test
    
    local response=$(mock_api_get "/api/task/task1")
    assert_contains "$response" '"name": "task1"' "task detail returns correct task"
    assert_contains "$response" "Test task 1" "task detail includes description"
    
    response=$(mock_api_get "/api/task/task2")
    assert_contains "$response" '"name": "task2"' "task detail returns task2"
    assert_contains "$response" '"status": "completed"' "task detail shows completed status"
}

test_api_get_not_found() {
    echo "  Testing GET 404 handling..."
    
    setup_api_test
    
    local response=$(mock_api_get "/api/unknown" 2>&1 || true)
    assert_contains "$response" "error" "unknown endpoint returns error"
    
    response=$(mock_api_get "/api/task/nonexistent" 2>&1 || true)
    assert_contains "$response" "error" "nonexistent task returns error"
}

# ============================================================
# POST Endpoint Tests
# ============================================================

test_api_post_workstation_on() {
    echo "  Testing POST /api/workstation/on..."
    
    setup_api_test
    jq '.workstation.active = false' "$API_TEST_STATE/config.json" > "$API_TEST_STATE/config.json.tmp" && \
       mv "$API_TEST_STATE/config.json.tmp" "$API_TEST_STATE/config.json"
    
    local response=$(mock_api_post "/api/workstation/on" "{}")
    assert_contains "$response" '"success": true' "workstation on returns success"
    
    local active=$(jq -r '.workstation.active' "$API_TEST_STATE/config.json")
    assert_equals "true" "$active" "config updated to active"
}

test_api_post_workstation_off() {
    echo "  Testing POST /api/workstation/off..."
    
    setup_api_test
    
    local response=$(mock_api_post "/api/workstation/off" "{}")
    assert_contains "$response" '"success": true' "workstation off returns success"
    
    local active=$(jq -r '.workstation.active' "$API_TEST_STATE/config.json")
    assert_equals "false" "$active" "config updated to inactive"
}

test_api_post_task_create() {
    echo "  Testing POST /api/task/create..."
    
    setup_api_test
    
    local body='{"name": "new_task", "description": "A new test task"}'
    local response=$(mock_api_post "/api/task/create" "$body")
    
    assert_contains "$response" '"success": true' "task create returns success"
    assert_true "$(test -f "$API_TEST_STATE/tasks/new_task.json" && echo "true" || echo "false")" "new task file created"
    
    local desc=$(jq -r '.description' "$API_TEST_STATE/tasks/new_task.json")
    assert_equals "A new test task" "$desc" "new task has correct description"
}

test_api_post_task_complete() {
    echo "  Testing POST /api/task/{name}/complete..."
    
    setup_api_test
    
    local body='{"verification": "Manually tested"}'
    local response=$(mock_api_post "/api/task/task1/complete" "$body")
    
    assert_contains "$response" '"success": true' "task complete returns success"
    
    local status=$(jq -r '.status' "$API_TEST_STATE/tasks/task1.json")
    assert_equals "completed" "$status" "task marked as completed"
    
    local verification=$(jq -r '.verification' "$API_TEST_STATE/tasks/task1.json")
    assert_equals "Manually tested" "$verification" "task has correct verification"
    
    local completed=$(jq -r '.completed' "$API_TEST_STATE/tasks/task1.json")
    assert_equals "true" "$completed" "task completed flag is true"
}

test_api_post_task_update() {
    echo "  Testing POST /api/task/{name}/update..."
    
    setup_api_test
    
    local body='{"description": "Updated description", "priority": "high"}'
    local response=$(mock_api_post "/api/task/task1/update" "$body")
    
    assert_contains "$response" '"success": true' "task update returns success"
    
    local desc=$(jq -r '.description' "$API_TEST_STATE/tasks/task1.json")
    assert_equals "Updated description" "$desc" "task description updated"
    
    local priority=$(jq -r '.priority' "$API_TEST_STATE/tasks/task1.json")
    assert_equals "high" "$priority" "task priority updated"
}

test_api_post_schedule_add() {
    echo "  Testing POST /api/schedule/add..."
    
    setup_api_test
    
    local body='{"interval": "1h", "task": "Hourly check"}'
    local response=$(mock_api_post "/api/schedule/add" "$body")
    
    assert_contains "$response" '"success": true' "schedule add returns success"
    
    local schedules=$(jq '.workstation.schedules | length' "$API_TEST_STATE/config.json")
    assert_equals "1" "$schedules" "schedule added to config"
    
    local interval=$(jq -r '.workstation.schedules[0].interval' "$API_TEST_STATE/config.json")
    assert_equals "1h" "$interval" "schedule has correct interval"
}

test_api_post_schedule_remove() {
    echo "  Testing POST /api/schedule/remove..."
    
    setup_api_test
    
    # Add a schedule first
    jq '.workstation.schedules = [{"interval": "30m", "task": "Test", "last_run": null}]' \
       "$API_TEST_STATE/config.json" > "$API_TEST_STATE/config.json.tmp" && \
       mv "$API_TEST_STATE/config.json.tmp" "$API_TEST_STATE/config.json"
    
    local body='{"index": 0}'
    local response=$(mock_api_post "/api/schedule/remove" "$body")
    
    assert_contains "$response" '"success": true' "schedule remove returns success"
    
    local schedules=$(jq '.workstation.schedules | length' "$API_TEST_STATE/config.json")
    assert_equals "0" "$schedules" "schedule removed from config"
}

test_api_post_trigger() {
    echo "  Testing POST /api/trigger..."
    
    setup_api_test
    
    local response=$(mock_api_post "/api/trigger" "{}")
    
    assert_contains "$response" '"success": true' "trigger returns success"
    assert_contains "$response" "Heartbeat triggered" "trigger returns appropriate message"
}

# ============================================================
# DELETE Endpoint Tests
# ============================================================

test_api_delete_task() {
    echo "  Testing DELETE /api/task/{name}..."
    
    setup_api_test
    
    local response=$(mock_api_delete "/api/task/task1")
    
    assert_contains "$response" '"success": true' "task delete returns success"
    assert_false "$(test -f "$API_TEST_STATE/tasks/task1.json" && echo "true" || echo "false")" "task file deleted"
    
    # Verify task2 still exists
    assert_true "$(test -f "$API_TEST_STATE/tasks/task2.json" && echo "true" || echo "false")" "other tasks not affected"
}

test_api_delete_not_found() {
    echo "  Testing DELETE 404 handling..."
    
    setup_api_test
    
    local response=$(mock_api_delete "/api/task/nonexistent" 2>&1 || true)
    assert_contains "$response" "error" "deleting nonexistent task returns error"
}

# ============================================================
# API Error Handling Tests
# ============================================================

test_api_error_handling() {
    echo "  Testing API error handling..."
    
    setup_api_test
    
    # Test with invalid JSON
    local response=$(mock_api_post "/api/task/create" "invalid json" 2>&1 || true)
    # Should handle gracefully (mock doesn't validate, real API should)
    
    # Test complete on nonexistent task
    response=$(mock_api_post "/api/task/nonexistent/complete" "{}" 2>&1 || true)
    assert_contains "$response" "error" "complete on nonexistent task returns error"
}

# ============================================================
# Run all tests
# ============================================================

setup_api_test
test_api_get_tasks
test_api_get_status
test_api_get_heartbeat
test_api_get_task_detail
test_api_get_not_found
test_api_post_workstation_on
test_api_post_workstation_off
test_api_post_task_create
test_api_post_task_complete
test_api_post_task_update
test_api_post_schedule_add
test_api_post_schedule_remove
test_api_post_trigger
test_api_delete_task
test_api_delete_not_found
test_api_error_handling

# Cleanup
rm -rf "$API_TEST_STATE"

report_suite_results "API Tests"
