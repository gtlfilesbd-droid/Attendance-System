from django.test import TestCase
from django.contrib.gis.geos import Point
from django.utils import timezone
from .models import LocationLog
from employees.models import Employee, Department, Designation
from datetime import date


def _create_employee(employee_id='EMP001', **kwargs):
    """Helper to create an Employee."""
    defaults = {
        'employee_id': employee_id,
        'name': 'Test User',
        'email': f'test{employee_id}@example.com',
        'phone': '+8801234567890',
        'password': 'testpass123',
        'join_date': date.today(),
        **kwargs
    }
    emp = Employee(**defaults)
    emp.set_password('testpass123')
    emp.save()
    return emp


class LocationLogTest(TestCase):
    def setUp(self):
        self.employee = _create_employee()
        self.location = LocationLog.objects.create(
            employee=self.employee,
            location=Point(-122.4194, 37.7749),  # (longitude, latitude)
            timestamp=timezone.now(),
            accuracy=10.5,
            battery_level=85,
            speed=1.2,
            address='123 Main St'
        )

    def test_location_creation(self):
        """Test location log creation"""
        self.assertEqual(self.location.employee, self.employee)
        self.assertIsNotNone(self.location.location)
        self.assertEqual(self.location.accuracy, 10.5)
        self.assertEqual(self.location.battery_level, 85)

    def test_location_coordinates(self):
        """Test latitude/longitude properties"""
        self.assertAlmostEqual(self.location.latitude, 37.7749, places=4)
        self.assertAlmostEqual(self.location.longitude, -122.4194, places=4)

    def test_location_str(self):
        """Test location log string representation"""
        self.assertIn(self.employee.name, str(self.location))
        self.assertIn(str(self.location.timestamp.date()), str(self.location))
