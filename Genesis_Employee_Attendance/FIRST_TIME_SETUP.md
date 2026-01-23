# First Time Setup Guide

Welcome to Genesis Employee Attendance System! Follow these steps to get started.

## Prerequisites

✅ Docker Desktop is installed and running
✅ All containers are up and running (check with `docker compose ps`)

## Step 1: Create Admin User

You need to create a Django superuser to access the admin panel and dashboard.

### Option A: Using Docker (Recommended)

Run this command in your terminal:

```bash
docker compose exec web python manage.py createsuperuser
```

You'll be prompted to enter:
- Username (e.g., `admin`)
- Email (e.g., `admin@genesis.com`)
- Password (choose a strong password)

### Option B: Using Python Script

We'll create a script to automate this (see below).

## Step 2: Access the System

### 2.1 Django Admin Panel
- URL: http://localhost:8000/admin/
- Login with the superuser credentials you just created
- Here you can:
  - Manage employees
  - View location logs
  - Check attendance records
  - Configure Celery Beat schedules

### 2.2 Web Dashboard
- URL: http://localhost:8000/dashboard/
- Login with the superuser credentials
- Features:
  - Live employee tracking
  - Route history playback
  - Attendance reports
  - Statistics and charts

### 2.3 API Endpoints
- Base URL: http://localhost:8000/api/
- API Documentation: See `API_DOCUMENTATION.md`

## Step 3: Create Your First Employee

### Method 1: Via Django Admin
1. Go to http://localhost:8000/admin/
2. Login with superuser credentials
3. Navigate to **Employees** → **Add Employee**
4. Fill in the required fields:
   - Employee ID (unique, e.g., `EMP001`)
   - Name
   - Email (unique)
   - Phone
   - Password (will be hashed automatically)
   - Department
   - Designation
   - Join Date
   - Is Active: ✓

### Method 2: Via API
```bash
# First, get JWT token (login as admin)
curl -X POST http://localhost:8000/api/auth/token/ \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@genesis.com", "password": "your_password"}'

# Then create employee (use the access token from above)
curl -X POST http://localhost:8000/api/employees/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "employee_id": "EMP001",
    "name": "John Doe",
    "email": "john@genesis.com",
    "phone": "+1234567890",
    "password": "securepassword123",
    "department": "IT",
    "designation": "Software Developer",
    "join_date": "2024-01-01",
    "is_active": true
  }'
```

## Step 4: Test Location Tracking

### Via Mobile App (API)
```bash
# Employee login to get JWT token
curl -X POST http://localhost:8000/api/auth/token/ \
  -H "Content-Type: application/json" \
  -d '{"email": "john@genesis.com", "password": "securepassword123"}'

# Log location (use access token from login)
curl -X POST http://localhost:8000/api/tracking/log-location/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 23.8103,
    "longitude": 90.4125,
    "accuracy": 10.5,
    "battery_level": 85,
    "speed": 0.0
  }'
```

### View Live Locations
- Go to http://localhost:8000/dashboard/live-tracking/
- You'll see all active employees on the map

## Step 5: Check Attendance

### Via Dashboard
- Go to http://localhost:8000/dashboard/reports/
- Select date range and view attendance records

### Via API
```bash
# Get employee's own attendance
curl -X GET "http://localhost:8000/api/attendance/my-attendance/?start_date=2024-01-01&end_date=2024-01-31" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# Admin: Get all employees attendance
curl -X GET "http://localhost:8000/api/attendance/all/?date=2024-01-15" \
  -H "Authorization: Bearer ADMIN_ACCESS_TOKEN"
```

## Step 6: Verify Celery Tasks

Celery tasks run automatically:
- **Daily Attendance Calculation**: Runs at 6:45 PM (18:45) every day
- **Location Reminders**: Runs every hour during work hours (9:30 AM - 6:30 PM)
- **Cleanup Old Locations**: Runs weekly on Sunday at 2 AM

Check Celery logs:
```bash
docker compose logs celery
docker compose logs celery-beat
```

## Quick Commands Reference

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f web
docker compose logs -f celery

# Create superuser
docker compose exec web python manage.py createsuperuser

# Run migrations
docker compose exec web python manage.py migrate

# Access Django shell
docker compose exec web python manage.py shell

# Check container status
docker compose ps
```

## Troubleshooting

### Can't access admin panel?
- Make sure you created a superuser
- Check if web container is running: `docker compose ps`
- Check web logs: `docker compose logs web`

### Database errors?
- Reset database: `docker compose down -v` then `docker compose up -d`
- Run migrations: `docker compose exec web python manage.py migrate`

### Celery not working?
- Check Redis is running: `docker compose ps redis`
- Check Celery logs: `docker compose logs celery`
- Restart Celery: `docker compose restart celery celery-beat`

## Next Steps

1. ✅ Create admin user
2. ✅ Create employees
3. ✅ Test location tracking
4. ✅ View attendance reports
5. 📱 Integrate with mobile app
6. 🔧 Configure Celery Beat schedules if needed
7. 🔒 Update security settings for production

## Support

For more information, see:
- `API_DOCUMENTATION.md` - Complete API reference
- `QUICK_START.md` - Quick start guide
- `DOCKER_SETUP_GUIDE.md` - Docker setup details
