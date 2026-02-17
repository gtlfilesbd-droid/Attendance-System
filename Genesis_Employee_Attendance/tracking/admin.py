from django.contrib import admin
from django.contrib.gis.admin import OSMGeoAdmin
from django.utils import timezone
from config.admin_export import AdminExportMixin
from .models import LocationLog
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
        return super().get_queryset(request).select_related('employee')

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
