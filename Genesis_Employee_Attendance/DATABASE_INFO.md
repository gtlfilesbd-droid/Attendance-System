# Database Information

## Database Name
**`genesis_attendance_db`**

### Database Configuration
- **Type**: PostgreSQL with PostGIS extension
- **Host**: `db` (Docker service name) or `localhost` (local)
- **Port**: `5432`
- **User**: `postgres`
- **Password**: `postgres` (default, change in production)
- **Engine**: `django.contrib.gis.db.backends.postgis`

---

## Application Tables (Custom Models)

### 1. **`employees`**
- **Model**: `Employee`
- **Description**: Stores employee information
- **Key Fields**:
  - `id` (UUID, Primary Key)
  - `employee_id` (CharField, Unique)
  - `name` (CharField)
  - `email` (EmailField, Unique)
  - `phone` (CharField)
  - `password` (CharField, Hashed)
  - `department` (CharField)
  - `designation` (CharField)
  - `join_date` (DateField)
  - `is_active` (BooleanField)
  - `profile_picture` (ImageField, Optional)
  - `created_at` (DateTimeField)
  - `updated_at` (DateTimeField)

### 2. **`location_logs`**
- **Model**: `LocationLog`
- **Description**: Stores employee GPS location logs with PostGIS PointField
- **Key Fields**:
  - `id` (AutoField, Primary Key)
  - `employee_id` (ForeignKey → `employees.id`)
  - `location` (PointField - PostGIS geography)
  - `timestamp` (DateTimeField)
  - `accuracy` (FloatField - meters)
  - `battery_level` (IntegerField - 0-100)
  - `speed` (FloatField, Optional)
  - `address` (TextField, Optional - reverse geocoded)
  - `created_at` (DateTimeField)

### 3. **`attendance`**
- **Model**: `Attendance`
- **Description**: Stores daily attendance records
- **Key Fields**:
  - `id` (AutoField, Primary Key)
  - `employee_id` (ForeignKey → `employees.id`)
  - `date` (DateField)
  - `first_location_time` (TimeField, Optional)
  - `last_location_time` (TimeField, Optional)
  - `check_in_time` (TimeField, Optional)
  - `check_out_time` (TimeField, Optional)
  - `total_hours` (DecimalField)
  - `total_locations_logged` (IntegerField)
  - `status` (CharField - PRESENT, LATE, HALF_DAY, ABSENT)
  - `remarks` (TextField, Optional)
  - `created_at` (DateTimeField)
  - `updated_at` (DateTimeField)
  - **Unique Constraint**: (`employee`, `date`)

---

## Django System Tables

These tables are automatically created by Django:

### Authentication & Authorization
- `auth_user` - Django's built-in User model
- `auth_group` - User groups
- `auth_permission` - Permissions
- `auth_user_groups` - User-Group relationships
- `auth_user_user_permissions` - User-Permission relationships

### Django Framework
- `django_migrations` - Migration history
- `django_content_type` - Content types for models
- `django_session` - Session data
- `django_admin_log` - Admin action logs

### Celery Beat (Task Scheduling)
- `django_celery_beat_periodictask` - Periodic tasks
- `django_celery_beat_intervalschedule` - Interval schedules
- `django_celery_beat_crontabschedule` - Cron schedules
- `django_celery_beat_solarschedule` - Solar schedules
- `django_celery_beat_clockedschedule` - Clocked schedules
- `django_celery_beat_periodictasks` - Task metadata

### PostGIS Extension Tables
- `spatial_ref_sys` - Spatial reference systems
- `geometry_columns` - Geometry column metadata

---

## Table Relationships

```
employees (1) ──→ (N) location_logs
employees (1) ──→ (N) attendance
```

---

## Accessing the Database

### Via Docker
```bash
# Connect to PostgreSQL
docker compose exec db psql -U postgres -d genesis_attendance_db

# List all tables
\dt

# Describe a table
\d employees
\d location_logs
\d attendance
```

### Via Django Shell
```bash
# Access Django shell
docker compose exec web python manage.py shell

# Query examples
from employees.models import Employee
from tracking.models import LocationLog
from attendance.models import Attendance

# List all employees
Employee.objects.all()

# List all location logs
LocationLog.objects.all()

# List all attendance records
Attendance.objects.all()
```

### Connection String
```
postgresql://postgres:postgres@localhost:5432/genesis_attendance_db
```

---

## Important Notes

1. **Database Name**: `genesis_attendance_db` (defined in `docker-compose.yml` and `settings.py`)
2. **PostGIS**: The database uses PostGIS extension for geospatial data (PointField in `location_logs`)
3. **UUID Primary Key**: `employees` table uses UUID as primary key
4. **Auto Primary Keys**: `location_logs` and `attendance` use auto-increment integers
5. **Indexes**: All tables have indexes on frequently queried fields (employee_id, timestamp, date, etc.)

---

## Quick Reference

| Table Name | Model Class | Primary Key | Description |
|------------|-------------|-------------|-------------|
| `employees` | `Employee` | UUID | Employee information |
| `location_logs` | `LocationLog` | Auto Integer | GPS location tracking |
| `attendance` | `Attendance` | Auto Integer | Daily attendance records |
| `auth_user` | `User` (Django) | Auto Integer | Django admin users |
| `django_migrations` | - | - | Migration history |
| `django_celery_beat_*` | - | - | Celery Beat schedules |
