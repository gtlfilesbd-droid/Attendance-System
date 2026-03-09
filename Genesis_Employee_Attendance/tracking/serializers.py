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
        """Validate timestamp is not in the future (10 s tolerance for phone clock drift)."""
        from django.utils import timezone
        from datetime import timedelta
        if value > timezone.now() + timedelta(seconds=10):
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
        from django.db.models import Q

        # Get employee
        try:
            employee = Employee.objects.get(id=employee_id)
        except Employee.DoesNotExist:
            return None

        MAX_ACCURACY_METERS = 150.0

        # Base queryset — only fetch fields we actually need
        base_qs = (
            LocationLog.objects
            .filter(employee=employee, timestamp__gte=start_datetime, timestamp__lte=end_datetime)
            .only('id', 'location', 'timestamp', 'accuracy', 'battery_level', 'speed', 'address')
            .order_by('timestamp')
        )

        # SQL-level accuracy filter (single DB round-trip, no Python-side loop)
        filtered_qs = base_qs.filter(Q(accuracy__isnull=True) | Q(accuracy__lte=MAX_ACCURACY_METERS))
        locations_list = list(filtered_qs)

        # Fall back to unfiltered only when too few accurate points (preserves original behaviour)
        if len(locations_list) < 2:
            locations_list = list(base_qs)

        if not locations_list:
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
                'avg_speed_kmh_computed': None,
                'avg_speed_kmh_device': None,
            }
        # Calculate total distance and per-segment distance/speed
        # PostGIS Geography .distance() returns meters (no * 111320)
        total_distance = 0
        segment_distances = [None]  # first point has no segment from previous
        segment_speeds = [None]  # speed in m/s for segment into this point

        for i in range(1, len(locations_list)):
            prev_loc = locations_list[i - 1]
            curr_loc = locations_list[i]
            dist_m = prev_loc.location.distance(curr_loc.location)
            total_distance += dist_m
            segment_distances.append(dist_m)
            time_sec = (curr_loc.timestamp - prev_loc.timestamp).total_seconds()
            speed_mps = (dist_m / time_sec) if time_sec > 0 else None
            segment_speeds.append(speed_mps)

        # Duration
        first_timestamp = locations_list[0].timestamp
        last_timestamp = locations_list[-1].timestamp
        duration = (last_timestamp - first_timestamp).total_seconds() / 60  # minutes

        # Average speeds for UI (computed = segment distance/time; device = from GPS)
        speeds_computed = [s for s in segment_speeds if s is not None]
        speeds_device = []
        for loc in locations_list:
            s = getattr(loc, 'speed', None)
            if s is not None:
                speeds_device.append(float(s))
        avg_speed_kmh_computed = (
            (sum(speeds_computed) / len(speeds_computed) * 3.6) if speeds_computed else None
        )
        avg_speed_kmh_device = (
            (sum(speeds_device) / len(speeds_device) * 3.6) if speeds_device else None
        )

        return {
            'employee': str(employee.id),
            'employee_name': employee.name,
            'employee_email': employee.email,
            'start_datetime': start_datetime,
            'end_datetime': end_datetime,
            'total_locations': len(locations_list),
            'first_location': {
                'timestamp': first_timestamp,
                'latitude': locations_list[0].latitude,
                'longitude': locations_list[0].longitude,
            },
            'last_location': {
                'timestamp': last_timestamp,
                'latitude': locations_list[-1].latitude,
                'longitude': locations_list[-1].longitude,
            },
            'locations': [
                {
                    'id': loc.id,
                    'latitude': loc.latitude,
                    'longitude': loc.longitude,
                    'timestamp': loc.timestamp,
                    'accuracy': loc.accuracy,
                    'battery_level': loc.battery_level,
                    'speed': getattr(loc, 'speed', None),
                    'address': loc.address,
                    'speed_computed': segment_speeds[j] if j < len(segment_speeds) else None,
                    'segment_distance_meters': segment_distances[j] if j < len(segment_distances) else None,
                }
                for j, loc in enumerate(locations_list)
            ],
            'total_distance_meters': round(total_distance, 2),
            'total_distance_km': round(total_distance / 1000, 2),
            'duration_minutes': round(duration, 2),
            'avg_speed_kmh_computed': round(avg_speed_kmh_computed, 1) if avg_speed_kmh_computed is not None else None,
            'avg_speed_kmh_device': round(avg_speed_kmh_device, 1) if avg_speed_kmh_device is not None else None,
        }
