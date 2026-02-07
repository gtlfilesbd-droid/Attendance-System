from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    log_location, live_locations, latest_location, employee_route, my_route_today,
    LocationLogViewSet
)

router = DefaultRouter()
router.register(r'location-logs', LocationLogViewSet, basename='location-log')

urlpatterns = [
    # Location tracking endpoints
    path('log-location/', log_location, name='log-location'),
    path('live-locations/', live_locations, name='live-locations'),
    path('latest-location/', latest_location, name='latest-location'),
    path('employee-route/', employee_route, name='employee-route'),
    path('my-route-today/', my_route_today, name='my-route-today'),
    
    # ViewSet routes
    path('', include(router.urls)),
]
