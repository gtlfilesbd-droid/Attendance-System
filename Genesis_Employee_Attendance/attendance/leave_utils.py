"""
Helpers for admin-managed leave: materialize LEAVE into Attendance and safe cleanup.
"""
from datetime import timedelta

from django.core.exceptions import ValidationError

from .models import Attendance, DutySession, LeaveAssignment


def iter_dates_inclusive(start_date, end_date):
    d = start_date
    while d <= end_date:
        yield d
        d += timedelta(days=1)


def date_set_in_range(start_date, end_date):
    return set(iter_dates_inclusive(start_date, end_date))


def duty_sessions_exist(employee, start_date, end_date):
    return DutySession.objects.filter(
        employee=employee,
        date__gte=start_date,
        date__lte=end_date,
    ).exists()


def validate_leave_no_duty_sessions(employee, start_date, end_date):
    if duty_sessions_exist(employee, start_date, end_date):
        raise ValidationError(
            'Cannot assign leave: this employee has duty session(s) in the selected date range. '
            'Remove or adjust duty sessions first.'
        )


def leave_remarks(reason):
    r = (reason or '').strip()
    return f'Leave: {r}' if r else 'Leave'


def materialize_leave_attendance(employee, start_date, end_date, reason):
    """Create/update one Attendance row per day with status=LEAVE."""
    remark = leave_remarks(reason)
    for d in iter_dates_inclusive(start_date, end_date):
        Attendance.objects.update_or_create(
            employee=employee,
            date=d,
            defaults={
                'status': 'LEAVE',
                'remarks': remark,
                'first_location_time': None,
                'last_location_time': None,
                'check_in_time': None,
                'check_out_time': None,
                'total_hours': 0,
                'total_locations_logged': 0,
            },
        )


def remove_leave_attendance_safe(employee, start_date, end_date):
    """
    Remove LEAVE-only attendance rows for dates in range when no DutySession exists for that day.
    Used when deleting a LeaveAssignment or when dates drop out of an updated range.
    """
    for d in iter_dates_inclusive(start_date, end_date):
        if DutySession.objects.filter(employee=employee, date=d).exists():
            continue
        Attendance.objects.filter(employee=employee, date=d, status='LEAVE').delete()


def remove_leave_dates_removed_from_range(employee, old_start, old_end, new_start, new_end):
    """After shrinking/moving a leave range, clear LEAVE rows for old dates not in the new range."""
    old_dates = date_set_in_range(old_start, old_end)
    new_dates = date_set_in_range(new_start, new_end)
    for d in sorted(old_dates - new_dates):
        remove_leave_attendance_safe(employee, d, d)


def leave_assignment_covers_date(employee, on_date):
    return LeaveAssignment.objects.filter(
        employee=employee,
        start_date__lte=on_date,
        end_date__gte=on_date,
    ).exists()


def existing_pairs_from_leave_assignments(employee_ids, range_start, range_end):
    """
    (employee_id, date) pairs covered by any LeaveAssignment overlapping [range_start, range_end].
    Used so synthetic ABSENT is not generated for leave days without an Attendance row yet.
    """
    pairs = set()
    if not employee_ids:
        return pairs
    qs = LeaveAssignment.objects.filter(
        employee_id__in=employee_ids,
        start_date__lte=range_end,
        end_date__gte=range_start,
    ).only('employee_id', 'start_date', 'end_date')
    for la in qs:
        rs = max(la.start_date, range_start)
        re_date = min(la.end_date, range_end)
        if rs > re_date:
            continue
        for d in iter_dates_inclusive(rs, re_date):
            pairs.add((la.employee_id, d))
    return pairs
