from django.test import TestCase
from .models import Employee, Department, Designation
from datetime import date


def _create_employee(employee_id='EMP001', name='Test User', email='test@example.com',
                     department=None, designation=None, **kwargs):
    """Helper to create an Employee with required fields."""
    defaults = {
        'employee_id': employee_id,
        'name': name,
        'email': email,
        'phone': '+8801234567890',
        'password': 'testpass123',
        'join_date': date.today(),
        'department': department,
        'designation': designation,
        **kwargs
    }
    emp = Employee(**defaults)
    emp.set_password(defaults['password'])
    emp.save()
    return emp


class DepartmentModelTest(TestCase):
    def setUp(self):
        self.department = Department.objects.create(
            name='Information Technology',
            description='IT Department',
            is_active=True
        )

    def test_department_creation(self):
        """Test department creation"""
        self.assertEqual(self.department.name, 'Information Technology')
        self.assertEqual(self.department.description, 'IT Department')
        self.assertTrue(self.department.is_active)

    def test_department_str(self):
        """Test department string representation"""
        self.assertEqual(str(self.department), 'Information Technology')


class DesignationModelTest(TestCase):
    def setUp(self):
        self.designation = Designation.objects.create(
            name='Developer',
            description='Software developer',
            is_active=True
        )

    def test_designation_creation(self):
        """Test designation creation"""
        self.assertEqual(self.designation.name, 'Developer')
        self.assertTrue(self.designation.is_active)

    def test_designation_str(self):
        """Test designation string representation"""
        self.assertEqual(str(self.designation), 'Developer')


class EmployeeModelTest(TestCase):
    def setUp(self):
        self.department = Department.objects.create(name='IT', description='IT Dept')
        self.designation = Designation.objects.create(name='Developer')
        self.employee = _create_employee(
            employee_id='EMP001',
            name='Test User',
            email='test@example.com',
            department=self.department,
            designation=self.designation
        )

    def test_employee_creation(self):
        """Test employee creation"""
        self.assertEqual(self.employee.employee_id, 'EMP001')
        self.assertEqual(self.employee.name, 'Test User')
        self.assertEqual(self.employee.email, 'test@example.com')
        self.assertEqual(self.employee.department, self.department)
        self.assertEqual(self.employee.designation, self.designation)

    def test_employee_str(self):
        """Test employee string representation"""
        self.assertEqual(str(self.employee), 'EMP001 - Test User')

    def test_employee_password_check(self):
        """Test password hashing and verification"""
        self.assertTrue(self.employee.check_password('testpass123'))
        self.assertFalse(self.employee.check_password('wrong'))
