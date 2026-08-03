from django.contrib import admin
from django import forms
from django.contrib import messages
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone
from django.utils.safestring import mark_safe
from config.admin_export import AdminExportMixin
from .models import Employee, Department, Designation, DeviceToken
from .department_permissions import get_permitted_departments


# Related managers whose rows must not be loaded into the delete confirmation page.
# Format: (related_name, verbose label for confirmation summary)
_EMPLOYEE_RELATED_COUNTS = (
    ('location_logs', 'location logs'),
    ('mobile_logs', 'mobile logs'),
    ('login_logs', 'login logs'),
    ('location_anomalies', 'location anomalies'),
    ('attendances', 'attendance records'),
    ('duty_sessions', 'duty sessions'),
    ('leave_assignments', 'leave assignments'),
    ('todo_tasks', 'to-do tasks'),
    ('device_tokens', 'device tokens'),
)


def _purge_employee_related(employee):
    """
    Efficiently delete high-volume related rows before removing an Employee.
    Avoids NestedObjects / ORM collector loading every LocationLog into memory.
    Linked Django User is unlinked, not deleted.
    """
    from attendance.models import Attendance, DutySession, LeaveAssignment
    from audit.models import MobileLog, UserLoginLog
    from todos.models import EmployeeTodoPermission, TodoTask
    from tracking.models import LocationAnomaly, LocationLog

    LocationLog.objects.filter(employee=employee).delete()
    MobileLog.objects.filter(employee=employee).delete()
    UserLoginLog.objects.filter(employee=employee).delete()
    LocationAnomaly.objects.filter(employee=employee).delete()
    Attendance.objects.filter(employee=employee).delete()
    DutySession.objects.filter(employee=employee).delete()
    LeaveAssignment.objects.filter(employee=employee).delete()
    TodoTask.objects.filter(employee=employee).delete()
    TodoTask.objects.filter(assigned_by=employee).update(assigned_by=None)
    EmployeeTodoPermission.objects.filter(employee=employee).delete()
    DeviceToken.objects.filter(employee=employee).delete()
    if employee.user_id:
        Employee.objects.filter(pk=employee.pk).update(user=None)
        employee.user = None


class EmployeeAdminForm(forms.ModelForm):
    """
    Admin form that treats Employee.password as a raw password input.
    - Leave blank to keep existing password (on change)
    - If provided, it will be hashed in EmployeeAdmin.save_model()
    """

    password = forms.CharField(
        label='Password',
        required=False,
        widget=forms.PasswordInput(render_value=False, attrs={'autocomplete': 'new-password'}),
        help_text='Leave blank to keep the current password.',
    )

    class Meta:
        model = Employee
        fields = '__all__'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Never show the stored hash in the form
        if 'password' in self.fields:
            self.fields['password'].initial = ''


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
    form = EmployeeAdminForm
    actions = ['assign_leave_for_today']

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

    def get_deleted_objects(self, objs, request):
        """
        Summarize related row counts instead of NestedObjects loading every
        LocationLog / MobileLog into the confirmation page (which times out).
        """
        deleted_objects = []
        model_count = {}
        for obj in objs:
            related_lines = []
            for related_name, label in _EMPLOYEE_RELATED_COUNTS:
                manager = getattr(obj, related_name, None)
                if manager is None:
                    continue
                try:
                    count = manager.count()
                except Exception:
                    continue
                if count:
                    model_count[label] = model_count.get(label, 0) + count
                    related_lines.append(f'{count} {label}')
            # OneToOne todo permission (optional)
            if hasattr(obj, 'todo_permission'):
                model_count['to-do permissions'] = model_count.get('to-do permissions', 0) + 1
                related_lines.append('1 to-do permission')
            assigned_count = getattr(obj, 'todo_tasks_assigned', None)
            if assigned_count is not None:
                try:
                    n = assigned_count.count()
                except Exception:
                    n = 0
                if n:
                    model_count['assigned-by references (will be cleared)'] = (
                        model_count.get('assigned-by references (will be cleared)', 0) + n
                    )
                    related_lines.append(f'{n} assigned-by references (cleared, not deleted)')
            if obj.user_id:
                related_lines.append('linked Django user (unlinked, not deleted)')
            if related_lines:
                deleted_objects.append([str(obj), related_lines])
            else:
                deleted_objects.append(str(obj))
        return deleted_objects, model_count, set(), []

    def delete_model(self, request, obj):
        with transaction.atomic():
            _purge_employee_related(obj)
            obj.delete()

    def delete_queryset(self, request, queryset):
        with transaction.atomic():
            for obj in queryset:
                _purge_employee_related(obj)
            queryset.delete()

    def save_model(self, request, obj, form, change):
        # Hash password if it's being set/changed (and not blank).
        # Blank means "keep existing password".
        if 'password' in form.changed_data:
            raw = (form.cleaned_data.get('password') or '').strip()
            if raw:
                obj.set_password(raw)
        super().save_model(request, obj, form, change)

    @admin.action(description='Assign leave for today')
    def assign_leave_for_today(self, request, queryset):
        from attendance.models import LeaveAssignment
        from attendance.leave_utils import materialize_leave_attendance, validate_leave_no_duty_sessions

        today = timezone.localdate()
        ok = 0
        skipped = []
        for emp in queryset:
            try:
                validate_leave_no_duty_sessions(emp, today, today)
            except ValidationError as exc:
                skipped.append(f'{emp.employee_id}: {exc.messages[0]}')
                continue
            LeaveAssignment.objects.update_or_create(
                employee=emp,
                start_date=today,
                end_date=today,
                defaults={'reason': '', 'created_by': request.user},
            )
            materialize_leave_attendance(emp, today, today, '')
            ok += 1
        self.message_user(request, f'Leave assigned for today to {ok} employee(s).', messages.SUCCESS)
        if skipped:
            self.message_user(
                request,
                'Skipped (duty session exists or validation failed): ' + ' | '.join(skipped[:15]),
                messages.WARNING,
            )
