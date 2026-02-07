from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes, action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from rest_framework.pagination import PageNumberPagination
from django_filters.rest_framework import DjangoFilterBackend
from django.utils import timezone
from django.db.models import Q, Count, Sum, Avg
from datetime import datetime, timedelta
from .models import Attendance
from employees.models import Employee
from tracking.models import LocationLog
from .serializers import (
    AttendanceSerializer, AttendanceReportSerializer, DailyAttendanceSummarySerializer
)


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
    loc_qs = LocationLog.objects.filter(employee=employee)
    att_count = att_qs.count()
    loc_count = loc_qs.count()
    att_qs.delete()
    loc_qs.delete()

    return Response({
        'success': True,
        'message': 'Your attendance and location data have been deleted.',
        'data': {
            'attendance_deleted': att_count,
            'location_logs_deleted': loc_count,
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
    
    # Build query
    queryset = Attendance.objects.filter(
        employee=employee,
        date__gte=start_date,
        date__lte=end_date
    )
    
    # Apply status filter
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    
    # Order by date descending
    queryset = queryset.order_by('-date')
    
    # Serialize
    serializer = AttendanceSerializer(queryset, many=True)
    
    # Calculate summary statistics
    summary = {
        'total_days': queryset.count(),
        'present_count': queryset.filter(status='PRESENT').count(),
        'late_count': queryset.filter(status='LATE').count(),
        'half_day_count': queryset.filter(status='HALF_DAY').count(),
        'absent_count': queryset.filter(status='ABSENT').count(),
        'total_hours': float(queryset.aggregate(Sum('total_hours'))['total_hours__sum'] or 0),
        'average_hours': float(queryset.aggregate(Avg('total_hours'))['total_hours__avg'] or 0),
    }
    
    return Response({
        'success': True,
        'data': {
            'records': serializer.data,
            'summary': summary,
            'date_range': {
                'start_date': start_date,
                'end_date': end_date
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
    - employee_id (UUID, optional) - Specific employee
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
    employee_id = request.query_params.get('employee_id')
    
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
        queryset = queryset.filter(employee__department=department)
    
    # Filter by status
    if status_filter:
        queryset = queryset.filter(status=status_filter)
    
    # Filter by employee
    if employee_id:
        queryset = queryset.filter(employee__id=employee_id)
    
    # Order by date descending, then employee name
    queryset = queryset.order_by('-date', 'employee__name')
    
    # Paginate
    paginator = StandardResultsSetPagination()
    page = paginator.paginate_queryset(queryset, request)
    
    if page is not None:
        serializer = AttendanceReportSerializer(page, many=True)
        return paginator.get_paginated_response({
            'success': True,
            'data': serializer.data
        })
    
    serializer = AttendanceReportSerializer(queryset, many=True)
    return Response({
        'success': True,
        'data': serializer.data
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
            queryset = queryset.filter(employee__department=department)
        
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
            queryset = queryset.filter(employee__department=department)
        
        # Calculate statistics
        from employees.models import Employee
        total_employees = Employee.objects.filter(is_active=True).count()
        if department:
            total_employees = Employee.objects.filter(
                is_active=True,
                department=department
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
