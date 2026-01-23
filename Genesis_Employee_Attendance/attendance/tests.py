from django.test import TestCase
from django.contrib.auth import get_user_model
from django.utils import timezone
from .models import AttendanceRecord, LeaveRequest, LeaveBalance, Holiday
from datetime import date, timedelta

Employee = get_user_model()


class AttendanceRecordTest(TestCase):
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
        
        self.attendance = AttendanceRecord.objects.create(
            employee=self.employee,
            date=date.today(),
            status='PRESENT',
            check_in_time=timezone.now()
        )
    
    def test_attendance_creation(self):
        """Test attendance record creation"""
        self.assertEqual(self.attendance.employee, self.employee)
        self.assertEqual(self.attendance.status, 'PRESENT')
        self.assertIsNotNone(self.attendance.check_in_time)
    
    def test_attendance_str(self):
        """Test attendance string representation"""
        expected = f"Test User - {date.today()} - PRESENT"
        self.assertEqual(str(self.attendance), expected)


class LeaveRequestTest(TestCase):
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
        
        self.leave = LeaveRequest.objects.create(
            employee=self.employee,
            leave_type='SICK',
            start_date=date.today(),
            end_date=date.today() + timedelta(days=2),
            total_days=3,
            reason='Medical appointment',
            status='PENDING'
        )
    
    def test_leave_creation(self):
        """Test leave request creation"""
        self.assertEqual(self.leave.employee, self.employee)
        self.assertEqual(self.leave.leave_type, 'SICK')
        self.assertEqual(self.leave.status, 'PENDING')
    
    def test_leave_total_days_calculation(self):
        """Test total days calculation"""
        self.assertEqual(self.leave.total_days, 3)


class LeaveBalanceTest(TestCase):
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
        
        self.balance = LeaveBalance.objects.create(
            employee=self.employee,
            year=2026,
            sick_leave_total=10,
            sick_leave_used=2,
            casual_leave_total=12,
            casual_leave_used=3
        )
    
    def test_leave_balance_creation(self):
        """Test leave balance creation"""
        self.assertEqual(self.balance.employee, self.employee)
        self.assertEqual(self.balance.year, 2026)
    
    def test_leave_remaining_properties(self):
        """Test leave remaining calculations"""
        self.assertEqual(self.balance.sick_leave_remaining, 8)
        self.assertEqual(self.balance.casual_leave_remaining, 9)
