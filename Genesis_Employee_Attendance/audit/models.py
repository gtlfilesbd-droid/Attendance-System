from django.db import models
from django.contrib.auth.models import User


class UserLoginLog(models.Model):
    """Log of login and logout events (admin/dashboard = User; app = Employee)."""
    ACTION_CHOICES = [
        ('LOGIN', 'Login'),
        ('LOGOUT', 'Logout'),
    ]
    SOURCE_WEB = 'web'
    SOURCE_APP = 'app'
    SOURCE_CHOICES = [
        (SOURCE_WEB, 'Web (Admin/Dashboard)'),
        (SOURCE_APP, 'App'),
    ]
    # Logout reason (app sends; for root cause analysis)
    REASON_MANUAL = 'MANUAL_LOGOUT'
    REASON_TOKEN_REFRESH = 'TOKEN_REFRESH_FAILED'
    REASON_NO_HEARTBEAT = 'NO_HEARTBEAT_TIMEOUT'
    REASON_SERVER_FORCE = 'SERVER_FORCE_LOGOUT'
    REASON_SESSION_EXPIRED = 'SESSION_EXPIRED'
    REASON_NETWORK_SYNC = 'NETWORK_SYNC_FAILURE'

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='login_logs',
        db_index=True,
        null=True,
        blank=True,
    )
    employee = models.ForeignKey(
        'employees.Employee',
        on_delete=models.CASCADE,
        related_name='login_logs',
        db_index=True,
        null=True,
        blank=True,
    )
    action = models.CharField(max_length=10, choices=ACTION_CHOICES, db_index=True)
    source = models.CharField(max_length=10, choices=SOURCE_CHOICES, default=SOURCE_WEB, db_index=True)
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)
    reason = models.CharField(max_length=50, null=True, blank=True, db_index=True)
    device_brand = models.CharField(max_length=64, null=True, blank=True)
    device_model = models.CharField(max_length=128, null=True, blank=True)
    android_version = models.CharField(max_length=20, null=True, blank=True)

    class Meta:
        db_table = 'audit_userloginlog'
        ordering = ['-timestamp']
        verbose_name = 'User Login Log'
        verbose_name_plural = 'User Login Logs'
        indexes = [
            models.Index(fields=['user', '-timestamp'], name='audit_ulog_user_ts'),
            models.Index(fields=['employee', '-timestamp'], name='audit_ulog_emp_ts'),
        ]

    def __str__(self):
        who = self.user.username if self.user_id else (f"{self.employee.name} ({self.employee.email})" if self.employee_id else '—')
        return f"{who} - {self.action} - {self.timestamp}"


class MobileLog(models.Model):
    """Phase 2: Mobile app logs uploaded in bulk for debugging and root cause analysis."""
    employee = models.ForeignKey(
        'employees.Employee',
        on_delete=models.CASCADE,
        related_name='mobile_logs',
        db_index=True,
    )
    timestamp = models.DateTimeField(db_index=True)  # client timestamp
    level = models.CharField(max_length=10, db_index=True)  # DEBUG, INFO, WARN, ERROR
    category = models.CharField(max_length=32, db_index=True)  # AUTH, API, TRACKING, SYNC, etc.
    message = models.TextField()
    extra_json = models.TextField(null=True, blank=True)
    stack_trace = models.TextField(null=True, blank=True)
    duration_ms = models.IntegerField(null=True, blank=True)
    device_android_version = models.CharField(max_length=20, null=True, blank=True, db_index=True)
    device_brand = models.CharField(max_length=64, null=True, blank=True, db_index=True)
    device_model = models.CharField(max_length=128, null=True, blank=True, db_index=True)
    received_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = 'audit_mobilelog'
        ordering = ['-timestamp']
        verbose_name = 'Mobile Log'
        verbose_name_plural = 'Mobile Logs'
        indexes = [
            models.Index(fields=['employee', '-timestamp'], name='audit_mlog_emp_ts'),
            models.Index(fields=['category', '-timestamp'], name='audit_mlog_cat_ts'),
        ]

    def __str__(self):
        return f"{self.employee_id} {self.category} {self.timestamp}"
