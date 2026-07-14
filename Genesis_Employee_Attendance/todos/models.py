import uuid
from django.db import models


class TodoTask(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    employee = models.ForeignKey(
        'employees.Employee',
        on_delete=models.CASCADE,
        related_name='todo_tasks',
        db_index=True,
    )
    title = models.CharField(max_length=50)
    description = models.TextField()
    is_completed = models.BooleanField(default=False, db_index=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    task_date = models.DateField(db_index=True)
    sort_order = models.PositiveIntegerField()
    assigned_by = models.ForeignKey(
        'employees.Employee',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='todo_tasks_assigned',
    )
    assigned_by_username = models.CharField(max_length=150, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'todo_tasks'
        ordering = ['task_date', 'sort_order']
        verbose_name = 'To-Do Task'
        verbose_name_plural = 'To-Do Tasks'
        constraints = [
            models.UniqueConstraint(
                fields=['employee', 'task_date', 'sort_order'],
                name='unique_todo_per_employee_date_order',
            ),
        ]
        indexes = [
            models.Index(fields=['employee', 'task_date']),
            models.Index(fields=['employee', 'task_date', 'is_completed']),
        ]

    def __str__(self):
        return f'{self.title} - {self.employee.name} ({self.task_date})'

    @property
    def is_pending(self):
        return not self.is_completed

    @property
    def assigner_display(self):
        if self.assigned_by_id:
            return f'{self.assigned_by.name} ({self.assigned_by.employee_id})'
        if self.assigned_by_username:
            return self.assigned_by_username
        return None


class EmployeeTodoPermission(models.Model):
    employee = models.OneToOneField(
        'employees.Employee',
        on_delete=models.CASCADE,
        related_name='todo_permission',
    )
    can_edit_my_app = models.BooleanField(default=True)
    can_delete_my_app = models.BooleanField(default=True)
    can_edit_my_web = models.BooleanField(default=True)
    can_delete_my_web = models.BooleanField(default=True)
    can_edit_assigned_web = models.BooleanField(default=True)
    can_delete_assigned_web = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'employee_todo_permissions'
        verbose_name = 'Employee To-Do Permission'
        verbose_name_plural = 'Employee To-Do Permissions'

    def __str__(self):
        return f'To-Do permissions for {self.employee.name}'
