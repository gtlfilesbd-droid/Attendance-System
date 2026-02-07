"""
Link existing Employee records to Django User accounts.

Creates a User for each Employee that has no user (username=employee_id)
and links them. Use after adding the Employee.user OneToOneField.

Usage:
  python manage.py link_employees_to_users
  python manage.py link_employees_to_users --password 'YourDefaultPassword'
  python manage.py link_employees_to_users --dry-run
"""
from django.contrib.auth.models import User
from django.core.management.base import BaseCommand

from employees.models import Employee


class Command(BaseCommand):
    help = "Create or link Django User for each Employee (for dashboard login)."

    def add_arguments(self, parser):
        parser.add_argument(
            '--password',
            type=str,
            default='Test@123',
            help='Default password for newly created User accounts (default: Test@123)',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Only print what would be done, do not save.',
        )

    def handle(self, *args, **options):
        password = options['password']
        dry_run = options['dry_run']
        if dry_run:
            self.stdout.write(self.style.WARNING('DRY RUN - no changes will be saved'))

        for emp in Employee.objects.all():
            if emp.user_id:
                self.stdout.write(f'Already linked: {emp.employee_id} -> user id={emp.user_id}')
                continue

            user, created = User.objects.get_or_create(
                username=emp.employee_id,
                defaults={
                    'email': emp.email,
                    'first_name': (emp.name.split()[0] if emp.name else '')[:150],
                    'last_name': (emp.name.split(maxsplit=1)[1] if len(emp.name.split()) > 1 else '')[:150],
                },
            )
            if created:
                user.set_password(password)
                if not dry_run:
                    user.save()
                self.stdout.write(self.style.SUCCESS(f'Created user {user.username} and linked to {emp.employee_id}'))
            else:
                self.stdout.write(f'Linking existing user {user.username} to {emp.employee_id}')

            if not dry_run:
                emp.user = user
                emp.save()

        self.stdout.write(self.style.SUCCESS('Done.'))
