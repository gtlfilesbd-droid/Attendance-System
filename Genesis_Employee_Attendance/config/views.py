"""
API Root View for Genesis Employee Attendance System
"""
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import AllowAny


@api_view(['GET'])
@permission_classes([AllowAny])
def api_root(request, format=None):
    """
    API Root endpoint that lists all available API endpoints.
    """
    # Get the base URL for the API
    scheme = request.scheme
    host = request.get_host()
    base_url = f'{scheme}://{host}/api'
    
    return Response({
        'message': 'Genesis Employee Attendance API',
        'version': '1.0.0',
        'base_url': base_url,
        'endpoints': {
            'authentication': {
                'employee_login': f'{base_url}/employees/auth/login/',
                'employee_register': f'{base_url}/employees/auth/register/',
                'token_obtain': f'{base_url}/auth/token/',
                'token_refresh': f'{base_url}/auth/token/refresh/',
                'token_verify': f'{base_url}/auth/token/verify/',
            },
            'employees': {
                'my_profile': f'{base_url}/employees/me/',
                'list_all': f'{base_url}/employees/employees/',
                'detail': f'{base_url}/employees/employees/{{id}}/',
            },
            'tracking': {
                'log_location': f'{base_url}/tracking/log-location/',
                'log_location_bulk': f'{base_url}/tracking/log-location/bulk/',
                'live_locations': f'{base_url}/tracking/live-locations/',
                'my_route_today': f'{base_url}/tracking/my-route-today/',
                'employee_route': f'{base_url}/tracking/employee-route/',
                'location_logs': f'{base_url}/tracking/location-logs/',
            },
            'attendance': {
                'my_attendance': f'{base_url}/attendance/my-attendance/',
                'all_attendance': f'{base_url}/attendance/all/',
                'attendance_report': f'{base_url}/attendance/report/',
                'attendance_list': f'{base_url}/attendance/attendance/',
            },
            'todos': {
                'my_tasks': f'{base_url}/todos/my-tasks/',
                'tasks': f'{base_url}/todos/tasks/',
                'team_tasks': f'{base_url}/todos/team-tasks/',
                'report': f'{base_url}/todos/report/',
                'export': f'{base_url}/todos/export/',
            },
        },
        'documentation': {
            'api_docs': 'See API_VIEWS_DOCUMENTATION.md for detailed documentation',
            'dashboard': request.build_absolute_uri('/dashboard/'),
        },
        'info': {
            'description': 'Employee attendance tracking system with GPS location monitoring',
            'authentication': 'JWT tokens required for most endpoints (except login/register)',
            'format': 'JSON',
        }
    })
