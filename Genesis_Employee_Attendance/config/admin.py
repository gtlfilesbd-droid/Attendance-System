"""
Custom admin for User and Group with export support.
Must be imported before admin URLs are loaded.
"""
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin, GroupAdmin as BaseGroupAdmin
from django.contrib.auth.models import User, Group
from .admin_export import AdminExportMixin


class UserAdminWithExport(AdminExportMixin, BaseUserAdmin):
    change_list_template = 'admin/change_list_export.html'


class GroupAdminWithExport(AdminExportMixin, BaseGroupAdmin):
    change_list_template = 'admin/change_list_export.html'


admin.site.unregister(User)
admin.site.unregister(Group)
admin.site.register(User, UserAdminWithExport)
admin.site.register(Group, GroupAdminWithExport)
