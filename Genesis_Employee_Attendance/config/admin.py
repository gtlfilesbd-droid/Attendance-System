"""
Custom admin for User and Group with export support.
Must be imported before admin URLs are loaded.
"""
from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin, GroupAdmin as BaseGroupAdmin
from django.contrib.auth.models import User, Group
from employees.models import UserDepartmentPermission
from .admin_export import AdminExportMixin


class UserChangeWithPasswordForm(forms.ModelForm):
    """
    Extend the default Django User change form to allow optionally setting a new
    password from the same 'Change user' page.

    If password fields are left empty, the password is unchanged.
    """

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

    def clean(self):
        cleaned = super().clean()
        p1 = cleaned.get('new_password1') or ''
        p2 = cleaned.get('new_password2') or ''
        if (p1 or p2) and p1 != p2:
            raise forms.ValidationError('New password and confirmation do not match.')
        return cleaned


class UserDepartmentPermissionInline(admin.StackedInline):
    model = UserDepartmentPermission
    extra = 0
    filter_horizontal = ['departments']  # Horizontal multi-select for department assignment


class UserAdminWithExport(AdminExportMixin, BaseUserAdmin):
    change_list_template = 'admin/change_list_export.html'
    inlines = [UserDepartmentPermissionInline]
    form = UserChangeWithPasswordForm

    # Replace BaseUserAdmin fieldsets to avoid showing the hashed password summary
    # ("algorithm: pbkdf2_sha256 ..."). Password can be set inline via the
    # new_password1/new_password2 fields instead.
    fieldsets = (
        (None, {'fields': ('username',)}),
        ('Personal info', {'fields': ('first_name', 'last_name', 'email')}),
        ('Permissions', {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
        ('Set password', {'fields': ('new_password1', 'new_password2')}),
    )

    readonly_fields = ('last_login', 'date_joined')

    def save_model(self, request, obj, form, change):
        p1 = form.cleaned_data.get('new_password1') if hasattr(form, 'cleaned_data') else None
        if p1:
            obj.set_password(p1)
        super().save_model(request, obj, form, change)


class GroupAdminWithExport(AdminExportMixin, BaseGroupAdmin):
    change_list_template = 'admin/change_list_export.html'


admin.site.unregister(User)
admin.site.unregister(Group)
admin.site.register(User, UserAdminWithExport)
admin.site.register(Group, GroupAdminWithExport)
