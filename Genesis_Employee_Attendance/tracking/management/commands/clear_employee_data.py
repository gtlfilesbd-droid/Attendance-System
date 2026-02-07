"""
Management command to delete attendance and location data for one or more employees.

Usage:
  python manage.py clear_employee_data --employee=<UUID> [--employee=<UUID> ...]
  python manage.py clear_employee_data --all
  python manage.py clear_employee_data --all --dry-run

With Docker:
  docker compose exec web python manage.py clear_employee_data --all
"""
import uuid
from django.core.management.base import BaseCommand
from employees.models import Employee
from attendance.models import Attendance
from tracking.models import LocationLog


class Command(BaseCommand):
    help = (
        "Delete all Attendance and LocationLog records for specified employee(s). "
        "Use --employee=<UUID> (repeat for multiple) or --all. Use --dry-run to only print what would be deleted."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--employee",
            action="append",
            dest="employee_ids",
            metavar="UUID",
            help="Employee UUID. Can be repeated for multiple employees.",
        )
        parser.add_argument(
            "--all",
            action="store_true",
            help="Clear data for all active employees.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Only print what would be deleted; do not delete.",
        )

    def handle(self, *args, **options):
        employee_ids = options.get("employee_ids") or []
        clear_all = options.get("all", False)
        dry_run = options.get("dry_run", False)

        if not employee_ids and not clear_all:
            self.stderr.write(
                self.style.ERROR(
                    "Must specify at least one --employee=<UUID> or --all."
                )
            )
            return

        if employee_ids and clear_all:
            self.stderr.write(
                self.style.ERROR("Use either --employee or --all, not both.")
            )
            return

        if dry_run:
            self.stdout.write(self.style.WARNING("DRY RUN - no data will be deleted."))

        # Resolve employees
        if clear_all:
            employees = list(Employee.objects.filter(is_active=True))
            if not employees:
                self.stdout.write(self.style.WARNING("No active employees found."))
                return
        else:
            employees = []
            for eid in employee_ids:
                try:
                    eid_parsed = uuid.UUID(eid)
                except ValueError:
                    self.stderr.write(
                        self.style.ERROR(f"Invalid UUID: {eid}")
                    )
                    continue
                try:
                    emp = Employee.objects.get(id=eid_parsed)
                    employees.append(emp)
                except Employee.DoesNotExist:
                    self.stderr.write(
                        self.style.ERROR(f"Employee not found: {eid}")
                    )

        if not employees:
            self.stderr.write(self.style.ERROR("No valid employees to process."))
            return

        total_attendance_deleted = 0
        total_location_deleted = 0

        for emp in employees:
            att_qs = Attendance.objects.filter(employee=emp)
            loc_qs = LocationLog.objects.filter(employee=emp)
            att_count = att_qs.count()
            loc_count = loc_qs.count()

            if dry_run:
                self.stdout.write(
                    f"Would delete {att_count} attendance, {loc_count} location logs for {emp.name} ({emp.email})"
                )
            else:
                att_qs.delete()
                loc_qs.delete()
                self.stdout.write(
                    self.style.SUCCESS(
                        f"Deleted {att_count} attendance, {loc_count} location logs for {emp.name} ({emp.email})"
                    )
                )
            total_attendance_deleted += att_count
            total_location_deleted += loc_count

        if dry_run:
            self.stdout.write(
                self.style.WARNING(
                    f"Would delete total: {total_attendance_deleted} attendance, {total_location_deleted} location logs."
                )
            )
        else:
            self.stdout.write(
                self.style.SUCCESS(
                    f"Done. Total deleted: {total_attendance_deleted} attendance, {total_location_deleted} location logs."
                )
            )
