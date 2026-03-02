from django.urls import path
from .views import mobile_logs_bulk

urlpatterns = [
    path('mobile-logs/bulk/', mobile_logs_bulk, name='mobile-logs-bulk'),
]
