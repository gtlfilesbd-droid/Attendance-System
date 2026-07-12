from datetime import datetime, timedelta

from django.contrib.auth.decorators import login_required
from django.db.models import Count, Q
from django.http import HttpResponse, HttpResponseForbidden
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from employees.department_permissions import get_permitted_departments
from employees.models import Department, Employee
from .models import EmployeeTodoPermission, TodoTask
from .permissions import resolve_employee
from .utils import (
    employee_can_delete,
    employee_can_edit,
    format_task_title,
    get_next_sort_order,
    validate_task_date_for_create,
)
from .views import _apply_completion, export_todos_csv as api_export_todos_csv


def _require_staff(user):
    return user.is_authenticated and user.is_staff


@login_required
def todos_dashboard(request):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')

    today = timezone.localdate()
    max_date = today + timedelta(days=30)

    date_str = request.GET.get('date')
    if date_str:
        try:
            selected_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            selected_date = today
    else:
        selected_date = today

    search = request.GET.get('search', '').strip()
    department = request.GET.get('department', '').strip()
    view_mode = request.GET.get('view')
    employee = resolve_employee(request.user)
    permitted = get_permitted_departments(request.user)

    if view_mode not in ('mine', 'team'):
        view_mode = 'mine' if employee else 'team'

    if view_mode == 'mine' and employee:
        queryset = TodoTask.objects.filter(employee=employee)
    else:
        queryset = TodoTask.objects.filter(employee__department__in=permitted)
        view_mode = 'team'

    queryset = queryset.select_related('employee', 'employee__department')
    queryset = queryset.filter(task_date=selected_date)
    if search:
        queryset = queryset.filter(Q(title__icontains=search) | Q(description__icontains=search))
    if department:
        queryset = queryset.filter(employee__department__name=department)
    tasks = list(queryset.order_by('employee__name', 'sort_order'))
    pending_tasks = [t for t in tasks if not t.is_completed]
    completed_tasks = [t for t in tasks if t.is_completed]
    pending_count = len(pending_tasks)
    completed_count = len(completed_tasks)
    total_count = len(tasks)

    departments = Department.objects.filter(is_active=True)
    if not request.user.is_superuser:
        departments = departments.filter(id__in=permitted.values_list('id', flat=True))

    can_add = bool(employee) and employee_can_edit(employee)
    can_edit = can_add
    addable_employees = []
    if view_mode == 'team' and request.user.is_staff:
        addable_employees = list(
            Employee.objects.filter(is_active=True, department__in=permitted)
            .select_related('department')
            .order_by('name')
        )
    can_add_for_team = bool(addable_employees)

    context = {
        'today': today,
        'max_date': max_date,
        'selected_date': selected_date,
        'search': search,
        'department': department,
        'view_mode': view_mode,
        'tasks': tasks,
        'pending_tasks': pending_tasks,
        'completed_tasks': completed_tasks,
        'pending_count': pending_count,
        'completed_count': completed_count,
        'total_count': total_count,
        'departments': departments,
        'has_employee_profile': bool(employee),
        'can_add': can_add,
        'can_edit': can_edit,
        'can_add_for_team': can_add_for_team,
        'addable_employees': addable_employees,
        'employee': employee,
    }
    return render(request, 'todos/index.html', context)


@login_required
@require_POST
def todos_add_task(request):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')

    employee = resolve_employee(request.user)
    employee_id = request.POST.get('employee_id')
    if not employee and employee_id and request.user.is_staff:
        try:
            employee = Employee.objects.get(pk=employee_id, is_active=True)
            permitted = get_permitted_departments(request.user)
            if not request.user.is_superuser and employee.department_id:
                if not permitted.filter(pk=employee.department_id).exists():
                    return HttpResponseForbidden('Not permitted for this employee.')
        except Employee.DoesNotExist:
            return redirect('todos-dashboard')

    if not employee:
        return redirect('todos-dashboard?link_required=1')
    if not employee_can_edit(employee):
        return redirect('todos-dashboard')

    description = (request.POST.get('description') or '').strip()
    date_str = request.POST.get('task_date')
    try:
        task_date = datetime.strptime(date_str, '%Y-%m-%d').date() if date_str else timezone.localdate()
    except ValueError:
        task_date = timezone.localdate()

    view_mode = 'mine' if resolve_employee(request.user) else 'team'
    if description:
        try:
            validate_task_date_for_create(task_date)
            sort_order = get_next_sort_order(employee, task_date)
            TodoTask.objects.create(
                employee=employee,
                title=format_task_title(sort_order),
                description=description,
                task_date=task_date,
                sort_order=sort_order,
            )
        except Exception:
            pass

    return redirect(f'/dashboard/todos/?date={task_date.isoformat()}&view={view_mode}')


@login_required
@require_POST
def todos_update_task(request, task_id):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')

    task = get_object_or_404(TodoTask, pk=task_id)
    user = request.user
    employee = resolve_employee(user)

    if not user.is_superuser:
        if employee and task.employee_id == employee.id:
            if not employee_can_edit(employee):
                return redirect('todos-dashboard')
        else:
            permitted = get_permitted_departments(user)
            if not permitted.filter(pk=task.employee.department_id).exists():
                return HttpResponseForbidden('Not permitted.')

    description = (request.POST.get('description') or '').strip()
    if description:
        task.description = description
        task.save(update_fields=['description', 'updated_at'])
    return redirect(request.POST.get('next', '/dashboard/todos/'))


@login_required
@require_POST
def todos_delete_task(request, task_id):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')

    task = get_object_or_404(TodoTask, pk=task_id)
    user = request.user
    employee = resolve_employee(user)
    task_date = task.task_date.isoformat()

    if employee and task.employee_id == employee.id:
        if not employee_can_delete(employee):
            return redirect('todos-dashboard')
    elif not user.is_superuser:
        permitted = get_permitted_departments(user)
        if not permitted.filter(pk=task.employee.department_id).exists():
            return HttpResponseForbidden('Not permitted.')
    else:
        pass

    task.delete()
    return redirect(request.POST.get('next', f'/dashboard/todos/?date={task_date}'))


@login_required
@require_POST
def todos_toggle_complete(request, task_id):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')

    task = get_object_or_404(TodoTask, pk=task_id)
    user = request.user
    employee = resolve_employee(user)

    if employee and task.employee_id == employee.id:
        pass
    elif user.is_superuser:
        pass
    else:
        permitted = get_permitted_departments(user)
        if not permitted.filter(pk=task.employee.department_id).exists():
            return HttpResponseForbidden('Not permitted.')
        if not (employee and task.employee_id == employee.id):
            return HttpResponseForbidden('Team leaders can view only.')

    is_completed = request.POST.get('is_completed') in ('1', 'true', 'True', 'on')
    _apply_completion(task, is_completed)
    return redirect(request.POST.get('next', '/dashboard/todos/'))


@login_required
def todos_report(request):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')

    today = timezone.localdate()
    start_str = request.GET.get('start_date')
    end_str = request.GET.get('end_date')
    department = request.GET.get('department', '').strip()

    try:
        start_date = datetime.strptime(start_str, '%Y-%m-%d').date() if start_str else today
    except ValueError:
        start_date = today
    try:
        end_date = datetime.strptime(end_str, '%Y-%m-%d').date() if end_str else today
    except ValueError:
        end_date = today

    permitted = get_permitted_departments(request.user)
    queryset = TodoTask.objects.filter(
        employee__department__in=permitted,
        task_date__gte=start_date,
        task_date__lte=end_date,
    ).select_related('employee', 'employee__department')
    if department:
        queryset = queryset.filter(employee__department__name=department)

    summary = queryset.aggregate(
        total=Count('id'),
        completed_count=Count('id', filter=Q(is_completed=True)),
        pending_count=Count('id', filter=Q(is_completed=False)),
    )
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

    departments = Department.objects.filter(is_active=True)
    if not request.user.is_superuser:
        departments = departments.filter(id__in=permitted.values_list('id', flat=True))

    return render(request, 'todos/report.html', {
        'today': today,
        'start_date': start_date,
        'end_date': end_date,
        'department': department,
        'departments': departments,
        'summary': summary,
        'by_department': by_department,
        'by_employee': by_employee,
    })


@login_required
def todos_export_csv(request):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')
    return api_export_todos_csv(request)


@login_required
def todos_permissions(request):
    if not _require_staff(request.user):
        return HttpResponseForbidden('Staff access required.')

    permitted = get_permitted_departments(request.user)
    employees = Employee.objects.filter(is_active=True, department__in=permitted).select_related('department')

    if request.method == 'POST':
        employee_id = request.POST.get('employee_id')
        try:
            emp = employees.get(pk=employee_id)
        except Employee.DoesNotExist:
            return redirect('todos-permissions')
        EmployeeTodoPermission.objects.update_or_create(
            employee=emp,
            defaults={
                'can_edit': request.POST.get('can_edit') == 'on',
                'can_delete': request.POST.get('can_delete') == 'on',
            },
        )
        return redirect('todos-permissions')

    permission_map = {
        p.employee_id: p
        for p in EmployeeTodoPermission.objects.filter(employee__in=employees)
    }
    rows = []
    for emp in employees:
        perm = permission_map.get(emp.id)
        rows.append({
            'employee': emp,
            'can_edit': perm.can_edit if perm else True,
            'can_delete': perm.can_delete if perm else True,
        })

    return render(request, 'todos/permissions.html', {'rows': rows})
