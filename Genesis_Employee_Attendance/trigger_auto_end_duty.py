#!/usr/bin/env python
"""
One-time trigger for auto_end_duty_sessions (for verification).
Run from project root: python trigger_auto_end_duty.py
Requires: Django env, Redis, and Celery broker configured.
"""
import os
import sys
import django

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from attendance.tasks import auto_end_duty_sessions

if __name__ == "__main__":
    result = auto_end_duty_sessions.delay()
    print("Task triggered. Celery task id:", result.id)
    print("Check Celery worker log for 'Auto-closed duty session' and task result.")
