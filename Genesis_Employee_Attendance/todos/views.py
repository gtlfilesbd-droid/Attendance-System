import csv
from datetime import datetime, timedelta

from django.core.exceptions import ValidationError
from django.db.models import Count, Q
from django.http import HttpResponse
from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from employees.department_permissions import get_permitted_departments
from employees.models import Employee
from .models import EmployeeTodoPermission, TodoTask
from .permissions import IsOwnerOrStaff, IsStaffUser, resolve_employee
from .serializers import (
    EmployeeTodoPermissionSerializer,
    TodoTaskCompleteSerializer,
    TodoTaskCreateSerializer,
    TodoTaskSerializer,
    TodoTaskUpdateSerializer,
)
from .utils import (
    employee_can_delete,
    employee_can_edit,
    format_task_title,
    get_next_sort_order,
    validate_task_date_for_create,
)


class StandardResultsSetPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 200


def _success(data=None, message='', status_code=status.HTTP_200_OK):
    return Response({'success': True, 'data': data, 'message': message}, status=status_code)


def _error(message, errors=None, status_code=status.HTTP_400_BAD_REQUEST):
    payload = {'success': False, 'message': message}
    if errors is not None:
        payload['errors'] = errors
    return Response(payload, status=status_code)


def _apply_completion(task, is_completed):
    if is_completed:
        task.is_completed = True
        task.completed_at = timezone.now()
    else:
        task.is_completed = False
        task.completed_at = None
    task.save(update_fields=['is_completed', 'completed_at', 'updated_at'])


def _filter_tasks_queryset(queryset, request):
    task_date = request.query_params.get('task_date')
    task_date_from = request.query_params.get('task_date_from')
    task_date_to = request.query_params.get('task_date_to')
    search = request.query_params.get('search', '').strip()
    department = request.query_params.get('department', '').strip()
    is_completed = request.query_params.get('is_completed')

    if task_date:
        queryset = queryset.filter(task_date=task_date)
    if task_date_from:
        queryset = queryset.filter(task_date__gte=task_date_from)
    if task_date_to:
        queryset = queryset.filter(task_date__lte=task_date_to)
    if search:
        queryset = queryset.filter(
            Q(title__icontains=search) | Q(description__icontains=search)
        )
    if department:
        queryset = queryset.filter(employee__department__name=department)
    if is_completed in ('true', '1'):
        queryset = queryset.filter(is_completed=True)
    elif is_completed in ('false', '0'):
        queryset = queryset.filter(is_completed=False)
    return queryset.order_by('task_date', 'sort_order')


def _staff_queryset(user):
    permitted = get_permitted_departments(user)
    return TodoTask.objects.filter(
        employee__department__in=permitted
    ).select_related('employee', 'employee__department')


def _report_aggregates(queryset):
    return queryset.aggregate(
        total=Count('id'),
        completed_count=Count('id', filter=Q(is_completed=True)),
        pending_count=Count('id', filter=Q(is_completed=False)),
    )


class TodoTaskViewSet(viewsets.ModelViewSet):
    serializer_class = TodoTaskSerializer
    pagination_class = StandardResultsSetPagination
    permission_classes = [IsAuthenticated, IsOwnerOrStaff]
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    def get_queryset(self):
        user = self.request.user
        qs = TodoTask.objects.select_related('employee', 'employee__department')
        if isinstance(user, Employee):
            return _filter_tasks_queryset(qs.filter(employee=user), self.request)
        if getattr(user, 'is_staff', False):
            return _filter_tasks_queryset(_staff_queryset(user), self.request)
        employee = resolve_employee(user)
        if employee:
            return _filter_tasks_queryset(qs.filter(employee=employee), self.request)
        return TodoTask.objects.none()

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        page = self.paginate_queryset(queryset)
        serializer = self.get_serializer(page or queryset, many=True)
        if page is not None:
            paginated = self.get_paginated_response(serializer.data)
            return _success({
                'results': paginated.data['results'],
                'count': paginated.data['count'],
                'next': paginated.data.get('next'),
                'previous': paginated.data.get('previous'),
            })
        return _success(serializer.data)

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        return _success(self.get_serializer(instance).data)

    def create(self, request, *args, **kwargs):
        user = request.user
        if not isinstance(user, Employee):
            return _error('Only employees can create tasks.', status_code=status.HTTP_403_FORBIDDEN)
        if not employee_can_edit(user):
            return _error('Edit permission is disabled for your account.', status_code=status.HTTP_403_FORBIDDEN)

        serializer = TodoTaskCreateSerializer(data=request.data)
        if not serializer.is_valid():
            return _error('Validation failed.', errors=serializer.errors)

        task_date = serializer.validated_data.get('task_date') or timezone.localdate()
        try:
            validate_task_date_for_create(task_date)
        except ValidationError as exc:
            return _error(exc.messages[0] if exc.messages else str(exc))

        sort_order = get_next_sort_order(user, task_date)
        task = TodoTask.objects.create(
            employee=user,
            title=format_task_title(sort_order),
            description=serializer.validated_data['description'],
            task_date=task_date,
            sort_order=sort_order,
            is_completed=False,
        )
        return _success(
            TodoTaskSerializer(task, context={'request': request}).data,
            message='Task created.',
            status_code=status.HTTP_201_CREATED,
        )

    def partial_update(self, request, *args, **kwargs):
        instance = self.get_object()
        user = request.user
        employee = user if isinstance(user, Employee) else resolve_employee(user)
        if employee and instance.employee_id == employee.id:
            if not employee_can_edit(employee):
                return _error('Edit permission is disabled for your account.', status_code=status.HTTP_403_FORBIDDEN)

        serializer = TodoTaskUpdateSerializer(data=request.data, partial=True)
        if not serializer.is_valid():
            return _error('Validation failed.', errors=serializer.errors)

        if 'description' in serializer.validated_data:
            instance.description = serializer.validated_data['description']
            instance.save(update_fields=['description', 'updated_at'])
        return _success(
            TodoTaskSerializer(instance, context={'request': request}).data,
            message='Task updated.',
        )

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        user = request.user
        if isinstance(user, Employee) and instance.employee_id == user.id:
            if not employee_can_delete(user):
                return _error('Delete permission is disabled for your account.', status_code=status.HTTP_403_FORBIDDEN)
        instance.delete()
        return _success(message='Task deleted.')

    @action(detail=True, methods=['patch'], url_path='complete')
    def toggle_complete(self, request, pk=None):
        instance = self.get_object()
        user = request.user
        employee = user if isinstance(user, Employee) else resolve_employee(user)
        if isinstance(user, Employee) and instance.employee_id != user.id:
            return _error('You can only update your own tasks.', status_code=status.HTTP_403_FORBIDDEN)
        if employee and instance.employee_id == employee.id:
            pass
        elif not getattr(user, 'is_staff', False):
            return _error('Not permitted.', status_code=status.HTTP_403_FORBIDDEN)

        serializer = TodoTaskCompleteSerializer(data=request.data)
        if not serializer.is_valid():
            return _error('Validation failed.', errors=serializer.errors)

        _apply_completion(instance, serializer.validated_data['is_completed'])
        return _success(
            TodoTaskSerializer(instance, context={'request': request}).data,
            message='Task marked complete.' if instance.is_completed else 'Task marked incomplete.',
        )


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def my_tasks(request):
    """GET /api/todos/my-tasks/ — employee's own tasks."""
    user = request.user
    if not isinstance(user, Employee):
        return _error('Employee JWT required.', status_code=status.HTTP_403_FORBIDDEN)

    queryset = _filter_tasks_queryset(
        TodoTask.objects.filter(employee=user).select_related('employee', 'employee__department'),
        request,
    )
    serializer = TodoTaskSerializer(queryset, many=True, context={'request': request})
    return _success(serializer.data)


@api_view(['GET'])
@permission_classes([IsAuthenticated, IsStaffUser])
def team_tasks(request):
    """GET /api/todos/team-tasks/ — department-scoped tasks for staff."""
    queryset = _filter_tasks_queryset(_staff_queryset(request.user), request)
    paginator = StandardResultsSetPagination()
    page = paginator.paginate_queryset(queryset, request)
    serializer = TodoTaskSerializer(page or queryset, many=True, context={'request': request})
    if page is not None:
        return paginator.get_paginated_response(serializer.data)
    return _success(serializer.data)


@api_view(['GET'])
@permission_classes([IsAuthenticated, IsStaffUser])
def todo_report(request):
    """GET /api/todos/report/ — aggregated team report."""
    queryset = _filter_tasks_queryset(_staff_queryset(request.user), request)
    summary = _report_aggregates(queryset)
    by_department = list(
        queryset.values('employee__department__name')
        .annotate(
            total=Count('id'),
            completed_count=Count('id', filter=Q(is_completed=True)),
            pending_count=Count('id', filter=Q(is_completed=False)),
        )
        .order_by('employee__department__name')
    )
    by_employee = list(
        queryset.values('employee__employee_id', 'employee__name', 'employee__department__name')
        .annotate(
            total=Count('id'),
            completed_count=Count('id', filter=Q(is_completed=True)),
            pending_count=Count('id', filter=Q(is_completed=False)),
        )
        .order_by('employee__name')
    )
    return _success({
        'summary': summary,
        'by_department': by_department,
        'by_employee': by_employee,
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated, IsStaffUser])
def export_todos_csv(request):
    """GET /api/todos/export/ — CSV export for staff/admin."""
    queryset = _filter_tasks_queryset(_staff_queryset(request.user), request)
    today = timezone.localdate()
    filename = f'todo_report_{today}.csv'
    response = HttpResponse(content_type='text/csv')
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    writer = csv.writer(response)
    writer.writerow([
        'Employee ID', 'Employee Name', 'Department', 'Task Date',
        'Task', 'Description', 'Completed', 'Completed At', 'Created At',
    ])
    for task in queryset:
        writer.writerow([
            task.employee.employee_id,
            task.employee.name,
            task.employee.department.name if task.employee.department_id else '',
            task.task_date.isoformat(),
            task.title,
            task.description,
            'Yes' if task.is_completed else 'No',
            task.completed_at.strftime('%Y-%m-%d %H:%M:%S') if task.completed_at else '',
            task.created_at.strftime('%Y-%m-%d %H:%M:%S'),
        ])
    return response


class EmployeeTodoPermissionViewSet(viewsets.ModelViewSet):
    serializer_class = EmployeeTodoPermissionSerializer
    permission_classes = [IsAuthenticated, IsStaffUser]
    http_method_names = ['get', 'put', 'patch', 'post', 'head', 'options']
    queryset = EmployeeTodoPermission.objects.select_related('employee', 'employee__department')

    def get_queryset(self):
        permitted = get_permitted_departments(self.request.user)
        return self.queryset.filter(employee__department__in=permitted)

    def list(self, request, *args, **kwargs):
        queryset = self.filter_queryset(self.get_queryset())
        serializer = self.get_serializer(queryset, many=True)
        return _success(serializer.data)

    def create(self, request, *args, **kwargs):
        employee_id = request.data.get('employee')
        if not employee_id:
            return _error('employee is required.')
        try:
            employee = Employee.objects.get(pk=employee_id)
        except Employee.DoesNotExist:
            return _error('Employee not found.', status_code=status.HTTP_404_NOT_FOUND)

        permitted = get_permitted_departments(request.user)
        if employee.department_id and not permitted.filter(pk=employee.department_id).exists():
            return _error('Not permitted for this employee.', status_code=status.HTTP_403_FORBIDDEN)

        obj, _created = EmployeeTodoPermission.objects.update_or_create(
            employee=employee,
            defaults={
                'can_edit': request.data.get('can_edit', True),
                'can_delete': request.data.get('can_delete', True),
            },
        )
        return _success(self.get_serializer(obj).data, message='Permission saved.')

    def partial_update(self, request, *args, **kwargs):
        instance = self.get_object()
        for field in ('can_edit', 'can_delete'):
            if field in request.data:
                setattr(instance, field, bool(request.data[field]))
        instance.save()
        return _success(self.get_serializer(instance).data, message='Permission updated.')
