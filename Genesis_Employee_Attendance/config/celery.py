"""
Celery configuration for Genesis Employee Attendance System
"""
import os
from celery import Celery
from decouple import config

# Set the default Django settings module for the 'celery' program.
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

# Initialize Celery app with Redis as broker
app = Celery(
    'genesis_attendance',
    broker=config('CELERY_BROKER_URL', default='redis://localhost:6379/0'),
    backend=config('CELERY_RESULT_BACKEND', default='redis://localhost:6379/0')
)

# Load configuration from Django settings
app.config_from_object('django.conf:settings', namespace='CELERY')

# Configure Celery settings
app.conf.update(
    timezone='Asia/Dhaka',  # Set timezone to Asia/Dhaka
    enable_utc=False,  # Use local time
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    task_track_started=True,
    task_time_limit=30 * 60,  # 30 minutes
    worker_prefetch_multiplier=1,
    worker_max_tasks_per_child=1000,
)

# Load task modules from all registered Django apps.
app.autodiscover_tasks()


@app.task(bind=True, ignore_result=True)
def debug_task(self):
    """Debug task for testing Celery setup"""
    print(f'Request: {self.request!r}')
