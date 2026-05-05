"""
Safely clean up ABSENT Attendance rows that were auto-created by the old Django Admin
"ABSENT filter materialize" behavior.

Default is DRY-RUN (no deletions). Use --apply to actually delete.

Targets only rows with:
- status = 'ABSENT'
- remarks = 'Auto-marked absent (admin filter)'

And deletes them only when they are clearly wrong:
- date is in the future, OR
- a DutySession exists for the same employee+date, OR
- employee is on leave that day (LeaveAssignment coverage OR Attendance(status='LEAVE'))

Run:
  python manage.py cleanup_auto_absent
  python manage.py cleanup_auto_absent --apply
  python manage.py cleanup_auto_absent --days 31 --apply
"""

from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Exists, OuterRef, Q
from django.utils import timezone

from attendance.models import Attendance, DutySession


class Command(BaseCommand):
    help = "Dry-run cleanup for auto-created ABSENT rows from admin filter materialization."

    def add_arguments(self, parser):
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Actually delete rows (otherwise dry-run).",
        )
        parser.add_argument(
            "--days",
            type=int,
            default=31,
            help="Limit scan to last N days up to today (default: 31).",
        )
        parser.add_argument(
            "--include-future",
            action="store_true",
            help="Also scan future dates (still only deletes ABSENT rows that match safety rules).",
        )

    def handle(self, *args, **options):
        apply = bool(options["apply"])
        days = int(options["days"] or 31)
        include_future = bool(options["include_future"])

        today = timezone.localdate()
        start_date = today - timedelta(days=max(days, 0))
        end_date = today if not include_future else today + timedelta(days=366)

        # Compute leave coverage efficiently via LeaveAssignment table.
        # We avoid importing helpers that may iterate per employee for large sets.
        from attendance.models import LeaveAssignment

        duty_exists = DutySession.objects.filter(
            employee_id=OuterRef("employee_id"),
            date=OuterRef("date"),
        )
        leave_assignment_exists = LeaveAssignment.objects.filter(
            employee_id=OuterRef("employee_id"),
            start_date__lte=OuterRef("date"),
            end_date__gte=OuterRef("date"),
        )
        leave_att_exists = Attendance.objects.filter(
            employee_id=OuterRef("employee_id"),
            date=OuterRef("date"),
            status="LEAVE",
        )

        base = Attendance.objects.filter(
            status="ABSENT",
            remarks="Auto-marked absent (admin filter)",
            date__gte=start_date,
            date__lte=end_date,
        ).annotate(
            _has_duty=Exists(duty_exists),
            _has_leave_assignment=Exists(leave_assignment_exists),
            _has_leave_att=Exists(leave_att_exists),
        )

        # Only delete when clearly invalid.
        to_delete = base.filter(
            Q(date__gt=today) | Q(_has_duty=True) | Q(_has_leave_assignment=True) | Q(_has_leave_att=True)
        )

        total = to_delete.count()
        self.stdout.write(
            f"Scan window: {start_date} → {end_date} (today={today}). Candidates to delete: {total}."
        )

        if total and not apply:
            sample = list(
                to_delete.values_list("id", "employee__employee_id", "date")[:20]
            )
            self.stdout.write("Dry-run sample (up to 20):")
            for row in sample:
                self.stdout.write(f"  id={row[0]} employee={row[1]} date={row[2]}")
            self.stdout.write("Re-run with --apply to delete.")
            return

        if not total:
            self.stdout.write(self.style.SUCCESS("Nothing to delete."))
            return

        with transaction.atomic():
            deleted = to_delete.delete()
        self.stdout.write(self.style.SUCCESS(f"Deleted: {deleted[0]} row(s)."))

