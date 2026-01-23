# Genesis Employee Attendance System - Project Structure

```
Genesis_Employee_Attendance/
│
├── config/                          # Main project configuration
│   ├── __init__.py                 # Celery app initialization
│   ├── settings.py                 # Django settings
│   ├── urls.py                     # Main URL configuration
│   ├── wsgi.py                     # WSGI configuration
│   ├── asgi.py                     # ASGI configuration
│   ├── celery.py                   # Celery configuration
│   └── settings_celery_beat.py     # Celery Beat schedule
│
├── employees/                       # Employee management app
│   ├── __init__.py
│   ├── admin.py                    # Admin interface configuration
│   ├── apps.py                     # App configuration
│   ├── models.py                   # Employee, Department, WorkShift, EmployeeShift
│   ├── serializers.py              # DRF serializers
│   ├── views.py                    # API viewsets
│   ├── urls.py                     # URL routes
│   ├── tests.py                    # Unit tests
│   └── migrations/                 # Database migrations
│
├── tracking/                        # Location tracking app
│   ├── __init__.py
│   ├── admin.py                    # Admin interface configuration
│   ├── apps.py                     # App configuration
│   ├── models.py                   # LocationPoint, GeofenceZone, GeofenceEvent, Route, EmployeeMovement
│   ├── serializers.py              # DRF serializers with GeoJSON support
│   ├── views.py                    # API viewsets with geospatial queries
│   ├── urls.py                     # URL routes
│   ├── tasks.py                    # Celery tasks for geofencing, route generation
│   ├── tests.py                    # Unit tests
│   └── migrations/                 # Database migrations
│
├── attendance/                      # Attendance management app
│   ├── __init__.py
│   ├── admin.py                    # Admin interface configuration
│   ├── apps.py                     # App configuration
│   ├── models.py                   # AttendanceRecord, LeaveRequest, LeaveBalance, Holiday, WorkSession, AttendanceAlert
│   ├── serializers.py              # DRF serializers
│   ├── views.py                    # API viewsets for check-in/out, leave management
│   ├── urls.py                     # URL routes
│   ├── tasks.py                    # Celery tasks for auto-absence, reminders, reports
│   ├── tests.py                    # Unit tests
│   └── migrations/                 # Database migrations
│
├── static/                          # Static files (CSS, JS, images)
│   └── .gitkeep
│
├── media/                           # User-uploaded files
│   └── .gitkeep
│
├── logs/                            # Application logs
│   └── .gitkeep
│
├── templates/                       # Django templates
│   └── .gitkeep
│
├── manage.py                        # Django management script
├── setup.py                         # Setup and initialization script
├── requirements.txt                 # Python dependencies
│
├── Dockerfile                       # Docker image definition
├── docker-compose.yml               # Docker services orchestration
│
├── .gitignore                       # Git ignore rules
├── env.example                      # Environment variables template
│
├── README.md                        # Project overview and documentation
├── QUICK_START.md                   # Quick start guide
├── API_DOCUMENTATION.md             # API endpoints documentation
├── PROJECT_STRUCTURE.md             # This file - project structure
├── LICENSE                          # MIT License
│
├── install.bat                      # Windows installation script
├── install.sh                       # Linux/Mac installation script
│
└── pytest.ini                       # Pytest configuration

```

## Core Components

### 1. Employee Management (`employees/`)
- **Employee Model**: Extended Django User model with employee-specific fields
- **Department Model**: Organizational departments
- **WorkShift Model**: Different work shift definitions
- **EmployeeShift Model**: Shift assignments to employees
- **Features**:
  - User authentication and authorization
  - Employee profile management
  - Department hierarchy
  - Shift scheduling

### 2. Location Tracking (`tracking/`)
- **LocationPoint Model**: GPS coordinates with PostGIS support
- **GeofenceZone Model**: Geographic boundaries (office, sites)
- **GeofenceEvent Model**: Entry/exit events
- **Route Model**: Employee movement paths
- **EmployeeMovement Model**: Daily movement summaries
- **Features**:
  - Real-time location tracking
  - Geofence monitoring
  - Route visualization
  - Movement analytics

### 3. Attendance Management (`attendance/`)
- **AttendanceRecord Model**: Daily check-in/out records
- **LeaveRequest Model**: Leave applications
- **LeaveBalance Model**: Leave quota tracking
- **Holiday Model**: Company holidays
- **WorkSession Model**: Break and session tracking
- **AttendanceAlert Model**: Attendance violations
- **Features**:
  - Check-in/check-out with location
  - Leave management workflow
  - Automatic absence marking
  - Overtime calculation
  - Alert system

## Database Schema

### Key Models and Relationships

```
Employee (Custom User)
├── AttendanceRecord (1:N)
├── LeaveRequest (1:N)
├── LeaveBalance (1:N)
├── LocationPoint (1:N)
├── GeofenceEvent (1:N)
├── Route (1:N)
├── EmployeeMovement (1:N)
├── WorkSession (1:N via AttendanceRecord)
├── AttendanceAlert (1:N)
└── EmployeeShift (1:N)

Department
├── Employee (1:N)
└── GeofenceZone (optional head reference)

WorkShift
└── EmployeeShift (1:N)

GeofenceZone
├── AttendanceRecord (1:N for check-in/out zones)
└── GeofenceEvent (1:N)
```

## API Structure

### Authentication Endpoints
- `/api/auth/token/` - Obtain JWT token
- `/api/auth/token/refresh/` - Refresh JWT token
- `/api/auth/token/verify/` - Verify JWT token

### Employee Endpoints
- `/api/employees/` - Employee CRUD
- `/api/employees/me/` - Current user profile
- `/api/employees/departments/` - Department management
- `/api/employees/shifts/` - Work shift management
- `/api/employees/employee-shifts/` - Shift assignments

### Tracking Endpoints
- `/api/tracking/locations/` - Location points
- `/api/tracking/geofence-zones/` - Geofence zones
- `/api/tracking/geofence-events/` - Entry/exit events
- `/api/tracking/routes/` - Employee routes
- `/api/tracking/movements/` - Movement summaries

### Attendance Endpoints
- `/api/attendance/records/` - Attendance records
- `/api/attendance/records/check_in/` - Check-in action
- `/api/attendance/records/check_out/` - Check-out action
- `/api/attendance/leaves/` - Leave requests
- `/api/attendance/leave-balances/` - Leave balances
- `/api/attendance/holidays/` - Company holidays
- `/api/attendance/work-sessions/` - Work sessions
- `/api/attendance/alerts/` - Attendance alerts

## Celery Tasks

### Attendance Tasks (`attendance/tasks.py`)
- `mark_absent_employees` - Auto-mark absent employees (11:59 PM daily)
- `check_late_arrivals` - Check for late arrivals (hourly)
- `calculate_daily_hours` - Calculate work hours (1:00 AM daily)
- `send_attendance_reminders` - Send check-in reminders (10:00 AM daily)
- `generate_attendance_reports` - Monthly reports (1st day of month)

### Tracking Tasks (`tracking/tasks.py`)
- `process_geofence_events` - Process geofence entries/exits (every 10 min)
- `calculate_employee_movements` - Daily movement summaries (2:00 AM daily)
- `generate_daily_routes` - Generate route paths (3:00 AM daily)
- `cleanup_old_location_points` - Archive old data (weekly)
- `detect_location_anomalies` - Detect mock locations (every 30 min)

## Technology Stack

### Backend
- **Django 4.2**: Web framework
- **Django REST Framework**: RESTful API
- **PostgreSQL**: Database
- **PostGIS**: Geographic database extension
- **Celery**: Task queue
- **Redis**: Message broker and cache
- **JWT**: Authentication

### Frontend Integration
- **django-cors-headers**: CORS support for mobile apps
- **REST API**: JSON responses for any frontend

### DevOps
- **Docker**: Containerization
- **Docker Compose**: Multi-container orchestration
- **Gunicorn**: WSGI server (production)

## Configuration Files

### Environment (`.env`)
```
SECRET_KEY                  # Django secret key
DEBUG                       # Debug mode
ALLOWED_HOSTS              # Allowed hosts
DB_NAME, DB_USER, etc.     # Database configuration
CORS_ALLOWED_ORIGINS       # CORS settings
JWT_ACCESS_TOKEN_LIFETIME  # JWT settings
CELERY_BROKER_URL          # Celery broker
```

### Django Settings (`config/settings.py`)
- Database configuration (PostgreSQL + PostGIS)
- REST Framework settings
- CORS configuration
- JWT authentication
- Celery configuration
- Logging configuration

### Celery Beat Schedule
Automated tasks scheduled in `config/settings.py` under `CELERY_BEAT_SCHEDULE`

## Testing

- Unit tests in each app's `tests.py`
- Run tests: `python manage.py test`
- With pytest: `pytest`

## Deployment

### Development
- `python manage.py runserver`
- `celery -A config worker -l info`
- `celery -A config beat -l info`

### Production (Docker)
- `docker-compose up -d`
- All services run in containers
- PostgreSQL, Redis, Django, Celery, Celery Beat

## Security Features

- JWT token-based authentication
- Password hashing (Django default)
- CORS configuration
- SQL injection protection (Django ORM)
- XSS protection (Django middleware)
- CSRF protection
- Permission-based access control

## Scalability Considerations

- Celery for background processing
- Redis for caching
- Database indexing on frequently queried fields
- Pagination on all list endpoints
- Geographic indexing with PostGIS

## Future Enhancements

- WebSocket support for real-time updates
- Push notifications
- Advanced analytics dashboard
- Mobile app (React Native/Flutter)
- Facial recognition integration
- Biometric authentication
- Multi-tenancy support
- Advanced reporting with charts
