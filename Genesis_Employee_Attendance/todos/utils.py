from datetime import timedelta

from django.core.exceptions import ValidationError
from django.db.models import Max
from django.utils import timezone

from .models import TodoTask

MAX_FUTURE_DAYS = 30


def validate_task_date_for_create(task_date) -> None:
    """Reject past dates and dates more than 30 days in the future."""
    today = timezone.localdate()
    if task_date < today:
        raise ValidationError('Cannot add tasks for past dates.')
    if task_date > today + timedelta(days=MAX_FUTURE_DAYS):
        raise ValidationError('Tasks can only be planned up to 30 days ahead.')


def get_next_sort_order(employee, task_date) -> int:
    last = TodoTask.objects.filter(
        employee=employee,
        task_date=task_date,
    ).aggregate(max_order=Max('sort_order'))
    return (last['max_order'] or 0) + 1


def format_task_title(sort_order: int) -> str:
    return f'Task-{sort_order:02d}'


def employee_can_edit(employee) -> bool:
    try:
        return employee.todo_permission.can_edit
    except Exception:
        return True


def employee_can_delete(employee) -> bool:
    try:
        return employee.todo_permission.can_delete
    except Exception:
        return True
