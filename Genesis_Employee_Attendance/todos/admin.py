from django.contrib import admin

from employees.department_permissions import get_permitted_departments
from .models import EmployeeTodoPermission, TodoTask


@admin.register(TodoTask)
class TodoTaskAdmin(admin.ModelAdmin):
    list_display = ('title', 'employee', 'task_date', 'is_completed', 'completed_at', 'sort_order', 'created_at')
    list_filter = ('is_completed', 'task_date', 'employee__department')
    search_fields = ('title', 'description', 'employee__name', 'employee__employee_id')
    readonly_fields = ('id', 'title', 'sort_order', 'created_at', 'updated_at', 'completed_at')
    ordering = ('-task_date', 'sort_order')

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee', 'employee__department')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)


@admin.register(EmployeeTodoPermission)
class EmployeeTodoPermissionAdmin(admin.ModelAdmin):
    list_display = ('employee', 'can_edit', 'can_delete', 'updated_at')
    search_fields = ('employee__name', 'employee__employee_id')
    list_filter = ('can_edit', 'can_delete')

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee', 'employee__department')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)
