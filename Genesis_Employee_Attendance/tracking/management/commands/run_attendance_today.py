"""
Management command to run today's attendance calculation (for testing).

Normally the Celery task tracking.calculate_daily_attendance runs at 6:45 PM daily.
Use this command to run it immediately so "Present today" and dashboard data appear.

Usage:
  python manage.py run_attendance_today
  docker compose exec web python manage.py run_attendance_today
"""
from django.core.management.base import BaseCommand
from django.utils import timezone


class Command(BaseCommand):
    help = "Run today's attendance calculation from location logs (same as Celery at 6:45 PM). Use for testing."

    def handle(self, *args, **options):
        from tracking.tasks import calculate_daily_attendance

        today = timezone.now().date()
        self.stdout.write(f"Running attendance calculation for {today}...")
        result = calculate_daily_attendance()
        self.stdout.write(self.style.SUCCESS(f"Done: {result}"))
        self.stdout.write(
            "Dashboard 'Present today' and recent activities will now show data for today."
        )
