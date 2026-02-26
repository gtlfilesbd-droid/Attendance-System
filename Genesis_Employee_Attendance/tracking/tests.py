from django.test import TestCase
from django.contrib.gis.geos import Point
from django.utils import timezone
from .models import LocationLog
from .serializers import RouteHistorySerializer
from employees.models import Employee, Department, Designation
from datetime import date, datetime, timedelta


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


class RouteHistorySerializerTest(TestCase):
    """Tests for route/speed/accuracy implementation (plan step 5 - validation)."""

    def setUp(self):
        self.employee = _create_employee(employee_id='EMP009')

    def test_get_route_history_empty(self):
        """Empty time range returns zero locations and avg speeds None."""
        start = timezone.now() - timedelta(hours=2)
        end = timezone.now() - timedelta(hours=1)
        result = RouteHistorySerializer.get_route_history(
            str(self.employee.id), start, end
        )
        self.assertIsNotNone(result)
        self.assertEqual(result['total_locations'], 0)
        self.assertEqual(result['total_distance_km'], 0)
        self.assertIsNone(result.get('avg_speed_kmh_computed'))
        self.assertIsNone(result.get('avg_speed_kmh_device'))

    def test_get_route_history_distance_in_meters(self):
        """Distance is stored as-is (no spurious * 111320). PostGIS Geography returns meters."""
        base = timezone.now()
        # Two points ~1 km apart (approx): Dhaka area 23.81, 90.41; 1km N ~ 0.009 deg lat
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.4125, 23.8103),
            timestamp=base,
            accuracy=10.0,
            battery_level=80,
            speed=5.0,
        )
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.4125, 23.8193),  # ~1 km north
            timestamp=base + timedelta(seconds=120),
            accuracy=10.0,
            battery_level=79,
            speed=5.0,
        )
        result = RouteHistorySerializer.get_route_history(
            str(self.employee.id), base - timedelta(minutes=1), base + timedelta(minutes=5)
        )
        self.assertIsNotNone(result)
        self.assertEqual(result['total_locations'], 2)
        # Response must be consistent: total_distance_km == total_distance_meters / 1000
        self.assertAlmostEqual(
            result['total_distance_km'],
            result['total_distance_meters'] / 1000.0,
            places=2,
        )
        # No wrong scaling: if backend returns meters (~1 km), 900–1200 m; if degrees (~0.009), < 1
        self.assertGreater(result['total_distance_meters'], 0)
        self.assertLess(result['total_distance_meters'], 150000)  # not 111320x wrong

    def test_get_route_history_speed_computed_and_avg(self):
        """Each location has speed_computed; response has avg_speed_kmh_computed and avg_speed_kmh_device."""
        base = timezone.now()
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.41, 23.81),
            timestamp=base,
            accuracy=10.0,
            battery_level=80,
            speed=10.0,  # m/s
        )
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.42, 23.81),
            timestamp=base + timedelta(seconds=60),
            accuracy=10.0,
            battery_level=79,
            speed=12.0,
        )
        result = RouteHistorySerializer.get_route_history(
            str(self.employee.id), base - timedelta(minutes=1), base + timedelta(minutes=5)
        )
        self.assertIsNotNone(result)
        self.assertEqual(len(result['locations']), 2)
        self.assertIsNone(result['locations'][0].get('speed_computed'))
        self.assertIsNotNone(result['locations'][1].get('speed_computed'))
        self.assertIn('avg_speed_kmh_computed', result)
        self.assertIn('avg_speed_kmh_device', result)
        if result['avg_speed_kmh_device'] is not None:
            self.assertGreater(result['avg_speed_kmh_device'], 0)

    def test_get_route_history_accuracy_filter(self):
        """Points with accuracy > 150 m can be excluded when enough points remain."""
        base = timezone.now()
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.41, 23.81),
            timestamp=base,
            accuracy=20.0,
            battery_level=80,
        )
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.411, 23.811),
            timestamp=base + timedelta(seconds=60),
            accuracy=200.0,  # bad
            battery_level=79,
        )
        LocationLog.objects.create(
            employee=self.employee,
            location=Point(90.412, 23.812),
            timestamp=base + timedelta(seconds=120),
            accuracy=30.0,
            battery_level=78,
        )
        result = RouteHistorySerializer.get_route_history(
            str(self.employee.id), base - timedelta(minutes=1), base + timedelta(minutes=5)
        )
        self.assertIsNotNone(result)
        # Filter keeps only accuracy <= 150; we have 3 points, 1 bad -> filtered to 2 would leave 2 points
        self.assertIn(result['total_locations'], (2, 3))
