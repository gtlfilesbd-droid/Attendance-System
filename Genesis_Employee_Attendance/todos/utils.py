from datetime import timedelta

from django.core.exceptions import ValidationError
from django.db.models import Max
from django.utils import timezone

from employees.models import Employee
from .models import TodoTask
from .permissions import resolve_employee

MAX_FUTURE_DAYS = 30
MAX_PAST_DAYS = 3 * 365  # Dashboard filter lookback for viewing past tasks


def validate_task_date_for_create(task_date) -> None:
    """Reject dates older than lookback and dates more than 30 days in the future."""
    today = timezone.localdate()
    min_date = today - timedelta(days=MAX_PAST_DAYS)
    if task_date < min_date:
        raise ValidationError('Cannot add tasks older than the allowed lookback period.')
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


def is_assigned_task(task) -> bool:
    return bool(getattr(task, 'assigned_by_id', None) or getattr(task, 'assigned_by_username', None))


def _permission_flag(employee, field: str, default: bool = True) -> bool:
    if employee is None:
        return default
    try:
        from .models import EmployeeTodoPermission
        value = (
            EmployeeTodoPermission.objects.filter(employee_id=employee.id)
            .values_list(field, flat=True)
            .first()
        )
        if value is None:
            return default
        return bool(value)
    except Exception:
        return default


def employee_can_edit_my_app(employee) -> bool:
    return _permission_flag(employee, 'can_edit_my_app')


def employee_can_delete_my_app(employee) -> bool:
    return _permission_flag(employee, 'can_delete_my_app')


def employee_can_edit_my_web(employee) -> bool:
    return _permission_flag(employee, 'can_edit_my_web')


def employee_can_delete_my_web(employee) -> bool:
    return _permission_flag(employee, 'can_delete_my_web')


def employee_can_edit_assigned_web(employee) -> bool:
    return _permission_flag(employee, 'can_edit_assigned_web')


def employee_can_delete_assigned_web(employee) -> bool:
    return _permission_flag(employee, 'can_delete_assigned_web')


# Backward-compatible aliases used for "create my task" gating on app/web.
def employee_can_edit(employee) -> bool:
    return employee_can_edit_my_app(employee)


def employee_can_delete(employee) -> bool:
    return employee_can_delete_my_app(employee)


def _actor_employee(user):
    if isinstance(user, Employee):
        return user
    return resolve_employee(user)


def _is_assigner(user, task) -> bool:
    employee = _actor_employee(user)
    if employee and getattr(task, 'assigned_by_id', None) and task.assigned_by_id == employee.id:
        return True
    username = getattr(task, 'assigned_by_username', None)
    if username and getattr(user, 'get_username', None):
        return user.get_username() == username
    if username and getattr(user, 'username', None):
        return user.username == username
    return False


def _assigner_permission_employee(user, task):
    """Employee whose assigned_web flags apply for the current assigner action."""
    employee = _actor_employee(user)
    if employee:
        return employee
    assigned_by_id = getattr(task, 'assigned_by_id', None)
    if assigned_by_id:
        return Employee.objects.filter(pk=assigned_by_id).first()
    return None


def _superuser_unlinked_bypass(user) -> bool:
    """Superusers without a linked Employee keep full edit/delete access."""
    return bool(getattr(user, 'is_superuser', False) and _actor_employee(user) is None)


def user_can_edit_task(user, task, *, channel: str) -> bool:
    if _superuser_unlinked_bypass(user):
        return True

    employee = _actor_employee(user)
    assigned = is_assigned_task(task)

    if assigned:
        if employee and task.employee_id == employee.id:
            return False
        if channel == 'web' and _is_assigner(user, task):
            flag_employee = _assigner_permission_employee(user, task)
            if flag_employee is None:
                return True
            return employee_can_edit_assigned_web(flag_employee)
        return False

    if employee and task.employee_id == employee.id:
        if channel == 'app':
            return employee_can_edit_my_app(employee)
        if channel == 'web':
            return employee_can_edit_my_web(employee)
    return False


def user_can_delete_task(user, task, *, channel: str) -> bool:
    if _superuser_unlinked_bypass(user):
        return True

    employee = _actor_employee(user)
    assigned = is_assigned_task(task)

    if assigned:
        if employee and task.employee_id == employee.id:
            return False
        if channel == 'web' and _is_assigner(user, task):
            flag_employee = _assigner_permission_employee(user, task)
            if flag_employee is None:
                return True
            return employee_can_delete_assigned_web(flag_employee)
        return False

    if employee and task.employee_id == employee.id:
        if channel == 'app':
            return employee_can_delete_my_app(employee)
        if channel == 'web':
            return employee_can_delete_my_web(employee)
    return False
