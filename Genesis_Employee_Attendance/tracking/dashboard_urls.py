from django.urls import path
from django.contrib.auth.views import LogoutView

from . import views

urlpatterns = [
    path("", views.dashboard_home, name="dashboard-home"),
    path("live-tracking/", views.live_tracking_view, name="live-tracking"),
    path("route-history/", views.route_history_view, name="route-history"),
    path("reports/", views.attendance_reports_view, name="attendance-reports"),
    path("export-csv/", views.export_csv, name="export-csv"),
    path("logout/", LogoutView.as_view(next_page='/dashboard/'), name="logout"),
]

