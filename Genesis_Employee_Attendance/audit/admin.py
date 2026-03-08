from django.contrib import admin
from django.utils import timezone
from employees.department_permissions import get_permitted_departments
from .models import UserLoginLog, MobileLog


@admin.register(UserLoginLog)
class UserLoginLogAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'get_actor', 'source', 'action', 'reason', 'device_brand', 'device_model', 'android_version',
        'formatted_date', 'formatted_time',
    ]
    list_filter = ['action', 'source', 'reason', 'user']
    search_fields = ['user__username', 'user__email', 'employee__name', 'employee__email', 'employee__employee_id']
    ordering = ['-timestamp']
    readonly_fields = ['id', 'user', 'employee', 'action', 'source', 'timestamp', 'reason', 'device_brand', 'device_model', 'android_version']

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('user', 'employee')
        if request.user.is_superuser:
            return qs
        from django.db.models import Q
        permitted = get_permitted_departments(request.user)
        # Show: own user logins OR employee logins in permitted departments
        return qs.filter(Q(user_id=request.user.id) | Q(employee__department__in=permitted))

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


@admin.register(MobileLog)
class MobileLogAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'employee', 'timestamp', 'level', 'category', 'message_short',
        'device_brand', 'device_model', 'device_android_version', 'received_at',
    ]
    list_filter = ['employee', 'level', 'category', 'device_brand', 'device_android_version']
    search_fields = ['employee__name', 'employee__email', 'message']
    ordering = ['-timestamp']

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)
    readonly_fields = [
        'employee', 'timestamp', 'level', 'category', 'message', 'extra_json',
        'stack_trace', 'duration_ms', 'device_android_version', 'device_brand',
        'device_model', 'received_at',
    ]

    def message_short(self, obj):
        return (obj.message[:60] + '...') if obj.message and len(obj.message) > 60 else (obj.message or '')
    message_short.short_description = 'Message'

    def has_add_permission(self, request):
        return False
