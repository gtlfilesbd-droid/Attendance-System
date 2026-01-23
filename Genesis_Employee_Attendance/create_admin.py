#!/usr/bin/env python
"""
Script to create admin user and first employee for Genesis Employee Attendance System
Run this inside Docker container: docker compose exec web python create_admin.py
"""
import os
import sys
import django
from pathlib import Path
from datetime import date

# Add the project directory to Python path
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from employees.models import Employee

User = get_user_model()


def create_admin_user():
    """Create Django superuser for admin access"""
    username = os.getenv('ADMIN_USERNAME', 'admin')
    email = os.getenv('ADMIN_EMAIL', 'admin@genesis.com')
    password = os.getenv('ADMIN_PASSWORD', 'admin123')
    
    if User.objects.filter(username=username).exists():
        print(f"✓ Admin user '{username}' already exists")
        return User.objects.get(username=username)
    
    print(f"Creating admin user: {username}")
    admin = User.objects.create_superuser(
        username=username,
        email=email,
        password=password
    )
    print(f"✓ Admin user created successfully!")
    print(f"  Username: {username}")
    print(f"  Email: {email}")
    print(f"  Password: {password}")
    print(f"\n⚠️  IMPORTANT: Change the password after first login!")
    return admin


def create_first_employee():
    """Create first employee for testing"""
    employee_id = 'EMP001'
    
    if Employee.objects.filter(employee_id=employee_id).exists():
        print(f"✓ Employee '{employee_id}' already exists")
        return Employee.objects.get(employee_id=employee_id)
    
    print(f"\nCreating first employee: {employee_id}")
    employee = Employee.objects.create(
        employee_id=employee_id,
        name='John Doe',
        email='john.doe@genesis.com',
        phone='+1234567890',
        password='employee123',  # Will be hashed automatically
        department='IT',
        designation='Software Developer',
        join_date=date.today(),
        is_active=True
    )
    print(f"✓ Employee created successfully!")
    print(f"  Employee ID: {employee.employee_id}")
    print(f"  Name: {employee.name}")
    print(f"  Email: {employee.email}")
    print(f"  Password: employee123")
    print(f"\n⚠️  IMPORTANT: Change the password after first login!")
    return employee


def main():
    """Main function"""
    print("\n" + "="*60)
    print("Genesis Employee Attendance - First Time Setup")
    print("="*60 + "\n")
    
    try:
        # Create admin user
        admin = create_admin_user()
        
        # Create first employee
        employee = create_first_employee()
        
        print("\n" + "="*60)
        print("Setup Complete!")
        print("="*60)
        print("\n📋 Login Credentials:")
        print("\n1. Django Admin Panel:")
        print(f"   URL: http://localhost:8000/admin/")
        print(f"   Username: {admin.username}")
        print(f"   Password: admin123 (or your ADMIN_PASSWORD)")
        
        print("\n2. Employee Login (API):")
        print(f"   Email: {employee.email}")
        print(f"   Password: employee123")
        print(f"   API: http://localhost:8000/api/auth/token/")
        
        print("\n3. Web Dashboard:")
        print(f"   URL: http://localhost:8000/dashboard/")
        print(f"   Use admin credentials to login")
        
        print("\n" + "="*60)
        print("Next Steps:")
        print("1. Login to admin panel and change default passwords")
        print("2. Create more employees via admin panel or API")
        print("3. Test location tracking via API")
        print("4. View live tracking on dashboard")
        print("="*60 + "\n")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
