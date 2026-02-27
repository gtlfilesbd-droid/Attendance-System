from django.db import models
from django.contrib.gis.db import models as gis_models
from employees.models import Employee
from django.utils import timezone


class LocationLog(models.Model):
    """
    Model to store employee location logs with PostGIS
    """
    # Auto-increment primary key (default)
    id = models.AutoField(primary_key=True)
    
    # Foreign key to Employee
    employee = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name='location_logs',
        db_index=True
    )
    
    # Location as PostGIS PointField (lat/long)
    location = gis_models.PointField(geography=True, help_text='Geographic location (longitude, latitude)')
    
    # Timestamp with timezone
    timestamp = models.DateTimeField(db_index=True)
    
    # Accuracy in meters
    accuracy = models.FloatField(help_text='Location accuracy in meters')
    
    # Battery level (0-100)
    battery_level = models.IntegerField(help_text='Battery percentage (0-100)')
    
    # Speed (optional)
    speed = models.FloatField(null=True, blank=True, help_text='Speed in m/s')
    
    # Reverse geocoded address (optional)
    address = models.TextField(null=True, blank=True, help_text='Reverse geocoded address')
    
    # Auto timestamp
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        db_table = 'location_logs'
        ordering = ['-timestamp']
        verbose_name = 'Location Log'
        verbose_name_plural = 'Location Logs'
        indexes = [
            models.Index(fields=['employee', '-timestamp'], name='idx_employee_timestamp'),
            models.Index(fields=['-timestamp'], name='idx_timestamp'),
            models.Index(fields=['employee'], name='idx_employee'),
        ]
    
    def __str__(self):
        return f"{self.employee.name} - {self.timestamp}"
    
    @property
    def latitude(self):
        """Get latitude from point"""
        return self.location.y if self.location else None
    
    @property
    def longitude(self):
        """Get longitude from point"""
        return self.location.x if self.location else None


class LocationAnomaly(models.Model):
    """
    Aggregated anomaly record per employee per day.
    Stores suspicious movement patterns (high speed, long jump, night movement, etc.).
    """
    REASON_HIGH_SPEED = 'high_speed'
    REASON_LONG_JUMP = 'long_jump'
    REASON_NIGHT_ACTIVITY = 'night_activity'

    REASON_CHOICES = [
        (REASON_HIGH_SPEED, 'High speed'),
        (REASON_LONG_JUMP, 'Long jump'),
        (REASON_NIGHT_ACTIVITY, 'Night activity'),
    ]

    id = models.AutoField(primary_key=True)
    employee = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name='location_anomalies',
        db_index=True,
    )
    date = models.DateField(db_index=True)
    reason = models.CharField(max_length=50, choices=REASON_CHOICES, db_index=True)
    score = models.FloatField(default=1.0, help_text='Relative severity score')
    details = models.JSONField(default=dict, blank=True, help_text='Extra context (times, distances, etc.)')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'location_anomalies'
        unique_together = ('employee', 'date', 'reason')
        ordering = ['-date', '-updated_at']
        indexes = [
            models.Index(fields=['employee', '-date'], name='idx_anom_employee_date'),
            models.Index(fields=['reason', '-date'], name='idx_anom_reason_date'),
        ]

    def __str__(self):
        return f'{self.employee} {self.date} {self.reason}'

    @classmethod
    def today(cls):
        return timezone.now().date()
