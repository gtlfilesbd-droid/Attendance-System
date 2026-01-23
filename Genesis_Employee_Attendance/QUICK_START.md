# Genesis Employee Attendance System - Quick Start Guide

## Prerequisites

- Python 3.11+
- PostgreSQL 14+ with PostGIS extension
- Redis (for Celery)
- pip (Python package manager)

## Installation

### 1. Clone or Navigate to Project
```bash
cd Genesis_Employee_Attendance
```

### 2. Create Virtual Environment
```bash
# Windows
python -m venv venv
venv\Scripts\activate

# Linux/Mac
python3 -m venv venv
source venv/bin/activate
```

### 3. Install Dependencies
```bash
pip install -r requirements.txt
```

### 4. Setup PostgreSQL with PostGIS

#### Install PostgreSQL with PostGIS
```bash
# Ubuntu/Debian
sudo apt-get install postgresql postgresql-contrib postgis

# macOS (using Homebrew)
brew install postgresql postgis

# Windows: Download installer from postgresql.org
```

#### Create Database
```sql
-- Connect to PostgreSQL
psql -U postgres

-- Create database
CREATE DATABASE genesis_attendance_db;

-- Connect to the database
\c genesis_attendance_db;

-- Enable PostGIS extension
CREATE EXTENSION postgis;

-- Exit
\q
```

### 5. Configure Environment Variables
```bash
# Copy example environment file
cp env.example .env

# Edit .env file with your settings
```

Example `.env` file:
```env
SECRET_KEY=your-very-secret-key-change-this
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1

DB_NAME=genesis_attendance_db
DB_USER=postgres
DB_PASSWORD=your-postgres-password
DB_HOST=localhost
DB_PORT=5432

CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

JWT_ACCESS_TOKEN_LIFETIME=60
JWT_REFRESH_TOKEN_LIFETIME=1440

CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
```

### 6. Run Setup Script
```bash
python setup.py
```

This will:
- Run database migrations
- Create a superuser (admin/admin123)
- Create default departments
- Create default work shifts
- Collect static files

### 7. Start Development Server
```bash
python manage.py runserver
```

The server will start at http://localhost:8000

### 8. Start Celery Worker (in a new terminal)
```bash
# Activate virtual environment first
# Windows
venv\Scripts\activate

# Linux/Mac
source venv/bin/activate

# Start Celery worker
celery -A config worker -l info
```

### 9. Start Celery Beat (in another terminal)
```bash
# Activate virtual environment first
celery -A config beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler
```

## Docker Setup (Alternative)

If you prefer using Docker:

### 1. Install Docker and Docker Compose
- Docker: https://docs.docker.com/get-docker/
- Docker Compose: https://docs.docker.com/compose/install/

### 2. Create .env file
```bash
cp env.example .env
# Edit .env with your settings
```

### 3. Start Services
```bash
docker-compose up -d
```

This will start:
- PostgreSQL with PostGIS
- Redis
- Django application
- Celery worker
- Celery beat

### 4. Run Migrations
```bash
docker-compose exec web python manage.py migrate
```

### 5. Create Superuser
```bash
docker-compose exec web python manage.py createsuperuser
```

### 6. Access Application
- Web: http://localhost:8000
- Admin: http://localhost:8000/admin

## Access the Application

### Admin Panel
- URL: http://localhost:8000/admin
- Username: admin
- Password: admin123

**Important:** Change the default password immediately!

### API Endpoints
- Base URL: http://localhost:8000/api/
- Authentication: http://localhost:8000/api/auth/token/
- Employees: http://localhost:8000/api/employees/
- Tracking: http://localhost:8000/api/tracking/
- Attendance: http://localhost:8000/api/attendance/

## Testing the API

### 1. Get JWT Token
```bash
curl -X POST http://localhost:8000/api/auth/token/ \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}'
```

Response:
```json
{
  "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "access": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

### 2. Use Token in Requests
```bash
curl -X GET http://localhost:8000/api/employees/me/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### 3. Check-In
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

## Common Tasks

### Create New Employee
```bash
python manage.py shell
```

```python
from employees.models import Employee

employee = Employee.objects.create_user(
    username='jane.doe',
    email='jane.doe@genesis.com',
    password='password123',
    employee_id='EMP003',
    first_name='Jane',
    last_name='Doe',
    department='HR',
    role='STAFF',
    designation='HR Manager'
)
```

### Create Geofence Zone
```python
from tracking.models import GeofenceZone
from django.contrib.gis.geos import Point

zone = GeofenceZone.objects.create(
    name='Main Office',
    zone_type='OFFICE',
    center_point=Point(-122.4194, 37.7749),
    radius=100,
    is_active=True,
    requires_checkin=True
)
```

### View Celery Tasks
```bash
# List registered tasks
celery -A config inspect registered

# Check active tasks
celery -A config inspect active

# Check scheduled tasks
celery -A config inspect scheduled
```

## Troubleshooting

### PostgreSQL Connection Error
- Ensure PostgreSQL is running
- Check database credentials in .env
- Verify PostGIS extension is installed

### Redis Connection Error
- Ensure Redis is running
- Check CELERY_BROKER_URL in .env
- Start Redis: `redis-server` or `sudo service redis-server start`

### Import Errors
- Ensure virtual environment is activated
- Reinstall requirements: `pip install -r requirements.txt`

### Migration Issues
```bash
# Reset migrations (CAUTION: This will delete all data)
python manage.py migrate --fake-initial
python manage.py migrate
```

## Next Steps

1. **Configure Settings**: Review and update `config/settings.py`
2. **Setup Email**: Configure email settings for notifications
3. **Create Departments**: Add your organization's departments
4. **Add Employees**: Create employee accounts
5. **Setup Geofences**: Define office locations and work sites
6. **Configure Work Shifts**: Set up work shift schedules
7. **Test Mobile Integration**: Test API with your mobile app
8. **Setup Monitoring**: Configure logging and monitoring

## Production Deployment

For production deployment:

1. Set `DEBUG=False` in `.env`
2. Generate a new `SECRET_KEY`
3. Configure `ALLOWED_HOSTS`
4. Setup HTTPS/SSL
5. Use a production WSGI server (Gunicorn)
6. Configure a reverse proxy (Nginx)
7. Setup database backups
8. Configure email service
9. Enable security features
10. Setup monitoring and logging

See `DEPLOYMENT.md` for detailed production deployment guide.

## Support

For issues and questions:
- Check documentation: `README.md` and `API_DOCUMENTATION.md`
- Review logs: `logs/django.log`
- Check Django admin for data verification

## License

MIT License - See LICENSE file for details
