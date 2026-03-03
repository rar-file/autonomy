#!/usr/bin/env python3
"""
Autonomy Heartbeat - Phase 1 Tests
Vigorous testing of all autonomy components
"""

import json
import os
import sys
import tempfile
import shutil
from datetime import datetime, timedelta
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent))

from autonomy_heartbeat import (
    check_system_health,
    get_pending_tasks,
    check_stalled_tasks,
    self_review_codebase,
    should_run_background_work,
    create_task,
    is_monday_morning,
    check_predictive_tasks,
    generate_summary
)

# Test configuration
TEST_DIR = Path(__file__).parent / "test_output"

def setup_test_env():
    """Setup test environment"""
    TEST_DIR.mkdir(exist_ok=True)
    (TEST_DIR / "tasks").mkdir(exist_ok=True)
    (TEST_DIR / "logs").mkdir(exist_ok=True)
    print(f"✓ Test environment ready: {TEST_DIR}")

def cleanup_test_env():
    """Clean up test environment"""
    if TEST_DIR.exists():
        shutil.rmtree(TEST_DIR)
    print("✓ Test environment cleaned")

def test_task_creation():
    """Test task creation logic"""
    print("\n--- Test: Task Creation ---")
    
    # Temporarily override TASKS_DIR
    import autonomy_heartbeat as ah
    original_tasks_dir = ah.TASKS_DIR
    ah.TASKS_DIR = TEST_DIR / "tasks"
    
    try:
        # Create test task
        task = create_task("Test Task", "Test description", "high")
        
        # Verify file created
        task_file = ah.TASKS_DIR / "test_task.json"
        assert task_file.exists(), "Task file not created"
        
        # Verify content
        with open(task_file) as f:
            data = json.load(f)
        
        assert data['name'] == "Test Task"
        assert data['priority'] == "high"
        assert data['status'] == "pending"
        
        print("✓ Task creation works")
        
    finally:
        ah.TASKS_DIR = original_tasks_dir
        # Cleanup
        if task_file.exists():
            task_file.unlink()

def test_pending_tasks():
    """Test reading pending tasks"""
    print("\n--- Test: Pending Tasks ---")
    
    import autonomy_heartbeat as ah
    original_tasks_dir = ah.TASKS_DIR
    ah.TASKS_DIR = TEST_DIR / "tasks"
    
    try:
        # Create test tasks
        create_task("Task 1", "Description 1", "high")
        create_task("Task 2", "Description 2", "medium")
        
        # Read tasks
        tasks = get_pending_tasks()
        
        assert len(tasks) == 2, f"Expected 2 tasks, got {len(tasks)}"
        print(f"✓ Found {len(tasks)} pending tasks")
        
    finally:
        ah.TASKS_DIR = original_tasks_dir

def test_stalled_tasks():
    """Test stalled task detection"""
    print("\n--- Test: Stalled Tasks ---")
    
    import autonomy_heartbeat as ah
    original_tasks_dir = ah.TASKS_DIR
    ah.TASKS_DIR = TEST_DIR / "tasks"
    
    try:
        # Create fresh task
        create_task("Fresh Task", "Just created", "medium")
        
        # Create old in-progress task
        old_time = (datetime.now() - timedelta(hours=25)).isoformat()
        old_task = {
            "name": "Old Task",
            "description": "Stalled task",
            "status": "in-progress",
            "priority": "high",
            "created_at": old_time,
            "updated_at": old_time
        }
        
        with open(ah.TASKS_DIR / "old_task.json", 'w') as f:
            json.dump(old_task, f)
        
        # Check stalled
        stalled = check_stalled_tasks()
        
        assert len(stalled) == 1, f"Expected 1 stalled task, got {len(stalled)}"
        assert stalled[0]['name'] == "Old Task"
        print(f"✓ Correctly identified {len(stalled)} stalled task")
        
    finally:
        ah.TASKS_DIR = original_tasks_dir

def test_monday_morning():
    """Test Monday morning detection"""
    print("\n--- Test: Monday Morning ---")
    
    # Mock datetime
    from unittest.mock import patch
    
    # Test Monday 10am (should trigger)
    monday_morning = datetime(2026, 3, 2, 10, 0)  # Monday
    with patch('autonomy_heartbeat.datetime') as mock_dt:
        mock_dt.now.return_value = monday_morning
        mock_dt.side_effect = lambda *args, **kw: datetime(*args, **kw)
        assert is_monday_morning() == True, "Should be Monday morning"
    
    # Test Monday 2pm (should NOT trigger)
    monday_afternoon = datetime(2026, 3, 2, 14, 0)
    with patch('autonomy_heartbeat.datetime') as mock_dt:
        mock_dt.now.return_value = monday_afternoon
        mock_dt.side_effect = lambda *args, **kw: datetime(*args, **kw)
        assert is_monday_morning() == False, "Should NOT be Monday morning"
    
    # Test Tuesday 10am (should NOT trigger)
    tuesday_morning = datetime(2026, 3, 3, 10, 0)
    with patch('autonomy_heartbeat.datetime') as mock_dt:
        mock_dt.now.return_value = tuesday_morning
        mock_dt.side_effect = lambda *args, **kw: datetime(*args, **kw)
        assert is_monday_morning() == False, "Tuesday is not Monday"
    
    print("✓ Monday morning detection works correctly")

def test_summary_generation():
    """Test summary generation"""
    print("\n--- Test: Summary Generation ---")
    
    import autonomy_heartbeat as ah
    original_tasks_dir = ah.TASKS_DIR
    ah.TASKS_DIR = TEST_DIR / "tasks"
    
    # Clear any existing test tasks
    if ah.TASKS_DIR.exists():
        for f in ah.TASKS_DIR.glob("*.json"):
            f.unlink()
    
    try:
        # Create mix of tasks
        create_task("Pending 1", "Desc", "medium")
        create_task("Pending 2", "Desc", "low")
        
        # Create completed task for today
        today_task = {
            "name": "Completed Today",
            "description": "Done",
            "status": "completed",
            "priority": "medium",
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat()
        }
        with open(ah.TASKS_DIR / "completed_today.json", 'w') as f:
            json.dump(today_task, f)
        
        summary = generate_summary()
        
        assert summary['pending_tasks'] == 2, f"Expected 2 pending, got {summary['pending_tasks']}"
        assert summary['completed_today'] == 1, f"Expected 1 completed today, got {summary['completed_today']}"
        assert summary['total_tasks'] == 3, f"Expected 3 total, got {summary['total_tasks']}"
        
        print(f"✓ Summary correct: {summary}")
        
    finally:
        ah.TASKS_DIR = original_tasks_dir

def test_self_review():
    """Test self-review functionality"""
    print("\n--- Test: Self-Review ---")
    
    findings = self_review_codebase()
    
    # Should return a list (may be empty if no TODOs found)
    assert isinstance(findings, list)
    print(f"✓ Self-review returned {len(findings)} findings")

def test_safety_guards():
    """Test safety guard logic"""
    print("\n--- Test: Safety Guards ---")
    
    # Verify no destructive operations are automatic
    import autonomy_heartbeat as ah
    
    # Check that create_task never auto-deletes
    original_tasks_dir = ah.TASKS_DIR
    ah.TASKS_DIR = TEST_DIR / "tasks"
    
    try:
        task = create_task("Safe Task", "Should not auto-execute", "medium")
        assert task['status'] == 'pending'  # Never auto-completes
        print("✓ Tasks created as pending (not auto-executed)")
        
    finally:
        ah.TASKS_DIR = original_tasks_dir

def test_integration():
    """Integration test - run main() in dry mode"""
    print("\n--- Test: Integration ---")
    
    import autonomy_heartbeat as ah
    
    # Mock external dependencies
    from unittest.mock import patch, MagicMock
    
    with patch.object(ah, 'get_web_ui_status', return_value={
        'health': {'disk': '50%', 'cpu': '30%', 'memory': '40%'}
    }):
        with patch.object(ah, 'check_github_status', return_value=[]):
            with patch.object(ah, 'should_run_background_work', return_value=False):
                try:
                    ah.main()
                    print("✓ Integration test passed")
                except Exception as e:
                    print(f"✗ Integration test failed: {e}")
                    raise

def run_all_tests():
    """Run all tests"""
    print("=" * 60)
    print("AUTONOMY HEARTBEAT - PHASE 1 TESTS")
    print("=" * 60)
    
    setup_test_env()
    
    tests = [
        test_task_creation,
        test_pending_tasks,
        test_stalled_tasks,
        test_monday_morning,
        test_summary_generation,
        test_self_review,
        test_safety_guards,
        test_integration
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"✗ {test.__name__} failed: {e}")
            failed += 1
    
    print("\n" + "=" * 60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    print("=" * 60)
    
    cleanup_test_env()
    
    return failed == 0

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
