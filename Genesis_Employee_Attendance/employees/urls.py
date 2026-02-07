from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import EmployeeViewSet, employee_login, employee_register, employee_me

router = DefaultRouter()
router.register(r'employees', EmployeeViewSet, basename='employee')

urlpatterns = [
    # Authentication endpoints
    path('auth/login/', employee_login, name='employee-login'),
    path('auth/register/', employee_register, name='employee-register'),
    # App calls /api/employees/me/ (router would expose /api/employees/employees/me/)
    path('me/', employee_me, name='employee-me'),
    # Employee CRUD endpoints
    path('', include(router.urls)),
]
