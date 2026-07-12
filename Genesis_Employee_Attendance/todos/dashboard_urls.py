from django.urls import path

from . import dashboard_views

urlpatterns = [
    path('', dashboard_views.todos_dashboard, name='todos-dashboard'),
    path('report/', dashboard_views.todos_report, name='todos-report'),
    path('export-csv/', dashboard_views.todos_export_csv, name='todos-export-csv'),
    path('permissions/', dashboard_views.todos_permissions, name='todos-permissions'),
    path('add/', dashboard_views.todos_add_task, name='todos-add-task'),
    path('<uuid:task_id>/edit/', dashboard_views.todos_update_task, name='todos-update-task'),
    path('<uuid:task_id>/delete/', dashboard_views.todos_delete_task, name='todos-delete-task'),
    path('<uuid:task_id>/complete/', dashboard_views.todos_toggle_complete, name='todos-toggle-complete'),
]
