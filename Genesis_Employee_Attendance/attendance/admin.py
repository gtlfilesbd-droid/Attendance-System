from django import forms
from django.contrib import admin
from django.contrib import messages
from django.http import HttpResponseRedirect
from django.urls import path
from django.utils import timezone
from datetime import datetime, timedelta
from django.db.models import Exists, OuterRef
from config.admin_export import AdminExportMixin
from employees.department_permissions import get_permitted_departments
from .models import Attendance, DutySession, LeaveAssignment
from .leave_utils import (
    materialize_leave_attendance,
    remove_leave_attendance_safe,
    remove_leave_dates_removed_from_range,
    validate_leave_no_duty_sessions,
)
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

    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path(
                'computed-absent/',
                self.admin_site.admin_view(self.computed_absent_view),
                name='attendance_attendance_computed_absent',
            ),
        ]
        return custom + urls

    def _parse_date_window(self, request):
        """
        Admin date filter uses [date__gte, date__lt). Return (start_date, end_date_inclusive)
        or (None, None) if missing/invalid.
        """
        gte = request.GET.get('date__gte')
        lt = request.GET.get('date__lt')
        if not (gte and lt):
            return None, None
        try:
            start_date = datetime.strptime(gte, '%Y-%m-%d').date()
            end_date = datetime.strptime(lt, '%Y-%m-%d').date() - timedelta(days=1)
            return start_date, end_date
        except Exception:
            return None, None

    def computed_absent_view(self, request):
        """
        Compute absent employees for a date window WITHOUT writing Attendance rows.
        Rules match dashboard/reports: absent if no duty session and no attendance row
        (and not on leave). Past-only, capped.
        """
        from employees.models import Employee
        from attendance.leave_utils import existing_pairs_from_leave_assignments

        start_date, end_date = self._parse_date_window(request)
        if start_date is None or end_date is None:
            today = timezone.localdate()
            start_date, end_date = today, today

        # Past-only (no future computation)
        today = timezone.localdate()
        if end_date > today:
            end_date = today

        # Hard cap to avoid heavy admin pages
        max_days = 7
        if (end_date - start_date).days > (max_days - 1):
            end_date = start_date + timedelta(days=max_days - 1)
            messages.warning(request, f'Date range capped to {max_days} day(s) for safety.')

        permitted = get_permitted_departments(request.user)
        emp_qs = Employee.objects.filter(is_active=True)
        if not request.user.is_superuser:
            emp_qs = emp_qs.filter(department__in=permitted)
        employees = list(emp_qs.only('id', 'employee_id', 'name', 'department_id'))
        emp_ids = [e.id for e in employees]

        if not emp_ids:
            context = dict(
                self.admin_site.each_context(request),
                title='Computed Absent',
                start_date=start_date,
                end_date=end_date,
                rows=[],
                total=0,
            )
            from django.template.response import TemplateResponse
            return TemplateResponse(request, 'admin/attendance/attendance/computed_absent.html', context)

        existing_att_pairs = set(
            Attendance.objects.filter(
                employee_id__in=emp_ids,
                date__gte=start_date,
                date__lte=end_date,
            ).values_list('employee_id', 'date')
        )
        duty_pairs = set(
            DutySession.objects.filter(
                employee_id__in=emp_ids,
                date__gte=start_date,
                date__lte=end_date,
            ).values_list('employee_id', 'date')
        )
        leave_pairs = existing_pairs_from_leave_assignments(set(emp_ids), start_date, end_date)
        leave_att_pairs = set(
            Attendance.objects.filter(
                employee_id__in=emp_ids,
                date__gte=start_date,
                date__lte=end_date,
                status='LEAVE',
            ).values_list('employee_id', 'date')
        )
        blocked = existing_att_pairs | duty_pairs | leave_pairs | leave_att_pairs

        emp_by_id = {e.id: e for e in employees}
        rows = []
        cur = start_date
        while cur <= end_date:
            for emp_id in emp_ids:
                if (emp_id, cur) in blocked:
                    continue
                e = emp_by_id.get(emp_id)
                if not e:
                    continue
                rows.append({'employee': e, 'date': cur})
            cur += timedelta(days=1)

        context = dict(
            self.admin_site.each_context(request),
            title='Computed Absent',
            start_date=start_date,
            end_date=end_date,
            rows=rows,
            total=len(rows),
            changelist_url='../',
        )
        from django.template.response import TemplateResponse
        return TemplateResponse(request, 'admin/attendance/attendance/computed_absent.html', context)

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee')
        if request.user.is_superuser:
            base_qs = qs
        else:
            permitted = get_permitted_departments(request.user)
            base_qs = qs.filter(employee__department__in=permitted)

        # Safety net: when viewing ABSENT rows for a specific date window,
        # exclude entries that now have duty session activity for that day.
        if request.GET.get('status__exact') == 'ABSENT':
            gte = request.GET.get('date__gte')
            lt = request.GET.get('date__lt')
            if gte and lt:
                try:
                    start_date = datetime.strptime(gte, '%Y-%m-%d').date()
                    end_date = datetime.strptime(lt, '%Y-%m-%d').date() - timedelta(days=1)
                    duty_exists = DutySession.objects.filter(
                        employee_id=OuterRef('employee_id'),
                        date=OuterRef('date'),
                    )
                    base_qs = base_qs.filter(date__gte=start_date, date__lte=end_date).annotate(
                        _has_duty=Exists(duty_exists)
                    ).exclude(_has_duty=True)
                except Exception:
                    pass
        return base_qs

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == 'employee' and not request.user.is_superuser:
            from employees.models import Employee
            permitted = get_permitted_departments(request.user)
            kwargs['queryset'] = Employee.objects.filter(department__in=permitted)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

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
        qs = super().get_queryset(request).select_related('employee')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == 'employee' and not request.user.is_superuser:
            from employees.models import Employee
            permitted = get_permitted_departments(request.user)
            kwargs['queryset'] = Employee.objects.filter(department__in=permitted)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

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


class LeaveAssignmentForm(forms.ModelForm):
    class Meta:
        model = LeaveAssignment
        fields = ('employee', 'start_date', 'end_date', 'reason')

    def clean(self):
        cleaned = super().clean()
        emp = cleaned.get('employee')
        sd = cleaned.get('start_date')
        ed = cleaned.get('end_date')
        if emp and sd and ed:
            if sd > ed:
                raise forms.ValidationError('Start date must be on or before end date.')
            validate_leave_no_duty_sessions(emp, sd, ed)
        return cleaned


@admin.register(LeaveAssignment)
class LeaveAssignmentAdmin(AdminExportMixin, admin.ModelAdmin):
    form = LeaveAssignmentForm
    change_list_template = 'admin/change_list_export.html'
    list_display = [
        'id', 'employee', 'start_date', 'end_date', 'reason',
        'created_by', 'created_at',
    ]
    list_filter = ['start_date', 'end_date', 'employee']
    search_fields = ['employee__employee_id', 'employee__name', 'employee__email', 'reason']
    ordering = ['-start_date', '-created_at']
    readonly_fields = ['created_at', 'updated_at']
    autocomplete_fields = ['employee']

    fieldsets = (
        (None, {
            'fields': ('employee', 'start_date', 'end_date', 'reason'),
            'description': (
                'Saves one Attendance row per day with status Leave for the selected range. '
                'Cannot overlap days where the employee already has a duty session.'
            ),
        }),
    )

    def get_queryset(self, request):
        qs = super().get_queryset(request).select_related('employee', 'created_by')
        if request.user.is_superuser:
            return qs
        permitted = get_permitted_departments(request.user)
        return qs.filter(employee__department__in=permitted)

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == 'employee' and not request.user.is_superuser:
            from employees.models import Employee
            permitted = get_permitted_departments(request.user)
            kwargs['queryset'] = Employee.objects.filter(department__in=permitted)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    def save_model(self, request, obj, form, change):
        prev = None
        if change:
            prev = LeaveAssignment.objects.filter(pk=obj.pk).first()
        if not change:
            obj.created_by = request.user
        super().save_model(request, obj, form, change)
        materialize_leave_attendance(obj.employee, obj.start_date, obj.end_date, obj.reason)
        if prev:
            if prev.employee_id != obj.employee_id:
                remove_leave_attendance_safe(prev.employee, prev.start_date, prev.end_date)
            else:
                remove_leave_dates_removed_from_range(
                    prev.employee, prev.start_date, prev.end_date, obj.start_date, obj.end_date
                )

    def delete_model(self, request, obj):
        remove_leave_attendance_safe(obj.employee, obj.start_date, obj.end_date)
        obj.delete()

    def delete_queryset(self, request, queryset):
        for o in queryset:
            remove_leave_attendance_safe(o.employee, o.start_date, o.end_date)
        queryset.delete()
