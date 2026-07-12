from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    EmployeeTodoPermissionViewSet,
    TodoTaskViewSet,
    export_todos_csv,
    my_tasks,
    team_tasks,
    todo_report,
)

router = DefaultRouter()
router.register(r'tasks', TodoTaskViewSet, basename='todo-task')
router.register(r'permissions', EmployeeTodoPermissionViewSet, basename='todo-permission')

urlpatterns = [
    path('my-tasks/', my_tasks, name='my-tasks'),
    path('team-tasks/', team_tasks, name='team-tasks'),
    path('report/', todo_report, name='todo-report'),
    path('export/', export_todos_csv, name='todo-export'),
    path('', include(router.urls)),
]
