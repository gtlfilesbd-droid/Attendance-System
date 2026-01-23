from rest_framework import serializers
from rest_framework_gis.serializers import GeoFeatureModelSerializer
from django.contrib.gis.geos import Point
from datetime import datetime
from .models import LocationLog
from employees.serializers import EmployeeProfileSerializer


class LocationLogSerializer(GeoFeatureModelSerializer):
    """
    Complete LocationLog serializer with all fields including employee name
    """
    employee_name = serializers.CharField(source='employee.name', read_only=True)
    employee_email = serializers.EmailField(source='employee.email', read_only=True)
    latitude = serializers.FloatField(source='location.y', read_only=True)
    longitude = serializers.FloatField(source='location.x', read_only=True)
    
    class Meta:
        model = LocationLog
        geo_field = 'location'
        fields = [
            'id', 'employee', 'employee_name', 'employee_email',
            'location', 'latitude', 'longitude', 'timestamp',
            'accuracy', 'battery_level', 'speed', 'address',
            'created_at'
        ]
        read_only_fields = ['id', 'created_at', 'latitude', 'longitude']
    
    def validate_accuracy(self, value):
        """Validate accuracy is positive"""
        if value < 0:
            raise serializers.ValidationError("Accuracy must be a positive value.")
        if value > 1000:
            raise serializers.ValidationError("Accuracy value seems too high (max 1000 meters).")
        return value
    
    def validate_battery_level(self, value):
        """Validate battery level is between 0 and 100"""
        if value < 0 or value > 100:
            raise serializers.ValidationError("Battery level must be between 0 and 100.")
        return value
    
    def validate_speed(self, value):
        """Validate speed if provided"""
        if value is not None and value < 0:
            raise serializers.ValidationError("Speed cannot be negative.")
        return value


class LocationCreateSerializer(serializers.Serializer):
    """
    Serializer for mobile app to send location data
    Accepts latitude/longitude and converts to PostGIS Point
    """
    employee = serializers.UUIDField(required=True)
    latitude = serializers.FloatField(required=True, min_value=-90, max_value=90)
    longitude = serializers.FloatField(required=True, min_value=-180, max_value=180)
    timestamp = serializers.DateTimeField(required=True)
    accuracy = serializers.FloatField(required=True, min_value=0)
    battery_level = serializers.IntegerField(required=True, min_value=0, max_value=100)
    speed = serializers.FloatField(required=False, allow_null=True, min_value=0)
    address = serializers.CharField(required=False, allow_null=True, allow_blank=True, max_length=500)
    
    def validate_timestamp(self, value):
        """Validate timestamp is not in the future"""
        from django.utils import timezone
        if value > timezone.now():
            raise serializers.ValidationError("Timestamp cannot be in the future.")
        return value
    
    def validate(self, attrs):
        """Validate employee exists and is active"""
        from employees.models import Employee
        
        employee_id = attrs.get('employee')
        try:
            employee = Employee.objects.get(id=employee_id)
            if not employee.is_active:
                raise serializers.ValidationError({
                    'employee': 'Employee account is inactive.'
                })
            attrs['employee_obj'] = employee
        except Employee.DoesNotExist:
            raise serializers.ValidationError({
                'employee': 'Employee not found.'
            })
        
        return attrs
    
    def create(self, validated_data):
        """Create LocationLog from validated data"""
        latitude = validated_data.pop('latitude')
        longitude = validated_data.pop('longitude')
        employee_obj = validated_data.pop('employee_obj')
        validated_data.pop('employee')  # Remove UUID, use employee_obj
        
        # Create Point (longitude first in PostGIS)
        location = Point(longitude, latitude, srid=4326)
        
        location_log = LocationLog.objects.create(
            employee=employee_obj,
            location=location,
            **validated_data
        )
        
        return location_log
    
    def to_representation(self, instance):
        """Return LocationLogSerializer representation"""
        return LocationLogSerializer(instance).data


class RouteHistorySerializer(serializers.Serializer):
    """
    Serializer for employee route history for a specific date/time range
    Returns aggregated location data with route information
    """
    employee = serializers.UUIDField()
    employee_name = serializers.CharField(read_only=True)
    employee_email = serializers.CharField(read_only=True)
    start_datetime = serializers.DateTimeField()
    end_datetime = serializers.DateTimeField()
    total_locations = serializers.IntegerField(read_only=True)
    first_location = serializers.DictField(read_only=True)
    last_location = serializers.DictField(read_only=True)
    locations = LocationLogSerializer(many=True, read_only=True)
    total_distance_meters = serializers.FloatField(read_only=True)
    total_distance_km = serializers.FloatField(read_only=True)
    duration_minutes = serializers.FloatField(read_only=True)
    
    def validate(self, attrs):
        """Validate date range"""
        start = attrs.get('start_datetime')
        end = attrs.get('end_datetime')
        
        if start and end and start >= end:
            raise serializers.ValidationError({
                'end_datetime': 'End datetime must be after start datetime.'
            })
        
        # Validate range is not too large (max 7 days)
        if start and end:
            delta = end - start
            if delta.days > 7:
                raise serializers.ValidationError(
                    'Date range cannot exceed 7 days.'
                )
        
        return attrs
    
    @staticmethod
    def get_route_history(employee_id, start_datetime, end_datetime):
        """
        Static method to fetch and process route history
        """
        from employees.models import Employee
        from django.contrib.gis.measure import Distance
        
        # Get employee
        try:
            employee = Employee.objects.get(id=employee_id)
        except Employee.DoesNotExist:
            return None
        
        # Get location logs in range
        locations = LocationLog.objects.filter(
            employee=employee,
            timestamp__gte=start_datetime,
            timestamp__lte=end_datetime
        ).order_by('timestamp')
        
        if not locations.exists():
            return {
                'employee': str(employee.id),
                'employee_name': employee.name,
                'employee_email': employee.email,
                'start_datetime': start_datetime,
                'end_datetime': end_datetime,
                'total_locations': 0,
                'first_location': None,
                'last_location': None,
                'locations': [],
                'total_distance_meters': 0,
                'total_distance_km': 0,
                'duration_minutes': 0,
            }
        
        # Calculate total distance
        total_distance = 0
        previous_location = None
        for location in locations:
            if previous_location:
                # Calculate distance between points
                distance = previous_location.location.distance(location.location) * 111320  # Convert to meters
                total_distance += distance
            previous_location = location
        
        # Calculate duration
        first_timestamp = locations.first().timestamp
        last_timestamp = locations.last().timestamp
        duration = (last_timestamp - first_timestamp).total_seconds() / 60  # minutes
        
        return {
            'employee': str(employee.id),
            'employee_name': employee.name,
            'employee_email': employee.email,
            'start_datetime': start_datetime,
            'end_datetime': end_datetime,
            'total_locations': locations.count(),
            'first_location': {
                'timestamp': locations.first().timestamp,
                'latitude': locations.first().latitude,
                'longitude': locations.first().longitude,
            },
            'last_location': {
                'timestamp': locations.last().timestamp,
                'latitude': locations.last().latitude,
                'longitude': locations.last().longitude,
            },
            'locations': locations,
            'total_distance_meters': round(total_distance, 2),
            'total_distance_km': round(total_distance / 1000, 2),
            'duration_minutes': round(duration, 2),
        }
