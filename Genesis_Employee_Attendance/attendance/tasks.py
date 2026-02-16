"""
Celery tasks for attendance app
"""
from decimal import Decimal
from celery import shared_task
from django.utils import timezone
from django.db.models import Q, Sum
from datetime import timedelta
from .models import AttendanceRecord, AttendanceAlert, LeaveRequest, DutySession, Attendance
from employees.models import Employee


@shared_task
def mark_absent_employees():
    """
    Mark employees as absent if they haven't checked in by end of day
    """
    today = timezone.now().date()
    yesterday = today - timedelta(days=1)
    
    # Get all active employees
    active_employees = Employee.objects.filter(is_active_employee=True)
    
    for employee in active_employees:
        # Check if employee has leave approved for yesterday
        has_leave = LeaveRequest.objects.filter(
            employee=employee,
            status='APPROVED',
            start_date__lte=yesterday,
            end_date__gte=yesterday
        ).exists()
        
        if has_leave:
            continue
        
        # Check if attendance record exists
        attendance = AttendanceRecord.objects.filter(
            employee=employee,
            date=yesterday
        ).first()
        
        if not attendance:
            # Create absent record
            AttendanceRecord.objects.create(
                employee=employee,
                date=yesterday,
                status='ABSENT'
            )
            
            # Create alert
            AttendanceAlert.objects.create(
                employee=employee,
                alert_type='ABSENT',
                severity='HIGH',
                message=f'{employee.get_full_name()} was marked absent for {yesterday}'
            )
        elif attendance.check_in_time and not attendance.check_out_time:
            # Create missing checkout alert
            AttendanceAlert.objects.create(
                employee=employee,
                attendance_record=attendance,
                alert_type='MISSING_CHECKOUT',
                severity='MEDIUM',
                message=f'{employee.get_full_name()} forgot to check out on {yesterday}'
            )
    
    return f"Processed attendance for {active_employees.count()} employees"


@shared_task
def check_late_arrivals():
    """
    Check for late arrivals and create alerts
    """
    today = timezone.now().date()
    
    # Get attendance records with check-in time
    records = AttendanceRecord.objects.filter(
        date=today,
        check_in_time__isnull=False,
        status='PRESENT'
    )
    
    late_count = 0
    for record in records:
        # Check if employee has a shift assigned
        employee_shift = record.employee.shifts.filter(is_current=True).first()
        if not employee_shift:
            continue
        
        # Get shift start time
        shift_start = employee_shift.shift.start_time
        check_in_time = record.check_in_time.time()
        
        # If checked in more than 15 minutes late
        from datetime import datetime, timedelta
        shift_start_dt = datetime.combine(today, shift_start)
        grace_period = shift_start_dt + timedelta(minutes=15)
        check_in_dt = datetime.combine(today, check_in_time)
        
        if check_in_dt > grace_period:
            record.status = 'LATE'
            record.save()
            
            # Create alert if not already exists
            if not AttendanceAlert.objects.filter(
                employee=record.employee,
                attendance_record=record,
                alert_type='LATE'
            ).exists():
                AttendanceAlert.objects.create(
                    employee=record.employee,
                    attendance_record=record,
                    alert_type='LATE',
                    severity='MEDIUM',
                    message=f'{record.employee.get_full_name()} arrived late on {today}'
                )
                late_count += 1
    
    return f"Found {late_count} late arrivals"


@shared_task
def calculate_daily_hours():
    """
    Calculate total hours for all attendance records without check-out time
    """
    yesterday = timezone.now().date() - timedelta(days=1)
    
    records = AttendanceRecord.objects.filter(
        date=yesterday,
        check_in_time__isnull=False,
        check_out_time__isnull=False,
        total_hours=0
    )
    
    for record in records:
        record.calculate_hours()
    
    return f"Calculated hours for {records.count()} records"


@shared_task
def send_attendance_reminders():
    """
    Send reminders to employees who haven't checked in
    """
    from django.core.mail import send_mail
    from django.conf import settings
    
    today = timezone.now().date()
    current_time = timezone.now().time()
    
    # Check if it's past 10 AM
    if current_time.hour < 10:
        return "Too early for reminders"
    
    # Get active employees who haven't checked in
    active_employees = Employee.objects.filter(is_active_employee=True)
    
    reminder_count = 0
    for employee in active_employees:
        # Check if already checked in
        has_attendance = AttendanceRecord.objects.filter(
            employee=employee,
            date=today,
            check_in_time__isnull=False
        ).exists()
        
        # Check if on leave
        has_leave = LeaveRequest.objects.filter(
            employee=employee,
            status='APPROVED',
            start_date__lte=today,
            end_date__gte=today
        ).exists()
        
        if not has_attendance and not has_leave and employee.email:
            # Send email reminder
            try:
                send_mail(
                    'Attendance Reminder',
                    f'Hi {employee.first_name},\n\n'
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
    Generate monthly attendance reports
    """
    from django.db.models import Count, Avg, Sum
    
    today = timezone.now().date()
    first_day = today.replace(day=1)
    
    employees = Employee.objects.filter(is_active_employee=True)
    
    report_data = []
    for employee in employees:
        records = AttendanceRecord.objects.filter(
            employee=employee,
            date__gte=first_day,
            date__lt=today
        )
        
        stats = {
            'employee_id': employee.employee_id,
            'name': employee.get_full_name(),
            'total_days': records.count(),
            'present_days': records.filter(status='PRESENT').count(),
            'absent_days': records.filter(status='ABSENT').count(),
            'late_days': records.filter(status='LATE').count(),
            'total_hours': records.aggregate(Sum('total_hours'))['total_hours__sum'] or 0,
            'avg_hours': records.aggregate(Avg('total_hours'))['total_hours__avg'] or 0,
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


def _auto_close_session(session, remark, end_lat=None, end_lon=None, end_addr=None):
    """Close a DutySession with remark. Updates end_time, total_hours, end location, remarks."""
    now = timezone.now()
    session.end_time = now
    session.end_latitude = end_lat
    session.end_longitude = end_lon
    session.end_address = end_addr
    delta = session.end_time - session.start_time
    session.total_hours = round(Decimal(delta.total_seconds()) / Decimal(3600), 2)
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

        # Priority 1: Date change
        if session.date < today:
            remark = "Date changes."

        # Priority 2: 9 hours active
        elif remark is None and (now - session.start_time).total_seconds() >= nine_hours_secs:
            remark = "9 hours active."

        # Priority 3: 30 min no LocationLog
        elif remark is None:
            last_log = (
                LocationLog.objects.filter(employee=session.employee)
                .order_by('-timestamp')
                .values_list('timestamp', flat=True)
                .first()
            )
            if last_log is None or last_log < cutoff_30min:
                remark = "User kept mobile network turned off for 30 minutes."

        if remark:
            last_log_obj = (
                LocationLog.objects.filter(employee=session.employee)
                .order_by('-timestamp')
                .first()
            )
            end_lat = end_lon = end_addr = None
            if last_log_obj and last_log_obj.location:
                end_lat = last_log_obj.location.y if hasattr(last_log_obj.location, 'y') else None
                end_lon = last_log_obj.location.x if hasattr(last_log_obj.location, 'x') else None
                end_addr = last_log_obj.address
            _auto_close_session(session, remark, end_lat=end_lat, end_lon=end_lon, end_addr=end_addr)
            closed += 1

    return f"Auto-closed {closed} duty sessions"
