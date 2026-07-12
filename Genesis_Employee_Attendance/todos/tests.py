from datetime import date, timedelta

from django.contrib.auth.models import User
from django.test import TestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from employees.models import Department, Employee, UserDepartmentPermission
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
            can_edit=False,
            can_delete=True,
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
