from django.contrib import admin
from django.utils.safestring import mark_safe
from config.admin_export import AdminExportMixin
from .models import Employee, Department, Designation, DeviceToken
from .department_permissions import get_permitted_departments


@admin.register(Department)
class DepartmentAdmin(AdminExportMixin, admin.ModelAdmin):
    list_display = ['name', 'is_active', 'created_at']
    list_filter = ['is_active']
    search_fields = ['name', 'description']
    ordering = ['name']


@admin.register(Designation)
class DesignationAdmin(AdminExportMixin, admin.ModelAdmin):
    list_display = ['name', 'is_active', 'created_at']
    list_filter = ['is_active']
    search_fields = ['name', 'description']
    ordering = ['name']


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ['employee', 'platform', 'created_at', 'updated_at']
    list_filter = ['platform']
    search_fields = ['employee__name', 'employee__email', 'fcm_token']
    readonly_fields = ['created_at', 'updated_at']

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == 'employee' and not request.user.is_superuser:
            permitted = get_permitted_departments(request.user)
            kwargs['queryset'] = Employee.objects.filter(department__in=permitted)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)


@admin.register(Employee)
class EmployeeAdmin(AdminExportMixin, admin.ModelAdmin):
    list_display = ['employee_id', 'name', 'email', 'department', 'designation', 'is_active', 'join_date', 'created_at']
    list_filter = ['is_active', 'department', 'designation', 'join_date', 'created_at']
    search_fields = ['employee_id', 'name', 'email', 'phone', 'department__name', 'designation__name']
    ordering = ['-created_at']
    readonly_fields = ['id', 'created_at', 'updated_at', 'profile_picture_preview']
    
    fieldsets = (
        ('Profile', {
            'fields': ('profile_picture_preview', 'profile_picture'),
            'description': 'Profile picture is shown in the app. Only admins can change it here.'
        }),
        ('Basic Information', {
            'fields': ('id', 'employee_id', 'name', 'email', 'phone', 'password')
        }),
        ('Employment Details', {
            'fields': ('department', 'designation', 'join_date', 'is_active')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at')
        }),
    )
    
    def profile_picture_preview(self, obj):
        if obj and obj.profile_picture:
            label = f'{obj.employee_id} - {obj.name}' if obj.employee_id and obj.name else 'Profile picture'
            return mark_safe(
                '<div style="margin-bottom: 12px;">'
                '<img src="%s" alt="%s" style="'
                'width: 120px; height: 120px; object-fit: cover; border-radius: 50%%; '
                'border: 3px solid #e0e0e0; box-shadow: 0 2px 8px rgba(0,0,0,0.1); '
                'display: block;" />'
                '<span style="display: block; margin-top: 8px; font-size: 13px; color: #666;">%s</span>'
                '</div>'
                % (obj.profile_picture.url, label, label)
            )
        return mark_safe(
            '<div style="width: 120px; height: 120px; border-radius: 50%%; '
            'background: #f5f5f5; border: 2px dashed #ccc; display: flex; align-items: center; '
            'justify-content: center; color: #999; font-size: 12px; text-align: center; padding: 8px;">'
            'No image set</div>'
        )
    
    profile_picture_preview.short_description = 'Profile picture'

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(department__in=permitted)

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == 'department' and not request.user.is_superuser:
            permitted = get_permitted_departments(request.user)
            kwargs['queryset'] = permitted
        return super().formfield_for_foreignkey(db_field, request, **kwargs)
    
    def save_model(self, request, obj, form, change):
        # Hash password if it's being set/changed
        if 'password' in form.changed_data:
            obj.set_password(form.cleaned_data['password'])
        super().save_model(request, obj, form, change)
