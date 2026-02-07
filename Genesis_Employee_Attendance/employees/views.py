import json
import os
from rest_framework import viewsets, status, generics
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, IsAdminUser, AllowAny
from rest_framework.pagination import PageNumberPagination
from rest_framework_simplejwt.tokens import RefreshToken
from django_filters.rest_framework import DjangoFilterBackend
from django.shortcuts import get_object_or_404
from .models import Employee
from .serializers import (
    EmployeeSerializer, EmployeeLoginSerializer, EmployeeProfileSerializer
)
import logging
logger = logging.getLogger('employees.views')


class StandardResultsSetPagination(PageNumberPagination):
    """Standard pagination class"""
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 100


class IsAdminOrReadOnly(IsAuthenticated):
    """Custom permission: Admin for write, authenticated for read"""
    def has_permission(self, request, view):
        if request.method in ['GET', 'HEAD', 'OPTIONS']:
            return request.user and request.user.is_authenticated
        # For write operations, check if user has admin privileges
        return request.user and request.user.is_authenticated and (
            hasattr(request.user, 'is_staff') and request.user.is_staff
        )


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def employee_me(request):
    """
    Get current employee profile (JWT auth).
    GET /api/employees/me/
    Used by the app; router exposes me at /api/employees/employees/me/, this path is /api/employees/me/.
    """
    user = request.user
    if not isinstance(user, Employee):
        return Response(
            {'success': False, 'message': 'Not an employee account. Use employee JWT.'},
            status=status.HTTP_403_FORBIDDEN,
        )
    serializer = EmployeeProfileSerializer(user)
    return Response({
        'success': True,
        'data': serializer.data,
    })


@api_view(['POST'])
@permission_classes([AllowAny])
def employee_login(request):
    """
    Employee login endpoint
    POST /api/auth/login/
    
    Request body:
    {
        "email": "employee@example.com",
        "password": "password123"
    }
    
    Returns JWT access and refresh tokens
    """
    # #region agent log – login attempt visibility
    client_ip = request.META.get('REMOTE_ADDR', '')
    req_email = (request.data or {}).get('email', '') or '(no email)'
    logger.info(
        "employee_login: request from client_ip=%s email=%s path=%s",
        client_ip, req_email, request.path,
    )
    # #endregion
    serializer = EmployeeLoginSerializer(data=request.data)
    
    if serializer.is_valid():
        employee = serializer.validated_data['employee']
        # #region agent log
        try:
            _lp = os.environ.get('DEBUG_LOG_PATH', r'e:\Attendance System\.cursor\debug.log')
            with open(_lp, 'a') as _f:
                _f.write(json.dumps({'sessionId': 'debug-session', 'runId': 'run1', 'hypothesisId': 'H2', 'location': 'employees/views.py:employee_login', 'message': 'login_success', 'data': {'employee_id': str(employee.id), 'email': employee.email}, 'timestamp': __import__('time').time() * 1000}) + '\n')
        except Exception:
            pass
        # #endregion
        # Generate JWT tokens
        refresh = RefreshToken.for_user(employee)
        
        return Response({
            'success': True,
            'message': 'Login successful',
            'data': {
                'access': str(refresh.access_token),
                'refresh': str(refresh),
                'employee': EmployeeProfileSerializer(employee).data
            }
        }, status=status.HTTP_200_OK)
    
    # #region agent log – login failure reason
    logger.warning(
        "employee_login: failed client_ip=%s email=%s errors=%s",
        request.META.get('REMOTE_ADDR', ''), req_email, serializer.errors,
    )
    # #endregion
    return Response({
        'success': False,
        'message': 'Login failed',
        'errors': serializer.errors
    }, status=status.HTTP_400_BAD_REQUEST)


@api_view(['POST'])
@permission_classes([IsAdminUser])
def employee_register(request):
    """
    Register new employee endpoint (Admin only)
    POST /api/auth/register/
    
    Request body:
    {
        "employee_id": "EMP001",
        "name": "John Doe",
        "email": "john@example.com",
        "password": "password123",
        "phone": "+1234567890",
        "department": "IT",
        "designation": "Developer",
        "join_date": "2024-01-15",
        "is_active": true
    }
    """
    serializer = EmployeeSerializer(data=request.data)
    
    if serializer.is_valid():
        employee = serializer.save()
        
        return Response({
            'success': True,
            'message': 'Employee registered successfully',
            'data': EmployeeProfileSerializer(employee).data
        }, status=status.HTTP_201_CREATED)
    
    return Response({
        'success': False,
        'message': 'Registration failed',
        'errors': serializer.errors
    }, status=status.HTTP_400_BAD_REQUEST)


class EmployeeViewSet(viewsets.ModelViewSet):
    """
    ViewSet for Employee management
    
    Endpoints:
    - GET /api/employees/ - List all employees (admin only)
    - GET /api/employees/me/ - Get current employee profile
    - PUT /api/employees/me/ - Update current employee profile
    - GET /api/employees/{id}/ - Get specific employee
    - POST /api/employees/ - Create employee (admin only)
    - PUT /api/employees/{id}/ - Update employee (admin only)
    - DELETE /api/employees/{id}/ - Delete employee (admin only)
    """
    queryset = Employee.objects.all()
    serializer_class = EmployeeSerializer
    pagination_class = StandardResultsSetPagination
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['department', 'designation', 'is_active']
    
    def get_permissions(self):
        """Set permissions based on action"""
        if self.action in ['list', 'create', 'destroy']:
            # Only admin can list all, create, or delete
            return [IsAdminUser()]
        elif self.action in ['retrieve', 'update', 'partial_update']:
            # Admin can view/edit anyone, users can only view/edit themselves
            return [IsAuthenticated()]
        elif self.action in ['me', 'update_me']:
            return [IsAuthenticated()]
        return [IsAuthenticated()]
    
    def get_serializer_class(self):
        """Return appropriate serializer"""
        if self.action in ['me', 'update_me']:
            return EmployeeProfileSerializer
        return EmployeeSerializer
    
    def retrieve(self, request, *args, **kwargs):
        """Get specific employee - admin or self only"""
        employee = self.get_object()
        
        # Check if user is admin or requesting their own profile
        if not (request.user.is_staff or request.user.id == employee.id):
            return Response({
                'success': False,
                'message': 'You do not have permission to view this profile'
            }, status=status.HTTP_403_FORBIDDEN)
        
        serializer = EmployeeProfileSerializer(employee)
        return Response({
            'success': True,
            'data': serializer.data
        })
    
    def update(self, request, *args, **kwargs):
        """Update employee - admin or self only"""
        employee = self.get_object()
        
        # Check if user is admin or updating their own profile
        if not (request.user.is_staff or request.user.id == employee.id):
            return Response({
                'success': False,
                'message': 'You do not have permission to update this profile'
            }, status=status.HTTP_403_FORBIDDEN)
        
        partial = kwargs.pop('partial', False)
        serializer = self.get_serializer(employee, data=request.data, partial=partial)
        
        if serializer.is_valid():
            serializer.save()
            return Response({
                'success': True,
                'message': 'Profile updated successfully',
                'data': serializer.data
            })
        
        return Response({
            'success': False,
            'message': 'Update failed',
            'errors': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)
    
    def list(self, request, *args, **kwargs):
        """List all employees (admin only)"""
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        
        if page is not None:
            serializer = EmployeeProfileSerializer(page, many=True)
            return self.get_paginated_response({
                'success': True,
                'data': serializer.data
            })
        
        serializer = EmployeeProfileSerializer(queryset, many=True)
        return Response({
            'success': True,
            'data': serializer.data
        })
    
    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated])
    def me(self, request):
        """
        Get current employee profile
        GET /api/employees/me/
        """
        serializer = EmployeeProfileSerializer(request.user)
        return Response({
            'success': True,
            'data': serializer.data
        })
    
    @action(detail=False, methods=['put', 'patch'], permission_classes=[IsAuthenticated])
    def update_me(self, request):
        """
        Update current employee profile
        PUT /api/employees/me/
        
        Allows employees to update their own profile
        (excluding sensitive fields like employee_id, email)
        """
        serializer = EmployeeProfileSerializer(
            request.user,
            data=request.data,
            partial=request.method == 'PATCH'
        )
        
        if serializer.is_valid():
            serializer.save()
            return Response({
                'success': True,
                'message': 'Profile updated successfully',
                'data': serializer.data
            })
        
        return Response({
            'success': False,
            'message': 'Update failed',
            'errors': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)
