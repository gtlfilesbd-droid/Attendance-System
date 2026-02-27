import uuid
from django.db import models
from django.contrib.auth.models import User
from django.contrib.auth.hashers import make_password, check_password


class Department(models.Model):
    name = models.CharField(max_length=100, unique=True)
    description = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'departments'
        ordering = ['name']
        verbose_name = 'Department'
        verbose_name_plural = 'Departments'

    def __str__(self):
        return self.name


class Designation(models.Model):
    name = models.CharField(max_length=100, unique=True)
    description = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'designations'
        ordering = ['name']
        verbose_name = 'Designation'
        verbose_name_plural = 'Designations'

    def __str__(self):
        return self.name


class Employee(models.Model):
    """
    Employee model for Genesis Employee Attendance System.
    Optional OneToOne link to Django User for dashboard/session auth.
    API JWT auth still uses Employee (EmployeeJWTAuthentication).
    """
    # Primary key as UUID
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # Optional link to Django User (for dashboard login, session auth)
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='employee',
        null=True,
        blank=True,
    )
    # Basic Information
    employee_id = models.CharField(max_length=50, unique=True, db_index=True)
    name = models.CharField(max_length=200)
    email = models.EmailField(unique=True, db_index=True)
    phone = models.CharField(max_length=20)
    password = models.CharField(max_length=128)  # Hashed password
    
    # Employment Information (ForeignKey - select from dropdown in admin)
    department = models.ForeignKey(
        Department,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='employees'
    )
    designation = models.ForeignKey(
        Designation,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='employees'
    )
    join_date = models.DateField()
    is_active = models.BooleanField(default=True, db_index=True)
    
    # Profile
    profile_picture = models.ImageField(upload_to='employee_profiles/', null=True, blank=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Monitoring & offline detection (plan: last_seen, heartbeat)
    last_seen_at = models.DateTimeField(null=True, blank=True, db_index=True)
    last_location_at = models.DateTimeField(null=True, blank=True, db_index=True)
    last_heartbeat_at = models.DateTimeField(null=True, blank=True, db_index=True)
    last_device_os = models.CharField(max_length=50, null=True, blank=True)
    battery_opt_out = models.BooleanField(default=False, help_text='User requested battery optimization exemption')
    
    class Meta:
        db_table = 'employees'
        ordering = ['-created_at']
        verbose_name = 'Employee'
        verbose_name_plural = 'Employees'
        indexes = [
            models.Index(fields=['employee_id']),
            models.Index(fields=['email']),
            models.Index(fields=['is_active']),
            models.Index(fields=['-created_at']),
        ]
    
    def __str__(self):
        return f"{self.employee_id} - {self.name}"
    
    def set_password(self, raw_password):
        """Hash and set password"""
        self.password = make_password(raw_password)
    
    def check_password(self, raw_password):
        """Check if password matches"""
        return check_password(raw_password, self.password)

    @property
    def is_authenticated(self):
        """Always return True. This is a way to tell if the user has been authenticated in templates."""
        return True

    @property
    def is_staff(self):
        """Return False for regular employees unless promoted (future proofing)"""
        return False

    def save(self, *args, **kwargs):
        # Hash password if it's not already hashed
        if self.password and not self.password.startswith('pbkdf2_'):
            self.set_password(self.password)
        super().save(*args, **kwargs)


class DeviceToken(models.Model):
    """
    FCM token for push notifications. One employee can have multiple devices.
    """
    PLATFORM_ANDROID = 'android'
    PLATFORM_IOS = 'ios'
    PLATFORM_CHOICES = [
        (PLATFORM_ANDROID, 'Android'),
        (PLATFORM_IOS, 'iOS'),
    ]

    employee = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name='device_tokens',
    )
    fcm_token = models.CharField(max_length=512, unique=True, db_index=True)
    platform = models.CharField(max_length=20, choices=PLATFORM_CHOICES, default=PLATFORM_ANDROID)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'employee_device_tokens'
        ordering = ['-updated_at']
        verbose_name = 'Device Token'
        verbose_name_plural = 'Device Tokens'
        indexes = [
            models.Index(fields=['employee', 'platform']),
        ]

    def __str__(self):
        return f"{self.employee.name} ({self.platform})"
