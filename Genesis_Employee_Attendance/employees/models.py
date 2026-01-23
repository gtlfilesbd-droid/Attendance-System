import uuid
from django.db import models
from django.contrib.auth.hashers import make_password, check_password


class Employee(models.Model):
    """
    Employee model for Genesis Employee Attendance System
    """
    # Primary key as UUID
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    
    # Basic Information
    employee_id = models.CharField(max_length=50, unique=True, db_index=True)
    name = models.CharField(max_length=200)
    email = models.EmailField(unique=True, db_index=True)
    phone = models.CharField(max_length=20)
    password = models.CharField(max_length=128)  # Hashed password
    
    # Employment Information
    department = models.CharField(max_length=100)
    designation = models.CharField(max_length=100)
    join_date = models.DateField()
    is_active = models.BooleanField(default=True, db_index=True)
    
    # Profile
    profile_picture = models.ImageField(upload_to='employee_profiles/', null=True, blank=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
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
    
    def save(self, *args, **kwargs):
        # Hash password if it's not already hashed
        if self.password and not self.password.startswith('pbkdf2_'):
            self.set_password(self.password)
        super().save(*args, **kwargs)
