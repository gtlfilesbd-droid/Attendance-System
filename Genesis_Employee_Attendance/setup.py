#!/usr/bin/env python
"""
Setup script for Genesis Employee Attendance System
"""
import os
import sys
import django
from pathlib import Path

# Add the project directory to Python path
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.core.management import call_command
from django.contrib.auth import get_user_model
from employees.models import Employee, Department, WorkShift
from datetime import time


def create_superuser():
    """Create a superuser if it doesn't exist"""
    User = get_user_model()
    
    if not User.objects.filter(username='admin').exists():
        print("Creating superuser...")
        User.objects.create_superuser(
            username='admin',
            email='admin@genesis.com',
            password='admin123',
            employee_id='EMP001',
            first_name='System',
            last_name='Administrator',
            department='IT',
            role='ADMIN',
            designation='System Administrator'
        )
        print("✓ Superuser created (username: admin, password: admin123)")
    else:
        print("✓ Superuser already exists")


def create_departments():
    """Create default departments"""
    departments_data = [
        {'name': 'Information Technology', 'code': 'IT', 'description': 'IT Department'},
        {'name': 'Human Resources', 'code': 'HR', 'description': 'HR Department'},
        {'name': 'Finance', 'code': 'FIN', 'description': 'Finance Department'},
        {'name': 'Operations', 'code': 'OPS', 'description': 'Operations Department'},
        {'name': 'Marketing', 'code': 'MKT', 'description': 'Marketing Department'},
        {'name': 'Sales', 'code': 'SLS', 'description': 'Sales Department'},
    ]
    
    print("Creating departments...")
    for dept_data in departments_data:
        dept, created = Department.objects.get_or_create(
            code=dept_data['code'],
            defaults={
                'name': dept_data['name'],
                'description': dept_data['description']
            }
        )
        if created:
            print(f"  ✓ Created department: {dept.name}")
        else:
            print(f"  - Department already exists: {dept.name}")


def create_work_shifts():
    """Create default work shifts"""
    shifts_data = [
        {'name': 'Morning Shift', 'start_time': time(9, 0), 'end_time': time(17, 0), 'description': '9 AM to 5 PM'},
        {'name': 'Evening Shift', 'start_time': time(14, 0), 'end_time': time(22, 0), 'description': '2 PM to 10 PM'},
        {'name': 'Night Shift', 'start_time': time(22, 0), 'end_time': time(6, 0), 'description': '10 PM to 6 AM'},
    ]
    
    print("Creating work shifts...")
    for shift_data in shifts_data:
        shift, created = WorkShift.objects.get_or_create(
            name=shift_data['name'],
            defaults={
                'start_time': shift_data['start_time'],
                'end_time': shift_data['end_time'],
                'description': shift_data['description']
            }
        )
        if created:
            print(f"  ✓ Created shift: {shift.name}")
        else:
            print(f"  - Shift already exists: {shift.name}")


def main():
    """Main setup function"""
    print("\n" + "="*60)
    print("Genesis Employee Attendance System - Setup")
    print("="*60 + "\n")
    
    # Run migrations
    print("Running database migrations...")
    try:
        call_command('migrate', verbosity=0)
        print("✓ Migrations completed\n")
    except Exception as e:
        print(f"✗ Migration failed: {e}\n")
        return
    
    # Create superuser
    try:
        create_superuser()
        print()
    except Exception as e:
        print(f"✗ Failed to create superuser: {e}\n")
    
    # Create departments
    try:
        create_departments()
        print()
    except Exception as e:
        print(f"✗ Failed to create departments: {e}\n")
    
    # Create work shifts
    try:
        create_work_shifts()
        print()
    except Exception as e:
        print(f"✗ Failed to create work shifts: {e}\n")
    
    # Collect static files
    print("Collecting static files...")
    try:
        call_command('collectstatic', '--noinput', verbosity=0)
        print("✓ Static files collected\n")
    except Exception as e:
        print(f"✗ Failed to collect static files: {e}\n")
    
    print("="*60)
    print("Setup completed successfully!")
    print("="*60)
    print("\nNext steps:")
    print("1. Copy env.example to .env and update with your settings")
    print("2. Make sure PostgreSQL with PostGIS is running")
    print("3. Run: python manage.py runserver")
    print("4. Access admin panel: http://localhost:8000/admin")
    print("   Username: admin")
    print("   Password: admin123")
    print("\nFor production:")
    print("- Change the default admin password")
    print("- Update SECRET_KEY in .env")
    print("- Set DEBUG=False")
    print("- Configure proper database credentials")
    print("="*60 + "\n")


if __name__ == '__main__':
    main()
