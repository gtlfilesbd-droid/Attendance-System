# Genesis Employee Attendance System - Final Setup Guide 🚀

## 🎉 Project 100% Complete!

This guide will help you get the system up and running in minutes.

---

## ⚡ Quick Start (5 Steps)

### **Step 1: Install Prerequisites**

**Required:**
- Python 3.11+
- PostgreSQL 14+ with PostGIS
- Redis

**Windows:**
```bash
# Python: Download from python.org
# PostgreSQL: Download from postgresql.org (include PostGIS)
# Redis: Download from https://github.com/microsoftarchive/redis/releases
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install python3 python3-pip postgresql postgresql-contrib postgis redis-server
```

**macOS:**
```bash
brew install python postgresql postgis redis
brew services start postgresql
brew services start redis
```

---

### **Step 2: Setup Database**

```bash
# Connect to PostgreSQL
psql -U postgres

# Create database
CREATE DATABASE genesis_attendance_db;

# Connect to database
\c genesis_attendance_db;

# Enable PostGIS extension
CREATE EXTENSION postgis;

# Verify PostGIS
SELECT PostGIS_version();

# Exit
\q
```

---

### **Step 3: Install Project**

```bash
# Navigate to project
cd Genesis_Employee_Attendance

# Run installation script
# Windows:
install.bat

# Linux/Mac:
chmod +x install.sh
./install.sh
```

**This will:**
- Create virtual environment
- Install all Python packages
- Create .env file
- Create necessary directories

---

### **Step 4: Configure Environment**

Edit `.env` file:

```env
# REQUIRED: Change these
SECRET_KEY=change-this-to-random-secret-key
DB_PASSWORD=your-postgres-password

# OPTIONAL: Get from Google Cloud Console
# No API key required - OpenStreetMap + Leaflet.js is free

# Keep defaults for development
DEBUG=True
DB_NAME=genesis_attendance_db
DB_USER=postgres
DB_HOST=localhost
DB_PORT=5432
CELERY_BROKER_URL=redis://localhost:6379/0
```

**No API Key Required:**
Leaflet.js and OpenStreetMap are free and open source. The map library loads automatically from CDN - no registration or API key needed.
2. Create project
3. Enable "Maps JavaScript API"
4. Create credentials → API Key
5. Add to .env file

---

### **Step 5: Run Setup & Start Services**

```bash
# Run database migrations and create superuser
python setup.py

# This creates:
# - Database tables
# - Superuser (admin/admin123)
# - Default departments
# - Work shifts
```

**Start Services (3 terminals):**

**Terminal 1 - Django Server:**
```bash
# Windows
run_dev.bat

# Linux/Mac
python manage.py runserver
```

**Terminal 2 - Celery Worker:**
```bash
# Windows
run_celery_worker.bat

# Linux/Mac
chmod +x run_celery_worker.sh
./run_celery_worker.sh
```

**Terminal 3 - Celery Beat:**
```bash
celery -A config beat -l info
```

---

## 🌐 Access the System

### **Web Dashboard**
- URL: http://localhost:8000/dashboard/
- Login: `admin@genesis.com` / `admin123`

### **Admin Panel**
- URL: http://localhost:8000/admin/
- Login: `admin` / `admin123`

### **API Root**
- URL: http://localhost:8000/api/

---

## 🐳 Docker Alternative (Easier!)

If you want to skip manual setup:

```bash
# 1. Create .env file
cp env.example .env
# Edit .env with your settings

# 2. Start all services
docker-compose up -d

# 3. Run migrations
docker-compose exec web python manage.py migrate

# 4. Create superuser
docker-compose exec web python manage.py createsuperuser

# 5. Access
# Dashboard: http://localhost:8000/dashboard/
# Admin: http://localhost:8000/admin/
```

**Docker includes:**
- PostgreSQL with PostGIS ✓
- Redis ✓
- Django ✓
- Celery Worker ✓
- Celery Beat ✓

**Everything runs automatically!**

---

## 📱 Test the System

### **1. Login to Dashboard**
```
http://localhost:8000/dashboard/
Email: admin@genesis.com
Password: admin123
```

### **2. Create Test Employee**

Go to Admin Panel → Employees → Add:
```
Employee ID: EMP002
Name: Test User
Email: test@example.com
Password: test123
Phone: +1234567890
Department: IT
Designation: Developer
Join Date: 2024-01-15
Is Active: ✓
```

### **3. Test API Login**

```bash
curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'
```

**Save the access token!**

### **4. Log Test Location**

```bash
curl -X POST http://localhost:8000/api/tracking/log-location/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 23.8103,
    "longitude": 90.4125,
    "timestamp": "2024-01-15T10:30:00Z",
    "accuracy": 10.5,
    "battery_level": 85
  }'
```

### **5. View in Dashboard**

- Go to **Live Tracking** - See the location on map
- Go to **Route History** - Select employee and date
- Go to **Reports** - Generate daily report

### **6. Test Celery Task**

```bash
python test_celery.py
```

Or manually:
```bash
python manage.py shell
>>> from tracking.tasks import calculate_daily_attendance
>>> result = calculate_daily_attendance()
>>> print(result)
```

---

## 🔧 Common Issues & Solutions

### **Issue 1: GDAL Not Found**

**Error:** `Could not find the GDAL library`

**Solution (Windows):**
1. Download OSGeo4W: https://trac.osgeo.org/osgeo4w/
2. Install GDAL, GEOS, PROJ
3. Add to PATH: `C:\OSGeo4W64\bin`

**Or use Docker** (easiest):
```bash
docker-compose up -d
```

---

### **Issue 2: Redis Connection Failed**

**Error:** `Error connecting to Redis`

**Solution:**
```bash
# Check if Redis is running
redis-cli ping
# Should return: PONG

# Start Redis
# Windows: Start Redis service
# Linux: sudo systemctl start redis
# Mac: brew services start redis
```

---

### **Issue 3: Database Connection Failed**

**Error:** `could not connect to server`

**Solution:**
```bash
# Check PostgreSQL is running
pg_isready

# Start PostgreSQL
# Windows: Start PostgreSQL service
# Linux: sudo systemctl start postgresql
# Mac: brew services start postgresql

# Verify credentials in .env match your PostgreSQL setup
```

---

### **Issue 4: Map Not Loading**

**Error:** Map shows gray screen or doesn't load or doesn't load

**Solution:**
1. Check browser console for errors
2. Verify internet connection (Leaflet.js loads from CDN)
3. Ensure Leaflet CSS is loaded (check Network tab)
4. Check if Leaflet.js script is blocked by ad blockers
5. Try clearing browser cache

---

## 📋 Verification Checklist

After setup, verify:

- [ ] PostgreSQL is running
- [ ] PostGIS extension is enabled
- [ ] Redis is running
- [ ] Django server starts without errors
- [ ] Celery worker connects to Redis
- [ ] Celery beat shows scheduled tasks
- [ ] Can login to dashboard
- [ ] Can login to admin panel
- [ ] Can access API endpoints
- [ ] OpenStreetMap loads (Leaflet.js from CDN)

---

## 🎯 Next Steps After Setup

### **1. Create Employees**
- Via Admin Panel: http://localhost:8000/admin/
- Via API: `POST /api/auth/register/`

### **2. Map Configuration (Automatic)**
- No configuration needed
- Leaflet.js loads automatically from CDN
- OpenStreetMap tiles are free

### **3. Test Mobile Integration**
- Use API to log locations
- View in live tracking
- Check attendance calculation

### **4. Customize Settings**
- Update timezone if needed
- Configure work hours
- Adjust late arrival threshold
- Set location reminder interval

### **5. Deploy to Production**
- Set `DEBUG=False`
- Generate new `SECRET_KEY`
- Configure `ALLOWED_HOSTS`
- Setup HTTPS/SSL
- Use production database
- Configure email service

---

## 📚 Essential Commands

### **Development**
```bash
# Start Django
python manage.py runserver

# Start Celery Worker
celery -A config worker -l info --pool=solo  # Windows
celery -A config worker -l info              # Linux/Mac

# Start Celery Beat
celery -A config beat -l info

# Run migrations
python manage.py makemigrations
python manage.py migrate

# Create superuser
python manage.py createsuperuser

# Django shell
python manage.py shell

# Test Celery
python test_celery.py
```

### **Docker**
```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# Logs
docker-compose logs -f

# Execute command
docker-compose exec web python manage.py migrate
```

---

## 🎓 Learning Resources

### **Django**
- Official Docs: https://docs.djangoproject.com/
- REST Framework: https://www.django-rest-framework.org/

### **PostGIS**
- PostGIS Docs: https://postgis.net/documentation/
- GeoDjango: https://docs.djangoproject.com/en/4.2/ref/contrib/gis/

### **Celery**
- Celery Docs: https://docs.celeryproject.org/
- Redis: https://redis.io/documentation

### **OpenStreetMap + Leaflet.js**
- Leaflet.js: https://leafletjs.com/
- OpenStreetMap: https://www.openstreetmap.org/
- Leaflet Documentation: https://leafletjs.com/reference.html

---

## 💡 Pro Tips

### **Development**
1. Use Docker for easier setup (avoids GDAL issues)
2. Keep Celery worker running in background
3. Monitor logs: `tail -f logs/django.log`
4. Use Django Debug Toolbar for optimization

### **Testing**
1. Create test employees with different departments
2. Log multiple locations throughout the day
3. Wait until 6:45 PM or run task manually
4. Check attendance records in dashboard

### **Production**
1. Use environment variables for all secrets
2. Enable HTTPS
3. Setup database backups
4. Monitor Celery tasks
5. Setup error tracking (Sentry)
6. Configure email notifications

---

## 🎉 You're All Set!

Your Genesis Employee Attendance System is ready to:

✅ Track employees in real-time  
✅ Calculate attendance automatically  
✅ Generate comprehensive reports  
✅ Integrate with mobile apps  
✅ Scale to production  

**Happy tracking!** 🚀

---

## 📞 Need Help?

1. Check documentation in project folder
2. Review logs in `logs/` directory
3. Test Celery with `test_celery.py`
4. Verify services are running
5. Check `.env` configuration

---

**Genesis Employee Attendance System**  
*Complete. Production-Ready. Well-Documented.*
