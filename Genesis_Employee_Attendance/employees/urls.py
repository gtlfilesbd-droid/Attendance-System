from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import EmployeeViewSet, employee_login, employee_register

router = DefaultRouter()
router.register(r'employees', EmployeeViewSet, basename='employee')

urlpatterns = [
    # Authentication endpoints
    path('auth/login/', employee_login, name='employee-login'),
    path('auth/register/', employee_register, name='employee-register'),
    
    # Employee CRUD endpoints
    path('', include(router.urls)),
]
