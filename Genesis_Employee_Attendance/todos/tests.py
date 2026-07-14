from datetime import date, timedelta

from django.contrib.auth.models import User
from django.test import TestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from employees.models import Department, Employee, UserDepartmentPermission
from .dashboard_views import todos_add_task
from .models import EmployeeTodoPermission, TodoTask
from .utils import format_task_title, get_next_sort_order, validate_task_date_for_create


def _create_employee(employee_id='EMP001', email='emp1@test.com', department=None):
    emp = Employee(
        employee_id=employee_id,
        name='Test Employee',
        email=email,
        phone='+8801234567890',
        join_date=date.today(),
        department=department,
    )
    emp.set_password('testpass123')
    emp.save()
    return emp


def _auth_client(employee):
    client = APIClient()
    token = RefreshToken.for_user(employee)
    client.credentials(HTTP_AUTHORIZATION=f'Bearer {token.access_token}')
    return client


class TodoUtilsTest(TestCase):
    def setUp(self):
        self.employee = _create_employee()

    def test_auto_numbering_same_day(self):
        today = timezone.localdate()
        first = get_next_sort_order(self.employee, today)
        TodoTask.objects.create(
            employee=self.employee,
            title=format_task_title(first),
            description='First',
            task_date=today,
            sort_order=first,
        )
        second = get_next_sort_order(self.employee, today)
        self.assertEqual(first, 1)
        self.assertEqual(second, 2)

    def test_validate_past_date_rejected(self):
        past = timezone.localdate() - timedelta(days=1)
        with self.assertRaises(Exception):
            validate_task_date_for_create(past)

    def test_validate_beyond_30_days_rejected(self):
        future = timezone.localdate() + timedelta(days=31)
        with self.assertRaises(Exception):
            validate_task_date_for_create(future)


class TodoAPITest(TestCase):
    def setUp(self):
        self.department = Department.objects.create(name='IT')
        self.other_department = Department.objects.create(name='HR')
        self.employee = _create_employee(department=self.department)
        self.other_employee = _create_employee(
            employee_id='EMP002',
            email='emp2@test.com',
            department=self.other_department,
        )
        self.client = _auth_client(self.employee)
        self.today = timezone.localdate()

    def test_create_task_auto_title(self):
        response = self.client.post('/api/todos/tasks/', {
            'description': 'Plan meeting',
            'task_date': self.today.isoformat(),
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['success'])
        self.assertEqual(response.data['data']['title'], 'Task-01')
        self.assertFalse(response.data['data']['is_completed'])
        self.assertIsNone(response.data['data']['completed_at'])

    def test_second_task_same_day(self):
        self.client.post('/api/todos/tasks/', {
            'description': 'First task',
            'task_date': self.today.isoformat(),
        }, format='json')
        response = self.client.post('/api/todos/tasks/', {
            'description': 'Second task',
            'task_date': self.today.isoformat(),
        }, format='json')
        self.assertEqual(response.data['data']['title'], 'Task-02')

    def test_future_date_within_30_days(self):
        future = self.today + timedelta(days=10)
        response = self.client.post('/api/todos/tasks/', {
            'description': 'Future task',
            'task_date': future.isoformat(),
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_past_date_rejected(self):
        past = self.today - timedelta(days=1)
        response = self.client.post('/api/todos/tasks/', {
            'description': 'Past task',
            'task_date': past.isoformat(),
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_complete_toggle_and_undo(self):
        create = self.client.post('/api/todos/tasks/', {
            'description': 'Complete me',
            'task_date': self.today.isoformat(),
        }, format='json')
        task_id = create.data['data']['id']
        complete = self.client.patch(
            f'/api/todos/tasks/{task_id}/complete/',
            {'is_completed': True},
            format='json',
        )
        self.assertTrue(complete.data['data']['is_completed'])
        self.assertIsNotNone(complete.data['data']['completed_at'])
        undo = self.client.patch(
            f'/api/todos/tasks/{task_id}/complete/',
            {'is_completed': False},
            format='json',
        )
        self.assertFalse(undo.data['data']['is_completed'])
        self.assertIsNone(undo.data['data']['completed_at'])

    def test_my_tasks_list(self):
        self.client.post('/api/todos/tasks/', {
            'description': 'Listed task',
            'task_date': self.today.isoformat(),
        }, format='json')
        response = self.client.get(f'/api/todos/my-tasks/?task_date={self.today.isoformat()}')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['data']), 1)

    def test_edit_permission_blocks_create(self):
        EmployeeTodoPermission.objects.create(
            employee=self.employee,
            can_edit_my_app=False,
            can_delete_my_app=True,
        )
        create = self.client.post('/api/todos/tasks/', {
            'description': 'Locked edit',
            'task_date': self.today.isoformat(),
        }, format='json')
        self.assertEqual(create.status_code, status.HTTP_403_FORBIDDEN)

    def test_staff_sees_department_tasks_only(self):
        TodoTask.objects.create(
            employee=self.other_employee,
            title='Task-01',
            description='HR task',
            task_date=self.today,
            sort_order=1,
        )
        staff_user = User.objects.create_user(username='staff1', password='pass', is_staff=True)
        UserDepartmentPermission.objects.create(user=staff_user)
        staff_user.department_permission.departments.add(self.department)

        staff_client = APIClient()
        staff_client.force_authenticate(user=staff_user)
        response = staff_client.get('/api/todos/team-tasks/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results') or response.data.get('data', [])
        if isinstance(results, dict):
            results = results.get('results', [])
        self.assertEqual(len(results), 0)

        TodoTask.objects.create(
            employee=self.employee,
            title='Task-01',
            description='IT task',
            task_date=self.today,
            sort_order=1,
        )
        response = staff_client.get('/api/todos/team-tasks/')
        results = response.data.get('results') or response.data.get('data', [])
        if isinstance(results, dict):
            results = results.get('results', [])
        self.assertEqual(len(results), 1)


class TodoDashboardAssignTest(TestCase):
    def setUp(self):
        self.department = Department.objects.create(name='IT')
        self.assigner = _create_employee(employee_id='EMP001', email='ashraf@test.com', department=self.department)
        self.assignee = _create_employee(employee_id='EMP008', email='anam@test.com', department=self.department)
        self.assigner.name = 'Ashraf'
        self.assigner.save(update_fields=['name'])
        self.assignee.name = 'Anam'
        self.assignee.save(update_fields=['name'])
        self.staff = User.objects.create_user(username='staff-linked', password='pass', is_staff=True)
        self.assigner.user = self.staff
        self.assigner.save(update_fields=['user'])
        perm = UserDepartmentPermission.objects.create(user=self.staff)
        perm.departments.add(self.department)
        self.today = timezone.localdate()

    def test_team_add_sets_assigned_by_linked_employee(self):
        from django.test import RequestFactory

        rf = RequestFactory()
        request = rf.post('/dashboard/todos/add/', {
            'employee_id': str(self.assignee.id),
            'description': 'Assigned task',
            'task_date': self.today.isoformat(),
            'add_for_team': '1',
        })
        request.user = self.staff
        response = todos_add_task(request)
        self.assertEqual(response.status_code, 302)

        task = TodoTask.objects.get(description='Assigned task')
        self.assertEqual(task.employee_id, self.assignee.id)
        self.assertEqual(task.assigned_by_id, self.assigner.id)
        self.assertIsNone(task.assigned_by_username)
        self.assertEqual(
            task.assigner_display,
            f'{self.assigner.name} ({self.assigner.employee_id})',
        )

    def test_team_add_without_linked_employee_uses_username(self):
        from django.test import RequestFactory

        staff = User.objects.create_user(username='adminstaff', password='pass', is_staff=True)
        perm = UserDepartmentPermission.objects.create(user=staff)
        perm.departments.add(self.department)

        rf = RequestFactory()
        request = rf.post('/dashboard/todos/add/', {
            'employee_id': str(self.assignee.id),
            'description': 'Username assigned task',
            'task_date': self.today.isoformat(),
            'add_for_team': '1',
        })
        request.user = staff
        response = todos_add_task(request)
        self.assertEqual(response.status_code, 302)

        task = TodoTask.objects.get(description='Username assigned task')
        self.assertIsNone(task.assigned_by_id)
        self.assertEqual(task.assigned_by_username, 'adminstaff')
        self.assertEqual(task.assigner_display, 'adminstaff')

    def test_my_tasks_api_returns_assigner_display(self):
        task = TodoTask.objects.create(
            employee=self.assignee,
            assigned_by=self.assigner,
            title='Task-01',
            description='From Ashraf',
            task_date=self.today,
            sort_order=1,
        )
        client = _auth_client(self.assignee)
        response = client.get(f'/api/todos/my-tasks/?task_date={self.today.isoformat()}')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        item = response.data['data'][0]
        self.assertEqual(item['assigner_display'], f'{self.assigner.name} ({self.assigner.employee_id})')
        self.assertIn('assigned a task for', item['assignment_label'])
        self.assertIn(self.assignee.name, item['assignment_label'])
        self.assertFalse(item['can_edit'])
        self.assertFalse(item['can_delete'])

    def test_self_created_task_has_no_assigner(self):
        response = _auth_client(self.assignee).post('/api/todos/tasks/', {
            'description': 'My own task',
            'task_date': self.today.isoformat(),
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIsNone(response.data['data']['assigner_display'])
        self.assertIsNone(response.data['data']['assignment_label'])


class TodoDashboardStatusFilterTest(TestCase):
    def setUp(self):
        self.department = Department.objects.create(name='IT')
        self.employee = _create_employee(department=self.department)
        self.staff = User.objects.create_user(username='staff-status', password='pass', is_staff=True)
        self.employee.user = self.staff
        self.employee.save(update_fields=['user'])
        perm = UserDepartmentPermission.objects.create(user=self.staff)
        perm.departments.add(self.department)
        self.today = timezone.localdate()
        TodoTask.objects.create(
            employee=self.employee,
            title='Task-01',
            description='Pending task',
            task_date=self.today,
            sort_order=1,
            is_completed=False,
        )
        TodoTask.objects.create(
            employee=self.employee,
            title='Task-02',
            description='Done task',
            task_date=self.today,
            sort_order=2,
            is_completed=True,
        )

    def test_status_filter_pending(self):
        from django.test import Client, override_settings

        with override_settings(ALLOWED_HOSTS=['testserver']):
            client = Client()
            client.force_login(self.staff)
            response = client.get('/dashboard/todos/', {
                'date': self.today.isoformat(),
                'view': 'mine',
                'status': 'pending',
            })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.context['pending_tasks']), 1)
        self.assertEqual(len(response.context['completed_tasks']), 1)
        self.assertEqual(response.context['status_filter'], 'pending')
        self.assertIn(b'data-task-group="pending"', response.content)
        self.assertIn(b'data-task-group="completed"', response.content)
        self.assertIn(b'id="todo-status-tabs"', response.content)

    def test_status_filter_completed(self):
        from django.test import Client, override_settings

        with override_settings(ALLOWED_HOSTS=['testserver']):
            client = Client()
            client.force_login(self.staff)
            response = client.get('/dashboard/todos/', {
                'date': self.today.isoformat(),
                'view': 'team',
                'status': 'completed',
            })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.context['pending_tasks']), 1)
        self.assertEqual(len(response.context['completed_tasks']), 1)
        self.assertEqual(response.context['status_filter'], 'completed')


class TodoSplitPermissionTest(TestCase):
    def setUp(self):
        self.department = Department.objects.create(name='IT')
        self.assignee = _create_employee(
            employee_id='EMP-A', email='assignee@test.com', department=self.department,
        )
        self.assigner = _create_employee(
            employee_id='EMP-B', email='assigner@test.com', department=self.department,
        )
        self.assigner.name = 'Assigner'
        self.assigner.save(update_fields=['name'])
        self.staff = User.objects.create_user(username='assigner-staff', password='pass', is_staff=True)
        self.assigner.user = self.staff
        self.assigner.save(update_fields=['user'])
        perm = UserDepartmentPermission.objects.create(user=self.staff)
        perm.departments.add(self.department)
        self.today = timezone.localdate()
        self.assigned_task = TodoTask.objects.create(
            employee=self.assignee,
            assigned_by=self.assigner,
            title='Task-01',
            description='Assigned',
            task_date=self.today,
            sort_order=1,
        )
        self.self_task = TodoTask.objects.create(
            employee=self.assignee,
            title='Task-02',
            description='Own task',
            task_date=self.today,
            sort_order=2,
        )

    def test_assignee_cannot_edit_or_delete_assigned_task_via_api(self):
        client = _auth_client(self.assignee)
        patch = client.patch(
            f'/api/todos/tasks/{self.assigned_task.id}/',
            {'description': 'Hacked'},
            format='json',
        )
        self.assertEqual(patch.status_code, status.HTTP_403_FORBIDDEN)
        delete = client.delete(f'/api/todos/tasks/{self.assigned_task.id}/')
        self.assertEqual(delete.status_code, status.HTTP_403_FORBIDDEN)
        complete = client.patch(
            f'/api/todos/tasks/{self.assigned_task.id}/complete/',
            {'is_completed': True},
            format='json',
        )
        self.assertEqual(complete.status_code, status.HTTP_200_OK)
        self.assertTrue(complete.data['data']['is_completed'])

    def test_self_task_respects_my_app_edit_flag(self):
        EmployeeTodoPermission.objects.create(
            employee=self.assignee,
            can_edit_my_app=False,
            can_delete_my_app=True,
        )
        client = _auth_client(self.assignee)
        patch = client.patch(
            f'/api/todos/tasks/{self.self_task.id}/',
            {'description': 'Nope'},
            format='json',
        )
        self.assertEqual(patch.status_code, status.HTTP_403_FORBIDDEN)
        create = client.post('/api/todos/tasks/', {
            'description': 'New',
            'task_date': self.today.isoformat(),
        }, format='json')
        self.assertEqual(create.status_code, status.HTTP_403_FORBIDDEN)

    def test_assigner_web_edit_respects_assigned_web_flag(self):
        from django.test import RequestFactory
        from .dashboard_views import todos_update_task

        EmployeeTodoPermission.objects.create(
            employee=self.assigner,
            can_edit_assigned_web=False,
            can_delete_assigned_web=True,
        )
        rf = RequestFactory()
        denied = rf.post(f'/dashboard/todos/{self.assigned_task.id}/edit/', {
            'description': 'Updated',
            'next': '/dashboard/todos/',
        })
        denied.user = self.staff
        resp = todos_update_task(denied, self.assigned_task.id)
        self.assertEqual(resp.status_code, 403)

        EmployeeTodoPermission.objects.filter(employee=self.assigner).update(can_edit_assigned_web=True)
        allowed = rf.post(f'/dashboard/todos/{self.assigned_task.id}/edit/', {
            'description': 'Updated by assigner',
            'next': '/dashboard/todos/',
        })
        allowed.user = self.staff
        resp2 = todos_update_task(allowed, self.assigned_task.id)
        self.assertEqual(resp2.status_code, 302)
        self.assigned_task.refresh_from_db()
        self.assertEqual(self.assigned_task.description, 'Updated by assigner')

    def test_non_assigner_staff_cannot_edit_assigned_task(self):
        from django.test import RequestFactory
        from .dashboard_views import todos_update_task

        other = User.objects.create_user(username='other-staff', password='pass', is_staff=True)
        UserDepartmentPermission.objects.create(user=other).departments.add(self.department)
        rf = RequestFactory()
        req = rf.post(f'/dashboard/todos/{self.assigned_task.id}/edit/', {
            'description': 'Intruder',
            'next': '/dashboard/todos/',
        })
        req.user = other
        resp = todos_update_task(req, self.assigned_task.id)
        self.assertEqual(resp.status_code, 403)
