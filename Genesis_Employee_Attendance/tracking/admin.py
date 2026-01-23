from django.contrib import admin
from django.contrib.gis.admin import OSMGeoAdmin
from .models import LocationLog


@admin.register(LocationLog)
class LocationLogAdmin(OSMGeoAdmin):
    list_display = ['id', 'employee', 'timestamp', 'latitude', 'longitude', 'accuracy', 'battery_level', 'speed']
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
