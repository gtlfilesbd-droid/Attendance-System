"""
Create a dummy employee for Locust load testing only.

Usage:
  python manage.py create_locust_test_user
  docker compose exec web python manage.py create_locust_test_user

Credentials created:
  Email: locust-test@genesis.local
  Password: LocustTestPass123

Remove after testing with: python manage.py remove_locust_test_user
"""
from datetime import date

from django.core.management.base import BaseCommand

from employees.models import Employee


LOCUST_TEST_EMAIL = "locust-test@genesis.local"
LOCUST_TEST_PASSWORD = "LocustTestPass123"
LOCUST_EMPLOYEE_ID = "LOCUST-TEST"


class Command(BaseCommand):
    help = "Create a dummy employee for Locust load testing (remove after test with remove_locust_test_user)."

    def handle(self, *args, **options):
        if Employee.objects.filter(email=LOCUST_TEST_EMAIL).exists():
            self.stdout.write(
                self.style.WARNING(
                    f'Locust test user already exists: {LOCUST_TEST_EMAIL}. '
                    'Use remove_locust_test_user first to recreate.'
                )
            )
            return

        emp = Employee(
            employee_id=LOCUST_EMPLOYEE_ID,
            name="Locust Test User",
            email=LOCUST_TEST_EMAIL,
            phone="+0000000000",
            join_date=date.today(),
            is_active=True,
        )
        emp.set_password(LOCUST_TEST_PASSWORD)
        emp.save()

        self.stdout.write(
            self.style.SUCCESS(
                f"Locust test user created: {LOCUST_TEST_EMAIL} / {LOCUST_TEST_PASSWORD}"
            )
        )
        self.stdout.write("Run load test, then: python manage.py remove_locust_test_user")
