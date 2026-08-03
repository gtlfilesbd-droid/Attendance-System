from django.test import TestCase, Client
from django.contrib.auth.models import User
from django.contrib.gis.geos import Point
from django.urls import reverse
from django.utils import timezone
from datetime import date

from tracking.models import LocationLog
from .models import Employee, Department, Designation


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


class EmployeeAdminDeleteTest(TestCase):
    """Admin employee delete must work even when related location logs exist."""

    def setUp(self):
        self.department = Department.objects.create(name='IT', description='IT Dept')
        self.designation = Designation.objects.create(name='Developer')
        self.employee = _create_employee(
            employee_id='EMP-DEL',
            name='Delete Me',
            email='delete.me@example.com',
            department=self.department,
            designation=self.designation,
        )
        self.linked_user = User.objects.create_user(
            username='linked-emp', password='pass',
        )
        self.employee.user = self.linked_user
        self.employee.save(update_fields=['user'])

        now = timezone.now()
        for i in range(5):
            LocationLog.objects.create(
                employee=self.employee,
                location=Point(90.4125 + i * 0.0001, 23.8103),
                timestamp=now,
                accuracy=10.0,
                battery_level=80,
            )

        self.admin = User.objects.create_superuser(
            username='admin', email='admin@example.com', password='adminpass',
        )
        self.client = Client()
        self.client.force_login(self.admin)

    def test_delete_confirmation_summarizes_location_logs(self):
        url = reverse('admin:employees_employee_delete', args=[self.employee.pk])
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        content = response.content.decode()
        self.assertIn('5 location logs', content)
        self.assertIn('linked Django user (unlinked, not deleted)', content)
        # Must still exist after viewing confirmation
        self.assertTrue(Employee.objects.filter(pk=self.employee.pk).exists())
        self.assertEqual(LocationLog.objects.filter(employee=self.employee).count(), 5)

    def test_admin_can_delete_employee_with_location_logs(self):
        emp_pk = self.employee.pk
        linked_user_id = self.linked_user.pk
        url = reverse('admin:employees_employee_delete', args=[emp_pk])
        response = self.client.post(url, {'post': 'yes'})
        self.assertEqual(response.status_code, 302)
        self.assertFalse(Employee.objects.filter(pk=emp_pk).exists())
        self.assertEqual(LocationLog.objects.filter(employee_id=emp_pk).count(), 0)
        # Linked user is preserved
        self.assertTrue(User.objects.filter(pk=linked_user_id).exists())
