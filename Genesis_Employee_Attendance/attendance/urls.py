from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    my_attendance, all_attendance, attendance_report, clear_my_data, AttendanceViewSet
)

router = DefaultRouter()
router.register(r'attendance', AttendanceViewSet, basename='attendance')

urlpatterns = [
    # Attendance query endpoints
    path('my-attendance/', my_attendance, name='my-attendance'),
    path('clear-my-data/', clear_my_data, name='clear-my-data'),
    path('all/', all_attendance, name='all-attendance'),
    path('report/', attendance_report, name='attendance-report'),
    
    # ViewSet routes
    path('', include(router.urls)),
]
