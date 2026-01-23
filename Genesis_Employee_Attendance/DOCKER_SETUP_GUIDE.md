# 🐳 Docker Setup Guide - Production Ready

## Step 1: Install Docker Desktop

### Download and Install

1. **Download Docker Desktop for Windows:**
   - Visit: https://www.docker.com/products/docker-desktop/
   - Click "Download for Windows"
   - Download the installer (Docker Desktop Installer.exe)

2. **Install Docker Desktop:**
   - Run the installer
   - Follow the installation wizard
   - **Important:** Enable "Use WSL 2 instead of Hyper-V" if prompted (recommended)
   - Restart your computer when prompted

3. **Verify Installation:**
   ```powershell
   docker --version
   docker compose version
   ```
   Both commands should show version numbers.

4. **Start Docker Desktop:**
   - Open Docker Desktop from Start Menu
   - Wait for it to start (whale icon in system tray)
   - Make sure it says "Docker Desktop is running"

---

## Step 2: Configure Environment

1. **Create `.env` file:**
   ```powershell
   cd "E:\Attendance System\Genesis_Employee_Attendance"
   copy env.example .env
   ```

2. **Edit `.env` file** (optional - defaults work for development):
   ```env
   SECRET_KEY=your-secret-key-here
   DEBUG=True
   ALLOWED_HOSTS=localhost,127.0.0.1
   
   # Database (Docker handles this automatically)
   DB_NAME=genesis_attendance_db
   DB_USER=postgres
   DB_PASSWORD=postgres
   DB_HOST=db
   DB_PORT=5432
   
   # Redis (Docker handles this automatically)
   CELERY_BROKER_URL=redis://redis:6379/0
   CELERY_RESULT_BACKEND=redis://redis:6379/0
   ```

---

## Step 3: Start All Services

### First Time Setup

```powershell
# Navigate to project directory
cd "E:\Attendance System\Genesis_Employee_Attendance"

# Build and start all containers
docker compose up -d --build

# Wait for services to be ready (about 30 seconds)
# Check status
docker compose ps
```

### Run Database Migrations

```powershell
# Create database tables
docker compose exec web python manage.py migrate

# Create superuser (admin account)
docker compose exec web python manage.py createsuperuser
```

---

## Step 4: Access Your Application

### URLs

- **Web Dashboard:** http://localhost:8000/dashboard/
- **Admin Panel:** http://localhost:8000/admin/
- **API Root:** http://localhost:8000/api/

### Login

Use the superuser credentials you created in Step 3.

---

## Step 5: Verify Everything Works

### Check Services Status

```powershell
docker compose ps
```

You should see 5 services running:
- `web` (Django application)
- `db` (PostgreSQL with PostGIS)
- `redis` (Cache & Celery broker)
- `celery` (Background worker)
- `celery-beat` (Scheduled tasks)

### Check Logs

```powershell
# View all logs
docker compose logs

# View specific service logs
docker compose logs web
docker compose logs db
docker compose logs celery
```

### Test Map Functionality

1. Open: http://localhost:8000/dashboard/live-tracking/
2. You should see:
   - ✅ OpenStreetMap tiles loading
   - ✅ No console errors
   - ✅ Leaflet.js working

---

## Common Commands

### Start Services
```powershell
docker compose up -d
```

### Stop Services
```powershell
docker compose down
```

### Restart Services
```powershell
docker compose restart
```

### View Logs
```powershell
docker compose logs -f web
```

### Run Django Commands
```powershell
# Create migrations
docker compose exec web python manage.py makemigrations

# Apply migrations
docker compose exec web python manage.py migrate

# Create superuser
docker compose exec web python manage.py createsuperuser

# Collect static files
docker compose exec web python manage.py collectstatic

# Django shell
docker compose exec web python manage.py shell
```

### Access Database
```powershell
# PostgreSQL shell
docker compose exec db psql -U postgres -d genesis_attendance_db
```

### Rebuild After Code Changes
```powershell
docker compose up -d --build
```

---

## Troubleshooting

### Issue: "Docker is not running"
**Solution:** Start Docker Desktop application

### Issue: Port 8000 already in use
**Solution:** 
```powershell
# Stop the service using port 8000, or change port in docker-compose.yml
# Change: "8000:8000" to "8001:8000"
```

### Issue: "Cannot connect to database"
**Solution:**
```powershell
# Wait a bit longer for database to start
docker compose logs db

# Restart services
docker compose restart
```

### Issue: "Permission denied" errors
**Solution:**
```powershell
# On Windows, make sure Docker Desktop is running with admin privileges
# Right-click Docker Desktop → Run as administrator
```

### Issue: Containers keep restarting
**Solution:**
```powershell
# Check logs for errors
docker compose logs web
docker compose logs db

# Rebuild containers
docker compose down
docker compose up -d --build
```

---

## Production Deployment

### For Production Server (Linux)

1. **Install Docker on Linux:**
   ```bash
   curl -fsSL https://get.docker.com -o get-docker.sh
   sh get-docker.sh
   ```

2. **Copy project files to server**

3. **Update `.env` for production:**
   ```env
   DEBUG=False
   SECRET_KEY=your-production-secret-key
   ALLOWED_HOSTS=your-domain.com,www.your-domain.com
   ```

4. **Start services:**
   ```bash
   docker compose up -d --build
   ```

5. **Use reverse proxy (nginx):**
   - Configure nginx to proxy to `localhost:8000`
   - Set up SSL certificates

---

## Benefits of Docker Setup

✅ **No GDAL Installation Needed** - Pre-installed in container  
✅ **Consistent Environment** - Same on dev/staging/production  
✅ **Easy Deployment** - One command to start everything  
✅ **Isolated Services** - Database, Redis, Celery all separate  
✅ **Easy Scaling** - Add more workers easily  
✅ **Production Ready** - Gunicorn, health checks, proper setup  

---

## Next Steps

1. ✅ Install Docker Desktop
2. ✅ Create `.env` file
3. ✅ Run `docker compose up -d --build`
4. ✅ Run migrations
5. ✅ Create superuser
6. ✅ Access http://localhost:8000/dashboard/
7. ✅ Test map functionality

---

**Need Help?** Check logs with `docker compose logs` or see troubleshooting section above.
