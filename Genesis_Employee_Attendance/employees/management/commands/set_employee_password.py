"""
Set or reset an employee's password by email (for app login).

Usage:
  python manage.py set_employee_password <email> <password>
  docker compose exec web python manage.py set_employee_password ashraf.anam@gel.com.bd 'Open@4321'
"""
from django.core.management.base import BaseCommand

from employees.models import Employee


class Command(BaseCommand):
    help = "Set an employee's password by email (for mobile app login)."

    def add_arguments(self, parser):
        parser.add_argument('email', type=str, help='Employee email')
        parser.add_argument('password', type=str, help='New password')

    def handle(self, *args, **options):
        email = options['email'].strip()
        password = options['password']

        try:
            employee = Employee.objects.get(email=email)
        except Employee.DoesNotExist:
            self.stdout.write(self.style.ERROR(f'No employee with email "{email}".'))
            self.stdout.write('Create the employee in Django Admin first, then run this command.')
            return

        employee.set_password(password)
        employee.save()
        self.stdout.write(self.style.SUCCESS(f'Password updated for {employee.email} ({employee.employee_id} - {employee.name}).'))
        self.stdout.write('The employee can now log in to the app with this email and password.')
