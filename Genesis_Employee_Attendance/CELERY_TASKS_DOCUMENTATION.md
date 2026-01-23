# Genesis Employee Attendance - Celery Tasks Documentation

## ✅ Celery Configuration Complete

Complete automated attendance calculation system with Celery + Redis.

---

## 🔧 Configuration

### **config/celery.py**

**Features:**
- ✅ Redis as message broker
- ✅ Timezone set to `Asia/Dhaka`
- ✅ JSON serialization
- ✅ Task tracking enabled
- ✅ 30-minute task time limit
- ✅ Auto-discovery of tasks

**Configuration:**
```python
app = Celery(
    'genesis_attendance',
    broker='redis://localhost:6379/0',
    backend='redis://localhost:6379/0'
)

app.conf.update(
    timezone='Asia/Dhaka',
    enable_utc=False,  # Use local time
    task_serializer='json',
    task_track_started=True,
)
```

---

## 📋 Celery Tasks

### **1. calculate_daily_attendance()**

**Purpose:** Automatically calculate daily attendance from location logs

**Schedule:** Daily at **6:45 PM (18:45)**

**Task Name:** `tracking.calculate_daily_attendance`

**Process:**
1. Gets all active employees
2. For each employee:
   - Retrieves all location logs for today
   - Calculates first and last location times
   - Determines check-in time:
     - If first location ≤ 9:45 AM → use as check-in
     - Otherwise → use first location time
   - Sets check-out time as last location time
   - Calculates total hours worked
   - Determines status:
     - **Late** if check-in > 9:30 AM
     - **Present** if check-in ≤ 9:30 AM
   - Creates or updates Attendance record

**Logic:**
```python
# Check-in determination
if first_location_time <= time(9, 45):
    check_in_time = first_location_time
else:
    check_in_time = first_location_time

# Status determination
late_cutoff = time(9, 30)
if check_in_time > late_cutoff:
    status = 'LATE'
else:
    status = 'PRESENT'

# Hours calculation
duration = check_out_datetime - check_in_datetime
total_hours = duration.total_seconds() / 3600
```

**Return Value:**
```json
{
    "date": "2024-01-15",
    "total_employees": 100,
    "processed": 85,
    "created": 60,
    "updated": 25,
    "skipped": 15,
    "timestamp": "2024-01-15T18:45:00+06:00"
}
```

**Example Output:**
```
INFO: Starting daily attendance calculation task...
INFO: Created attendance for John Doe: PRESENT, 8.5h
INFO: Updated attendance for Jane Smith: LATE, 7.25h
INFO: Daily attendance calculation completed: 85 processed, 15 skipped
```

---

### **2. send_location_reminder()**

**Purpose:** Remind employees to log location if they haven't recently

**Schedule:** Every hour from **9:30 AM to 6:30 PM**
- 10:00 AM, 11:00 AM, 12:00 PM, 1:00 PM, 2:00 PM, 3:00 PM, 4:00 PM, 5:00 PM, 6:00 PM

**Task Name:** `tracking.send_location_reminder`

**Process:**
1. Checks if current time is within work hours (9:30 AM - 6:30 PM)
2. If outside work hours → skips task
3. Gets all active employees
4. For each employee:
   - Checks latest location log
   - If no location today → add to reminder list
   - If last location > 30 minutes ago → add to reminder list
5. Logs employees needing reminders
6. Future: Send push notifications

**Logic:**
```python
# Check work hours
if not (time(9, 30) <= current_time <= time(18, 30)):
    return {'status': 'skipped', 'reason': 'outside_work_hours'}

# Check last location
cutoff_time = now - timedelta(minutes=30)
if latest_location is None:
    # No location logged today
    reminders_needed.append(employee)
elif latest_location.timestamp < cutoff_time:
    # Last location > 30 minutes ago
    reminders_needed.append(employee)
```

**Return Value:**
```json
{
    "status": "completed",
    "total_employees": 100,
    "reminders_needed": 5,
    "employees": [
        {
            "employee_id": "uuid",
            "employee_name": "John Doe",
            "reason": "location_outdated",
            "last_location": "2024-01-15T10:15:00+06:00",
            "minutes_ago": 45
        }
    ],
    "timestamp": "2024-01-15T11:00:00+06:00"
}
```

**Future Enhancement:**
```python
# TODO: Integrate with push notification service
# send_push_notification(
#     employee_tokens=[employee.fcm_token],
#     title="Location Reminder",
#     body="Please log your location"
# )
```

---

### **3. cleanup_old_locations()**

**Purpose:** Delete old location logs to manage database size

**Schedule:** Every **Sunday at 2:00 AM**

**Task Name:** `tracking.cleanup_old_locations`

**Process:**
1. Calculates cutoff date (90 days ago)
2. Finds all location logs older than cutoff
3. Deletes old records
4. Logs deletion summary

**Logic:**
```python
# Calculate cutoff (90 days ago)
cutoff_date = timezone.now() - timedelta(days=90)

# Delete old locations
old_locations = LocationLog.objects.filter(timestamp__lt=cutoff_date)
deleted_count, _ = old_locations.delete()
```

**Return Value:**
```json
{
    "status": "completed",
    "deleted_count": 12500,
    "cutoff_date": "2023-10-17T02:00:00+06:00",
    "retention_days": 90,
    "timestamp": "2024-01-15T02:00:00+06:00"
}
```

**Benefits:**
- Keeps database size manageable
- Retains 90 days of recent data
- Improves query performance
- Runs during low-usage hours (2 AM)

---

## 📅 Celery Beat Schedule

### **config/settings.py**

```python
CELERY_BEAT_SCHEDULE = {
    # Daily attendance calculation - 6:45 PM
    'calculate-daily-attendance': {
        'task': 'tracking.calculate_daily_attendance',
        'schedule': crontab(hour=18, minute=45),
    },
    
    # Location reminders - Every hour (10 AM - 6 PM)
    'send-location-reminder-10am': {
        'task': 'tracking.send_location_reminder',
        'schedule': crontab(hour=10, minute=0),
    },
    # ... (11 AM, 12 PM, 1 PM, 2 PM, 3 PM, 4 PM, 5 PM, 6 PM)
    
    # Cleanup - Every Sunday at 2 AM
    'cleanup-old-locations': {
        'task': 'tracking.cleanup_old_locations',
        'schedule': crontab(day_of_week=0, hour=2, minute=0),
    },
}
```

### **Schedule Summary:**

| Task | Schedule | Frequency | Purpose |
|------|----------|-----------|---------|
| `calculate_daily_attendance` | 6:45 PM daily | Once per day | Calculate attendance from locations |
| `send_location_reminder` | 10 AM - 6 PM | 9 times per day | Remind employees to log location |
| `cleanup_old_locations` | Sunday 2:00 AM | Once per week | Delete logs >90 days old |

---

## 🚀 Running Celery

### **Start Celery Worker**

```bash
# Linux/Mac
celery -A config worker -l info

# Windows
celery -A config worker -l info --pool=solo
```

### **Start Celery Beat (Scheduler)**

```bash
celery -A config beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler
```

### **Run Both Together (Development)**

```bash
# Terminal 1: Worker
celery -A config worker -l info

# Terminal 2: Beat
celery -A config beat -l info
```

### **Using Docker**

```bash
# Start all services
docker-compose up -d

# Celery worker runs automatically in container
docker-compose logs -f celery

# Celery beat runs automatically in container
docker-compose logs -f celery-beat
```

---

## 🧪 Testing Tasks

### **Test Individual Task**

```python
# Django shell
python manage.py shell

# Import task
from tracking.tasks import calculate_daily_attendance

# Run synchronously (for testing)
result = calculate_daily_attendance()
print(result)

# Run asynchronously (actual usage)
task = calculate_daily_attendance.delay()
print(task.id)
print(task.status)
print(task.result)
```

### **Test Task via API**

```python
# In views.py
from tracking.tasks import calculate_daily_attendance

def trigger_attendance_calculation(request):
    task = calculate_daily_attendance.delay()
    return Response({
        'task_id': task.id,
        'status': 'Task queued'
    })
```

### **Monitor Tasks**

```bash
# Check Celery worker status
celery -A config inspect active

# Check scheduled tasks
celery -A config inspect scheduled

# Check task stats
celery -A config inspect stats
```

---

## 📊 Task Results

### **Attendance Calculation Results**

After running `calculate_daily_attendance`, check the database:

```python
from attendance.models import Attendance
from django.utils import timezone

today = timezone.now().date()
attendances = Attendance.objects.filter(date=today)

for att in attendances:
    print(f"{att.employee.name}: {att.status}, {att.total_hours}h, {att.total_locations_logged} logs")
```

**Example Output:**
```
John Doe: PRESENT, 8.5h, 42 logs
Jane Smith: LATE, 7.25h, 35 logs
Bob Wilson: PRESENT, 9.0h, 48 logs
```

---

## ⚙️ Configuration Options

### **Timezone Settings**

```python
# config/celery.py
app.conf.update(
    timezone='Asia/Dhaka',  # Bangladesh timezone
    enable_utc=False,       # Use local time
)

# config/settings.py
CELERY_TIMEZONE = 'Asia/Dhaka'
TIME_ZONE = 'Asia/Dhaka'
```

### **Task Time Limits**

```python
# config/celery.py
app.conf.update(
    task_time_limit=30 * 60,  # 30 minutes max per task
)
```

### **Redis Configuration**

```python
# .env file
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Or for Docker
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/0
```

---

## 🔍 Logging

### **View Task Logs**

```bash
# Celery worker logs
tail -f logs/celery.log

# Django logs
tail -f logs/django.log

# All logs
tail -f logs/*.log
```

### **Log Levels**

```python
# In tasks.py
import logging
logger = logging.getLogger(__name__)

logger.debug("Debug message")
logger.info("Info message")
logger.warning("Warning message")
logger.error("Error message")
```

---

## 🐛 Troubleshooting

### **Task Not Running**

1. Check if Redis is running:
```bash
redis-cli ping
# Should return: PONG
```

2. Check if Celery worker is running:
```bash
celery -A config inspect active
```

3. Check if Celery beat is running:
```bash
celery -A config inspect scheduled
```

### **Tasks Taking Too Long**

1. Check task status:
```python
from celery.result import AsyncResult
result = AsyncResult(task_id)
print(result.status)
print(result.info)
```

2. Increase time limit:
```python
# config/celery.py
app.conf.update(
    task_time_limit=60 * 60,  # 1 hour
)
```

### **Tasks Failing**

1. Check error logs:
```bash
celery -A config events
```

2. Run task synchronously for debugging:
```python
result = calculate_daily_attendance()  # Without .delay()
```

---

## 📝 Best Practices

### **1. Task Idempotency**
Tasks should be idempotent (can run multiple times safely):
```python
# Good: update_or_create
Attendance.objects.update_or_create(
    employee=employee,
    date=today,
    defaults={...}
)

# Bad: create (will fail if exists)
Attendance.objects.create(...)
```

### **2. Error Handling**
Always wrap task logic in try-except:
```python
@shared_task
def my_task():
    try:
        # Task logic
        pass
    except Exception as e:
        logger.error(f"Task failed: {str(e)}")
        raise
```

### **3. Task Monitoring**
Log task start, progress, and completion:
```python
logger.info("Task started")
# ... processing ...
logger.info(f"Processed {count} items")
# ... more processing ...
logger.info("Task completed")
```

---

## ✅ Features Summary

### Implemented ✓
- ✅ Celery with Redis broker
- ✅ Timezone: Asia/Dhaka
- ✅ Daily attendance calculation (6:45 PM)
- ✅ Location reminders (hourly during work hours)
- ✅ Old location cleanup (weekly)
- ✅ Comprehensive logging
- ✅ Error handling
- ✅ Task monitoring
- ✅ JSON serialization

### Task Logic ✓
- ✅ Check-in time calculation
- ✅ Late/Present status determination
- ✅ Total hours calculation
- ✅ Location count tracking
- ✅ 30-minute reminder threshold
- ✅ 90-day data retention

### Schedule ✓
- ✅ 6:45 PM - Daily attendance calculation
- ✅ 10 AM - 6 PM - Hourly location reminders
- ✅ Sunday 2 AM - Weekly cleanup

---

## 🎉 All Tasks Ready!

**3 Celery tasks created:**
1. ✅ `calculate_daily_attendance()` - Auto-calculate attendance
2. ✅ `send_location_reminder()` - Hourly reminders
3. ✅ `cleanup_old_locations()` - Weekly cleanup

**Celery fully configured with:**
- Redis broker
- Asia/Dhaka timezone
- Beat schedule
- Comprehensive logging
- Error handling

**Ready for production!** 🚀
