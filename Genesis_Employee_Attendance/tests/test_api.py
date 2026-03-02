from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from django.contrib.auth import get_user_model
from employees.models import Employee, Department, Designation
from tracking.models import LocationLog
from django.utils import timezone
from datetime import timedelta

User = get_user_model()

class EmployeeApiTests(APITestCase):
    def setUp(self):
        # Create test employee (department/designation are FK; use instances or None)
        self.employee_password = 'testpassword123'
        dept = Department.objects.create(name='IT', description='IT Dept', is_active=True)
        desig = Designation.objects.create(name='Developer', description='Dev', is_active=True)
        self.employee = Employee(
            email='test@example.com',
            name='Test Employee',
            employee_id='TEST001',
            phone='+8801234567890',
            password='',  # set below
            department=dept,
            designation=desig,
            join_date=timezone.now().date(),
            is_active=True,
        )
        self.employee.set_password(self.employee_password)
        self.employee.save()
        
        # Create admin user
        self.admin_password = 'adminpassword123'
        self.admin = User.objects.create_superuser(
            username='admin',
            email='admin@example.com',
            password=self.admin_password
        )
        
        # Endpoints
        self.login_url = '/api/employees/auth/login/'
        self.log_location_url = reverse('log-location')
        self.live_locations_url = reverse('live-locations')
        self.employee_route_url = reverse('employee-route')

    def test_employee_login_valid(self):
        """Test login with valid credentials"""
        data = {
            'email': self.employee.email,
            'password': self.employee_password
        }
        response = self.client.post(self.login_url, data)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        self.assertIn('access', response.data['data'])
        self.assertIn('refresh', response.data['data'])

    def test_employee_login_invalid(self):
        """Test login with invalid credentials"""
        data = {
            'email': self.employee.email,
            'password': 'wrongpassword'
        }
        response = self.client.post(self.login_url, data)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(response.data['success'])

    def test_login_rate_limit_phase7(self):
        """Phase 7: Login throttle allows 10/min; 11th request gets 429 with throttle detail."""
        from django.core.cache import cache
        cache.clear()
        data = {'email': self.employee.email, 'password': 'wrong'}
        for i in range(11):
            response = self.client.post(self.login_url, data, format='json')
            if i < 10:
                self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST, msg=f'request {i+1}')
            else:
                self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS, msg='11th request over limit')
                self.assertIn('detail', response.data, msg='429 response should include throttle detail')
        cache.clear()

    def test_employee_logout_with_reason(self):
        """Phase 1: Logout with reason and device saves to UserLoginLog"""
        self.client.force_authenticate(user=self.employee)
        logout_url = '/api/employees/auth/logout/'
        data = {
            'reason': 'MANUAL_LOGOUT',
            'device_brand': 'Samsung',
            'device_model': 'SM-A536B',
            'android_version': '14',
        }
        response = self.client.post(logout_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data.get('success'))
        from audit.models import UserLoginLog
        log = UserLoginLog.objects.filter(employee=self.employee, action='LOGOUT').order_by('-timestamp').first()
        self.assertIsNotNone(log)
        self.assertEqual(log.reason, 'MANUAL_LOGOUT')
        self.assertEqual(log.device_brand, 'Samsung')
        self.assertEqual(log.device_model, 'SM-A536B')
        self.assertEqual(log.android_version, '14')

    def test_mobile_logs_bulk_phase2(self):
        """Phase 2: POST /api/audit/mobile-logs/bulk/ creates MobileLog rows with device + logs."""
        from audit.models import MobileLog
        self.client.force_authenticate(user=self.employee)
        url = '/api/audit/mobile-logs/bulk/'
        data = {
            'device': {'android_version': '14', 'brand': 'Samsung', 'model': 'SM-A536B'},
            'logs': [
                {
                    'timestamp': '2026-02-27T10:00:00Z',
                    'level': 'INFO',
                    'category': 'AUTH',
                    'message': 'Login success',
                    'extra_json': None,
                    'stack_trace': None,
                    'duration_ms': None,
                },
                {
                    'timestamp': '2026-02-27T10:01:00Z',
                    'level': 'ERROR',
                    'category': 'API',
                    'message': 'Token refresh failed',
                    'extra_json': {'path': '/api/foo'},
                    'stack_trace': 'Error: ...',
                    'duration_ms': 45,
                },
            ],
        }
        response = self.client.post(url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data.get('success'))
        self.assertEqual(response.data.get('created'), 2)
        logs = list(MobileLog.objects.filter(employee=self.employee).order_by('timestamp'))
        self.assertEqual(len(logs), 2)
        self.assertEqual(logs[0].level, 'INFO')
        self.assertEqual(logs[0].category, 'AUTH')
        self.assertEqual(logs[0].message, 'Login success')
        self.assertIsNone(logs[0].extra_json)
        self.assertEqual(logs[0].device_brand, 'Samsung')
        self.assertEqual(logs[0].device_model, 'SM-A536B')
        self.assertEqual(logs[0].device_android_version, '14')
        self.assertEqual(logs[1].level, 'ERROR')
        self.assertEqual(logs[1].category, 'API')
        self.assertIn('path', logs[1].extra_json or '')
        self.assertEqual(logs[1].duration_ms, 45)

    def test_log_location_authenticated(self):
        """Test logging location with valid token"""
        self.client.force_authenticate(user=self.employee)
        data = {
            'employee': str(self.employee.id),
            'latitude': 23.8103,
            'longitude': 90.4125,
            'timestamp': timezone.now(),
            'accuracy': 10.0,
            'battery_level': 80,
            'speed': 0.0
        }
        response = self.client.post(self.log_location_url, data)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['success'])

    def test_log_location_unauthenticated(self):
        """Test logging location without token"""
        data = {
            'employee': str(self.employee.id),
            'latitude': 23.8103,
            'longitude': 90.4125,
            'timestamp': timezone.now(),
            'accuracy': 10.0,
            'battery_level': 80
        }
        response = self.client.post(self.log_location_url, data)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_log_location_bulk_phase3(self):
        """Phase 3: POST /api/tracking/log-location/bulk/ creates multiple LocationLogs."""
        from tracking.models import LocationLog
        self.client.force_authenticate(user=self.employee)
        bulk_url = reverse('log-location-bulk')
        now = timezone.now()
        data = {
            'locations': [
                {
                    'employee': str(self.employee.id),
                    'latitude': 23.8103,
                    'longitude': 90.4125,
                    'timestamp': now,
                    'accuracy': 10.0,
                    'battery_level': 80,
                    'speed': 0.0,
                },
                {
                    'employee': str(self.employee.id),
                    'latitude': 23.8104,
                    'longitude': 90.4126,
                    'timestamp': now - timedelta(minutes=1),
                    'accuracy': 12.0,
                    'battery_level': 79,
                    'speed': None,
                },
            ],
        }
        response = self.client.post(bulk_url, data, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data.get('success'))
        self.assertEqual(response.data.get('created'), 2)
        self.assertEqual(len(response.data.get('ids', [])), 2)
        count = LocationLog.objects.filter(employee=self.employee).count()
        self.assertGreaterEqual(count, 2)

    def test_live_locations_admin_only(self):
        """Test live locations endpoint accessibility"""
        # Unauthenticated
        response = self.client.get(self.live_locations_url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        
        # Employee (Not Admin)
        self.client.force_authenticate(user=self.employee)
        response = self.client.get(self.live_locations_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        
        # Admin
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(self.live_locations_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_route_history(self):
        """Test route history retrieval"""
        self.client.force_authenticate(user=self.employee)
        
        # Create some location logs
        from django.contrib.gis.geos import Point
        now = timezone.now()
        
        # Log 1
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.4125, 23.8103),
            timestamp=now - timedelta(hours=2),
            accuracy=10,
            battery_level=90
        )
        
        # Log 2
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.4126, 23.8104),
            timestamp=now - timedelta(hours=1),
            accuracy=10,
            battery_level=85
        )
        
        params = {
            'employee_id': self.employee.id,
            'date': now.date().isoformat()
        }
        
        response = self.client.get(self.employee_route_url, params)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        self.assertEqual(response.data['data']['total_locations'], 2)

    def test_attendance_calculation(self):
        """Test daily attendance calculation based on logs"""
        # This is an integration test for the calculation logic
        # Assuming you have a task or signal that calculates it, 
        # or we manually invoke the logic if it's a celery task.
        
        from tracking.tasks import calculate_daily_attendance
        from attendance.models import Attendance
        
        # Create logs spanning 9 hours
        start_time = timezone.now().replace(hour=9, minute=0, second=0)
        end_time = timezone.now().replace(hour=18, minute=0, second=0)
        
        from django.contrib.gis.geos import Point
        
        # Start Log
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.4125, 23.8103),
            timestamp=start_time,
            accuracy=10,
            battery_level=100
        )
        
        # End Log
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.4125, 23.8103),
            timestamp=end_time,
            accuracy=10,
            battery_level=50
        )
        
        # Run calculation
        calculate_daily_attendance()
        
        # Check attendance record
        attendance = Attendance.objects.filter(
            employee=self.employee, 
            date=start_time.date()
        ).first()
        
        self.assertIsNotNone(attendance)
        # 9 hours is > 8 hours -> PRESENT? Depends on logic
        # self.assertEqual(attendance.status, 'PRESENT') 
        # (Assert status depending on your business logic)
