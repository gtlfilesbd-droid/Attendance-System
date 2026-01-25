from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from django.contrib.auth import get_user_model
from employees.models import Employee
from tracking.models import LocationLog
from django.utils import timezone
from datetime import timedelta

User = get_user_model()

class EmployeeApiTests(APITestCase):
    def setUp(self):
        # Create test employee
        self.employee_password = 'testpassword123'
        self.employee = Employee.objects.create(
            email='test@example.com',
            name='Test Employee',
            employee_id='TEST001',
            password=self.employee_password,
            department='IT',
            designation='Developer',
            join_date=timezone.now().date(),
            is_active=True
        )
        
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
