"""FCM helpers for TO-DO assignment push notifications."""
import logging
import os

from django.conf import settings
from django.utils import timezone

logger = logging.getLogger(__name__)

TODO_ASSIGNED_CHANNEL_ID = 'duty_reminder'  # reuse existing app channel so older APKs still show
_BODY_MAX_LEN = 80


def _snippet(text, max_len=_BODY_MAX_LEN):
    text = (text or '').strip()
    if len(text) <= max_len:
        return text
    return text[: max_len - 1].rstrip() + '…'


def send_todo_assigned_push(task):
    """
    Send FCM to the assignee's registered devices for a team-assigned task.
    Returns a summary dict. Never raises to callers that wrap it.
    """
    from employees.models import DeviceToken
    from config.circuit_breakers import with_circuit

    assignee = task.employee
    if not assignee or not assignee.is_active:
        return {'status': 'skipped', 'reason': 'inactive_or_missing_assignee'}

    assigner_id = task.assigned_by_id
    if assigner_id and assigner_id == assignee.id:
        return {'status': 'skipped', 'reason': 'self_assign'}

    if not task.assigned_by_id and not task.assigned_by_username:
        return {'status': 'skipped', 'reason': 'not_an_assignment'}

    tokens = list(
        DeviceToken.objects.filter(employee=assignee).values_list('fcm_token', flat=True)
    )
    if not tokens:
        logger.info(
            'send_todo_assigned_push: no FCM tokens for employee_id=%s task_id=%s',
            assignee.id,
            task.id,
        )
        return {
            'status': 'completed',
            'tokens_sent': 0,
            'task_id': str(task.id),
            'timestamp': timezone.now().isoformat(),
        }

    assigner_label = task.assigner_display or 'Someone'
    title = 'New task assigned'
    body = f'{assigner_label} assigned: {_snippet(task.description)}'
    task_id_str = str(task.id)

    cred_path = getattr(
        settings,
        'FIREBASE_CREDENTIALS_PATH',
        os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'),
    )
    if not cred_path or not os.path.isfile(cred_path):
        logger.error(
            'send_todo_assigned_push: Firebase credentials not found. '
            'Set FIREBASE_CREDENTIALS_PATH or GOOGLE_APPLICATION_CREDENTIALS.'
        )
        return {
            'status': 'error',
            'message': 'Firebase credentials not configured',
            'task_id': task_id_str,
            'timestamp': timezone.now().isoformat(),
        }

    try:
        import firebase_admin
        from firebase_admin import credentials, messaging

        def _send_all():
            if not firebase_admin._apps:
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)

            sent = 0
            invalid_tokens = []

            for token in tokens:
                try:
                    msg = messaging.Message(
                        notification=messaging.Notification(
                            title=title,
                            body=body,
                        ),
                        data={
                            'type': 'todo_assigned',
                            'task_id': task_id_str,
                        },
                        android=messaging.AndroidConfig(
                            priority='high',
                            notification=messaging.AndroidNotification(
                                channel_id=TODO_ASSIGNED_CHANNEL_ID,
                                title=title,
                                body=body,
                                priority='high',
                            ),
                        ),
                        token=token,
                    )
                    messaging.send(msg)
                    sent += 1
                except messaging.UnregisteredError:
                    invalid_tokens.append(token)
                except Exception as e:
                    logger.warning(
                        'send_todo_assigned_push: FCM send failed for token %s...: %s',
                        token[:20],
                        e,
                    )
                    err = str(e).lower()
                    if (
                        'not-registered' in err
                        or 'unregistered' in err
                        or 'invalid-argument' in err
                        or 'registration-token-not-registered' in err
                    ):
                        invalid_tokens.append(token)

            if invalid_tokens:
                DeviceToken.objects.filter(fcm_token__in=invalid_tokens).delete()
                logger.info(
                    'send_todo_assigned_push: removed %s invalid FCM tokens',
                    len(invalid_tokens),
                )

            return sent, len(invalid_tokens)

        try:
            sent, invalid_count = with_circuit('fcm', _send_all)
        except RuntimeError as e:
            if str(e) == 'circuit_open':
                logger.warning('send_todo_assigned_push: FCM circuit open, skipping')
                return {
                    'status': 'skipped',
                    'reason': 'fcm_circuit_open',
                    'task_id': task_id_str,
                    'timestamp': timezone.now().isoformat(),
                }
            raise

        summary = {
            'status': 'completed',
            'task_id': task_id_str,
            'tokens_sent': sent,
            'tokens_invalid_removed': invalid_count,
            'timestamp': timezone.now().isoformat(),
        }
        logger.info('send_todo_assigned_push completed: %s', summary)
        return summary

    except Exception as e:
        logger.exception('send_todo_assigned_push failed: %s', e)
        return {
            'status': 'error',
            'message': str(e),
            'task_id': task_id_str,
            'timestamp': timezone.now().isoformat(),
        }
