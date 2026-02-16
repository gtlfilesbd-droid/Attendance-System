"""
Shared admin mixin and helpers for report filters (Attendance, DutySession, LocationLog).
"""
import json
from datetime import datetime, time
from django.utils import timezone
from employees.models import Employee, Department


def _parse_report_filters(request):
    """Parse start/end date, time, department, employee_ids from request.GET."""
    start_date = request.GET.get('start_date', '').strip()
    end_date = request.GET.get('end_date', '').strip()
    start_time_str = request.GET.get('start_time', '').strip()
    end_time_str = request.GET.get('end_time', '').strip()
    department = request.GET.get('department', '').strip()
    employee_ids_raw = request.GET.get('employee_id', '')
    if isinstance(employee_ids_raw, list):
        employee_ids = [str(x).strip() for x in employee_ids_raw if x]
    else:
        employee_ids = [x.strip() for x in str(employee_ids_raw).split(',') if x.strip()]

    start_datetime = None
    end_datetime = None
    if start_date:
        try:
            start_d = datetime.strptime(start_date, '%Y-%m-%d').date()
            if start_time_str:
                try:
                    parts = start_time_str.split(':')
                    h, m = int(parts[0]), int(parts[1]) if len(parts) > 1 else 0
                    s = int(parts[2]) if len(parts) > 2 else 0
                    start_datetime = timezone.make_aware(
                        datetime.combine(start_d, time(h, m, s)),
                        timezone.get_current_timezone()
                    )
                except (ValueError, IndexError):
                    start_datetime = timezone.make_aware(
                        datetime.combine(start_d, time.min),
                        timezone.get_current_timezone()
                    )
            else:
                start_datetime = timezone.make_aware(
                    datetime.combine(start_d, time.min),
                    timezone.get_current_timezone()
                )
        except ValueError:
            pass
    if end_date:
        try:
            end_d = datetime.strptime(end_date, '%Y-%m-%d').date()
            if end_time_str:
                try:
                    parts = end_time_str.split(':')
                    h, m = int(parts[0]), int(parts[1]) if len(parts) > 1 else 0
                    s = int(parts[2]) if len(parts) > 2 else 0
                    end_datetime = timezone.make_aware(
                        datetime.combine(end_d, time(h, m, s)),
                        timezone.get_current_timezone()
                    )
                except (ValueError, IndexError):
                    end_datetime = timezone.make_aware(
                        datetime.combine(end_d, time.max),
                        timezone.get_current_timezone()
                    )
            else:
                end_datetime = timezone.make_aware(
                    datetime.combine(end_d, time.max),
                    timezone.get_current_timezone()
                )
        except ValueError:
            pass

    return {
        'start_date': start_date,
        'end_date': end_date,
        'start_time': start_time_str,
        'end_time': end_time_str,
        'start_datetime': start_datetime,
        'end_datetime': end_datetime,
        'department': department,
        'employee_ids': employee_ids,
    }


def _report_filter_context(request):
    """Build context for report filter template: departments, employees JSON, current filter values."""
    departments = list(
        Department.objects.filter(is_active=True)
        .values_list('name', flat=True)
        .distinct()
        .order_by('name')
    )
    employees = list(
        Employee.objects.filter(is_active=True)
        .select_related('department')
        .values('id', 'name', 'employee_id', 'department__name')
    )
    for e in employees:
        e['id'] = str(e['id'])
        e['department'] = e.pop('department__name', None) or ''
    employees_json = json.dumps(employees)

    f = _parse_report_filters(request)
    return {
        'report_filter_departments': departments,
        'report_filter_employees_json': employees_json,
        'report_filter_start_date': f['start_date'],
        'report_filter_end_date': f['end_date'],
        'report_filter_start_time': f['start_time'],
        'report_filter_end_time': f['end_time'],
        'report_filter_department': f['department'],
        'report_filter_employee_ids': ','.join(f['employee_ids']),
    }


def format_time_12h(t):
    """Format time/datetime as hh:mm:ss AM/PM."""
    if t is None:
        return '—'
    if hasattr(t, 'strftime'):
        return t.strftime('%I:%M:%S %p')
    return str(t)


def format_total_hours_hhmmss(hours):
    """Convert decimal hours to HH:MM:SS (e.g. 8.5 -> 08:30:00)."""
    if hours is None:
        return '—'
    try:
        h = float(hours)
        total_secs = int(round(h * 3600))
        hrs, remainder = divmod(total_secs, 3600)
        mins, secs = divmod(remainder, 60)
        return f"{hrs:02d}:{mins:02d}:{secs:02d}"
    except (TypeError, ValueError):
        return '—'
