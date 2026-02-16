from django.test import TestCase
from django.utils import timezone
from datetime import date, time, timedelta
from .models import Attendance, DutySession
from employees.models import Employee, Department, Designation


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


class AttendanceTest(TestCase):
    def setUp(self):
        self.employee = _create_employee()
        today = date.today()
        self.attendance = Attendance.objects.create(
            employee=self.employee,
            date=today,
            status='PRESENT',
            check_in_time=time(9, 0),
            check_out_time=time(17, 30),
            total_locations_logged=10
        )

    def test_attendance_creation(self):
        """Test attendance record creation"""
        self.assertEqual(self.attendance.employee, self.employee)
        self.assertEqual(self.attendance.status, 'PRESENT')
        self.assertIsNotNone(self.attendance.check_in_time)
        self.assertEqual(self.attendance.total_locations_logged, 10)

    def test_attendance_str(self):
        """Test attendance string representation"""
        expected = f"{self.employee.name} - {self.attendance.date} - PRESENT"
        self.assertEqual(str(self.attendance), expected)

    def test_calculate_total_hours(self):
        """Test total hours calculation"""
        self.attendance.calculate_total_hours()
        self.assertAlmostEqual(float(self.attendance.total_hours), 8.5, places=1)


class DutySessionTest(TestCase):
    def setUp(self):
        self.employee = _create_employee()
        today = date.today()
        start_dt = timezone.make_aware(
            timezone.datetime.combine(today, time(9, 0)),
            timezone.get_current_timezone()
        )
        self.session = DutySession.objects.create(
            employee=self.employee,
            date=today,
            start_time=start_dt,
            start_latitude=23.8103,
            start_longitude=90.4125,
            start_address='Office'
        )

    def test_duty_session_creation(self):
        """Test duty session creation"""
        self.assertEqual(self.session.employee, self.employee)
        self.assertIsNotNone(self.session.start_time)
        self.assertEqual(self.session.start_latitude, 23.8103)
        self.assertIsNone(self.session.end_time)

    def test_duty_session_str(self):
        """Test duty session string representation"""
        self.assertIn(self.employee.name, str(self.session))
        self.assertIn(str(self.session.date), str(self.session))
