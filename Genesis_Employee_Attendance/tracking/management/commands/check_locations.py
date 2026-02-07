"""
Management command to check if location logs are saved in the database.

Use this to debug: if the mobile app is logging but the dashboard shows nothing,
run this to see if locations are actually in the DB.

Usage:
  python manage.py check_locations
  docker compose exec web python manage.py check_locations

If total_logs and today_logs are 0: the mobile app is NOT saving data (check auth/API).
If counts are > 0: locations are saved; run run_attendance_today to update Present count,
and ensure you are logged in to the dashboard as admin to see Live Tracking.
"""
from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import timedelta


class Command(BaseCommand):
    help = "Check LocationLog counts (total, today, last 15 min). Use to debug dashboard not showing locations."

    def handle(self, *args, **options):
        from tracking.models import LocationLog

        total_logs = LocationLog.objects.count()
        self.stdout.write(f"Total location logs in database: {total_logs}")

        today = timezone.now().date()
        today_logs = LocationLog.objects.filter(timestamp__date=today)
        today_count = today_logs.count()
        self.stdout.write(f"Today's location logs: {today_count}")

        last_locations = LocationLog.objects.all().order_by("-timestamp")[:5]
        for loc in last_locations:
            self.stdout.write(
                f"  {loc.employee.name}: {loc.latitude}, {loc.longitude} at {loc.timestamp}"
            )

        recent = timezone.now() - timedelta(minutes=15)
        recent_logs = LocationLog.objects.filter(timestamp__gte=recent)
        recent_count = recent_logs.count()
        self.stdout.write(f"Locations in last 15 minutes: {recent_count}")

        if total_logs == 0:
            self.stdout.write(
                self.style.WARNING(
                    "No locations in DB. Mobile app may not be saving (check auth, baseUrl, backend logs)."
                )
            )
        else:
            self.stdout.write(
                self.style.SUCCESS(
                    "Locations exist. For Present count: run 'python manage.py run_attendance_today'. "
                    "For Live Map: open dashboard as admin and go to Live Tracking."
                )
            )
