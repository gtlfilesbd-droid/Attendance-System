from django.contrib import admin
from django.utils import timezone
from .models import UserLoginLog


@admin.register(UserLoginLog)
class UserLoginLogAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'get_actor', 'source', 'action', 'formatted_date', 'formatted_time',
    ]
    list_filter = ['action', 'source', 'user']
    search_fields = ['user__username', 'user__email', 'employee__name', 'employee__email', 'employee__employee_id']
    ordering = ['-timestamp']
    readonly_fields = ['id', 'user', 'employee', 'action', 'source', 'timestamp']

    def get_actor(self, obj):
        if obj.user_id:
            return obj.user.get_username()
        if obj.employee_id:
            return f"{obj.employee.name} ({obj.employee.email})"
        return '—'
    get_actor.short_description = 'User / Employee'

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def formatted_date(self, obj):
        if obj.timestamp:
            return timezone.localtime(obj.timestamp).strftime('%A, %d %b %Y')
        return '—'
    formatted_date.short_description = 'Date'
    formatted_date.admin_order_field = 'timestamp'

    def formatted_time(self, obj):
        if obj.timestamp:
            return timezone.localtime(obj.timestamp).strftime('%I:%M:%S %p')
        return '—'
    formatted_time.short_description = 'Time'
    formatted_time.admin_order_field = 'timestamp'
