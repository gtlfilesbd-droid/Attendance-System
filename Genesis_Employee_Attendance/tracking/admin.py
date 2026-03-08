from django.contrib import admin
from django.contrib.gis.admin import OSMGeoAdmin
from django.utils import timezone
from config.admin_export import AdminExportMixin
from employees.department_permissions import get_permitted_departments
from .models import LocationLog, LocationAnomaly
from attendance.admin_filters import format_time_12h


@admin.register(LocationLog)
class LocationLogAdmin(AdminExportMixin, OSMGeoAdmin):
    change_list_template = 'admin/tracking/locationlog/change_list.html'
    list_display = [
        'id', 'employee', 'formatted_date', 'formatted_timestamp',
        'latitude', 'longitude', 'accuracy', 'battery_level', 'speed'
    ]
    list_filter = ['timestamp', 'employee']
    search_fields = ['employee__employee_id', 'employee__name', 'employee__email', 'address']
    ordering = ['-timestamp']
    readonly_fields = ['id', 'created_at', 'latitude', 'longitude']

    fieldsets = (
        ('Employee & Location', {
            'fields': ('id', 'employee', 'location', 'latitude', 'longitude')
        }),
        ('Location Details', {
            'fields': ('timestamp', 'accuracy', 'speed', 'address')
        }),
        ('Device Info', {
            'fields': ('battery_level',)
        }),
        ('Timestamps', {
            'fields': ('created_at',)
        }),
    )

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == 'employee' and not request.user.is_superuser:
            from employees.models import Employee
            permitted = get_permitted_departments(request.user)
            kwargs['queryset'] = Employee.objects.filter(department__in=permitted)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    def formatted_date(self, obj):
        if obj.timestamp:
            local_ts = timezone.localtime(obj.timestamp)
            return local_ts.strftime('%A, %d %b %Y')
        return '—'
    formatted_date.short_description = 'Date'
    formatted_date.admin_order_field = 'timestamp'

    def formatted_timestamp(self, obj):
        return format_time_12h(timezone.localtime(obj.timestamp) if obj.timestamp else None)
    formatted_timestamp.short_description = 'Timestamp'
    formatted_timestamp.admin_order_field = 'timestamp'


@admin.register(LocationAnomaly)
class LocationAnomalyAdmin(AdminExportMixin, admin.ModelAdmin):
    list_display = ['id', 'employee', 'date', 'reason', 'score', 'created_at']
    list_filter = ['reason', 'date', 'employee']
    search_fields = ['employee__employee_id', 'employee__name', 'employee__email']
    ordering = ['-date', '-created_at']

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == 'employee' and not request.user.is_superuser:
            from employees.models import Employee
            permitted = get_permitted_departments(request.user)
            kwargs['queryset'] = Employee.objects.filter(department__in=permitted)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)
