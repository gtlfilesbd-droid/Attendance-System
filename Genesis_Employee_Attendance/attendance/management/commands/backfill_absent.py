"""
Backfill ABSENT attendance rows for a specific date (safe + optionally dry-run).

Usage:
  python manage.py backfill_absent --date 2026-05-08 --dry-run
  python manage.py backfill_absent --date 2026-05-08 --apply

Rules (same intent as mark_absent_employees):
- Only considers active employees
- Skips if ANY Attendance row exists for that employee+date (present/late/leave/absent)
- Skips if a DutySession exists for that employee+date
- Skips if a LeaveAssignment covers that date
"""

from datetime import date as date_type

from django.core.management.base import BaseCommand
from django.utils.dateparse import parse_date
from django.db import transaction

from attendance.models import Attendance, DutySession, LeaveAssignment
from employees.models import Employee


class Command(BaseCommand):
    help = "Backfill ABSENT Attendance rows for a specific date (dry-run by default)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--date",
            required=True,
            help="Target date (YYYY-MM-DD).",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Do not write to DB; only show what would be created (default behavior).",
        )
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Actually create missing ABSENT rows.",
        )
        parser.add_argument(
            "--sample",
            type=int,
            default=25,
            help="Sample size to print in dry-run (default: 25).",
        )

    def handle(self, *args, **options):
        raw = (options.get("date") or "").strip()
        target_date = parse_date(raw)
        if not isinstance(target_date, date_type):
            raise ValueError("--date must be in YYYY-MM-DD format")

        dry_run = bool(options.get("dry_run")) or (not bool(options.get("apply")))
        sample_n = int(options.get("sample") or 25)

        active_qs = Employee.objects.filter(is_active=True)
        active_count = active_qs.count()

        att_ids = set(
            Attendance.objects.filter(date=target_date).values_list("employee_id", flat=True)
        )
        duty_ids = set(
            DutySession.objects.filter(date=target_date).values_list("employee_id", flat=True)
        )
        leave_ids = set(
            LeaveAssignment.objects.filter(
                start_date__lte=target_date,
                end_date__gte=target_date,
            ).values_list("employee_id", flat=True)
        )
        skip_ids = att_ids | duty_ids | leave_ids

        to_create_qs = active_qs.exclude(id__in=skip_ids).values_list("id", "employee_id")
        to_create = list(to_create_qs)

        self.stdout.write(
            f"Target date: {target_date} | active_employees={active_count} | "
            f"skip(attendance={len(att_ids)}, duty={len(duty_ids)}, leave_assignment={len(leave_ids)}) | "
            f"missing_absent={len(to_create)} | mode={'DRY-RUN' if dry_run else 'APPLY'}"
        )

        if dry_run:
            if to_create and sample_n > 0:
                self.stdout.write(f"Sample (up to {min(sample_n, len(to_create))}) employees to mark ABSENT:")
                for emp_db_id, emp_code in to_create[:sample_n]:
                    self.stdout.write(f"  employee_db_id={emp_db_id} employee_id={emp_code}")
            return

        rows = [
            Attendance(
                employee_id=emp_db_id,
                date=target_date,
                status="ABSENT",
                remarks="Auto-marked absent (backfill)",
            )
            for emp_db_id, _emp_code in to_create
        ]

        if not rows:
            self.stdout.write(self.style.SUCCESS("Nothing to create."))
            return

        with transaction.atomic():
            Attendance.objects.bulk_create(rows, ignore_conflicts=True)

        self.stdout.write(self.style.SUCCESS(f"Created {len(rows)} ABSENT row(s)."))
