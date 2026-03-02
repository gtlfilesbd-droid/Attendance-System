from django.test import TestCase
from django.utils import timezone
from datetime import date, time, timedelta
from .models import Attendance, DutySession
from .tasks import auto_end_duty_sessions
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


class AutoEndDutySessionsPhase1Test(TestCase):
    """Phase 1: 60-min logic uses last_heartbeat_at; session not closed if heartbeat recent."""

    def setUp(self):
        self.employee = _create_employee(employee_id='EMP002')
        today = date.today()
        # Session started 2 hours ago (so > 60 min ago)
        session_start = timezone.now() - timedelta(hours=2)
        if timezone.is_naive(session_start):
            session_start = timezone.make_aware(session_start, timezone.get_current_timezone())
        self.session = DutySession.objects.create(
            employee=self.employee,
            date=today,
            start_time=session_start,
            start_latitude=23.81,
            start_longitude=90.41,
            start_address='Office',
        )
        self.session.refresh_from_db()
        self.assertIsNone(self.session.end_time)

    def test_heartbeat_recent_session_not_auto_closed(self):
        """When last_heartbeat_at is within 65 min, session must NOT be auto-closed even with no LocationLog."""
        # No LocationLog for this employee in this session. But set recent heartbeat.
        self.employee.last_heartbeat_at = timezone.now() - timedelta(minutes=10)
        if timezone.is_naive(self.employee.last_heartbeat_at):
            self.employee.last_heartbeat_at = timezone.make_aware(
                self.employee.last_heartbeat_at, timezone.get_current_timezone()
            )
        self.employee.save(update_fields=['last_heartbeat_at'])
        result = auto_end_duty_sessions()
        self.session.refresh_from_db()
        self.assertIsNone(self.session.end_time, 'Session should remain open when heartbeat is recent')
        self.assertIn('Auto-closed 0', result)

    def test_no_heartbeat_no_location_session_auto_closed(self):
        """When no heartbeat and no LocationLog in 65 min, session should be auto-closed."""
        self.employee.last_heartbeat_at = None
        self.employee.save(update_fields=['last_heartbeat_at'])
        result = auto_end_duty_sessions()
        self.session.refresh_from_db()
        self.assertIsNotNone(self.session.end_time, 'Session should be auto-closed when no activity')
        self.assertIn('Auto-closed 1', result)
