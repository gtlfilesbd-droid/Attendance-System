"""
Remove the Locust dummy test employee.

Usage:
  python manage.py remove_locust_test_user
  docker compose exec web python manage.py remove_locust_test_user
"""
from django.core.management.base import BaseCommand

from employees.models import Employee


LOCUST_TEST_EMAIL = "locust-test@genesis.local"


class Command(BaseCommand):
    help = "Remove the dummy Locust test employee (locust-test@genesis.local)."

    def handle(self, *args, **options):
        deleted, _ = Employee.objects.filter(email=LOCUST_TEST_EMAIL).delete()
        if deleted:
            self.stdout.write(self.style.SUCCESS(f"Removed Locust test user: {LOCUST_TEST_EMAIL}"))
        else:
            self.stdout.write(self.style.WARNING(f"No user found with email: {LOCUST_TEST_EMAIL}"))
