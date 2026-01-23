from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes, action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from rest_framework.pagination import PageNumberPagination
from django.utils import timezone
from django.db.models import Max
from datetime import datetime, timedelta, time
from .models import LocationLog
from .serializers import (
    LocationLogSerializer, LocationCreateSerializer, RouteHistorySerializer
)

# Dashboard (template) views
from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.conf import settings


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
        "employee": "uuid",
        "latitude": 37.7749,
        "longitude": -122.4194,
        "timestamp": "2024-01-15T10:30:00Z",
        "accuracy": 10.5,
        "battery_level": 85,
        "speed": 2.5,
        "address": "123 Main St"
    }
    
    Validates employee token and saves location with timestamp
    """
    # Set employee from authenticated user if not provided
    data = request.data.copy()
    if 'employee' not in data or not data['employee']:
        data['employee'] = str(request.user.id)
    
    serializer = LocationCreateSerializer(data=data)
    
    if serializer.is_valid():
        location_log = serializer.save()
        
        return Response({
            'success': True,
            'message': 'Location logged successfully',
            'data': serializer.data
        }, status=status.HTTP_201_CREATED)
    
    return Response({
        'success': False,
        'message': 'Failed to log location',
        'errors': serializer.errors
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
    # Get locations from last 15 minutes
    since = timezone.now() - timedelta(minutes=15)
    
    # Get latest location for each employee
    latest_timestamps = LocationLog.objects.filter(
        timestamp__gte=since
    ).values('employee').annotate(
        latest=Max('timestamp')
    )
    
    # Fetch the actual location records
    locations = []
    for item in latest_timestamps:
        location = LocationLog.objects.filter(
            employee=item['employee'],
            timestamp=item['latest']
        ).select_related('employee').first()
        
        if location and location.employee.is_active:
            locations.append({
                'employee_id': str(location.employee.id),
                'employee_name': location.employee.name,
                'employee_code': location.employee.employee_id,
                'department': location.employee.department,
                'designation': location.employee.designation,
                'latitude': location.latitude,
                'longitude': location.longitude,
                'accuracy': location.accuracy,
                'battery_level': location.battery_level,
                'speed': location.speed,
                'address': location.address,
                'timestamp': location.timestamp,
                'minutes_ago': int((timezone.now() - location.timestamp).total_seconds() / 60)
            })
    
    # Format for Leaflet.js/OpenStreetMap
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
            'timestamp': loc['timestamp'].isoformat() if hasattr(loc['timestamp'], 'isoformat') else str(loc['timestamp']),
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
            'last_updated': timezone.now(),
            'time_window_minutes': 15
        }
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
    
    # Serialize and format locations for frontend
    if route_data and 'locations' in route_data:
        # Serialize the LocationLog queryset
        from .serializers import LocationLogSerializer
        location_serializer = LocationLogSerializer(route_data['locations'], many=True)
        serialized_locations = location_serializer.data
        
        # Format for frontend (handle GeoJSON or regular format)
        formatted_locations = []
        for loc in serialized_locations:
            # Handle different location formats
            lat = None
            lng = None
            
            if 'latitude' in loc and 'longitude' in loc:
                lat = loc['latitude']
                lng = loc['longitude']
            elif 'geometry' in loc and 'coordinates' in loc['geometry']:
                # GeoJSON format: [longitude, latitude]
                coords = loc['geometry']['coordinates']
                lng = coords[0]
                lat = coords[1]
            elif 'location' in loc:
                if isinstance(loc['location'], dict):
                    lat = loc['location'].get('lat') or loc['location'].get('y')
                    lng = loc['location'].get('lng') or loc['location'].get('x')
                elif isinstance(loc['location'], list) and len(loc['location']) >= 2:
                    # [lng, lat]
                    lng = loc['location'][0]
                    lat = loc['location'][1]
            
            if lat is not None and lng is not None:
                formatted_locations.append({
                    'location': {
                        'lat': float(lat),
                        'lng': float(lng)
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
    
    Returns current employee's location logs for today with route calculation
    """
    today = timezone.now().date()
    start_datetime = timezone.make_aware(datetime.combine(today, time.min))
    end_datetime = timezone.make_aware(datetime.combine(today, time.max))
    
    # Get route history for current user
    route_data = RouteHistorySerializer.get_route_history(
        employee_id=str(request.user.id),
        start_datetime=start_datetime,
        end_datetime=end_datetime
    )
    
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
    Main dashboard page
    Template: dashboard/index.html
    """
    from employees.models import Employee
    from attendance.models import Attendance

    today = timezone.localdate()

    total_employees = Employee.objects.filter(is_active=True).count()
    todays_qs = Attendance.objects.filter(date=today).select_related('employee')

    present_count = todays_qs.filter(status='PRESENT').count()
    late_count = todays_qs.filter(status='LATE').count()
    half_day_count = todays_qs.filter(status='HALF_DAY').count()
    absent_count = max(total_employees - (present_count + late_count + half_day_count), 0)

    # Recent activities - use Attendance records instead of LocationLog
    recent_activities = todays_qs.order_by('-created_at')[:10]

    # Calculate attendance percentage
    attendance_percentage = ((present_count + late_count + half_day_count) / total_employees * 100) if total_employees > 0 else 0
    
    context = {
        'today': today,
        'stats': {
            'total_employees': total_employees,
            'present_count': present_count,
            'late_count': late_count,
            'absent_count': absent_count,
            'half_day_count': half_day_count,
            'attendance_percentage': round(attendance_percentage, 1),
        },
        'recent_activities': recent_activities,
    }
    return render(request, 'dashboard/index.html', context)


@login_required
def live_tracking_view(request):
    """
    Real-time tracking page (OpenStreetMap + Leaflet)
    Template: dashboard/live_tracking.html
    JavaScript polls live locations every 30 seconds.
    """
    context = {
        'poll_interval_ms': 30000,
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
    from employees.models import Employee
    
    # Get unique departments
    departments = Employee.objects.values_list('department', flat=True).distinct().order_by('department')
    
    context = {
        'departments': departments,
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
        writer.writerow(['Average Hours', summary['average_hours_worked']])
        writer.writerow(['Total Hours', summary['total_hours_worked']])
        writer.writerow([])
        
        # Get detailed records
        queryset = Attendance.objects.filter(date=reference_date).select_related('employee')
        if department:
            queryset = queryset.filter(employee__department=department)
        
        writer.writerow(['Employee ID', 'Name', 'Department', 'Check In', 'Check Out', 
                        'Total Hours', 'Locations Logged', 'Status', 'Remarks'])
        
        for att in queryset:
            writer.writerow([
                att.employee.employee_id,
                att.employee.name,
                att.employee.department,
                att.check_in_time or '—',
                att.check_out_time or '—',
                att.total_hours,
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
                summary['average_hours_worked'],
                summary['total_hours_worked']
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
        ).select_related('employee')
        
        if department:
            queryset = queryset.filter(employee__department=department)
        
        # Summary
        from django.db.models import Sum, Avg
        total_employees = Employee.objects.filter(is_active=True).count()
        if department:
            total_employees = Employee.objects.filter(is_active=True, department=department).count()
        
        writer.writerow(['Summary'])
        writer.writerow(['Working Days', (last_day - first_day).days + 1])
        writer.writerow(['Total Employees', total_employees])
        writer.writerow(['Total Records', queryset.count()])
        writer.writerow(['Present', queryset.filter(status='PRESENT').count()])
        writer.writerow(['Late', queryset.filter(status='LATE').count()])
        writer.writerow(['Half Day', queryset.filter(status='HALF_DAY').count()])
        writer.writerow(['Absent', queryset.filter(status='ABSENT').count()])
        writer.writerow(['Total Hours', queryset.aggregate(Sum('total_hours'))['total_hours__sum'] or 0])
        writer.writerow(['Average Hours', queryset.aggregate(Avg('total_hours'))['total_hours__avg'] or 0])
        writer.writerow([])
        
        # Detailed records
        writer.writerow(['Date', 'Employee ID', 'Name', 'Department', 'Check In', 
                        'Check Out', 'Total Hours', 'Status'])
        
        for att in queryset.order_by('date', 'employee__name'):
            writer.writerow([
                att.date,
                att.employee.employee_id,
                att.employee.name,
                att.employee.department,
                att.check_in_time or '—',
                att.check_out_time or '—',
                att.total_hours,
                att.status
            ])
    
    return response
