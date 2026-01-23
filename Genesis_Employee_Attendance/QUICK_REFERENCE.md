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

## ⚠️ Important Notes

- **Change default passwords** after first login
- Celery tasks run automatically (attendance calculation, reminders)
- Location tracking requires employee to log locations via API
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
