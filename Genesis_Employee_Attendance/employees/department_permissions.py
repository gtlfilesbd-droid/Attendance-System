"""
Department-level permission utilities for admin panel and dashboard.
"""
from .models import Department, UserDepartmentPermission


def get_permitted_departments(user):
    """
    Return the departments the user is allowed to access.
    - Superusers get all active departments.
    - Staff users with UserDepartmentPermission get only their assigned departments.
    - Users without permission or with empty assignment get none.
    """
    if user.is_superuser:
        return Department.objects.filter(is_active=True)
    try:
        return user.department_permission.departments.filter(is_active=True)
    except UserDepartmentPermission.DoesNotExist:
        return Department.objects.none()
