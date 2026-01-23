# Genesis Employee Attendance System - Command Reference

Quick reference for common commands and operations.

## Installation & Setup

### Initial Setup
```bash
# Windows
install.bat

# Linux/Mac
chmod +x install.sh
./install.sh
```

### Environment Setup
```bash
# Copy environment template
cp env.example .env

# Edit environment variables
# Windows: notepad .env
# Linux/Mac: nano .env
```

### Database Setup
```bash
# Create database and enable PostGIS
psql -U postgres
CREATE DATABASE genesis_attendance_db;
\c genesis_attendance_db;
CREATE EXTENSION postgis;
\q
```

### Run Initial Setup
```bash
python setup.py
```

## Development Server

### Start Django Server
```bash
# Windows
run_dev.bat

# Linux/Mac
python manage.py runserver

# Custom port
python manage.py runserver 0.0.0.0:8080
```

### Start Celery Worker
```bash
# Windows
run_celery.bat

# Linux/Mac
celery -A config worker -l info
```

### Start Celery Beat
```bash
# Windows
run_celery_beat.bat

# Linux/Mac
celery -A config beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler
```

## Database Management

### Migrations
```bash
# Create migrations
python manage.py makemigrations

# Apply migrations
python manage.py migrate

# Show migrations
python manage.py showmigrations

# Migrate specific app
python manage.py migrate employees

# Roll back migration
python manage.py migrate employees 0001
```

### Database Shell
```bash
# Django ORM shell
python manage.py shell

# Database SQL shell
python manage.py dbshell
```

### Reset Database (CAUTION!)
```bash
# Drop all tables and recreate
python manage.py flush

# Reset migrations (dangerous - backup first!)
# Delete all migration files except __init__.py
# Then:
python manage.py makemigrations
python manage.py migrate
```

## User Management

### Create Superuser
```bash
python manage.py createsuperuser
```

### Create User Programmatically
```python
# In Django shell
python manage.py shell

from employees.models import Employee

employee = Employee.objects.create_user(
    username='john.doe',
    email='john@example.com',
    password='password123',
    employee_id='EMP002',
    first_name='John',
    last_name='Doe',
    department='IT',
    role='STAFF',
    designation='Developer'
)
```

### Change User Password
```bash
python manage.py changepassword admin
```

## Static Files

### Collect Static Files
```bash
python manage.py collectstatic

# Without confirmation prompt
python manage.py collectstatic --noinput
```

## Testing

### Run All Tests
```bash
# Django test runner
python manage.py test

# Verbose output
python manage.py test --verbosity=2

# Keep test database
python manage.py test --keepdb
```

### Run Specific Tests
```bash
# Test specific app
python manage.py test employees

# Test specific test case
python manage.py test employees.tests.EmployeeModelTest

# Test specific method
python manage.py test employees.tests.EmployeeModelTest.test_employee_creation
```

### With Pytest
```bash
# Run all tests
pytest

# Verbose
pytest -v

# Coverage report
pytest --cov=.

# Run specific file
pytest employees/tests.py
```

## Django Shell Commands

### Django Shell
```bash
python manage.py shell
```

### Common Shell Operations
```python
# Import models
from employees.models import Employee, Department
from tracking.models import LocationPoint, GeofenceZone
from attendance.models import AttendanceRecord, LeaveRequest

# Query examples
employees = Employee.objects.all()
it_dept = Employee.objects.filter(department='IT')
active_employees = Employee.objects.filter(is_active_employee=True)

# Create records
from django.contrib.gis.geos import Point
location = LocationPoint.objects.create(
    employee=employee,
    location=Point(-122.4194, 37.7749),
    accuracy=10.5
)

# Update records
employee = Employee.objects.get(employee_id='EMP001')
employee.designation = 'Senior Developer'
employee.save()

# Delete records
employee.delete()
```

## Celery Management

### Celery Inspect
```bash
# List registered tasks
celery -A config inspect registered

# Active tasks
celery -A config inspect active

# Scheduled tasks
celery -A config inspect scheduled

# Worker stats
celery -A config inspect stats

# List workers
celery -A config inspect active_queues
```

### Celery Control
```bash
# Purge all tasks
celery -A config purge

# Stop worker
celery -A config control shutdown
```

### Run Specific Task
```python
# In Django shell
from attendance.tasks import mark_absent_employees
result = mark_absent_employees.delay()
print(result.get())
```

## Docker Commands

### Docker Compose
```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f web

# Restart service
docker-compose restart web

# Rebuild images
docker-compose build

# Run command in container
docker-compose exec web python manage.py migrate
docker-compose exec web python manage.py createsuperuser
```

### Docker Management
```bash
# List containers
docker ps

# Stop container
docker stop container_id

# Remove container
docker rm container_id

# View logs
docker logs container_id

# Execute command in container
docker exec -it container_id bash
```

## Data Management

### Export Data
```bash
# Export all data
python manage.py dumpdata > backup.json

# Export specific app
python manage.py dumpdata employees > employees_backup.json

# Export specific model
python manage.py dumpdata employees.Employee > employees_only.json

# Pretty print
python manage.py dumpdata --indent=2 > backup.json
```

### Import Data
```bash
# Import data
python manage.py loaddata backup.json

# Import specific fixture
python manage.py loaddata employees_backup.json
```

### Create Fixtures
```bash
# Create initial data fixtures
python manage.py dumpdata employees.Department --indent=2 > employees/fixtures/departments.json
```

## Logs & Debugging

### View Logs
```bash
# Django logs
tail -f logs/django.log

# Celery logs (if logging to file)
tail -f logs/celery.log

# Docker logs
docker-compose logs -f web
```

### Enable Debug Toolbar
```bash
# Add to requirements.txt
django-debug-toolbar

# Install
pip install django-debug-toolbar

# Configure in settings.py
# See Django Debug Toolbar documentation
```

## API Testing

### cURL Examples

#### Get Token
```bash
curl -X POST http://localhost:8000/api/auth/token/ \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}'
```

#### Get Current User
```bash
curl -X GET http://localhost:8000/api/employees/me/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

#### Check In
```bash
curl -X POST http://localhost:8000/api/attendance/records/check_in/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 37.7749,
    "longitude": -122.4194,
    "is_remote": false
  }'
```

#### Submit Location
```bash
curl -X POST http://localhost:8000/api/tracking/locations/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy": 10.5
  }'
```

## Maintenance

### Clear Cache
```bash
# If using Django cache
python manage.py shell
>>> from django.core.cache import cache
>>> cache.clear()
```

### Check System
```bash
# Check for issues
python manage.py check

# Check deployment readiness
python manage.py check --deploy
```

### Database Optimization
```bash
# Vacuum database (PostgreSQL)
python manage.py dbshell
VACUUM ANALYZE;

# Show table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

## Production Deployment

### Prepare for Production
```bash
# Set environment variables
DEBUG=False
SECRET_KEY=new-random-secret-key
ALLOWED_HOSTS=yourdomain.com

# Collect static files
python manage.py collectstatic --noinput

# Run migrations
python manage.py migrate

# Create superuser
python manage.py createsuperuser

# Check deployment settings
python manage.py check --deploy
```

### Gunicorn (Production Server)
```bash
# Install
pip install gunicorn

# Run
gunicorn config.wsgi:application --bind 0.0.0.0:8000

# With workers
gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 4

# With systemd (create service file)
sudo systemctl start gunicorn
sudo systemctl enable gunicorn
```

## Useful Management Commands

### Create Custom Command
Create file: `employees/management/commands/import_employees.py`
```python
from django.core.management.base import BaseCommand

class Command(BaseCommand):
    help = 'Import employees from CSV'
    
    def handle(self, *args, **options):
        # Your code here
        self.stdout.write(self.style.SUCCESS('Successfully imported'))
```

Run:
```bash
python manage.py import_employees
```

## Quick Tips

### One-liner Commands
```bash
# Count all employees
python manage.py shell -c "from employees.models import Employee; print(Employee.objects.count())"

# Today's attendance
python manage.py shell -c "from attendance.models import AttendanceRecord; from datetime import date; print(AttendanceRecord.objects.filter(date=date.today()).count())"

# Active employees
python manage.py shell -c "from employees.models import Employee; print(Employee.objects.filter(is_active_employee=True).count())"
```

### Backup Strategy
```bash
# Database backup
pg_dump -U postgres genesis_attendance_db > backup_$(date +%Y%m%d).sql

# Media files backup
tar -czf media_backup_$(date +%Y%m%d).tar.gz media/

# Full backup
python manage.py dumpdata > data_backup_$(date +%Y%m%d).json
```

### Restore
```bash
# Restore database
psql -U postgres genesis_attendance_db < backup_20260123.sql

# Restore data
python manage.py loaddata data_backup_20260123.json
```

## Troubleshooting Commands

### Check Services
```bash
# Check PostgreSQL
pg_isready

# Check Redis
redis-cli ping

# Check port usage
netstat -an | grep 8000
```

### Reset Everything (Development Only!)
```bash
# Stop all services
docker-compose down -v  # If using Docker

# Drop database
dropdb -U postgres genesis_attendance_db

# Recreate database
createdb -U postgres genesis_attendance_db
psql -U postgres genesis_attendance_db -c "CREATE EXTENSION postgis;"

# Run migrations
python manage.py migrate

# Run setup
python setup.py
```

---

**Keep this file handy for quick reference during development!**
