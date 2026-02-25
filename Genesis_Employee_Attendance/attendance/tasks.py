"""
Celery tasks for attendance app
"""
import logging
from decimal import Decimal
from celery import shared_task
from django.utils import timezone
from django.db.models import Q, Sum
from datetime import timedelta
from .models import DutySession, Attendance
from .utils import calculate_duration_seconds
from employees.models import Employee


@shared_task
def mark_absent_employees():
    """
    Mark employees as absent if they haven't checked in by end of day.
    Uses Attendance model (no LeaveRequest or AttendanceAlert in this schema).
    """
    today = timezone.now().date()
    yesterday = today - timedelta(days=1)

    active_employees = Employee.objects.filter(is_active=True)

    for employee in active_employees:
        attendance = Attendance.objects.filter(
            employee=employee,
            date=yesterday
        ).first()

        if not attendance:
            Attendance.objects.create(
                employee=employee,
                date=yesterday,
                status='ABSENT'
            )

    return f"Processed attendance for {active_employees.count()} employees"


@shared_task
def check_late_arrivals():
    """
    Check for late arrivals (check-in after 9:45 AM). Mark as LATE if applicable.
    """
    from datetime import datetime, time

    today = timezone.now().date()
    grace_time = time(9, 45)  # 9:45 AM grace period

    records = Attendance.objects.filter(
        date=today,
        check_in_time__isnull=False,
        status='PRESENT'
    )

    late_count = 0
    for record in records:
        if record.check_in_time and record.check_in_time > grace_time:
            record.status = 'LATE'
            record.save()
            late_count += 1

    return f"Found {late_count} late arrivals"


@shared_task
def calculate_daily_hours():
    """
    Calculate total hours for all attendance records with check-in and check-out.
    """
    yesterday = timezone.now().date() - timedelta(days=1)

    records = Attendance.objects.filter(
        date=yesterday,
        check_in_time__isnull=False,
        check_out_time__isnull=False,
        total_hours=0
    )

    for record in records:
        record.calculate_total_hours()
        record.save()

    return f"Calculated hours for {records.count()} records"


@shared_task
def send_attendance_reminders():
    """
    Send email reminders to employees who haven't checked in today.
    """
    from django.core.mail import send_mail
    from django.conf import settings

    today = timezone.now().date()
    current_time = timezone.now().time()

    if current_time.hour < 10:
        return "Too early for reminders"

    active_employees = Employee.objects.filter(is_active=True)
    reminder_count = 0

    for employee in active_employees:
        has_attendance = Attendance.objects.filter(
            employee=employee,
            date=today,
            check_in_time__isnull=False
        ).exists()

        if not has_attendance and employee.email and getattr(settings, 'DEFAULT_FROM_EMAIL', None):
            try:
                send_mail(
                    'Attendance Reminder',
                    f'Hi {employee.name},\n\n'
                    f'This is a reminder to check in for today if you haven\'t already.\n\n'
                    f'Thank you,\nHR Team',
                    settings.DEFAULT_FROM_EMAIL,
                    [employee.email],
                    fail_silently=True,
                )
                reminder_count += 1
            except Exception as e:
                print(f"Failed to send email to {employee.email}: {e}")

    return f"Sent {reminder_count} reminders"


@shared_task
def generate_attendance_reports():
    """
    Generate monthly attendance reports.
    """
    from django.db.models import Avg

    today = timezone.now().date()
    first_day = today.replace(day=1)

    employees = Employee.objects.filter(is_active=True)
    report_data = []

    for employee in employees:
        records = Attendance.objects.filter(
            employee=employee,
            date__gte=first_day,
            date__lt=today
        )

        stats = {
            'employee_id': employee.employee_id,
            'name': employee.name,
            'total_days': records.count(),
            'present_days': records.filter(status='PRESENT').count(),
            'absent_days': records.filter(status='ABSENT').count(),
            'late_days': records.filter(status='LATE').count(),
            'total_hours': records.aggregate(s=Sum('total_hours'))['s'] or Decimal('0'),
            'avg_hours': records.aggregate(a=Avg('total_hours'))['a'] or Decimal('0'),
        }
        report_data.append(stats)

    return f"Generated report for {len(report_data)} employees"


def _update_attendance_for_date(employee, date):
    """Set Attendance.total_hours for employee+date to sum of all closed DutySessions for that date."""
    total = DutySession.objects.filter(
        employee=employee,
        date=date,
        end_time__isnull=False,
    ).aggregate(s=Sum('total_hours'))['s'] or Decimal('0.00')
    first_session = DutySession.objects.filter(employee=employee, date=date).order_by('start_time').first()
    last_session = DutySession.objects.filter(employee=employee, date=date).order_by('-start_time').first()
    first_time = timezone.localtime(first_session.start_time).time() if first_session else None
    last_time = (
        timezone.localtime(last_session.end_time).time()
        if last_session and last_session.end_time
        else timezone.localtime(last_session.start_time).time() if last_session else None
    )
    Attendance.objects.update_or_create(
        employee=employee,
        date=date,
        defaults={
            'total_hours': total,
            'first_location_time': first_time,
            'last_location_time': last_time,
            'check_in_time': first_time,
            'check_out_time': last_time,
            'status': 'PRESENT',
        },
    )


def _auto_close_session(session, remark, end_lat=None, end_lon=None, end_addr=None, end_time=None):
    """Close a DutySession with remark. Updates end_time, total_hours, end location, remarks."""
    now = timezone.now()
    session.end_time = end_time if end_time is not None else now
    session.end_latitude = end_lat
    session.end_longitude = end_lon
    session.end_address = end_addr
    secs = calculate_duration_seconds(session.start_time, session.end_time)
    session.total_hours = Decimal(secs) / Decimal(3600)
    session.remarks = remark
    session.save()
    _update_attendance_for_date(session.employee, session.date)


@shared_task(name='attendance.auto_end_duty_sessions')
def auto_end_duty_sessions():
    """
    Auto-end open duty sessions:
    1. Date change: session.date < today -> remark "Date changes."
    2. 9 hours active: duration >= 9h -> remark "9 hours active."
    3. 30 min inactive: no LocationLog for employee in last 30 min -> remark "User kept mobile network turned off for 30 minutes."
    """
    from tracking.models import LocationLog

    now = timezone.now()
    today = timezone.localdate()
    cutoff_30min = now - timedelta(minutes=30)
    nine_hours_secs = 9 * 3600

    open_sessions = list(DutySession.objects.filter(end_time__isnull=True).select_related('employee'))
    closed = 0

    for session in open_sessions:
        remark = None
        auto_close_end_time = None  # For 30-min case: last location + 30 min (clamped to now)

        # Normalize session start to timezone-aware for duration and LocationLog scope
        session_start = session.start_time
        if timezone.is_naive(session_start):
            session_start = timezone.make_aware(session_start, timezone.get_current_timezone())

        # Priority 1: Date change
        if session.date < today:
            remark = "Date changes."

        # Priority 2: 9 hours active (timezone-safe duration)
        elif remark is None and (now - session_start).total_seconds() >= nine_hours_secs:
            remark = "9 hours active."

        # Priority 3: 30 min no LocationLog (scoped to this session; timezone-safe comparison)
        elif remark is None:
            last_log = (
                LocationLog.objects.filter(
                    employee=session.employee,
                    timestamp__gte=session_start,
                )
                .order_by('-timestamp')
                .values_list('timestamp', flat=True)
                .first()
            )
            if last_log is not None and timezone.is_naive(last_log):
                last_log = timezone.make_aware(last_log, timezone.get_current_timezone())
            if last_log is None or last_log < cutoff_30min:
                remark = "User kept mobile network turned off for 30 minutes."
                if last_log is not None:
                    computed = last_log + timedelta(minutes=30)
                    auto_close_end_time = min(computed, now)

        if remark:
            last_log_obj = (
                LocationLog.objects.filter(
                    employee=session.employee,
                    timestamp__gte=session_start,
                )
                .order_by('-timestamp')
                .first()
            )
            end_lat = end_lon = end_addr = None
            if last_log_obj and last_log_obj.location:
                end_lat = last_log_obj.location.y if hasattr(last_log_obj.location, 'y') else None
                end_lon = last_log_obj.location.x if hasattr(last_log_obj.location, 'x') else None
                end_addr = last_log_obj.address
            logging.getLogger(__name__).info(
                "Auto-closed duty session id=%s employee=%s remark=%s",
                session.id, getattr(session.employee, 'name', session.employee_id), remark,
            )
            _auto_close_session(
                session, remark,
                end_lat=end_lat, end_lon=end_lon, end_addr=end_addr,
                end_time=auto_close_end_time,
            )
            closed += 1

    return f"Auto-closed {closed} duty sessions"
