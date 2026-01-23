from django.test import TestCase
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from .models import LocationPoint, GeofenceZone, GeofenceEvent
from datetime import date

Employee = get_user_model()


class LocationPointTest(TestCase):
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
        
        self.location = LocationPoint.objects.create(
            employee=self.employee,
            location=Point(-122.4194, 37.7749),
            accuracy=10.5
        )
    
    def test_location_creation(self):
        """Test location point creation"""
        self.assertEqual(self.location.employee, self.employee)
        self.assertIsNotNone(self.location.location)
        self.assertEqual(self.location.accuracy, 10.5)
    
    def test_location_coordinates(self):
        """Test location coordinates properties"""
        self.assertAlmostEqual(self.location.latitude, 37.7749, places=4)
        self.assertAlmostEqual(self.location.longitude, -122.4194, places=4)


class GeofenceZoneTest(TestCase):
    def setUp(self):
        self.zone = GeofenceZone.objects.create(
            name='Main Office',
            zone_type='OFFICE',
            center_point=Point(-122.4194, 37.7749),
            radius=100,
            is_active=True,
            requires_checkin=True
        )
    
    def test_geofence_creation(self):
        """Test geofence zone creation"""
        self.assertEqual(self.zone.name, 'Main Office')
        self.assertEqual(self.zone.zone_type, 'OFFICE')
        self.assertEqual(self.zone.radius, 100)
    
    def test_point_inside_geofence(self):
        """Test if point is inside geofence"""
        # Point very close to center
        point = Point(-122.4194, 37.7749)
        self.assertTrue(self.zone.is_inside(point))
        
        # Point far away
        point_far = Point(-122.5, 37.8)
        self.assertFalse(self.zone.is_inside(point_far))
