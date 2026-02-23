"""
Celery tasks for tracking app - Automated attendance calculation
"""
from celery import shared_task
from django.utils import timezone
from django.db.models import Min, Max, Count
from datetime import datetime, timedelta, time
import logging

logger = logging.getLogger(__name__)


@shared_task(name='tracking.calculate_daily_attendance')
def calculate_daily_attendance():
    """
    Calculate daily attendance based on location logs
    
    Runs daily at 6:45 PM (18:45)
    
    For each employee:
    - Get all locations for today
    - Calculate first and last location times
    - Determine check-in and check-out times
    - Calculate total hours worked
    - Determine attendance status (Present/Late)
    - Create or update Attendance record
    
    Returns:
        dict: Summary of processed records
    """
    from employees.models import Employee
    from tracking.models import LocationLog
    from attendance.models import Attendance
    
    logger.info("Starting daily attendance calculation task...")
    
    # Get today's date
    today = timezone.now().date()
    
    # Get all active employees
    active_employees = Employee.objects.filter(is_active=True)
    
    processed = 0
    created = 0
    updated = 0
    skipped = 0
    
    for employee in active_employees:
        try:
            # Get all location logs for today
            locations = LocationLog.objects.filter(
                employee=employee,
                timestamp__date=today
            ).order_by('timestamp')
            
            if not locations.exists():
                logger.debug(f"No locations found for {employee.name} on {today}")
                skipped += 1
                continue
            
            # Get aggregated data
            location_stats = locations.aggregate(
                first_time=Min('timestamp'),
                last_time=Max('timestamp'),
                total_count=Count('id')
            )
            
            first_location_time = location_stats['first_time'].time()
            last_location_time = location_stats['last_time'].time()
            total_locations = location_stats['total_count']
            
            # Determine check-in time
            # If first location is before 9:45 AM, use it as check-in
            # Otherwise, use first location time
            cutoff_time = time(9, 45)  # 9:45 AM
            if first_location_time <= cutoff_time:
                check_in_time = first_location_time
            else:
                check_in_time = first_location_time
            
            # Check-out time is the last location time
            check_out_time = last_location_time
            
            # Calculate total hours
            check_in_datetime = datetime.combine(today, check_in_time)
            check_out_datetime = datetime.combine(today, check_out_time)
            
            # Handle case where check-out is past midnight
            if check_out_datetime < check_in_datetime:
                check_out_datetime += timedelta(days=1)
            
            duration = check_out_datetime - check_in_datetime
            total_hours = round(duration.total_seconds() / 3600, 2)
            
            # Determine status
            late_cutoff = time(9, 30)  # 9:30 AM
            if check_in_time > late_cutoff:
                status = 'LATE'
            else:
                status = 'PRESENT'
            
            # Create or update Attendance record
            attendance, is_created = Attendance.objects.update_or_create(
                employee=employee,
                date=today,
                defaults={
                    'first_location_time': first_location_time,
                    'last_location_time': last_location_time,
                    'check_in_time': check_in_time,
                    'check_out_time': check_out_time,
                    'total_hours': total_hours,
                    'total_locations_logged': total_locations,
                    'status': status,
                    'remarks': f'Auto-calculated from {total_locations} location logs'
                }
            )
            
            if is_created:
                created += 1
                logger.info(f"Created attendance for {employee.name}: {status}, {total_hours}h")
            else:
                updated += 1
                logger.info(f"Updated attendance for {employee.name}: {status}, {total_hours}h")
            
            processed += 1
            
        except Exception as e:
            logger.error(f"Error processing attendance for {employee.name}: {str(e)}")
            continue
    
    summary = {
        'date': str(today),
        'total_employees': active_employees.count(),
        'processed': processed,
        'created': created,
        'updated': updated,
        'skipped': skipped,
        'timestamp': timezone.now().isoformat()
    }
    
    logger.info(f"Daily attendance calculation completed: {summary}")
    
    return summary


@shared_task(name='tracking.send_location_reminder')
def send_location_reminder():
    """
    Send reminder to employees who haven't logged location recently
    
    Runs every hour during work hours (9:30 AM to 6:30 PM)
    
    Checks employees who haven't logged location in the last 30 minutes
    during work hours and sends them a reminder.
    
    Future enhancement: Integrate with push notification service
    
    Returns:
        dict: Summary of reminders sent
    """
    from employees.models import Employee
    from tracking.models import LocationLog
    
    logger.info("Starting location reminder task...")
    
    now = timezone.now()
    current_time = now.time()
    
    # Check if we're in work hours (9:30 AM to 6:30 PM)
    work_start = time(9, 30)
    work_end = time(18, 30)
    
    if not (work_start <= current_time <= work_end):
        logger.info(f"Outside work hours ({current_time}). Skipping reminder task.")
        return {
            'status': 'skipped',
            'reason': 'outside_work_hours',
            'current_time': str(current_time)
        }
    
    # Get cutoff time (30 minutes ago)
    cutoff_time = now - timedelta(minutes=30)
    
    # Get all active employees
    active_employees = Employee.objects.filter(is_active=True)
    
    reminders_needed = []
    
    for employee in active_employees:
        try:
            # Get latest location for this employee
            latest_location = LocationLog.objects.filter(
                employee=employee
            ).order_by('-timestamp').first()
            
            # Check if employee needs reminder
            if latest_location is None:
                # No location logged today at all
                reminders_needed.append({
                    'employee_id': str(employee.id),
                    'employee_name': employee.name,
                    'reason': 'no_location_logged_today',
                    'last_location': None
                })
                logger.info(f"Reminder needed for {employee.name}: No locations logged today")
                
            elif latest_location.timestamp < cutoff_time:
                # Last location is older than 30 minutes
                minutes_ago = int((now - latest_location.timestamp).total_seconds() / 60)
                reminders_needed.append({
                    'employee_id': str(employee.id),
                    'employee_name': employee.name,
                    'reason': 'location_outdated',
                    'last_location': latest_location.timestamp.isoformat(),
                    'minutes_ago': minutes_ago
                })
                logger.info(f"Reminder needed for {employee.name}: Last location {minutes_ago} minutes ago")
            
        except Exception as e:
            logger.error(f"Error checking location for {employee.name}: {str(e)}")
            continue
    
    # TODO: Integrate with push notification service
    # For now, just log the reminders
    if reminders_needed:
        logger.info(f"Would send reminders to {len(reminders_needed)} employees")
        # Future: Send push notifications here
        # send_push_notification(employee_tokens, message)
    
    summary = {
        'status': 'completed',
        'total_employees': active_employees.count(),
        'reminders_needed': len(reminders_needed),
        'employees': reminders_needed,
        'timestamp': now.isoformat()
    }
    
    logger.info(f"Location reminder task completed: {len(reminders_needed)} reminders needed")
    
    return summary


@shared_task(name='tracking.cleanup_old_locations')
def cleanup_old_locations():
    """
    Clean up old location logs to save storage space
    
    Runs weekly (every Sunday at 2 AM)
    
    Deletes location logs older than 90 days to keep database size manageable
    while retaining recent data for analysis and reporting.
    
    Returns:
        dict: Summary of cleanup operation
    """
    from tracking.models import LocationLog
    
    logger.info("Starting location cleanup task...")
    
    # Calculate cutoff date (90 days ago)
    cutoff_date = timezone.now() - timedelta(days=90)
    
    # Get count of old locations
    old_locations = LocationLog.objects.filter(timestamp__lt=cutoff_date)
    count_before = old_locations.count()
    
    if count_before == 0:
        logger.info("No old locations to delete")
        return {
            'status': 'completed',
            'deleted_count': 0,
            'cutoff_date': cutoff_date.isoformat(),
            'message': 'No old locations found',
            'timestamp': timezone.now().isoformat()
        }
    
    logger.info(f"Found {count_before} location logs older than {cutoff_date.date()}")
    
    # Delete old locations
    try:
        deleted_count, _ = old_locations.delete()
        
        summary = {
            'status': 'completed',
            'deleted_count': deleted_count,
            'cutoff_date': cutoff_date.isoformat(),
            'retention_days': 90,
            'timestamp': timezone.now().isoformat()
        }
        
        logger.info(f"Successfully deleted {deleted_count} old location logs")
        
        return summary
        
    except Exception as e:
        logger.error(f"Error deleting old locations: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': timezone.now().isoformat()
        }


@shared_task(name='tracking.send_duty_reminder_notification')
def send_duty_reminder_notification(message_type):
    """
    Send duty reminder push notification to all active employees via FCM.
    message_type: 'early' (9:00) or 'late' (9:28).
    Runs at 9:00 and 9:28 Asia/Dhaka, Mon-Thu and Sat-Sun (Friday excluded by Celery Beat).
    """
    from employees.models import Employee, DeviceToken
    from django.conf import settings
    import os

    MESSAGES = {
        'early': {
            'title': 'Genesis',
            'body': 'Your duty starts at 9:30 AM. Please be on time.',
        },
        'late': {
            'title': 'Genesis',
            'body': 'Duty starts at 9:30 AM. Be ready.',
        },
    }
    if message_type not in MESSAGES:
        logger.warning(f"send_duty_reminder_notification: invalid message_type={message_type}")
        return {'status': 'error', 'message': 'Invalid message_type'}

    payload = MESSAGES[message_type]
    logger.info(f"Starting duty reminder push (message_type={message_type})...")

    active_employee_ids = list(
        Employee.objects.filter(is_active=True).values_list('id', flat=True)
    )
    tokens_qs = DeviceToken.objects.filter(employee_id__in=active_employee_ids)
    tokens = list(tokens_qs.values_list('fcm_token', flat=True))

    if not tokens:
        logger.info("No FCM tokens registered. Skipping duty reminder push.")
        return {
            'status': 'completed',
            'message_type': message_type,
            'tokens_sent': 0,
            'timestamp': timezone.now().isoformat(),
        }

    cred_path = getattr(
        settings,
        'FIREBASE_CREDENTIALS_PATH',
        os.environ.get('GOOGLE_APPLICATION_CREDENTIALS'),
    )
    if not cred_path or not os.path.isfile(cred_path):
        logger.error("Firebase credentials not found. Set FIREBASE_CREDENTIALS_PATH or GOOGLE_APPLICATION_CREDENTIALS.")
        return {
            'status': 'error',
            'message': 'Firebase credentials not configured',
            'timestamp': timezone.now().isoformat(),
        }

    try:
        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)

        sent = 0
        invalid_tokens = []

        for token in tokens:
            try:
                msg = messaging.Message(
                    notification=messaging.Notification(
                        title=payload['title'],
                        body=payload['body'],
                    ),
                    android=messaging.AndroidConfig(
                        priority='high',
                        notification=messaging.AndroidNotification(
                            channel_id='duty_reminder',
                            title=payload['title'],
                            body=payload['body'],
                            priority='high',
                        ),
                    ),
                    token=token,
                )
                messaging.send(msg)
                sent += 1
            except messaging.UnregisteredError:
                invalid_tokens.append(token)
            except messaging.InvalidArgumentError:
                invalid_tokens.append(token)
            except Exception as e:
                logger.warning(f"FCM send failed for token {token[:20]}...: {e}")
                if 'not-registered' in str(e).lower() or 'invalid' in str(e).lower():
                    invalid_tokens.append(token)

        if invalid_tokens:
            DeviceToken.objects.filter(fcm_token__in=invalid_tokens).delete()
            logger.info(f"Removed {len(invalid_tokens)} invalid FCM tokens")

        summary = {
            'status': 'completed',
            'message_type': message_type,
            'tokens_sent': sent,
            'tokens_invalid_removed': len(invalid_tokens),
            'timestamp': timezone.now().isoformat(),
        }
        logger.info(f"Duty reminder push completed: {summary}")
        return summary

    except Exception as e:
        logger.exception(f"Duty reminder push failed: {e}")
        return {
            'status': 'error',
            'message_type': message_type,
            'error': str(e),
            'timestamp': timezone.now().isoformat(),
        }


@shared_task(name='tracking.test_task')
def test_task():
    """
    Simple test task to verify Celery is working
    
    Returns:
        dict: Test result
    """
    logger.info("Test task executed successfully!")
    
    return {
        'status': 'success',
        'message': 'Celery is working correctly',
        'timestamp': timezone.now().isoformat()
    }
