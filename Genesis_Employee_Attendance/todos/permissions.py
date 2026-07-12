from rest_framework.permissions import BasePermission, IsAuthenticated

from employees.models import Employee


def resolve_employee(user):
    if isinstance(user, Employee):
        return user
    return getattr(user, 'employee', None)


class IsStaffUser(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and getattr(user, 'is_staff', False))


class IsOwnerOrStaff(BasePermission):
    def has_object_permission(self, request, view, obj):
        user = request.user
        if getattr(user, 'is_staff', False):
            return True
        employee = resolve_employee(user)
        return employee is not None and obj.employee_id == employee.id
