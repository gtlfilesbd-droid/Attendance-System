from decimal import Decimal
from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes, action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from rest_framework.pagination import PageNumberPagination
from django_filters.rest_framework import DjangoFilterBackend
from django.utils import timezone
from django.db.models import Q, Count, Sum, Avg
from datetime import datetime, timedelta
from .models import Attendance, DutySession
from employees.models import Employee
from tracking.models import LocationLog
from .serializers import (
    AttendanceSerializer, AttendanceReportSerializer, DailyAttendanceSummarySerializer
)
from employees.serializers import EmployeeProfileSerializer


class StandardResultsSetPagination(PageNumberPagination):
    """Standard pagination class"""
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 200


@api_view(['POST', 'DELETE'])
@permission_classes([IsAuthenticated])
def clear_my_data(request):
    """
    Delete all attendance and location data for the current (logged-in) employee.
    POST /api/attendance/clear-my-data/ or DELETE /api/attendance/clear-my-data/
    Requires employee JWT. Returns deleted counts.
    """
    user = request.user
    employee = user if isinstance(user, Employee) else getattr(user, 'employee', None)
    if not employee:
        return Response({
            'success': False,
            'message': 'Not an employee. Use employee JWT or link your user to an employee.',
        }, status=status.HTTP_403_FORBIDDEN)

    att_qs = Attendance.objects.filter(employee=employee)
    duty_qs = DutySession.objects.filter(employee=employee)
    loc_qs = LocationLog.objects.filter(employee=employee)
    att_count = att_qs.count()
    duty_count = duty_qs.count()
    loc_count = loc_qs.count()
    duty_qs.delete()
    att_qs.delete()
    loc_qs.delete()

    return Response({
        'success': True,
        'message': 'Your attendance and location data have been deleted.',
        'data': {
            'attendance_deleted': att_count,
            'duty_sessions_deleted': duty_count,
            'location_logs_deleted': loc_count,
        },
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def start_duty(request):
    """
    Start a duty session. Records start time and location.
    POST /api/attendance/start-duty/
    Body: latitude, longitude, optional address.
    If employee has an open session, it is auto-closed with end_time=now and current location.
    """
    user = request.user
    employee = user if isinstance(user, Employee) else getattr(user, 'employee', None)
    if not employee:
        return Response({
            'success': False,
            'message': 'Not an employee. Use employee JWT or link your user to an employee.',
        }, status=status.HTTP_403_FORBIDDEN)

    lat = request.data.get('latitude')
    lon = request.data.get('longitude')
    if lat is None or lon is None:
        return Response({
            'success': False,
            'message': 'latitude and longitude are required.',
        }, status=status.HTTP_400_BAD_REQUEST)
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return Response({
            'success': False,
            'message': 'latitude and longitude must be numbers.',
        }, status=status.HTTP_400_BAD_REQUEST)
    address = request.data.get('address') or ''

    now = timezone.now()
    today = now.date()

    # Auto-close any existing open session for this employee (end at current location)
    open_sessions = DutySession.objects.filter(employee=employee, end_time__isnull=True)
    for sess in open_sessions:
        sess.end_time = now
        sess.end_latitude = lat
        sess.end_longitude = lon
        sess.end_address = address
        delta = sess.end_time - sess.start_time
        sess.total_hours = round(Decimal(delta.total_seconds()) / Decimal(3600), 2)
        sess.save()
        # Update Attendance for that session's date
        _update_attendance_for_date(employee, sess.date)

    session = DutySession.objects.create(
        employee=employee,
        date=today,
        start_time=now,
        start_latitude=lat,
        start_longitude=lon,
        start_address=address or None,
        end_time=None,
        total_hours=Decimal('0.00'),
    )
    return Response({
        'success': True,
        'data': {
            'session_id': session.id,
            'start_time': session.start_time.isoformat(),
            'date': today.isoformat(),
        },
    }, status=status.HTTP_201_CREATED)


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
    last_time = (timezone.localtime(last_session.end_time).time()
                 if last_session and last_session.end_time else
                 timezone.localtime(last_session.start_time).time() if last_session else None)
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


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def end_duty(request):
    """
    End the current duty session. Records end time and location.
    POST /api/attendance/end-duty/
    Body: latitude, longitude, optional address.
    """
    user = request.user
    employee = user if isinstance(user, Employee) else getattr(user, 'employee', None)
    if not employee:
        return Response({
            'success': False,
            'message': 'Not an employee. Use employee JWT or link your user to an employee.',
        }, status=status.HTTP_403_FORBIDDEN)

    lat = request.data.get('latitude')
    lon = request.data.get('longitude')
    if lat is None or lon is None:
        return Response({
            'success': False,
            'message': 'latitude and longitude are required.',
        }, status=status.HTTP_400_BAD_REQUEST)
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return Response({
            'success': False,
            'message': 'latitude and longitude must be numbers.',
        }, status=status.HTTP_400_BAD_REQUEST)
    address = request.data.get('address') or ''

    session = DutySession.objects.filter(employee=employee, end_time__isnull=True).order_by('-start_time').first()
    if not session:
        return Response({
            'success': False,
            'message': 'No open duty session. Start duty first.',
        }, status=status.HTTP_400_BAD_REQUEST)

    now = timezone.now()
    session.end_time = now
    session.end_latitude = lat
    session.end_longitude = lon
    session.end_address = address or None
    session.remarks = "User End this session"
    delta = session.end_time - session.start_time
    session.total_hours = round(Decimal(delta.total_seconds()) / Decimal(3600), 2)
    session.save()

    _update_attendance_for_date(employee, session.date)

    return Response({
        'success': True,
        'data': {
            'session_id': session.id,
            'end_time': session.end_time.isoformat(),
            'total_hours': float(session.total_hours),
        },
    }, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def my_attendance(request):
    """
    Get employee's own attendance records
    GET /api/attendance/my-attendance/
    
    Query params:
    - start_date (YYYY-MM-DD, optional) - Default: 30 days ago
    - end_date (YYYY-MM-DD, optional) - Default: today
    - status (optional) - Filter by status (PRESENT, LATE, HALF_DAY, ABSENT)
    
    Returns attendance records for the specified date range
    """
    # Get query parameters
    start_date_str = request.query_params.get('start_date')
    end_date_str = request.query_params.get('end_date')
    status_filter = request.query_params.get('status')
    
    # Parse dates
    if start_date_str:
        try:
            start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({
                'success': False,
                'message': 'Invalid start_date format. Use YYYY-MM-DD'
            }, status=status.HTTP_400_BAD_REQUEST)
    else:
        start_date = timezone.now().date() - timedelta(days=30)
    
    if end_date_str:
        try:
            end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({
                'success': False,
                'message': 'Invalid end_date format. Use YYYY-MM-DD'
            }, status=status.HTTP_400_BAD_REQUEST)
    else:
        end_date = timezone.now().date()

    # Resolve Employee: JWT auth gives Employee; session auth gives User with .employee
    user = request.user
    employee = user if isinstance(user, Employee) else getattr(user, 'employee', None)
    if not employee:
        return Response({
            'success': False,
            'message': 'Not an employee. Use employee JWT or link your user to an employee.',
        }, status=status.HTTP_403_FORBIDDEN)
    
    # Duty sessions in range (closed sessions only for per-date total; include open for display)
    sessions_qs = DutySession.objects.filter(
        employee=employee,
        date__gte=start_date,
        date__lte=end_date
    ).order_by('-date', '-start_time')

    # Build by_date: group by date, each with sessions list and total_hours
    from collections import defaultdict
    by_date_map = defaultdict(list)
    for sess in sessions_qs:
        start_location = sess.start_address or f"{sess.start_latitude}, {sess.start_longitude}"
        end_location = (
            (sess.end_address or f"{sess.end_latitude}, {sess.end_longitude}")
            if sess.end_time else None
        )
        by_date_map[sess.date].append({
            'start_time': sess.start_time.isoformat(),
            'start_location': start_location,
            'end_time': sess.end_time.isoformat() if sess.end_time else None,
            'end_location': end_location,
            'total_hours': float(sess.total_hours),
        })

    by_date = []
    total_hours_overall = Decimal('0.00')
    for date in sorted(by_date_map.keys(), reverse=True):
        # Sessions in chronological order (oldest first) per date
        sessions_list = sorted(by_date_map[date], key=lambda s: s['start_time'] or '')
        date_total = sum(Decimal(str(s['total_hours'])) for s in sessions_list)
        total_hours_overall += date_total
        by_date.append({
            'date': date.isoformat(),
            'sessions': sessions_list,
            'total_hours': float(date_total),
        })

    # Summary (for compatibility and stats)
    att_queryset = Attendance.objects.filter(
        employee=employee,
        date__gte=start_date,
        date__lte=end_date
    )
    if status_filter:
        att_queryset = att_queryset.filter(status=status_filter)
    summary = {
        'total_days': len(by_date),
        'present_count': att_queryset.filter(status='PRESENT').count(),
        'late_count': att_queryset.filter(status='LATE').count(),
        'half_day_count': att_queryset.filter(status='HALF_DAY').count(),
        'absent_count': att_queryset.filter(status='ABSENT').count(),
        'total_hours': float(total_hours_overall),
        'average_hours': float(total_hours_overall / len(by_date)) if by_date else 0,
    }

    return Response({
        'success': True,
        'data': {
            'by_date': by_date,
            'summary': summary,
            'date_range': {
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat()
            }
        }
    })


@api_view(['GET'])
@permission_classes([IsAdminUser])
def all_attendance(request):
    """
    Get all employees' attendance records (Admin only)
    GET /api/attendance/all/
    
    Query params:
    - date (YYYY-MM-DD, optional) - Specific date
    - start_date (YYYY-MM-DD, optional)
    - end_date (YYYY-MM-DD, optional)
    - department (optional) - Filter by department
    - status (optional) - Filter by status
    - employee_id (UUID, optional) - Specific employee or multiple (employee_id=id1&employee_id=id2)
    - include_sessions (1, optional) - Include DutySession details and derived times per record
    - include_absent (1, optional) - Include synthetic absent records for in-scope employees with no DutySession
    - page (int, optional) - Page number
    - page_size (int, optional) - Items per page
    
    Returns attendance records with filtering and pagination
    """
    # Get query parameters
    date_str = request.query_params.get('date')
    start_date_str = request.query_params.get('start_date')
    end_date_str = request.query_params.get('end_date')
    department = request.query_params.get('department')
    status_filter = request.query_params.get('status')
    employee_ids = request.query_params.getlist('employee_id')
    include_sessions = request.query_params.get('include_sessions') == '1'
    include_absent = request.query_params.get('include_absent') == '1'
    
    # Build base query
    queryset = Attendance.objects.all().select_related('employee')
    
    # Apply filters
    if date_str:
        try:
            filter_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            queryset = queryset.filter(date=filter_date)
        except ValueError:
            return Response({
                'success': False,
                'message': 'Invalid date format. Use YYYY-MM-DD'
            }, status=status.HTTP_400_BAD_REQUEST)
    elif start_date_str and end_date_str:
        try:
            start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
            end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
            queryset = queryset.filter(date__gte=start_date, date__lte=end_date)
        except ValueError:
            return Response({
                'success': False,
                'message': 'Invalid date format. Use YYYY-MM-DD'
            }, status=status.HTTP_400_BAD_REQUEST)
    else:
        # Default: last 7 days
        since = timezone.now().date() - timedelta(days=7)
        queryset = queryset.filter(date__gte=since)
    
    # Filter by department
    if department:
        queryset = queryset.filter(employee__department__name=department)
    
    # Filter by status
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    
    # Filter by employee (supports multiple)
    if employee_ids:
        queryset = queryset.filter(employee__id__in=employee_ids)
    
    # Order by date descending, then employee name
    queryset = queryset.order_by('-date', 'employee__name')
    
    # Build synthetic absent records when requested
    synthetic_absent = []
    if include_absent:
        # Resolve date range
        if date_str:
            try:
                filter_date = datetime.strptime(date_str, '%Y-%m-%d').date()
                start_date = end_date = filter_date
            except ValueError:
                start_date = end_date = None
        elif start_date_str and end_date_str:
            try:
                start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
                end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
            except ValueError:
                start_date = end_date = None
        else:
            since = timezone.now().date() - timedelta(days=7)
            start_date = since
            end_date = timezone.now().date()
        
        if start_date is not None and end_date is not None and (status_filter is None or status_filter == 'ABSENT'):
            # In-scope employees: department, employee_ids, or all active
            emp_qs = Employee.objects.filter(is_active=True)
            if department:
                emp_qs = emp_qs.filter(department__name=department)
            if employee_ids:
                emp_qs = emp_qs.filter(id__in=employee_ids)
            in_scope_ids = set(emp_qs.values_list('id', flat=True))
            
            # Existing records: employee+date we already have (from Attendance or DutySession)
            existing_att = set(
                Attendance.objects.filter(
                    date__gte=start_date, date__lte=end_date
                ).values_list('employee_id', 'date')
            )
            on_or_off_duty = set(
                DutySession.objects.filter(
                    date__gte=start_date, date__lte=end_date
                ).values_list('employee_id', 'date')
            )
            existing = existing_att | on_or_off_duty
            
            # Apply same filters to existing for consistency
            if department:
                emp_by_dept = set(Employee.objects.filter(department__name=department, is_active=True).values_list('id', flat=True))
                existing = {(e, d) for e, d in existing if e in emp_by_dept}
            if employee_ids:
                emp_ids_set = set(employee_ids)
                existing = {(e, d) for e, d in existing if str(e) in emp_ids_set or e in emp_ids_set}
            
            emp_cache = {e.id: e for e in Employee.objects.filter(id__in=in_scope_ids).select_related()}
            emp_serializer = EmployeeProfileSerializer(context={'request': request})
            
            current = start_date
            while current <= end_date:
                for emp_id in in_scope_ids:
                    if (emp_id, current) not in existing:
                        emp = emp_cache.get(emp_id)
                        if not emp:
                            continue
                        synthetic_absent.append({
                            'id': None,
                            'employee': str(emp.id),
                            'employee_details': emp_serializer.to_representation(emp),
                            'employee_name': emp.name,
                            'employee_id': emp.employee_id or '',
                            'date': current.isoformat(),
                            'status': 'ABSENT',
                            'first_location_time': None,
                            'last_location_time': None,
                            'check_in_time': None,
                            'check_out_time': None,
                            'total_hours': 0,
                            'duration_hours': '0h 0m',
                            'total_locations_logged': 0,
                            'location_tracking_quality': 'No tracking',
                            'is_complete': False,
                            'is_overtime': False,
                            'sessions': [],
                            'check_in_time_str': None,
                            'check_out_time_str': None,
                            'total_hours_str': None,
                            'duty_status': 'absent',
                            'remarks': None,
                            'created_at': None,
                            'updated_at': None,
                        })
                current += timedelta(days=1)
    
    # Serialize real records
    serializer = AttendanceReportSerializer(
        queryset, many=True,
        context={'request': request, 'include_sessions': include_sessions}
    )
    all_data = list(serializer.data)
    
    # Add synthetic absent and sort by date desc, employee name
    all_data.extend(synthetic_absent)
    all_data.sort(key=lambda r: (-(datetime.strptime(r['date'], '%Y-%m-%d').date() if r.get('date') else timezone.now().date()).toordinal(), (r.get('employee_name') or '').lower()))
    
    # Paginate combined list if needed
    paginator = StandardResultsSetPagination()
    page_num = request.query_params.get('page', 1)
    try:
        page_num = max(1, int(page_num))
    except (TypeError, ValueError):
        page_num = 1
    page_size = request.query_params.get('page_size') or paginator.page_size
    try:
        page_size = min(paginator.max_page_size, max(1, int(page_size)))
    except (TypeError, ValueError):
        page_size = paginator.page_size
    
    start_idx = (page_num - 1) * page_size
    end_idx = start_idx + page_size
    page_data = all_data[start_idx:end_idx]
    
    if len(all_data) > page_size:
        from urllib.parse import urlencode
        base_url = request.build_absolute_uri(request.path)
        get_params = dict(request.GET.items())
        next_url = prev_url = None
        if end_idx < len(all_data):
            get_params['page'] = page_num + 1
            next_url = f'{base_url}?{urlencode(get_params)}'
        if start_idx > 0:
            get_params['page'] = page_num - 1
            prev_url = f'{base_url}?{urlencode(get_params)}'
        return Response({
            'count': len(all_data),
            'next': next_url,
            'previous': prev_url,
            'results': {
                'success': True,
                'data': page_data,
            }
        })
    
    return Response({
        'success': True,
        'data': page_data
    })


@api_view(['GET'])
@permission_classes([IsAdminUser])
def attendance_report(request):
    """
    Generate attendance report
    GET /api/attendance/report/
    
    Query params:
    - report_type (required) - 'daily', 'weekly', or 'monthly'
    - date (YYYY-MM-DD, optional) - Reference date (default: today)
    - department (optional) - Filter by department
    - format (optional) - 'json' (default) or 'summary'
    
    Returns:
    - daily: Summary for a specific day
    - weekly: Last 7 days summary
    - monthly: Current month summary
    """
    # Get parameters
    report_type = request.query_params.get('report_type', 'daily')
    date_str = request.query_params.get('date')
    department = request.query_params.get('department')
    report_format = request.query_params.get('format', 'json')
    
    # Parse date
    if date_str:
        try:
            reference_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({
                'success': False,
                'message': 'Invalid date format. Use YYYY-MM-DD'
            }, status=status.HTTP_400_BAD_REQUEST)
    else:
        reference_date = timezone.now().date()
    
    # Generate report based on type
    if report_type == 'daily':
        # Daily report
        summary_data = DailyAttendanceSummarySerializer.get_daily_summary(reference_date)
        
        # Get detailed records
        queryset = Attendance.objects.filter(date=reference_date)
        if department:
            queryset = queryset.filter(employee__department__name=department)
        
        records = AttendanceReportSerializer(queryset, many=True).data
        
        return Response({
            'success': True,
            'report_type': 'daily',
            'date': reference_date,
            'summary': summary_data,
            'records': records if report_format == 'json' else []
        })
    
    elif report_type == 'weekly':
        # Weekly report (last 7 days)
        end_date = reference_date
        start_date = end_date - timedelta(days=6)
        
        # Get daily summaries
        daily_summaries = []
        current_date = start_date
        while current_date <= end_date:
            summary = DailyAttendanceSummarySerializer.get_daily_summary(current_date)
            daily_summaries.append(summary)
            current_date += timedelta(days=1)
        
        # Calculate weekly totals
        weekly_summary = {
            'start_date': start_date,
            'end_date': end_date,
            'total_working_days': 7,
            'average_present_percentage': sum(d['present_percentage'] for d in daily_summaries) / 7,
            'total_hours_worked': sum(d['total_hours_worked'] for d in daily_summaries),
            'average_daily_hours': sum(d['average_hours_worked'] for d in daily_summaries) / 7,
            'total_overtime_instances': sum(d['overtime_count'] for d in daily_summaries),
        }
        
        return Response({
            'success': True,
            'report_type': 'weekly',
            'summary': weekly_summary,
            'daily_breakdowns': daily_summaries
        })
    
    elif report_type == 'monthly':
        # Monthly report
        # Get first and last day of month
        first_day = reference_date.replace(day=1)
        if reference_date.month == 12:
            last_day = reference_date.replace(year=reference_date.year + 1, month=1, day=1) - timedelta(days=1)
        else:
            last_day = reference_date.replace(month=reference_date.month + 1, day=1) - timedelta(days=1)
        
        # Get all attendance for the month
        queryset = Attendance.objects.filter(
            date__gte=first_day,
            date__lte=last_day
        )
        
        if department:
            queryset = queryset.filter(employee__department__name=department)
        
        # Calculate statistics
        from employees.models import Employee
        total_employees = Employee.objects.filter(is_active=True).count()
        if department:
            total_employees = Employee.objects.filter(
                is_active=True,
                department__name=department
            ).count()
        
        working_days = (last_day - first_day).days + 1
        
        monthly_summary = {
            'month': reference_date.strftime('%B %Y'),
            'start_date': first_day,
            'end_date': last_day,
            'working_days': working_days,
            'total_employees': total_employees,
            'total_attendance_records': queryset.count(),
            'present_count': queryset.filter(status='PRESENT').count(),
            'late_count': queryset.filter(status='LATE').count(),
            'half_day_count': queryset.filter(status='HALF_DAY').count(),
            'absent_count': queryset.filter(status='ABSENT').count(),
            'total_hours_worked': float(queryset.aggregate(Sum('total_hours'))['total_hours__sum'] or 0),
            'average_hours_per_day': float(queryset.aggregate(Avg('total_hours'))['total_hours__avg'] or 0),
        }
        
        return Response({
            'success': True,
            'report_type': 'monthly',
            'summary': monthly_summary
        })
    
    else:
        return Response({
            'success': False,
            'message': 'Invalid report_type. Use: daily, weekly, or monthly'
        }, status=status.HTTP_400_BAD_REQUEST)


class AttendanceViewSet(viewsets.ModelViewSet):
    """
    ViewSet for Attendance CRUD operations
    
    Endpoints:
    - GET /api/attendance/attendance/ - List attendance (with filters)
    - POST /api/attendance/attendance/ - Create attendance (admin only)
    - GET /api/attendance/attendance/{id}/ - Get specific record
    - PUT /api/attendance/attendance/{id}/ - Update record (admin only)
    - DELETE /api/attendance/attendance/{id}/ - Delete record (admin only)
    """
    queryset = Attendance.objects.all().select_related('employee')
    serializer_class = AttendanceSerializer
    pagination_class = StandardResultsSetPagination
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['employee', 'date', 'status']
    
    def get_permissions(self):
        """Admin for write operations, authenticated for read"""
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [IsAdminUser()]
        return [IsAuthenticated()]
    
    def get_queryset(self):
        """Filter queryset based on user permissions"""
        if self.request.user.is_staff:
            return self.queryset
        else:
            # Regular users can only see their own attendance
            return self.queryset.filter(employee=self.request.user)
