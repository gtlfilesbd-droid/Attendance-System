# 🚀 Quick Start with Docker

## Prerequisites

1. **Install Docker Desktop**
   - Download: https://www.docker.com/products/docker-desktop/
   - Install and restart your computer
   - Start Docker Desktop and wait for it to be running

## One-Command Setup

### Windows
```powershell
cd "E:\Attendance System\Genesis_Employee_Attendance"
.\docker-start.bat
```

### Linux/Mac
```bash
cd Genesis_Employee_Attendance
chmod +x docker-start.sh
./docker-start.sh
```

## Manual Setup (Step by Step)

### 1. Navigate to Project
```bash
cd "E:\Attendance System\Genesis_Employee_Attendance"
```

### 2. Create Environment File
```bash
# Windows
copy env.example .env

# Linux/Mac
cp env.example .env
```

### 3. Start All Services
```bash
docker compose up -d --build
```

This will start:
- ✅ PostgreSQL with PostGIS (database)
- ✅ Redis (cache & Celery broker)
- ✅ Django web server
- ✅ Celery worker (background tasks)
- ✅ Celery Beat (scheduled tasks)

### 4. Wait for Services (30 seconds)
Services need time to initialize. Check status:
```bash
docker compose ps
```

All services should show "Up" status.

### 5. Run Database Migrations
```bash
docker compose exec web python manage.py migrate
```

### 6. Create Admin User
```bash
docker compose exec web python manage.py createsuperuser
```

Follow the prompts to create your admin account.

### 7. Access Application

Open your browser:
- **Dashboard:** http://localhost:8000/dashboard/
- **Admin Panel:** http://localhost:8000/admin/
- **API:** http://localhost:8000/api/

## Verify Everything Works

### Check Services
```bash
docker compose ps
```

Should show 5 services running:
- `web` - Django application
- `db` - PostgreSQL database
- `redis` - Redis cache
- `celery` - Background worker
- `celery-beat` - Scheduler

### Test Map
1. Go to: http://localhost:8000/dashboard/live-tracking/
2. You should see:
   - ✅ OpenStreetMap tiles loading
   - ✅ No console errors
   - ✅ Leaflet.js working

### Check Logs
```bash
docker compose logs web
```

## Common Issues

### Port Already in Use
If port 8000 is busy:
```bash
# Find what's using it (Windows)
netstat -ano | findstr :8000

# Or change port in docker-compose.yml
# Change "8000:8000" to "8001:8000"
```

### Services Won't Start
```bash
# Check logs
docker compose logs

# Rebuild
docker compose down
docker compose up -d --build
```

### Database Connection Error
```bash
# Wait longer for database
docker compose logs db

# Restart services
docker compose restart
```

## Next Steps

1. ✅ Create employees via admin panel
2. ✅ Test location logging via API
3. ✅ View live tracking on dashboard
4. ✅ Check route history
5. ✅ Generate attendance reports

## Stop Services

```bash
# Windows
.\docker-stop.bat

# Or manually
docker compose down
```

## Useful Commands

See `docker-commands.md` for complete command reference.

---

**Need Help?** Check `DOCKER_SETUP_GUIDE.md` for detailed troubleshooting.
