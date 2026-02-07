# Quick Reference Card

## 🚀 System is Ready!

Your Genesis Employee Attendance System is now running with default credentials.

## 🔑 Login Credentials

### Admin Access
- **URL**: http://localhost:8000/admin/
- **Username**: `admin`
- **Password**: `admin123`

### Web Dashboard
- **URL**: http://localhost:8000/dashboard/
- **Username**: `admin`
- **Password**: `admin123`

### Test Employee (API)
- **Email**: `john.doe@genesis.com`
- **Password**: `employee123`

## 📍 Quick Links

| Service | URL |
|---------|-----|
| Admin Panel | http://localhost:8000/admin/ |
| Dashboard | http://localhost:8000/dashboard/ |
| API Base | http://localhost:8000/api/ |
| API Docs | See `API_DOCUMENTATION.md` |

## 🎯 First Steps

1. **Login to Admin Panel**
   - Go to http://localhost:8000/admin/
   - Login with `admin` / `admin123`
   - **Change the password immediately!**

2. **Create More Employees**
   - In admin panel: Employees → Add Employee
   - Or use API: `POST /api/employees/`

3. **Test Location Tracking**
   - Employee login: `POST /api/auth/token/`
   - Log location: `POST /api/tracking/log-location/`
   - View on dashboard: http://localhost:8000/dashboard/live-tracking/

4. **View Attendance**
   - Dashboard: http://localhost:8000/dashboard/reports/
   - API: `GET /api/attendance/my-attendance/`

## 🛠️ Common Commands

```bash
# View all containers
docker compose ps

# View logs
docker compose logs -f web

# Stop system
docker compose down

# Start system
docker compose up -d

# Restart a service
docker compose restart web
```

## Present Today and Dashboard Data

- **"Present today"** and recent activities on the dashboard are filled by the **Celery task** `tracking.calculate_daily_attendance`, which runs **daily at 6:45 PM**. Until it runs (or you run it manually), today's Attendance table is empty and "Present today" shows 0.
- **For testing:** Run the attendance calculation for today immediately:
  ```bash
  docker compose exec web python manage.py run_attendance_today
  ```
  (Or without Docker: `python manage.py run_attendance_today`.) After this, the dashboard will show "Present today" and recent activities for today.

## Dashboard not showing locations / Present count 0 (debugging)

1. **Check if locations are in the database:**
   ```bash
   docker compose exec web python manage.py check_locations
   ```
   - If **Total location logs: 0** and **Today's location logs: 0**: the mobile app is not saving data. Check backend logs for "Employee JWT auth" and "log_location", restart web (`docker compose restart web`), ensure employee exists (`docker compose exec web python create_admin.py`), and that the app baseUrl points to your server.
   - If **counts are > 0**: locations are saved. Continue below.

2. **Update Present count:** Run the attendance calculation so "Present today" and recent activities appear:
   ```bash
   docker compose exec web python manage.py run_attendance_today
   ```
   Then refresh the dashboard home page.

3. **Live Tracking map:** The map shows employees who have at least one location in the **last 15 minutes**. Log in to the dashboard as **admin** (Django superuser), open **Live Tracking**, and click Refresh. If you have recent locations from step 1, they will appear.

## Important Notes

- **Change default passwords** after first login
- Celery tasks run automatically (attendance calculation at 6:45 PM, reminders)
- Location tracking requires the app to log locations (Employee JWT must be accepted; see employees.authentication)
- Dashboard shows real-time data from the database

## 📚 Documentation

- `FIRST_TIME_SETUP.md` - Detailed setup guide
- `API_DOCUMENTATION.md` - Complete API reference
- `QUICK_START.md` - Quick start guide

---

**System Status**: ✅ Running
**Database**: ✅ Connected
**Celery**: ✅ Active
**Redis**: ✅ Connected
