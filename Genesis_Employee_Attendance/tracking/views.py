import json
import logging
import os
from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes, action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from rest_framework.pagination import PageNumberPagination
from django.utils import timezone
from django.db.models import Max, Sum
from datetime import datetime, timedelta, time
from .models import LocationLog
from .serializers import (
    LocationLogSerializer, LocationCreateSerializer, RouteHistorySerializer
)

# Dashboard (template) views
from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.http import HttpResponse
from django.conf import settings
from decimal import Decimal

logger = logging.getLogger('tracking')


def _hours_to_hhmmss(hours):
    """Convert decimal hours to HH:MM:SS format."""
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


def _seconds_to_hhmmss(total_seconds):
    """Convert total seconds to HH:MM:SS format."""
    if total_seconds is None:
        return '—'
    try:
        s = int(total_seconds)
        hrs, remainder = divmod(s, 3600)
        mins, secs = divmod(remainder, 60)
        return f"{hrs:02d}:{mins:02d}:{secs:02d}"
    except (TypeError, ValueError):
        return '—'


def _get_time_ago(timestamp):
    """Return human-readable time ago string for a timestamp."""
    diff = timezone.now() - timestamp
    total_seconds = int(diff.total_seconds())
    if total_seconds < 0:
        return 'just now'
    if total_seconds < 60:
        return f'{total_seconds} seconds ago'
    if total_seconds < 3600:
        return f'{total_seconds // 60} minutes ago'
    if total_seconds < 86400:
        return f'{total_seconds // 3600} hours ago'
    days = total_seconds // 86400
    return f'{days} day{"s" if days != 1 else ""} ago'


class StandardResultsSetPagination(PageNumberPagination):
    """Standard pagination class"""
    page_size = 100
    page_size_query_param = 'page_size'
    max_page_size = 500


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def log_location(request):
    """
    Log location from mobile app
    POST /api/tracking/log-location/
    
    Request body:
    {
        "employee": "uuid",  (optional if JWT identifies employee)
        "latitude": 37.7749,
        "longitude": -122.4194,
        "timestamp": "2024-01-15T10:30:00Z",
        "accuracy": 10.5,
        "battery_level": 85,
        "speed": 2.5,
        "address": "123 Main St"
    }
    
    With EmployeeJWTAuthentication, request.user is the Employee instance.
    Validates employee and saves location with timestamp.
    """
    try:
        # #region agent log
        try:
            _lp = os.environ.get('DEBUG_LOG_PATH', r'e:\Attendance System\.cursor\debug.log')
            _u = request.user
            with open(_lp, 'a') as _f:
                _f.write(json.dumps({'sessionId': 'debug-session', 'runId': 'run1', 'hypothesisId': 'H2', 'location': 'tracking/views.py:log_location', 'message': 'log_location_request', 'data': {'employee_id': str(getattr(_u, 'id', None)), 'email': getattr(_u, 'email', None)}, 'timestamp': __import__('time').time() * 1000}) + '\n')
        except Exception:
            pass
        # #endregion
        logger.debug("log_location: received request from user=%s", request.user)
        logger.debug("log_location: request data=%s", request.data)

        # Set employee from authenticated user if not provided (request.user is Employee with custom JWT)
        data = request.data.copy()
        if 'employee' not in data or not data['employee']:
            data['employee'] = str(request.user.id)

        serializer = LocationCreateSerializer(data=data)

        if serializer.is_valid():
            location_log = serializer.save()
            logger.debug("log_location: location saved id=%s", location_log.id)
            logger.info(
                "log_location: created location_log_id=%s employee_id=%s",
                location_log.id,
                request.user.id,
            )
            return Response({
                'success': True,
                'message': 'Location logged successfully',
                'data': serializer.data
            }, status=status.HTTP_201_CREATED)

        logger.warning("log_location: validation errors %s", serializer.errors)
        return Response({
            'success': False,
            'message': 'Failed to log location',
            'errors': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)
    except Exception as e:
        logger.exception("log_location: unexpected error")
        return Response({
            'success': False,
            'message': str(e),
            'errors': {}
        }, status=status.HTTP_400_BAD_REQUEST)


@api_view(['GET'])
@permission_classes([IsAdminUser])
def live_locations(request):
    """
    Get latest locations of all active employees (last 15 minutes)
    GET /api/tracking/live-locations/
    
    Admin only - Returns all active employees' last location
    Format optimized for Leaflet.js/OpenStreetMap display
    
    Response format:
    {
        "success": true,
        "data": {
            "locations": [...],
            "count": 10,
            "last_updated": "2024-01-15T10:45:00Z"
        }
    }
    """
    try:
        # Get locations from last 15 minutes
        cutoff_time = timezone.now() - timedelta(minutes=15)
        latest_timestamps = LocationLog.objects.filter(
            timestamp__gte=cutoff_time
        ).values('employee').annotate(
            latest_time=Max('timestamp')
        )

        # Fetch the actual location records
        locations = []
        for item in latest_timestamps:
            location = LocationLog.objects.filter(
                employee_id=item['employee'],
                timestamp=item['latest_time']
            ).select_related('employee', 'employee__department', 'employee__designation').first()

            if location and location.employee.is_active:
                ts = location.timestamp
                ts_iso = ts.isoformat() if hasattr(ts, 'isoformat') else str(ts)
                locations.append({
                    'employee_id': str(location.employee.id),
                    'employee_name': location.employee.name,
                    'employee_code': location.employee.employee_id,
                    'department': location.employee.department.name if location.employee.department else '—',
                    'designation': location.employee.designation.name if location.employee.designation else '—',
                    'latitude': location.latitude,
                    'longitude': location.longitude,
                    'accuracy': location.accuracy,
                    'battery_level': location.battery_level,
                    'speed': location.speed,
                    'address': location.address or '',
                    'timestamp': ts_iso,
                    'last_update': _get_time_ago(location.timestamp),
                    'minutes_ago': int((timezone.now() - location.timestamp).total_seconds() / 60),
                })

        # Format for Leaflet.js/OpenStreetMap (and flat-list consumers)
        formatted_locations = []
        for loc in locations:
            formatted_locations.append({
                'employee_id': loc['employee_id'],
                'employee_name': loc['employee_name'],
                'employee_code': loc.get('employee_code', ''),
                'location': {
                    'lat': loc['latitude'],
                    'lng': loc['longitude']
                },
                'latitude': loc['latitude'],
                'longitude': loc['longitude'],
                'timestamp': loc['timestamp'],
                'last_update': loc['last_update'],
                'accuracy': loc.get('accuracy'),
                'battery_level': loc.get('battery_level'),
                'speed': loc.get('speed'),
                'address': loc.get('address', ''),
            })

        return Response({
            'success': True,
            'data': {
                'locations': formatted_locations,
                'count': len(formatted_locations),
                'last_updated': timezone.now().isoformat(),
                'time_window_minutes': 15
            }
        })
    except Exception as e:
        logger.exception('live_locations: unexpected error')
        return Response({
            'status': 'error',
            'message': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
@permission_classes([IsAdminUser])
def latest_location(request):
    """
    Get latest location for one employee by email (admin only).
    GET /api/tracking/latest-location/?email=ashraf.anam@gel.com.bd

    Returns same shape as one entry in live-locations. 404 if employee not found
    or no location logged yet.
    """
    from employees.models import Employee

    email = (request.query_params.get('email') or '').strip()
    if not email:
        return Response({
            'success': False,
            'message': 'Query parameter "email" is required.',
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        employee = Employee.objects.get(email=email)
    except Employee.DoesNotExist:
        return Response({
            'success': False,
            'message': f'No employee with email "{email}".',
        }, status=status.HTTP_404_NOT_FOUND)

    location = (
        LocationLog.objects.filter(employee=employee)
        .order_by('-timestamp')
        .select_related('employee', 'employee__department', 'employee__designation')
        .first()
    )
    if not location:
        return Response({
            'success': False,
            'message': f'No location logged yet for {employee.email} ({employee.employee_id} - {employee.name}).',
        }, status=status.HTTP_404_NOT_FOUND)

    ts = location.timestamp
    ts_iso = ts.isoformat() if hasattr(ts, 'isoformat') else str(ts)
    data = {
        'employee_id': str(employee.id),
        'employee_name': employee.name,
        'employee_code': employee.employee_id,
        'employee_email': employee.email,
        'department': employee.department.name if employee.department else '—',
        'designation': employee.designation.name if employee.designation else '—',
        'location': {
            'lat': location.latitude,
            'lng': location.longitude
        },
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timestamp': ts_iso,
        'last_update': _get_time_ago(location.timestamp),
        'minutes_ago': int((timezone.now() - location.timestamp).total_seconds() / 60),
        'accuracy': location.accuracy,
        'battery_level': location.battery_level,
        'speed': location.speed,
        'address': location.address or '',
    }
    return Response({
        'success': True,
        'data': data,
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def employee_route(request):
    """
    Get employee route history
    GET /api/tracking/employee-route/
    
    Query params:
    - employee_id (UUID, required)
    - date (YYYY-MM-DD, optional - defaults to today)
    - start_time (HH:MM:SS, optional - defaults to 00:00:00)
    - end_time (HH:MM:SS, optional - defaults to 23:59:59)
    
    Returns list of locations chronologically with route distance calculation
    
    Admins can view any employee's route
    Employees can only view their own route
    """
    # Get parameters
    employee_id = request.query_params.get('employee_id')
    date_str = request.query_params.get('date')
    start_time_str = request.query_params.get('start_time', '00:00:00')
    end_time_str = request.query_params.get('end_time', '23:59:59')
    
    # Validate employee_id
    if not employee_id:
        return Response({
            'success': False,
            'message': 'employee_id parameter is required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Check permissions
    if not request.user.is_staff and str(request.user.id) != employee_id:
        return Response({
            'success': False,
            'message': 'You do not have permission to view this route'
        }, status=status.HTTP_403_FORBIDDEN)
    
    # Parse date
    if date_str:
        try:
            route_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({
                'success': False,
                'message': 'Invalid date format. Use YYYY-MM-DD'
            }, status=status.HTTP_400_BAD_REQUEST)
    else:
        route_date = timezone.now().date()
    
    # Parse times
    try:
        start_time = datetime.strptime(start_time_str, '%H:%M:%S').time()
        end_time = datetime.strptime(end_time_str, '%H:%M:%S').time()
    except ValueError:
        return Response({
            'success': False,
            'message': 'Invalid time format. Use HH:MM:SS'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Create datetimes
    start_datetime = datetime.combine(route_date, start_time)
    end_datetime = datetime.combine(route_date, end_time)
    
    # Make timezone aware
    start_datetime = timezone.make_aware(start_datetime)
    end_datetime = timezone.make_aware(end_datetime)
    
    # Get route history
    route_data = RouteHistorySerializer.get_route_history(
        employee_id=employee_id,
        start_datetime=start_datetime,
        end_datetime=end_datetime
    )
    
    if not route_data:
        return Response({
            'success': False,
            'message': 'Employee not found'
        }, status=status.HTTP_404_NOT_FOUND)
    
    # Format locations for frontend (get_route_history already returns list of dicts)
    if route_data and 'locations' in route_data:
        formatted_locations = []
        for loc in route_data['locations']:
            lat = loc.get('latitude')
            lng = loc.get('longitude')
            if lat is not None and lng is not None:
                lat_f = float(lat)
                lng_f = float(lng)
                formatted_locations.append({
                    'latitude': lat_f,
                    'longitude': lng_f,
                    'location': {
                        'lat': lat_f,
                        'lng': lng_f
                    },
                    'timestamp': loc.get('timestamp'),
                    'address': loc.get('address', ''),
                    'speed': loc.get('speed'),
                    'accuracy': loc.get('accuracy'),
                })
        route_data['locations'] = formatted_locations
    
    return Response({
        'success': True,
        'data': route_data
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def my_route_today(request):
    """
    Get employee's own today's route
    GET /api/tracking/my-route-today/
    
    Returns current employee's location logs for today with route calculation.
    Requires employee JWT (request.user must be Employee).
    """
    from employees.models import Employee
    user = request.user
    employee = user if isinstance(user, Employee) else getattr(user, 'employee', None)
    if not employee:
        return Response({
            'success': False,
            'message': 'Not an employee. Use employee JWT.',
        }, status=status.HTTP_403_FORBIDDEN)
    # #region agent log
    try:
        _lp = os.environ.get('DEBUG_LOG_PATH', r'e:\Attendance System\.cursor\debug.log')
        with open(_lp, 'a') as _f:
            _f.write(json.dumps({'sessionId': 'debug-session', 'runId': 'run1', 'hypothesisId': 'H2', 'location': 'tracking/views.py:my_route_today', 'message': 'my_route_today_request', 'data': {'employee_id': str(employee.id), 'email': getattr(employee, 'email', None)}, 'timestamp': __import__('time').time() * 1000}) + '\n')
    except Exception:
        pass
    # #endregion
    today = timezone.localdate()
    start_datetime = timezone.make_aware(datetime.combine(today, time.min))
    end_datetime = timezone.make_aware(datetime.combine(today, time.max))
    route_data = RouteHistorySerializer.get_route_history(
        employee_id=str(employee.id),
        start_datetime=start_datetime,
        end_datetime=end_datetime
    )
    if route_data is None:
        return Response({
            'success': False,
            'message': 'Employee not found.',
        }, status=status.HTTP_404_NOT_FOUND)
    return Response({
        'success': True,
        'data': route_data
    })


class LocationLogViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet for viewing location logs (Read-only)
    
    Endpoints:
    - GET /api/tracking/location-logs/ - List all (admin only)
    - GET /api/tracking/location-logs/{id}/ - Get specific log
    - GET /api/tracking/location-logs/my-logs/ - Get own logs
    """
    queryset = LocationLog.objects.all().select_related('employee')
    serializer_class = LocationLogSerializer
    pagination_class = StandardResultsSetPagination
    permission_classes = [IsAuthenticated]
    
    def get_queryset(self):
        """Filter queryset based on user permissions"""
        if self.request.user.is_staff:
            # Admin can see all logs
            return self.queryset
        else:
            # Regular users can only see their own logs
            return self.queryset.filter(employee=self.request.user)
    
    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated])
    def my_logs(self, request):
        """
        Get current employee's location logs
        GET /api/tracking/location-logs/my-logs/
        
        Query params:
        - days (int, optional) - Number of days to look back (default: 7)
        - start_date (YYYY-MM-DD, optional)
        - end_date (YYYY-MM-DD, optional)
        """
        # Get query parameters
        days = int(request.query_params.get('days', 7))
        start_date_str = request.query_params.get('start_date')
        end_date_str = request.query_params.get('end_date')
        
        # Build query
        queryset = LocationLog.objects.filter(employee=request.user)
        
        if start_date_str and end_date_str:
            try:
                start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
                end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
                queryset = queryset.filter(
                    timestamp__date__gte=start_date,
                    timestamp__date__lte=end_date
                )
            except ValueError:
                return Response({
                    'success': False,
                    'message': 'Invalid date format. Use YYYY-MM-DD'
                }, status=status.HTTP_400_BAD_REQUEST)
        else:
            since = timezone.now() - timedelta(days=days)
            queryset = queryset.filter(timestamp__gte=since)
        
        queryset = queryset.order_by('-timestamp')
        
        # Paginate
        page = self.paginate_queryset(queryset)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response({
                'success': True,
                'data': serializer.data
            })
        
        serializer = self.get_serializer(queryset, many=True)
        return Response({
            'success': True,
            'data': serializer.data
        })


@login_required
def dashboard_home(request):
    """
    Main dashboard page. Stats from DutySession (duty-based):
    - On Duty = employees who started duty but have not ended it yet
    - Off Duty = employees who completed duty (both start and end)
    - Absent = employees who were never On Duty for the selected date
    Template: dashboard/index.html
    """
    from employees.models import Employee
    from attendance.models import Attendance, DutySession

    today = timezone.localdate()

    # Parse selected date from query param
    date_str = request.GET.get('date')
    if date_str:
        try:
            selected_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            selected_date = today
    else:
        selected_date = today

    # Don't allow future dates
    if selected_date > today:
        selected_date = today

    # Total active employees
    total_employees = Employee.objects.filter(is_active=True).count()

    # On Duty: employees with open session (end_time is NULL) for selected date
    on_duty_ids = set(
        DutySession.objects.filter(
            date=selected_date, end_time__isnull=True
        ).values_list('employee_id', flat=True).distinct()
    )
    on_duty_count = len(on_duty_ids)

    # Off Duty: employees with at least one closed session for date AND no open session
    employees_with_closed = set(
        DutySession.objects.filter(
            date=selected_date, end_time__isnull=False
        ).values_list('employee_id', flat=True).distinct()
    )
    off_duty_ids = employees_with_closed - on_duty_ids
    off_duty_count = len(off_duty_ids)

    # Absent: total_active - on_duty - off_duty
    absent_count = max(total_employees - on_duty_count - off_duty_count, 0)

    # Attendance percentage (on_duty + off_duty vs total)
    attended = on_duty_count + off_duty_count
    attendance_percentage = (
        (attended / total_employees * 100) if total_employees > 0 else 0
    )

    # Last 7 days trend (ending on selected_date)
    trend_dates = [selected_date - timedelta(days=i) for i in range(6, -1, -1)]
    trend_on_duty = []
    trend_off_duty = []
    trend_absent = []
    for d in trend_dates:
        on_ids = set(
            DutySession.objects.filter(date=d, end_time__isnull=True)
            .values_list('employee_id', flat=True)
            .distinct()
        )
        closed_ids = set(
            DutySession.objects.filter(date=d, end_time__isnull=False)
            .values_list('employee_id', flat=True)
            .distinct()
        )
        off_ids = closed_ids - on_ids
        trend_on_duty.append(len(on_ids))
        trend_off_duty.append(len(off_ids))
        trend_absent.append(max(total_employees - len(on_ids) - len(off_ids), 0))

    # Recent activities: selected date's Attendance records, enriched with start/end locations
    recent_activities = Attendance.objects.filter(
        date=selected_date
    ).select_related('employee').order_by('-created_at')[:10]

    recent_activities_enriched = []
    for att in recent_activities:
        first_sess = DutySession.objects.filter(
            employee=att.employee, date=att.date
        ).order_by('start_time').first()
        last_sess = DutySession.objects.filter(
            employee=att.employee, date=att.date
        ).order_by('-start_time').first()
        start_loc = first_sess.start_address if first_sess and first_sess.start_address else '—'
        end_loc = (last_sess.end_address if last_sess and last_sess.end_time and last_sess.end_address else '—')
        total_seconds = 0
        for sess in DutySession.objects.filter(employee=att.employee, date=att.date, end_time__isnull=False):
            total_seconds += int((sess.end_time - sess.start_time).total_seconds())
        recent_activities_enriched.append({
            'att': att,
            'start_location': start_loc or '—',
            'end_location': end_loc or '—',
            'check_in_time_str': timezone.localtime(first_sess.start_time).strftime('%I:%M:%S %p') if first_sess else '—',
            'check_out_time_str': timezone.localtime(last_sess.end_time).strftime('%I:%M:%S %p') if last_sess and last_sess.end_time else '—',
            'total_hours_str': _seconds_to_hhmmss(int(total_seconds)) if total_seconds else '—',
        })

    context = {
        'today': today,
        'selected_date': selected_date,
        'stats': {
            'total_employees': total_employees,
            'on_duty_count': on_duty_count,
            'off_duty_count': off_duty_count,
            'absent_count': absent_count,
            'attendance_percentage': round(attendance_percentage, 1),
            'selected_date': selected_date,
        },
        'trend_labels': json.dumps([d.strftime('%a %m/%d') for d in trend_dates]),
        'trend_on_duty': json.dumps(trend_on_duty),
        'trend_off_duty': json.dumps(trend_off_duty),
        'trend_absent': json.dumps(trend_absent),
        'recent_activities_enriched': recent_activities_enriched,
    }
    return render(request, 'dashboard/index.html', context)


@login_required
def dashboard_employee_list(request):
    """
    Return HTML partial (table) for employee list by filter.
    GET /dashboard/employee-list/?filter=total|on_duty|off_duty|absent&date=YYYY-MM-DD
    """
    from employees.models import Employee
    from attendance.models import DutySession

    filter_type = request.GET.get('filter', 'total')
    date_str = request.GET.get('date')
    today = timezone.localdate()

    if date_str:
        try:
            selected_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            selected_date = today
    else:
        selected_date = today

    if selected_date > today:
        selected_date = today

    employees = []
    if filter_type == 'total':
        employees = list(
            Employee.objects.filter(is_active=True)
            .select_related('department', 'designation')
            .order_by('name')
        )
        employees = [{'name': e.name, 'employee_id': e.employee_id, 'department': e.department.name if e.department else '—',
                     'designation': e.designation.name if e.designation else '—', 'email': e.email, 'phone': e.phone or '—'} for e in employees]
    elif filter_type == 'on_duty':
        on_duty_ids = list(
            DutySession.objects.filter(date=selected_date, end_time__isnull=True)
            .values_list('employee_id', flat=True)
            .distinct()
        )
        for emp in Employee.objects.filter(id__in=on_duty_ids, is_active=True).select_related('department', 'designation'):
            open_session = DutySession.objects.filter(
                employee=emp, date=selected_date, end_time__isnull=True
            ).order_by('-start_time').first()
            latest_log = LocationLog.objects.filter(
                employee=emp, timestamp__date=selected_date
            ).order_by('-timestamp').first()
            present_location = (latest_log.address if latest_log and latest_log.address
                               else (open_session.start_address if open_session else '—'))
            speed = (float(latest_log.speed) if latest_log and latest_log.speed is not None else None)
            current_seconds = None
            if open_session:
                delta = timezone.now() - open_session.start_time
                current_seconds = int(delta.total_seconds())
            employees.append({
                'name': emp.name,
                'employee_id': emp.employee_id,
                'department': emp.department.name if emp.department else '—',
                'start_time': timezone.localtime(open_session.start_time).strftime('%I:%M:%S %p') if open_session else '—',
                'present_location': present_location or '—',
                'speed': f'{speed:.2f} m/s' if speed is not None else '—',
                'current_duty_hours': _seconds_to_hhmmss(current_seconds),
            })
        employees.sort(key=lambda x: x['name'])
    elif filter_type == 'off_duty':
        on_duty_ids = set(
            DutySession.objects.filter(date=selected_date, end_time__isnull=True)
            .values_list('employee_id', flat=True)
            .distinct()
        )
        off_duty_ids = set(
            DutySession.objects.filter(date=selected_date, end_time__isnull=False)
            .values_list('employee_id', flat=True)
            .distinct()
        ) - on_duty_ids
        for emp in Employee.objects.filter(id__in=off_duty_ids, is_active=True).select_related('department', 'designation'):
            first_session = DutySession.objects.filter(
                employee=emp, date=selected_date
            ).order_by('start_time').first()
            last_closed = DutySession.objects.filter(
                employee=emp, date=selected_date, end_time__isnull=False
            ).order_by('-end_time').first()
            end_location = (last_closed.end_address if last_closed and last_closed.end_address else '—')
            total_seconds = 0
            for sess in DutySession.objects.filter(employee=emp, date=selected_date, end_time__isnull=False):
                total_seconds += int((sess.end_time - sess.start_time).total_seconds())
            latest_log = LocationLog.objects.filter(
                employee=emp,
                timestamp__date=selected_date,
                timestamp__lte=last_closed.end_time if last_closed else timezone.now()
            ).order_by('-timestamp').first()
            speed = (float(latest_log.speed) if latest_log and latest_log.speed is not None else None)
            employees.append({
                'name': emp.name,
                'employee_id': emp.employee_id,
                'department': emp.department.name if emp.department else '—',
                'start_time': timezone.localtime(first_session.start_time).strftime('%I:%M:%S %p') if first_session else '—',
                'end_time': timezone.localtime(last_closed.end_time).strftime('%I:%M:%S %p') if last_closed and last_closed.end_time else '—',
                'end_location': end_location or '—',
                'speed': f'{speed:.2f} m/s' if speed is not None else '—',
                'total_duty_hours': _seconds_to_hhmmss(int(total_seconds)),
            })
        employees.sort(key=lambda x: x['name'])
    elif filter_type == 'absent':
        on_duty_ids = set(
            DutySession.objects.filter(date=selected_date, end_time__isnull=True)
            .values_list('employee_id', flat=True)
            .distinct()
        )
        off_duty_ids = set(
            DutySession.objects.filter(date=selected_date, end_time__isnull=False)
            .values_list('employee_id', flat=True)
            .distinct()
        ) - on_duty_ids
        attended_ids = on_duty_ids | off_duty_ids
        for emp in Employee.objects.filter(is_active=True).exclude(id__in=attended_ids).select_related('department', 'designation').order_by('name'):
            employees.append({
                'name': emp.name,
                'employee_id': emp.employee_id,
                'department': emp.department.name if emp.department else '—',
                'designation': emp.designation.name if emp.designation else '—',
                'email': emp.email,
            })

    context = {
        'filter_type': filter_type,
        'employees': employees,
        'selected_date': selected_date,
    }
    return render(request, 'dashboard/employee_list_partial.html', context)


@login_required
def live_tracking_view(request):
    """
    Real-time tracking page (OpenStreetMap + Leaflet)
    Template: dashboard/live_tracking.html
    JavaScript polls live locations every 10 seconds for snappier updates during duty.
    """
    context = {
        'poll_interval_ms': 10000,
    }
    return render(request, 'dashboard/live_tracking.html', context)


@login_required
def route_history_view(request):
    """
    Route playback page
    Template: dashboard/route_history.html
    Includes date picker + employee selector.
    """
    from employees.models import Employee

    # Non-admin users only see themselves
    if getattr(request.user, 'is_staff', False):
        employees = Employee.objects.filter(is_active=True).order_by('name')
    else:
        employees = Employee.objects.filter(id=request.user.id)

    context = {
        'employees': employees,
        'today': timezone.localdate(),
    }
    return render(request, 'dashboard/route_history.html', context)


@login_required
def attendance_reports_view(request):
    """
    Reports page
    Template: dashboard/reports.html
    Date range selector + CSV/PDF export options.
    """
    from employees.models import Employee, Department
    
    # Get unique departments and all employees; filter by department on client
    import json
    departments = list(Department.objects.filter(is_active=True).values_list('name', flat=True).order_by('name'))
    employees = list(Employee.objects.filter(is_active=True).select_related('department').order_by('name').values('id', 'employee_id', 'name', 'department__name'))
    employees_json = json.dumps([{'id': str(e['id']), 'employee_id': e['employee_id'], 'name': e['name'], 'department': e['department__name'] or '—'} for e in employees], default=str)

    context = {
        'departments': departments,
        'employees_json': employees_json,
        'today': timezone.localdate(),
    }
    return render(request, 'dashboard/reports.html', context)


@login_required
def export_csv(request):
    """
    Export attendance report to CSV
    GET /dashboard/export-csv/
    
    Query params:
    - report_type: daily, weekly, or monthly
    - date: Reference date (YYYY-MM-DD)
    - department: Optional department filter
    """
    import csv
    from django.http import HttpResponse
    from attendance.models import Attendance
    from attendance.serializers import DailyAttendanceSummarySerializer
    from employees.models import Employee
    
    # Check if user is staff
    if not request.user.is_staff:
        return HttpResponse('Unauthorized', status=403)
    
    # Get parameters
    report_type = request.GET.get('report_type', 'daily')
    date_str = request.GET.get('date')
    department = request.GET.get('department', '')
    
    # Parse date
    if date_str:
        try:
            reference_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return HttpResponse('Invalid date format', status=400)
    else:
        reference_date = timezone.now().date()
    
    # Create CSV response
    response = HttpResponse(content_type='text/csv')
    filename = f'attendance_report_{report_type}_{reference_date}.csv'
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    
    writer = csv.writer(response)
    
    if report_type == 'daily':
        # Daily CSV export
        writer.writerow(['Daily Attendance Report'])
        writer.writerow(['Date:', reference_date])
        if department:
            writer.writerow(['Department:', department])
        writer.writerow([])
        
        # Get summary
        summary = DailyAttendanceSummarySerializer.get_daily_summary(reference_date)
        writer.writerow(['Summary'])
        writer.writerow(['Total Employees', summary['total_employees']])
        writer.writerow(['Present', summary['present_count']])
        writer.writerow(['Late', summary['late_count']])
        writer.writerow(['Half Day', summary['half_day_count']])
        writer.writerow(['Absent', summary['absent_count']])
        writer.writerow(['Attendance Rate', f"{summary['present_percentage']}%"])
        writer.writerow(['Average Hours', _hours_to_hhmmss(summary['average_hours_worked'])])
        writer.writerow(['Total Hours', _hours_to_hhmmss(summary['total_hours_worked'])])
        writer.writerow([])
        
        # Get detailed records
        queryset = Attendance.objects.filter(date=reference_date).select_related('employee', 'employee__department')
        if department:
            queryset = queryset.filter(employee__department__name=department)
        
        writer.writerow(['Employee ID', 'Name', 'Department', 'Check In', 'Check Out', 
                        'Total Hours', 'Locations Logged', 'Status', 'Remarks'])
        
        for att in queryset:
            writer.writerow([
                att.employee.employee_id,
                att.employee.name,
                att.employee.department.name if att.employee.department else '—',
                att.check_in_time or '—',
                att.check_out_time or '—',
                _hours_to_hhmmss(att.total_hours),
                att.total_locations_logged,
                att.status,
                att.remarks or ''
            ])
    
    elif report_type == 'weekly':
        # Weekly CSV export
        end_date = reference_date
        start_date = end_date - timedelta(days=6)
        
        writer.writerow(['Weekly Attendance Report'])
        writer.writerow(['Period:', f'{start_date} to {end_date}'])
        if department:
            writer.writerow(['Department:', department])
        writer.writerow([])
        
        # Daily summaries
        writer.writerow(['Date', 'Total Employees', 'Present', 'Late', 'Half Day', 
                        'Absent', 'Attendance Rate', 'Avg Hours', 'Total Hours'])
        
        current_date = start_date
        while current_date <= end_date:
            summary = DailyAttendanceSummarySerializer.get_daily_summary(current_date)
            writer.writerow([
                current_date,
                summary['total_employees'],
                summary['present_count'],
                summary['late_count'],
                summary['half_day_count'],
                summary['absent_count'],
                f"{summary['present_percentage']}%",
                _hours_to_hhmmss(summary['average_hours_worked']),
                _hours_to_hhmmss(summary['total_hours_worked'])
            ])
            current_date += timedelta(days=1)
    
    elif report_type == 'monthly':
        # Monthly CSV export
        first_day = reference_date.replace(day=1)
        if reference_date.month == 12:
            last_day = reference_date.replace(year=reference_date.year + 1, month=1, day=1) - timedelta(days=1)
        else:
            last_day = reference_date.replace(month=reference_date.month + 1, day=1) - timedelta(days=1)
        
        writer.writerow(['Monthly Attendance Report'])
        writer.writerow(['Month:', reference_date.strftime('%B %Y')])
        writer.writerow(['Period:', f'{first_day} to {last_day}'])
        if department:
            writer.writerow(['Department:', department])
        writer.writerow([])
        
        # Get all attendance for the month
        queryset = Attendance.objects.filter(
            date__gte=first_day,
            date__lte=last_day
        ).select_related('employee', 'employee__department')
        
        if department:
            queryset = queryset.filter(employee__department__name=department)
        
        # Summary
        from django.db.models import Sum, Avg
        total_employees = Employee.objects.filter(is_active=True).count()
        if department:
            total_employees = Employee.objects.filter(is_active=True, department__name=department).count()
        
        writer.writerow(['Summary'])
        writer.writerow(['Working Days', (last_day - first_day).days + 1])
        writer.writerow(['Total Employees', total_employees])
        writer.writerow(['Total Records', queryset.count()])
        writer.writerow(['Present', queryset.filter(status='PRESENT').count()])
        writer.writerow(['Late', queryset.filter(status='LATE').count()])
        writer.writerow(['Half Day', queryset.filter(status='HALF_DAY').count()])
        writer.writerow(['Absent', queryset.filter(status='ABSENT').count()])
        total_hrs = queryset.aggregate(Sum('total_hours'))['total_hours__sum'] or 0
        avg_hrs = queryset.aggregate(Avg('total_hours'))['total_hours__avg'] or 0
        writer.writerow(['Total Hours', _hours_to_hhmmss(total_hrs)])
        writer.writerow(['Average Hours', _hours_to_hhmmss(avg_hrs)])
        writer.writerow([])
        
        # Detailed records
        writer.writerow(['Date', 'Employee ID', 'Name', 'Department', 'Check In', 
                        'Check Out', 'Total Hours', 'Status'])
        
        for att in queryset.order_by('date', 'employee__name'):
            writer.writerow([
                att.date,
                att.employee.employee_id,
                att.employee.name,
                att.employee.department.name if att.employee.department else '—',
                att.check_in_time or '—',
                att.check_out_time or '—',
                _hours_to_hhmmss(att.total_hours),
                att.status
            ])
    
    return response
