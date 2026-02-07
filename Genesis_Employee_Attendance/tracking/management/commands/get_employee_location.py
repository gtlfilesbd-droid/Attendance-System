"""
Get the latest location for an employee by email (for app-connected users).

Usage:
  python manage.py get_employee_location <email>
  docker compose exec web python manage.py get_employee_location it@gel.com.bd
"""
from django.core.management.base import BaseCommand
from django.utils import timezone

from employees.models import Employee
from tracking.models import LocationLog


class Command(BaseCommand):
    help = "Print the latest location for an employee by email (app login)."

    def add_arguments(self, parser):
        parser.add_argument('email', type=str, help='Employee email (e.g. it@gel.com.bd)')

    def handle(self, *args, **options):
        email = options['email'].strip()

        try:
            employee = Employee.objects.get(email=email)
        except Employee.DoesNotExist:
            self.stdout.write(self.style.ERROR(f'No employee with email "{email}".'))
            return

        latest = (
            LocationLog.objects.filter(employee=employee)
            .order_by('-timestamp')
            .first()
        )

        if not latest:
            self.stdout.write(
                self.style.WARNING(
                    f'No location logged yet for {employee.email} ({employee.employee_id} - {employee.name}).'
                )
            )
            self.stdout.write('They need to open the app, tap Start Duty, and wait for a location send.')
            return

        self.stdout.write(self.style.SUCCESS(f'Latest location for {employee.email} ({employee.employee_id} - {employee.name}):'))
        self.stdout.write(f'  Latitude:  {latest.latitude}')
        self.stdout.write(f'  Longitude: {latest.longitude}')
        self.stdout.write(f'  Time:     {latest.timestamp} ({timezone.localtime(latest.timestamp)})')
        self.stdout.write(f'  Accuracy: {latest.accuracy} m')
        self.stdout.write(f'  Battery:  {latest.battery_level}%')
        if latest.address:
            self.stdout.write(f'  Address:  {latest.address}')
