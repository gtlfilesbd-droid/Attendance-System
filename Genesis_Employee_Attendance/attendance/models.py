from django.db import models
from employees.models import Employee


class Attendance(models.Model):
    """
    Model to store daily attendance records
    """
    STATUS_CHOICES = [
        ('PRESENT', 'Present'),
        ('LATE', 'Late'),
        ('HALF_DAY', 'Half-Day'),
        ('ABSENT', 'Absent'),
        ('LEAVE', 'Leave'),
    ]
    
    # Auto-increment primary key (default)
    id = models.AutoField(primary_key=True)
    
    # Foreign key to Employee
    employee = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name='attendances',
        db_index=True
    )
    
    # Date (unique with employee)
    date = models.DateField(db_index=True)
    
    # Time fields
    first_location_time = models.TimeField(null=True, blank=True, help_text='Time of first location log')
    last_location_time = models.TimeField(null=True, blank=True, help_text='Time of last location log')
    check_in_time = models.TimeField(null=True, blank=True, help_text='Official check-in time')
    check_out_time = models.TimeField(null=True, blank=True, help_text='Official check-out time')
    
    # Total hours worked
    total_hours = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=0.00,
        help_text='Total hours worked'
    )
    
    # Total locations logged
    total_locations_logged = models.IntegerField(default=0, help_text='Number of location logs for the day')
    
    # Attendance status
    status = models.CharField(
        max_length=10,
        choices=STATUS_CHOICES,
        default='PRESENT',
        db_index=True
    )
    
    # Remarks (optional)
    remarks = models.TextField(null=True, blank=True, help_text='Additional remarks or notes')
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'attendance'
        ordering = ['-date', '-created_at']
        verbose_name = 'Attendance'
        verbose_name_plural = 'Attendance Records'
        unique_together = [['employee', 'date']]
        indexes = [
            models.Index(fields=['employee', '-date'], name='idx_emp_date'),
            models.Index(fields=['-date'], name='idx_date'),
            models.Index(fields=['status'], name='idx_status'),
            models.Index(fields=['employee', 'status'], name='idx_emp_status'),
        ]
    
    def __str__(self):
        return f"{self.employee.name} - {self.date} - {self.status}"
    
    def calculate_total_hours(self):
        """Calculate total hours between check-in and check-out"""
        if self.check_in_time and self.check_out_time:
            from datetime import datetime, timedelta
            
            # Create datetime objects for today with the times
            check_in = datetime.combine(datetime.today(), self.check_in_time)
            check_out = datetime.combine(datetime.today(), self.check_out_time)
            
            # Handle case where check-out is past midnight
            if check_out < check_in:
                check_out += timedelta(days=1)
            
            # Calculate duration
            duration = check_out - check_in
            hours = duration.total_seconds() / 3600
            self.total_hours = round(hours, 2)
            return self.total_hours
        return 0.00


class DutySession(models.Model):
    """
    One duty session: Start Duty (start time + location) until End Duty (end time + location).
    Employee can have multiple sessions per date.
    """
    id = models.AutoField(primary_key=True)
    employee = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name='duty_sessions',
        db_index=True,
    )
    date = models.DateField(db_index=True)
    start_time = models.DateTimeField(db_index=True)
    start_latitude = models.FloatField()
    start_longitude = models.FloatField()
    start_address = models.TextField(null=True, blank=True)
    end_time = models.DateTimeField(null=True, blank=True, db_index=True)
    end_latitude = models.FloatField(null=True, blank=True)
    end_longitude = models.FloatField(null=True, blank=True)
    end_address = models.TextField(null=True, blank=True)
    total_hours = models.DecimalField(
        max_digits=7,
        decimal_places=4,
        default=0,
        help_text='Hours for this session (set when end_time is set)',
    )
    remarks = models.TextField(null=True, blank=True, help_text='Auto-end reason or manual note')

    class Meta:
        db_table = 'duty_sessions'
        ordering = ['-date', '-start_time']
        verbose_name = 'Duty Session'
        verbose_name_plural = 'Duty Sessions'
        indexes = [
            models.Index(fields=['employee', 'date'], name='idx_duty_emp_date'),
            models.Index(fields=['employee', 'end_time'], name='idx_duty_emp_end'),
        ]

    def __str__(self):
        return f"{self.employee.name} - {self.date} - {self.start_time}"


class LeaveAssignment(models.Model):
    """
    Admin-managed leave assignment for an employee.
    When a leave is assigned, the employee should not be counted as ABSENT.
    We materialize leave into per-day Attendance rows (status=LEAVE) for reporting.
    """

    id = models.AutoField(primary_key=True)
    employee = models.ForeignKey(
        Employee,
        on_delete=models.CASCADE,
        related_name='leave_assignments',
        db_index=True,
    )
    start_date = models.DateField(db_index=True)
    end_date = models.DateField(db_index=True)
    reason = models.CharField(max_length=255, blank=True, default='')
    created_by = models.ForeignKey(
        'auth.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='leave_assignments_created',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'leave_assignments'
        ordering = ['-start_date', '-created_at']
        verbose_name = 'Leave Assignment'
        verbose_name_plural = 'Leave Assignments'
        indexes = [
            models.Index(fields=['employee', 'start_date'], name='idx_leave_emp_start'),
            models.Index(fields=['employee', 'end_date'], name='idx_leave_emp_end'),
        ]

    def __str__(self):
        r = f"{self.employee} ({self.start_date} to {self.end_date})"
        return f"{r} - {self.reason}" if self.reason else r
