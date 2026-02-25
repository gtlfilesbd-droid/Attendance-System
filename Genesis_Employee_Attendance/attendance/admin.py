from django.contrib import admin
from django.utils import timezone
from config.admin_export import AdminExportMixin
from .models import Attendance, DutySession
from .admin_filters import (
    format_time_12h,
    format_total_hours_hhmmss,
    format_duration_from_timestamps,
    format_attendance_total_hours_from_sessions,
)


@admin.register(Attendance)
class AttendanceAdmin(AdminExportMixin, admin.ModelAdmin):
    change_list_template = 'admin/attendance/attendance/change_list.html'
    list_display = [
        'id', 'employee', 'formatted_date', 'status',
        'formatted_check_in_time', 'formatted_check_out_time',
        'formatted_total_hours', 'total_locations_logged',
        'get_check_in_location', 'get_check_out_location',
        'created_at'
    ]
    list_filter = ['status', 'date', 'employee']
    search_fields = ['employee__employee_id', 'employee__name', 'employee__email', 'remarks']
    ordering = ['-date', '-created_at']
    readonly_fields = ['id', 'created_at', 'updated_at']

    fieldsets = (
        ('Employee & Date', {
            'fields': ('id', 'employee', 'date', 'status')
        }),
        ('Time Tracking', {
            'fields': (
                'first_location_time', 'last_location_time',
                'check_in_time', 'check_out_time', 'total_hours'
            )
        }),
        ('Location Logs', {
            'fields': ('total_locations_logged',)
        }),
        ('Remarks', {
            'fields': ('remarks',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at')
        }),
    )

    actions = ['calculate_hours']

    def get_queryset(self, request):
        return super().get_queryset(request).select_related('employee')

    def formatted_date(self, obj):
        return obj.date.strftime('%A, %d %b %Y') if obj.date else '—'
    formatted_date.short_description = 'Date'
    formatted_date.admin_order_field = 'date'

    def formatted_check_in_time(self, obj):
        return format_time_12h(obj.check_in_time)
    formatted_check_in_time.short_description = 'Check In'
    formatted_check_in_time.admin_order_field = 'check_in_time'

    def formatted_check_out_time(self, obj):
        return format_time_12h(obj.check_out_time)
    formatted_check_out_time.short_description = 'Check Out'
    formatted_check_out_time.admin_order_field = 'check_out_time'

    def formatted_total_hours(self, obj):
        # Use session timestamps so Admin matches reports/app (same source of truth)
        return format_attendance_total_hours_from_sessions(obj)
    formatted_total_hours.short_description = 'Total hours'
    formatted_total_hours.admin_order_field = 'total_hours'

    def get_check_in_location(self, obj):
        first = obj.employee.duty_sessions.filter(date=obj.date).order_by('start_time').first()
        if first and first.start_address:
            addr = first.start_address
            return addr[:60] + '...' if len(addr) > 60 else addr
        return '—'
    get_check_in_location.short_description = 'Check In Location'

    def get_check_out_location(self, obj):
        last = obj.employee.duty_sessions.filter(date=obj.date).order_by('-start_time').first()
        if last and last.end_address:
            addr = last.end_address
            return addr[:60] + '...' if len(addr) > 60 else addr
        return '—'
    get_check_out_location.short_description = 'Check Out Location'

    def calculate_hours(self, request, queryset):
        """Admin action to calculate total hours for selected records"""
        count = 0
        for attendance in queryset:
            if attendance.check_in_time and attendance.check_out_time:
                attendance.calculate_total_hours()
                attendance.save()
                count += 1
        self.message_user(request, f'Calculated hours for {count} attendance records.')
    calculate_hours.short_description = "Calculate total hours for selected records"


@admin.register(DutySession)
class DutySessionAdmin(AdminExportMixin, admin.ModelAdmin):
    change_list_template = 'admin/attendance/dutysession/change_list.html'
    list_display = [
        'id', 'employee', 'formatted_date',
        'formatted_start_time', 'formatted_end_time',
        'formatted_total_hours',
        'get_start_location', 'get_end_location',
        'get_end_session_remark',
    ]
    list_filter = ['date', 'employee']
    search_fields = ['employee__name', 'employee__email']
    ordering = ['-date', '-start_time']
    readonly_fields = ['id']

    def get_queryset(self, request):
        return super().get_queryset(request).select_related('employee')

    def formatted_date(self, obj):
        return obj.date.strftime('%A, %d %b %Y') if obj.date else '—'
    formatted_date.short_description = 'Date'
    formatted_date.admin_order_field = 'date'

    def formatted_start_time(self, obj):
        return format_time_12h(timezone.localtime(obj.start_time) if obj.start_time else None)
    formatted_start_time.short_description = 'Start Time'
    formatted_start_time.admin_order_field = 'start_time'

    def formatted_end_time(self, obj):
        return format_time_12h(timezone.localtime(obj.end_time) if obj.end_time else None)
    formatted_end_time.short_description = 'End Time'
    formatted_end_time.admin_order_field = 'end_time'

    def formatted_total_hours(self, obj):
        # Use start_time/end_time so Admin matches App, dashboard, reports (same source of truth)
        return format_duration_from_timestamps(obj.start_time, obj.end_time)
    formatted_total_hours.short_description = 'Total hours'
    formatted_total_hours.admin_order_field = 'total_hours'

    def get_start_location(self, obj):
        if obj.start_address:
            addr = obj.start_address
            return addr[:60] + '...' if len(addr) > 60 else addr
        return '—'
    get_start_location.short_description = 'Start Location'

    def get_end_location(self, obj):
        if obj.end_address:
            addr = obj.end_address
            return addr[:60] + '...' if len(addr) > 60 else addr
        return '—'
    get_end_location.short_description = 'End Location'

    def get_end_session_remark(self, obj):
        if obj.remarks:
            r = obj.remarks
            return r[:60] + '...' if len(r) > 60 else r
        return '—'
    get_end_session_remark.short_description = 'End Session Remark'
