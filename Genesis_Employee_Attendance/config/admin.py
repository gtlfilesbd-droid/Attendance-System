"""
Custom admin for User and Group with export support.
Must be imported before admin URLs are loaded.
"""
from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin, GroupAdmin as BaseGroupAdmin
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth.models import User, Group
from employees.department_permissions import get_permitted_departments
from employees.models import Employee, UserDepartmentPermission
from .admin_export import AdminExportMixin


def _employee_queryset_for_request(request):
    qs = Employee.objects.filter(is_active=True).select_related('department').order_by('name')
    if request.user.is_superuser:
        return qs
    permitted = get_permitted_departments(request.user)
    return qs.filter(department__in=permitted)


def sync_user_employee_link(user, employee):
    """Link or unlink a Django User to an Employee (stored on Employee.user)."""
    Employee.objects.filter(user=user).exclude(
        pk=employee.pk if employee else None
    ).update(user=None)
    if employee is None:
        return
    Employee.objects.filter(pk=employee.pk).update(user=user)


class UserChangeWithPasswordForm(forms.ModelForm):
    """
    Extend the default Django User change form to allow optionally setting a new
    password from the same 'Change user' page.

    If password fields are left empty, the password is unchanged.
    """

    linked_employee = forms.ModelChoiceField(
        queryset=Employee.objects.none(),
        required=False,
        label='Linked employee',
        help_text='Select the employee record for this dashboard user (TO-DO My Tasks, etc.). Leave empty to unlink.',
    )

    new_password1 = forms.CharField(
        label='New password',
        required=False,
        widget=forms.PasswordInput(render_value=False, attrs={'autocomplete': 'new-password'}),
        help_text='Leave blank to keep the current password.',
    )
    new_password2 = forms.CharField(
        label='Confirm new password',
        required=False,
        widget=forms.PasswordInput(render_value=False, attrs={'autocomplete': 'new-password'}),
    )

    class Meta:
        model = User
        fields = '__all__'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.instance and self.instance.pk:
            try:
                self.fields['linked_employee'].initial = self.instance.employee
            except Employee.DoesNotExist:
                pass

    def clean(self):
        cleaned = super().clean()
        p1 = cleaned.get('new_password1') or ''
        p2 = cleaned.get('new_password2') or ''
        if (p1 or p2) and p1 != p2:
            raise forms.ValidationError('New password and confirmation do not match.')
        return cleaned


class UserAddWithEmployeeForm(UserCreationForm):
    linked_employee = forms.ModelChoiceField(
        queryset=Employee.objects.none(),
        required=False,
        label='Linked employee',
        help_text='Optional: link this new user to an employee from the list.',
    )

    class Meta(UserCreationForm.Meta):
        model = User
        fields = ('username',)


class UserDepartmentPermissionInline(admin.StackedInline):
    model = UserDepartmentPermission
    extra = 0
    filter_horizontal = ['departments']  # Horizontal multi-select for department assignment


class UserAdminWithExport(AdminExportMixin, BaseUserAdmin):
    change_list_template = 'admin/change_list_export.html'
    inlines = [UserDepartmentPermissionInline]
    form = UserChangeWithPasswordForm
    add_form = UserAddWithEmployeeForm

    list_display = BaseUserAdmin.list_display + ('linked_employee_display',)

    # Replace BaseUserAdmin fieldsets to avoid showing the hashed password summary
    # ("algorithm: pbkdf2_sha256 ..."). Password can be set inline via the
    # new_password1/new_password2 fields instead.
    fieldsets = (
        (None, {'fields': ('username',)}),
        ('Personal info', {'fields': ('first_name', 'last_name', 'email')}),
        ('Employee link', {
            'fields': ('linked_employee',),
            'description': 'Link this dashboard user to an employee for TO-DO and other employee features.',
        }),
        ('Permissions', {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
        ('Set password', {'fields': ('new_password1', 'new_password2')}),
    )

    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('username', 'password1', 'password2', 'linked_employee'),
        }),
    )

    readonly_fields = ('last_login', 'date_joined')

    @admin.display(description='Employee')
    def linked_employee_display(self, obj):
        try:
            emp = obj.employee
        except Employee.DoesNotExist:
            return '—'
        dept = emp.department.name if emp.department_id else ''
        if dept:
            return f'{emp.name} ({emp.employee_id}) · {dept}'
        return f'{emp.name} ({emp.employee_id})'

    def get_form(self, request, obj=None, **kwargs):
        form = super().get_form(request, obj, **kwargs)
        qs = _employee_queryset_for_request(request)
        if 'linked_employee' in form.base_fields:
            form.base_fields['linked_employee'].queryset = qs
            form.base_fields['linked_employee'].label_from_instance = (
                lambda emp: f'{emp.name} ({emp.employee_id})'
                + (f' — {emp.department.name}' if emp.department_id else '')
            )
        return form

    def save_model(self, request, obj, form, change):
        p1 = form.cleaned_data.get('new_password1') if hasattr(form, 'cleaned_data') else None
        if p1:
            obj.set_password(p1)
        super().save_model(request, obj, form, change)
        if hasattr(form, 'cleaned_data') and 'linked_employee' in form.cleaned_data:
            sync_user_employee_link(obj, form.cleaned_data.get('linked_employee'))


class GroupAdminWithExport(AdminExportMixin, BaseGroupAdmin):
    change_list_template = 'admin/change_list_export.html'


admin.site.unregister(User)
admin.site.unregister(Group)
admin.site.register(User, UserAdminWithExport)
admin.site.register(Group, GroupAdminWithExport)
