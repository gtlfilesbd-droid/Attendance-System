#!/usr/bin/env python
"""
Test script for Celery tasks
"""
import os
import sys
import django
from pathlib import Path

# Add project directory to Python path
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from tracking.tasks import (
    calculate_daily_attendance,
    send_location_reminder,
    cleanup_old_locations,
    test_task
)
from django.utils import timezone


def test_celery_connection():
    """Test if Celery can connect to Redis"""
    print("\n" + "="*60)
    print("Testing Celery Connection...")
    print("="*60)
    
    try:
        from config.celery import app
        
        # Test Redis connection
        result = app.control.ping(timeout=1.0)
        
        if result:
            print("✓ Celery worker is running and responding")
            print(f"  Workers: {list(result[0].keys())}")
        else:
            print("✗ No Celery workers found")
            print("  Please start a worker with: celery -A config worker -l info")
        
        return bool(result)
        
    except Exception as e:
        print(f"✗ Celery connection failed: {str(e)}")
        print("  Make sure Redis is running: redis-server")
        return False


def test_simple_task():
    """Test simple task execution"""
    print("\n" + "="*60)
    print("Testing Simple Task...")
    print("="*60)
    
    try:
        # Run test task
        result = test_task()
        print("✓ Test task executed successfully")
        print(f"  Result: {result}")
        return True
        
    except Exception as e:
        print(f"✗ Test task failed: {str(e)}")
        return False


def test_attendance_calculation():
    """Test attendance calculation task"""
    print("\n" + "="*60)
    print("Testing Attendance Calculation Task...")
    print("="*60)
    
    try:
        # Run attendance calculation
        result = calculate_daily_attendance()
        print("✓ Attendance calculation completed")
        print(f"  Date: {result.get('date')}")
        print(f"  Total employees: {result.get('total_employees')}")
        print(f"  Processed: {result.get('processed')}")
        print(f"  Created: {result.get('created')}")
        print(f"  Updated: {result.get('updated')}")
        print(f"  Skipped: {result.get('skipped')}")
        return True
        
    except Exception as e:
        print(f"✗ Attendance calculation failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


def test_location_reminder():
    """Test location reminder task"""
    print("\n" + "="*60)
    print("Testing Location Reminder Task...")
    print("="*60)
    
    try:
        # Run location reminder
        result = send_location_reminder()
        print("✓ Location reminder completed")
        print(f"  Status: {result.get('status')}")
        
        if result.get('status') == 'skipped':
            print(f"  Reason: {result.get('reason')}")
            print(f"  Current time: {result.get('current_time')}")
        else:
            print(f"  Total employees: {result.get('total_employees')}")
            print(f"  Reminders needed: {result.get('reminders_needed')}")
        
        return True
        
    except Exception as e:
        print(f"✗ Location reminder failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


def test_cleanup():
    """Test cleanup task"""
    print("\n" + "="*60)
    print("Testing Cleanup Task...")
    print("="*60)
    
    try:
        # Run cleanup
        result = cleanup_old_locations()
        print("✓ Cleanup completed")
        print(f"  Status: {result.get('status')}")
        print(f"  Deleted count: {result.get('deleted_count')}")
        print(f"  Retention days: {result.get('retention_days')}")
        return True
        
    except Exception as e:
        print(f"✗ Cleanup failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


def test_async_execution():
    """Test async task execution"""
    print("\n" + "="*60)
    print("Testing Async Task Execution...")
    print("="*60)
    
    try:
        # Queue task asynchronously
        task = test_task.delay()
        print(f"✓ Task queued successfully")
        print(f"  Task ID: {task.id}")
        print(f"  Status: {task.status}")
        
        # Wait for result (with timeout)
        result = task.get(timeout=10)
        print(f"✓ Task completed")
        print(f"  Result: {result}")
        return True
        
    except Exception as e:
        print(f"✗ Async execution failed: {str(e)}")
        print("  Make sure Celery worker is running")
        return False


def main():
    """Run all tests"""
    print("\n" + "="*60)
    print("Genesis Employee Attendance - Celery Test Suite")
    print("="*60)
    print(f"Time: {timezone.now()}")
    print(f"Timezone: {timezone.get_current_timezone()}")
    
    tests = [
        ("Celery Connection", test_celery_connection),
        ("Simple Task", test_simple_task),
        ("Attendance Calculation", test_attendance_calculation),
        ("Location Reminder", test_location_reminder),
        ("Cleanup Task", test_cleanup),
    ]
    
    # Only test async if worker is available
    if test_celery_connection():
        tests.append(("Async Execution", test_async_execution))
    
    results = []
    for name, test_func in tests:
        try:
            success = test_func()
            results.append((name, success))
        except Exception as e:
            print(f"\n✗ Test '{name}' crashed: {str(e)}")
            results.append((name, False))
    
    # Print summary
    print("\n" + "="*60)
    print("Test Summary")
    print("="*60)
    
    for name, success in results:
        status = "✓ PASS" if success else "✗ FAIL"
        print(f"{status}: {name}")
    
    passed = sum(1 for _, success in results if success)
    total = len(results)
    print(f"\nTotal: {passed}/{total} tests passed")
    
    print("\n" + "="*60)
    print("Test suite completed!")
    print("="*60 + "\n")
    
    return passed == total


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
