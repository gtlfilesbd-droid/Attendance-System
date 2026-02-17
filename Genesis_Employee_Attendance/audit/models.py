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
