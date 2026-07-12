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
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings as jwt_settings
from rest_framework.permissions import AllowAny
from .views import api_root


class EmployeeTokenRefreshSerializer(TokenRefreshSerializer):
    """
    Custom refresh serializer that skips the get_user_model() existence check.

    simplejwt 5.x added a user-existence check in validate() that calls
    get_user_model().objects.get(id=user_id_from_token).  Our Employee model
    uses a UUID primary key while Django's auth.User uses an integer, so the
    lookup raises ValueError.  Since we authenticate via EmployeeJWTAuthentication
    (not Django's user model), the existence check is unnecessary — the token
    signature + expiry validation done by self.token_class() is sufficient.
    """

    def validate(self, attrs):
        refresh = self.token_class(attrs['refresh'])
        # Token signature, expiry, and type are verified by self.token_class().
        # Skip the get_user_model() lookup — incompatible with UUID-pk Employee.
        data = {'access': str(refresh.access_token)}
        if jwt_settings.ROTATE_REFRESH_TOKENS:
            if jwt_settings.BLACKLIST_AFTER_ROTATION:
                try:
                    refresh.blacklist()
                except AttributeError:
                    # token_blacklist app not installed — expected, ignore silently.
                    pass
            refresh.set_jti()
            refresh.set_exp()
            refresh.set_iat()
            data['refresh'] = str(refresh)
        return data


class NoAuthTokenRefreshView(TokenRefreshView):
    """
    Token refresh endpoint with authentication and user-model lookup disabled.

    The standard TokenRefreshView inherits DEFAULT_AUTHENTICATION_CLASSES, so any
    expired access token in the Authorization header causes EmployeeJWTAuthentication
    or JWTAuthentication to raise AuthenticationFailed (401) before the refresh body
    is ever processed.  The mobile app then mis-reads this as "refresh token invalid"
    and triggers an auto-logout (TOKEN_REFRESH_FAILED).

    Setting authentication_classes = [] means DRF skips all authenticators entirely
    for this endpoint. The refresh token in the request body is the only credential
    needed; no Bearer token is required or expected.
    """
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = EmployeeTokenRefreshSerializer


urlpatterns = [
    path('', RedirectView.as_view(url='/dashboard/', permanent=False)),
    path('admin/', admin.site.urls),

    # API Root
    path('api/', api_root, name='api-root'),

    # JWT Authentication
    path('api/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/token/refresh/', NoAuthTokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/token/verify/', TokenVerifyView.as_view(), name='token_verify'),
    
    # App URLs
    path('api/employees/', include('employees.urls')),
    path('api/audit/', include('audit.urls')),
    path('api/tracking/', include('tracking.urls')),
    path('api/attendance/', include('attendance.urls')),
    path('api/todos/', include('todos.urls')),

    # Web dashboard (templates)
    path('dashboard/', include('tracking.dashboard_urls')),
    path('dashboard/todos/', include('todos.dashboard_urls')),
    
    # Logout
    path('logout/', LogoutView.as_view(next_page='/dashboard/'), name='logout'),
]

# Serve media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
