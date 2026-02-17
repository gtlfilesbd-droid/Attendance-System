from django.urls import path
from django.contrib.auth.views import LoginView, LogoutView

from . import views

urlpatterns = [
    path("login/", LoginView.as_view(
        template_name='registration/login.html',
        redirect_authenticated_user=True,
        success_url='/dashboard/',
    ), name='login'),
    path("", views.dashboard_home, name="dashboard-home"),
    path("employee-list/", views.dashboard_employee_list, name="dashboard-employee-list"),
    path("live-tracking/", views.live_tracking_view, name="live-tracking"),
    path("route-history/", views.route_history_view, name="route-history"),
    path("reports/", views.attendance_reports_view, name="attendance-reports"),
    path("export-csv/", views.export_csv, name="export-csv"),
    path("logout/", LogoutView.as_view(next_page='/dashboard/'), name="logout"),
]

