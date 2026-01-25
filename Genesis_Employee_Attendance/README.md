# 🎉 Genesis Employee Attendance System

> A complete, production-ready Django employee attendance tracking system with real-time GPS monitoring, automated attendance calculation, and beautiful web dashboard.

[![Django](https://img.shields.io/badge/Django-4.2-green.svg)](https://www.djangoproject.com/)
[![DRF](https://img.shields.io/badge/DRF-3.14-red.svg)](https://www.django-rest-framework.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14+-blue.svg)](https://www.postgresql.org/)
[![PostGIS](https://img.shields.io/badge/PostGIS-3.3-orange.svg)](https://postgis.net/)
[![Celery](https://img.shields.io/badge/Celery-5.3-green.svg)](https://docs.celeryproject.org/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ✨ Features

### **🎯 Core Features**
- ✅ **Real-time GPS Tracking** - Track employee locations with PostGIS
- ✅ **Automated Attendance** - Auto-calculate from location logs (daily at 6:45 PM)
- ✅ **Web Dashboard** - Beautiful UI with OpenStreetMap + Leaflet.js integration
- ✅ **REST API** - Complete API with JWT authentication
- ✅ **Mobile Support** - Ready for iOS/Android integration
- ✅ **Route Playback** - Visualize employee routes with timeline controls
- ✅ **Reports & Export** - Daily/Weekly/Monthly reports with CSV export
- ✅ **Background Tasks** - Celery for automated processing

### **📱 For Mobile Apps**
- Location logging API
- JWT authentication
- Real-time sync
- Battery-efficient

### **💼 For Admins**
- Live employee tracking on map
- Attendance reports
- Route history playback
- CSV export
- Employee management

### **🤖 Automated**
- Daily attendance calculation (6:45 PM)
- Hourly location reminders (10 AM - 6 PM)
- Weekly data cleanup (Sunday 2 AM)
- No manual work needed!

---

## 🚀 Quick Start

### **Option 1: Docker (Recommended)**

```bash
# 1. Clone and navigate
cd Genesis_Employee_Attendance

# 2. Configure environment
cp env.example .env
# Edit .env with your settings

# 3. Start everything
docker-compose up -d

# 4. Setup database
docker-compose exec web python manage.py migrate

# 5. Create admin
docker-compose exec web python manage.py createsuperuser

# 6. Access dashboard
# http://localhost:8000/dashboard/
```

**Done! All services running.** ✅

---

### **Option 2: Manual Installation**

```bash
# 1. Install dependencies
# Windows: install.bat
# Linux/Mac: ./install.sh

# 2. Setup PostgreSQL
createdb genesis_attendance_db
psql genesis_attendance_db -c "CREATE EXTENSION postgis;"

# 3. Configure .env
cp env.example .env
# Edit with your database credentials

# 4. Run setup
python setup.py

# 5. Start services (3 terminals)
python manage.py runserver                    # Terminal 1
celery -A config worker -l info --pool=solo   # Terminal 2
celery -A config beat -l info                 # Terminal 3
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| **[START_HERE.md](START_HERE.md)** ⭐ | **Start here!** Quick overview and first steps |
| [FINAL_SETUP_GUIDE.md](FINAL_SETUP_GUIDE.md) | Detailed setup instructions |
| [API_VIEWS_DOCUMENTATION.md](API_VIEWS_DOCUMENTATION.md) | Complete API reference |
| [DASHBOARD_DOCUMENTATION.md](DASHBOARD_DOCUMENTATION.md) | Dashboard features guide |
| [CELERY_TASKS_DOCUMENTATION.md](CELERY_TASKS_DOCUMENTATION.md) | Automated tasks documentation |
| [COMPLETE_PROJECT_SUMMARY.md](COMPLETE_PROJECT_SUMMARY.md) | Full project overview |

---

## 🏗️ Architecture

```
Mobile App (Location Logging)
        ↓
REST API (JWT Auth)
        ↓
PostgreSQL + PostGIS (Geographic Storage)
        ↓
Celery Tasks (Automated Processing)
        ↓
Web Dashboard (Visualization)
```

---

## 🛠️ Tech Stack

### **Backend**
- Django 4.2
- Django REST Framework
- PostgreSQL 14+ with PostGIS
- Celery 5.3 + Redis
- JWT Authentication

### **Frontend**
- Bootstrap 5
- Leaflet.js (OpenStreetMap)
- jQuery
- Font Awesome

### **DevOps**
- Docker + Docker Compose
- Gunicorn
- Redis

---

## 📊 Project Stats

- **3** Django apps (employees, tracking, attendance)
- **3** core database models
- **16** REST API endpoints
- **4** dashboard pages + login
- **3** automated Celery tasks
- **9** serializers with validation
- **6** HTML templates
- **12** documentation files
- **4000+** lines of code

---

## 🎯 Use Cases

### **Employee Tracking**
- Mobile app logs location every 1-5 minutes
- View real-time locations on dashboard
- Playback route history with timeline

### **Attendance Management**
- Automatic calculation from location logs
- Late detection (>9:30 AM = Late)
- Total hours calculation
- Status determination (Present/Late/Absent)

### **Reporting**
- Daily, weekly, monthly reports
- Department-wise filtering
- CSV export for analysis
- Print functionality

---

## 📱 API Endpoints

### **Authentication**
```bash
POST /api/auth/login/          # Login with JWT
POST /api/auth/register/       # Register employee (admin)
```

### **Location Tracking**
```bash
POST /api/tracking/log-location/       # Log location from mobile
GET  /api/tracking/live-locations/     # Get live locations (admin)
GET  /api/tracking/employee-route/     # Get route history
GET  /api/tracking/my-route-today/     # Get own today's route
```

### **Attendance**
```bash
GET /api/attendance/my-attendance/     # Get own attendance
GET /api/attendance/all/               # Get all (admin)
GET /api/attendance/report/            # Generate reports
```

### **Employees**
```bash
GET /api/employees/me/                 # Get own profile
PUT /api/employees/me/                 # Update profile
GET /api/employees/employees/          # List all (admin)
```

---

## 🌐 Dashboard Pages

- **`/dashboard/`** - Home with statistics
- **`/dashboard/live-tracking/`** - Real-time map
- **`/dashboard/route-history/`** - Route playback
- **`/dashboard/reports/`** - Reports & export

---

## 🤖 Automated Tasks

| Task | Schedule | Purpose |
|------|----------|---------|
| `calculate_daily_attendance` | 6:45 PM daily | Auto-calculate attendance |
| `send_location_reminder` | Hourly (10 AM - 6 PM) | Remind to log location |
| `cleanup_old_locations` | Sunday 2 AM | Delete logs >90 days |

**Timezone:** Asia/Dhaka (GMT+6)

---

## 🔒 Security

- JWT token authentication (API)
- Session authentication (Dashboard)
- Password hashing (automatic)
- Permission-based access control
- CORS configuration
- CSRF protection

---

## 📦 Installation

See **[FINAL_SETUP_GUIDE.md](FINAL_SETUP_GUIDE.md)** for detailed instructions.

**Quick install:**
```bash
# Windows
install.bat

# Linux/Mac
./install.sh
```

---

## 🧪 Testing

```bash
# Run Django tests (using Docker)
docker compose run --rm web python manage.py test tests/

# Test Celery tasks
python test_celery.py
```

For detailed testing instructions, see [TESTING.md](TESTING.md).


---

## 📖 API Documentation

Complete API documentation with examples: **[API_VIEWS_DOCUMENTATION.md](API_VIEWS_DOCUMENTATION.md)**

**Example - Log Location:**
```bash
POST /api/tracking/log-location/
Authorization: Bearer YOUR_TOKEN

{
  "latitude": 23.8103,
  "longitude": 90.4125,
  "timestamp": "2024-01-15T10:30:00Z",
  "accuracy": 10.5,
  "battery_level": 85
}
```

---

## 🎨 Screenshots

### Dashboard Home
![Dashboard](https://via.placeholder.com/800x400/2563eb/ffffff?text=Dashboard+Home+-+Statistics+%26+Recent+Activities)

### Live Tracking
![Live Tracking](https://via.placeholder.com/800x400/10b981/ffffff?text=Live+Tracking+-+Real-time+Employee+Locations)

### Route History
![Route History](https://via.placeholder.com/800x400/f59e0b/ffffff?text=Route+History+-+Playback+with+Timeline)

### Reports
![Reports](https://via.placeholder.com/800x400/ef4444/ffffff?text=Attendance+Reports+-+Daily+Weekly+Monthly)

---

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Built with:
- [Django](https://www.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [PostGIS](https://postgis.net/)
- [Celery](https://docs.celeryproject.org/)
- [Bootstrap](https://getbootstrap.com/)
- [Leaflet.js](https://leafletjs.com/) - [OpenStreetMap](https://www.openstreetmap.org/)

---

## 📞 Support

- 📖 Documentation: See docs in project folder
- 🐛 Issues: Check logs in `logs/` directory
- 💬 Questions: Review documentation files
- 🔧 Troubleshooting: See `FINAL_SETUP_GUIDE.md`

---

## ⭐ Star This Project!

If you find this useful, please star the repository!

---

**Genesis Employee Attendance System**  
*Complete • Production-Ready • Well-Documented*  
*© 2026 - MIT License*

