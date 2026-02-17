"""
URL configuration for Genesis Employee Attendance project.
"""
from django.contrib import admin
import config.admin  # noqa: F401 - re-registers User/Group with export mixin

admin.site.site_header = 'Genesis Administration'
admin.site.site_title = 'Genesis Administration'
admin.site.index_title = 'Genesis Administration'
admin.site.site_url = '/dashboard/'
from django.contrib.auth.views import LogoutView
from django.urls import path, include
from django.views.generic import RedirectView
from django.conf import settings
from django.conf.urls.static import static
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
    TokenVerifyView,
)
from .views import api_root

urlpatterns = [
    path('', RedirectView.as_view(url='/dashboard/', permanent=False)),
    path('admin/', admin.site.urls),
    
    # API Root
    path('api/', api_root, name='api-root'),
    
    # JWT Authentication
    path('api/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/token/verify/', TokenVerifyView.as_view(), name='token_verify'),
    
    # App URLs
    path('api/employees/', include('employees.urls')),
    path('api/tracking/', include('tracking.urls')),
    path('api/attendance/', include('attendance.urls')),

    # Web dashboard (templates)
    path('dashboard/', include('tracking.dashboard_urls')),
    
    # Logout
    path('logout/', LogoutView.as_view(next_page='/dashboard/'), name='logout'),
]

# Serve media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
