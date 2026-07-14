"""Celery tasks for the todos app."""
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(name='todos.send_todo_assigned_notification')
def send_todo_assigned_notification(task_id):
    """
    Async FCM push when a task is assigned to another employee.
    Safe to retry; missing task → no-op.
    """
    from .models import TodoTask
    from .notifications import send_todo_assigned_push

    try:
        task = (
            TodoTask.objects.select_related('employee', 'assigned_by')
            .filter(pk=task_id)
            .first()
        )
        if not task:
            logger.warning(
                'send_todo_assigned_notification: task not found id=%s',
                task_id,
            )
            return {'status': 'skipped', 'reason': 'task_not_found', 'task_id': str(task_id)}
        return send_todo_assigned_push(task)
    except Exception as e:
        logger.exception(
            'send_todo_assigned_notification error task_id=%s: %s',
            task_id,
            e,
        )
        return {'status': 'error', 'message': str(e), 'task_id': str(task_id)}
