from django.contrib import admin
from .models import Employee


@admin.register(Employee)
class EmployeeAdmin(admin.ModelAdmin):
    list_display = ['employee_id', 'name', 'email', 'department', 'designation', 'is_active', 'join_date', 'created_at']
    list_filter = ['is_active', 'department', 'join_date', 'created_at']
    search_fields = ['employee_id', 'name', 'email', 'phone', 'department', 'designation']
    ordering = ['-created_at']
    readonly_fields = ['id', 'created_at', 'updated_at']
    
    fieldsets = (
        ('Basic Information', {
            'fields': ('id', 'employee_id', 'name', 'email', 'phone', 'password')
        }),
        ('Employment Details', {
            'fields': ('department', 'designation', 'join_date', 'is_active')
        }),
        ('Profile', {
            'fields': ('profile_picture',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at')
        }),
    )
    
    def save_model(self, request, obj, form, change):
        # Hash password if it's being set/changed
        if 'password' in form.changed_data:
            obj.set_password(form.cleaned_data['password'])
        super().save_model(request, obj, form, change)
