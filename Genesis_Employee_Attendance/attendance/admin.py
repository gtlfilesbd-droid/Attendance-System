from django.contrib import admin
from .models import Attendance


@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'employee', 'date', 'status', 'check_in_time', 'check_out_time',
        'total_hours', 'total_locations_logged', 'created_at'
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
