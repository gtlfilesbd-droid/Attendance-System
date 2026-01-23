from django.test import TestCase
from django.contrib.auth import get_user_model
from .models import Employee, Department, WorkShift, EmployeeShift
from datetime import time, date

Employee = get_user_model()


class EmployeeModelTest(TestCase):
    def setUp(self):
        self.employee = Employee.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123',
            employee_id='EMP001',
            first_name='Test',
            last_name='User',
            department='IT',
            role='STAFF',
            designation='Developer'
        )
    
    def test_employee_creation(self):
        """Test employee creation"""
        self.assertEqual(self.employee.username, 'testuser')
        self.assertEqual(self.employee.employee_id, 'EMP001')
        self.assertEqual(self.employee.get_full_name(), 'Test User')
    
    def test_employee_str(self):
        """Test employee string representation"""
        expected = f"EMP001 - Test User"
        self.assertEqual(str(self.employee), expected)


class DepartmentModelTest(TestCase):
    def setUp(self):
        self.department = Department.objects.create(
            name='Information Technology',
            code='IT',
            description='IT Department'
        )
    
    def test_department_creation(self):
        """Test department creation"""
        self.assertEqual(self.department.name, 'Information Technology')
        self.assertEqual(self.department.code, 'IT')
    
    def test_department_str(self):
        """Test department string representation"""
        expected = "IT - Information Technology"
        self.assertEqual(str(self.department), expected)


class WorkShiftModelTest(TestCase):
    def setUp(self):
        self.shift = WorkShift.objects.create(
            name='Morning Shift',
            start_time=time(9, 0),
            end_time=time(17, 0),
            description='9 AM to 5 PM'
        )
    
    def test_shift_creation(self):
        """Test work shift creation"""
        self.assertEqual(self.shift.name, 'Morning Shift')
        self.assertEqual(self.shift.start_time, time(9, 0))
        self.assertEqual(self.shift.end_time, time(17, 0))
    
    def test_shift_str(self):
        """Test shift string representation"""
        expected = "Morning Shift (09:00:00 - 17:00:00)"
        self.assertEqual(str(self.shift), expected)
