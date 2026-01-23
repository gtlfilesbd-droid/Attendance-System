# 🚀 START HERE - Genesis Employee Attendance System

## Welcome! 👋

This is a **complete, production-ready** Django employee attendance tracking system.

---

## ✨ What This System Does

### **For Employees (Mobile App)**
1. 📱 Log location automatically from mobile app
2. 📊 View own attendance records
3. 🗺️ View own route history
4. 📈 Check attendance statistics

### **For Admins (Web Dashboard)**
1. 🗺️ Monitor all employees in real-time on map
2. 📊 View attendance reports (daily/weekly/monthly)
3. 📥 Export reports to CSV
4. 🎬 Playback employee routes with timeline
5. 👥 Manage employees and settings

### **Automated System**
1. 🤖 Calculates attendance daily at 6:45 PM
2. ⏰ Sends location reminders every hour
3. 🧹 Cleans up old data weekly
4. ✅ All automatic - no manual work needed!

---

## ⚡ Quick Start (Choose One)

### **Option 1: Docker (Easiest - Recommended!)**

```bash
# 1. Copy environment file
cp env.example .env

# 2. Start everything
docker-compose up -d

# 3. Run migrations
docker-compose exec web python manage.py migrate

# 4. Create admin user
docker-compose exec web python manage.py createsuperuser

# 5. Open browser
# http://localhost:8000/dashboard/
```

**Done! Everything is running.** ✅

---

### **Option 2: Manual Installation**

**Prerequisites:**
- Python 3.11+
- PostgreSQL with PostGIS
- Redis

**Steps:**

```bash
# 1. Install project
# Windows: install.bat
# Linux/Mac: ./install.sh

# 2. Setup database
psql -U postgres
CREATE DATABASE genesis_attendance_db;
\c genesis_attendance_db;
CREATE EXTENSION postgis;
\q

# 3. Configure .env
cp env.example .env
# Edit .env with your database password

# 4. Run setup
python setup.py

# 5. Start services (3 terminals)
# Terminal 1:
python manage.py runserver

# Terminal 2:
celery -A config worker -l info --pool=solo

# Terminal 3:
celery -A config beat -l info

# 6. Open browser
# http://localhost:8000/dashboard/
```

---

## 🎯 First Steps After Setup

### **1. Login to Dashboard**
```
URL: http://localhost:8000/dashboard/
Email: admin@genesis.com
Password: admin123
```

**⚠️ Change this password immediately!**

### **2. Create Employees**

**Via Admin Panel:**
- Go to: http://localhost:8000/admin/
- Click "Employees" → "Add Employee"
- Fill in details and save

**Via API:**
```bash
POST /api/auth/register/
{
  "employee_id": "EMP002",
  "name": "John Doe",
  "email": "john@example.com",
  "password": "password123",
  "phone": "+1234567890",
  "department": "IT",
  "designation": "Developer",
  "join_date": "2024-01-15",
  "is_active": true
}
```

### **3. Test Location Logging**

```bash
# Get token first
TOKEN=$(curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"john@example.com","password":"password123"}' \
  | jq -r '.data.access')

# Log location
curl -X POST http://localhost:8000/api/tracking/log-location/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 23.8103,
    "longitude": 90.4125,
    "timestamp": "2024-01-15T10:30:00Z",
    "accuracy": 10.5,
    "battery_level": 85
  }'
```

### **4. View Results**

- **Live Tracking:** http://localhost:8000/dashboard/live-tracking/
- **Route History:** http://localhost:8000/dashboard/route-history/
- **Reports:** http://localhost:8000/dashboard/reports/

---

## 📚 Documentation Guide

**Start with these files:**

1. **FINAL_SETUP_GUIDE.md** ← Detailed setup instructions
2. **QUICK_START.md** ← Quick reference
3. **API_VIEWS_DOCUMENTATION.md** ← API endpoints
4. **DASHBOARD_DOCUMENTATION.md** ← Dashboard features
5. **CELERY_TASKS_DOCUMENTATION.md** ← Automated tasks

**Other docs:**
- `COMPLETE_PROJECT_SUMMARY.md` - Full project overview
- `COMMANDS_REFERENCE.md` - Common commands
- `SERIALIZERS_DOCUMENTATION.md` - API serializers
- `PROJECT_STRUCTURE.md` - Architecture details

---

## 🎨 Dashboard Pages

Once logged in, you'll see:

### **📊 Dashboard Home**
- Today's attendance statistics
- Present, Late, Absent counts
- Recent activities
- Quick action buttons

### **🗺️ Live Tracking**
- Real-time employee locations on OpenStreetMap
- Updates every 30 seconds
- Click employee to focus
- Shows battery levels

### **📍 Route History**
- Select employee and date
- See their movement path
- Playback controls
- Distance and duration

### **📈 Reports**
- Daily/Weekly/Monthly reports
- Department filtering
- Export to CSV
- Print functionality

---

## 🔑 Default Credentials

### **Dashboard Login**
- Email: `admin@genesis.com`
- Password: `admin123`

### **Admin Panel**
- Username: `admin`
- Password: `admin123`

**⚠️ IMPORTANT: Change these passwords in production!**

---

## 🎯 System Features

### **✅ Completed Features**

**Backend:**
- ✅ Django 4.2 with PostgreSQL + PostGIS
- ✅ REST API with JWT authentication
- ✅ Real-time location tracking
- ✅ Automated attendance calculation
- ✅ Celery background tasks
- ✅ Redis message broker

**Frontend:**
- ✅ Web dashboard with Bootstrap 5
- ✅ OpenStreetMap + Leaflet.js integration
- ✅ Real-time updates (30s polling)
- ✅ Route playback with controls
- ✅ CSV export

**Automation:**
- ✅ Daily attendance at 6:45 PM
- ✅ Hourly location reminders
- ✅ Weekly data cleanup
- ✅ All automatic!

---

## 📱 Mobile App Integration

### **API Endpoints for Mobile**

**Login:**
```
POST /api/auth/login/
Body: {"email": "...", "password": "..."}
Returns: JWT tokens
```

**Log Location:**
```
POST /api/tracking/log-location/
Header: Authorization: Bearer TOKEN
Body: {latitude, longitude, timestamp, accuracy, battery_level}
```

**Get My Attendance:**
```
GET /api/attendance/my-attendance/?start_date=2024-01-01
Header: Authorization: Bearer TOKEN
```

**Get My Route:**
```
GET /api/tracking/my-route-today/
Header: Authorization: Bearer TOKEN
```

---

## 🏗️ Architecture Overview

```
Mobile App
    ↓ (logs location every 1-5 min)
    ↓
REST API (/api/tracking/log-location/)
    ↓
PostgreSQL + PostGIS (stores location)
    ↓
Celery Task (6:45 PM daily)
    ↓
Calculates Attendance
    ↓
Web Dashboard (displays results)
```

---

## 🎊 You're Ready!

Everything is set up and ready to use:

✅ **Models** - Employee, LocationLog, Attendance  
✅ **API** - 16 REST endpoints  
✅ **Dashboard** - 4 beautiful pages  
✅ **Automation** - 3 Celery tasks  
✅ **Documentation** - 10+ comprehensive guides  
✅ **Tests** - Unit tests included  
✅ **Docker** - One-command deployment  

**Start exploring the dashboard at:**
### 🌐 http://localhost:8000/dashboard/

---

## 🆘 Need Help?

1. **Setup Issues?** → Read `FINAL_SETUP_GUIDE.md`
2. **API Questions?** → Read `API_VIEWS_DOCUMENTATION.md`
3. **Dashboard Help?** → Read `DASHBOARD_DOCUMENTATION.md`
4. **Celery Issues?** → Read `CELERY_TASKS_DOCUMENTATION.md`
5. **Commands?** → Read `COMMANDS_REFERENCE.md`

---

**Happy Tracking! 🎉**

*Genesis Employee Attendance System - Built with ❤️ using Django*
