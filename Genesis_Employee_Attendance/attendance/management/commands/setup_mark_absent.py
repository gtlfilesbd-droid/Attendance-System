"""
Create or ensure the mark-absent-employees periodic task exists in the database.

This project runs Celery Beat with DatabaseScheduler (django_celery_beat), so
CELERY_BEAT_SCHEDULE entries in settings are ignored unless registered in DB.

Run once:
  python manage.py setup_mark_absent

Docker:
  docker exec -i genesis_employee_attendance-web-1 python manage.py setup_mark_absent
Then restart beat:
  docker compose restart celery-beat
"""

from django.core.management.base import BaseCommand
from django_celery_beat.models import CrontabSchedule, PeriodicTask, PeriodicTasks


class Command(BaseCommand):
    help = "Ensure 'mark-absent-employees' periodic task exists (00:30 Asia/Dhaka) for DatabaseScheduler."

    def add_arguments(self, parser):
        parser.add_argument("--hour", type=int, default=0, help="Hour (0-23). Default: 0")
        parser.add_argument("--minute", type=int, default=30, help="Minute (0-59). Default: 30")
        parser.add_argument("--disable", action="store_true", help="Create/update the task but set enabled=False.")

    def handle(self, *args, **options):
        hour = int(options["hour"])
        minute = int(options["minute"])
        disable = bool(options["disable"])

        if hour < 0 or hour > 23:
            raise ValueError("--hour must be between 0 and 23")
        if minute < 0 or minute > 59:
            raise ValueError("--minute must be between 0 and 59")

        # Keep timezone aligned with existing DB schedules (Asia/Dhaka).
        cron, _ = CrontabSchedule.objects.get_or_create(
            minute=str(minute),
            hour=str(hour),
            day_of_week="*",
            day_of_month="*",
            month_of_year="*",
            timezone="Asia/Dhaka",
        )

        task, created = PeriodicTask.objects.update_or_create(
            name="mark-absent-employees",
            defaults={
                "task": "attendance.tasks.mark_absent_employees",
                "crontab": cron,
                "enabled": (not disable),
            },
        )
        PeriodicTasks.changed(task)

        if created:
            self.stdout.write(
                self.style.SUCCESS(
                    f"Created periodic task: mark-absent-employees ({hour:02d}:{minute:02d} Asia/Dhaka)."
                )
            )
        else:
            self.stdout.write(
                self.style.SUCCESS(
                    f"Updated periodic task: mark-absent-employees ({hour:02d}:{minute:02d} Asia/Dhaka)."
                )
            )
        self.stdout.write("Restart celery-beat container so it picks up the schedule: docker compose restart celery-beat")

