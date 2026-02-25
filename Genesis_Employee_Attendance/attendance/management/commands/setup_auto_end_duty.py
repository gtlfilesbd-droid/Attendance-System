"""
Create or ensure the auto-end-duty-sessions periodic task exists in the database.
Use when Celery Beat runs with DatabaseScheduler (django_celery_beat).
Run once: python manage.py setup_auto_end_duty
Or in Docker: docker compose exec web python manage.py setup_auto_end_duty
"""
from django.core.management.base import BaseCommand
from django_celery_beat.models import PeriodicTask, IntervalSchedule, PeriodicTasks


class Command(BaseCommand):
    help = "Ensure 'auto-end-duty-sessions' periodic task exists (every 5 min) for DatabaseScheduler."

    def handle(self, *args, **options):
        schedule, _ = IntervalSchedule.objects.get_or_create(
            every=5,
            period=IntervalSchedule.MINUTES,
        )
        task, created = PeriodicTask.objects.update_or_create(
            name="auto-end-duty-sessions",
            defaults={
                "task": "attendance.auto_end_duty_sessions",
                "interval": schedule,
                "enabled": True,
            },
        )
        PeriodicTasks.changed(task)
        if created:
            self.stdout.write(self.style.SUCCESS("Created periodic task: auto-end-duty-sessions (every 5 min)."))
        else:
            self.stdout.write(self.style.SUCCESS("Updated periodic task: auto-end-duty-sessions (every 5 min)."))
        self.stdout.write("Restart celery-beat container so it picks up the schedule: docker compose restart celery-beat")
