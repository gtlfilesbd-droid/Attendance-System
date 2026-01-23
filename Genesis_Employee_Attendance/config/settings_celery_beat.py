"""
Celery Beat Schedule Configuration
"""
from celery.schedules import crontab

CELERY_BEAT_SCHEDULE = {
    # Attendance Tasks
    'mark-absent-employees': {
        'task': 'attendance.tasks.mark_absent_employees',
        'schedule': crontab(hour=23, minute=59),  # Run at 11:59 PM daily
    },
    'check-late-arrivals': {
        'task': 'attendance.tasks.check_late_arrivals',
        'schedule': crontab(hour='*/1'),  # Run every hour
    },
    'calculate-daily-hours': {
        'task': 'attendance.tasks.calculate_daily_hours',
        'schedule': crontab(hour=1, minute=0),  # Run at 1:00 AM daily
    },
    'send-attendance-reminders': {
        'task': 'attendance.tasks.send_attendance_reminders',
        'schedule': crontab(hour=10, minute=0),  # Run at 10:00 AM daily
    },
    'generate-attendance-reports': {
        'task': 'attendance.tasks.generate_attendance_reports',
        'schedule': crontab(day_of_month=1, hour=2, minute=0),  # First day of month at 2 AM
    },
    
    # Tracking Tasks
    'process-geofence-events': {
        'task': 'tracking.tasks.process_geofence_events',
        'schedule': crontab(minute='*/10'),  # Run every 10 minutes
    },
    'calculate-employee-movements': {
        'task': 'tracking.tasks.calculate_employee_movements',
        'schedule': crontab(hour=2, minute=0),  # Run at 2:00 AM daily
    },
    'generate-daily-routes': {
        'task': 'tracking.tasks.generate_daily_routes',
        'schedule': crontab(hour=3, minute=0),  # Run at 3:00 AM daily
    },
    'cleanup-old-location-points': {
        'task': 'tracking.tasks.cleanup_old_location_points',
        'schedule': crontab(day_of_week=0, hour=4, minute=0),  # Every Sunday at 4 AM
    },
    'detect-location-anomalies': {
        'task': 'tracking.tasks.detect_location_anomalies',
        'schedule': crontab(minute='*/30'),  # Run every 30 minutes
    },
}
