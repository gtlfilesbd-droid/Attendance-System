# Employee Location Tracking & Attendance System
## Complete Implementation Plan for Cursor AI

---

## 📋 PROJECT OVERVIEW

### System Requirements:
- **Mobile App**: Mandatory for all employees with GPS tracking
- **Working Hours**: 9:30 AM - 6:30 PM (automatic tracking)
- **Location Tracking**: Continuous GPS logging every 5-10 minutes
- **Web Portal**: Real-time monitoring & historical route replay
- **Auto Attendance**: Automatic check-in/check-out calculation
- **Technology**: Python (Django) + Flutter Mobile App

---

## 🏗️ SYSTEM ARCHITECTURE

```
┌─────────────────────────────────────────────────────────────┐
│                    MOBILE APP (Flutter)                      │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Background GPS Service (9:30 AM - 6:30 PM)        │    │
│  │  • Auto-start at 9:30 AM                           │    │
│  │  • Log location every 5 minutes                    │    │
│  │  • Auto-stop at 6:30 PM                            │    │
│  │  • Battery optimized                               │    │
│  └────────────────────────────────────────────────────┘    │
│                           ↓ REST API                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              BACKEND (Python Django + DRF)                   │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │   API Endpoints  │  │  Celery Tasks    │                │
│  │  • Auth          │  │  • Auto calc     │                │
│  │  • Location Log  │  │  • Daily report  │                │
│  │  • Live Track    │  │  • Notifications │                │
│  └──────────────────┘  └──────────────────┘                │
│                           ↓                                  │
│              PostgreSQL + PostGIS Database                   │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Employees   │  │ LocationLogs │  │ Attendance   │      │
│  └─────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                            ↑
┌─────────────────────────────────────────────────────────────┐
│            WEB DASHBOARD (Django + JavaScript)               │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Admin Panel Features:                             │    │
│  │  • Real-time employee location map (Google Maps)   │    │
│  │  • Route history & playback                        │    │
│  │  • Attendance reports (daily/monthly)              │    │
│  │  • Employee management                             │    │
│  │  • Analytics dashboard                             │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 PROJECT STRUCTURE

```
employee-tracking-system/
├── backend/                          # Django Backend
│   ├── config/                       # Django settings
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── celery.py
│   ├── apps/
│   │   ├── employees/                # Employee management
│   │   │   ├── models.py
│   │   │   ├── serializers.py
│   │   │   ├── views.py
│   │   │   └── urls.py
│   │   ├── tracking/                 # Location tracking
│   │   │   ├── models.py
│   │   │   ├── serializers.py
│   │   │   ├── views.py
│   │   │   ├── tasks.py              # Celery tasks
│   │   │   └── urls.py
│   │   └── attendance/               # Attendance management
│   │       ├── models.py
│   │       ├── serializers.py
│   │       ├── views.py
│   │       └── urls.py
│   ├── templates/                    # Web dashboard templates
│   │   ├── dashboard/
│   │   │   ├── index.html            # Main dashboard
│   │   │   ├── live_tracking.html    # Real-time map
│   │   │   ├── route_history.html    # Route playback
│   │   │   └── reports.html          # Attendance reports
│   ├── static/                       # CSS, JS, Images
│   │   ├── css/
│   │   ├── js/
│   │   │   └── map_tracking.js       # Google Maps logic
│   │   └── img/
│   ├── requirements.txt
│   └── manage.py
│
├── mobile_app/                       # Flutter Mobile App
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/
│   │   │   ├── auth_service.dart
│   │   │   ├── location_service.dart # Background GPS tracking
│   │   │   └── api_service.dart
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── home_screen.dart
│   │   │   └── profile_screen.dart
│   │   └── models/
│   │       ├── employee.dart
│   │       └── location.dart
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
│
└── docs/
    ├── API_DOCUMENTATION.md
    ├── DEPLOYMENT_GUIDE.md
    └── USER_MANUAL.md
```

---

## 🚀 STEP-BY-STEP IMPLEMENTATION PLAN

---

### **PHASE 1: Backend Setup (Django)**

#### Step 1.1: Initialize Django Project

**Prompt for Cursor AI:**
```
Create a Django project named "employee_tracking" with the following:

1. Install required packages:
   - Django==4.2
   - djangorestframework
   - django-cors-headers
   - psycopg2-binary
   - django-postgis
   - celery
   - redis
   - django-celery-beat
   - djangorestframework-simplejwt (for authentication)
   - python-decouple (for environment variables)

2. Project structure:
   - Create Django project: config
   - Create apps: employees, tracking, attendance
   - Configure PostgreSQL with PostGIS extension
   - Setup REST Framework
   - Configure CORS for mobile app
   - Setup JWT authentication
   - Create .env file for secrets

3. Settings configuration:
   - Database: PostgreSQL + PostGIS
   - REST Framework settings
   - CORS allowed origins
   - JWT settings
   - Static and media files
   - Celery configuration
```

#### Step 1.2: Create Database Models

**Prompt for Cursor AI:**
```
Create Django models for employee tracking system:

**employees/models.py:**
- Employee model:
  - id (UUID primary key)
  - employee_id (unique, string)
  - name (string)
  - email (unique, email)
  - phone (string)
  - password (hashed)
  - department (string)
  - designation (string)
  - join_date (date)
  - is_active (boolean)
  - profile_picture (image, optional)
  - created_at, updated_at (timestamps)

**tracking/models.py:**
- LocationLog model:
  - id (auto increment)
  - employee (ForeignKey to Employee)
  - location (PointField for lat/long - PostGIS)
  - timestamp (datetime with timezone)
  - accuracy (float, in meters)
  - battery_level (integer, 0-100)
  - speed (float, optional)
  - address (string, optional - reverse geocoded)
  - created_at (auto timestamp)
  - Index on: employee + timestamp

**attendance/models.py:**
- Attendance model:
  - id (auto increment)
  - employee (ForeignKey)
  - date (date, unique with employee)
  - first_location_time (time)
  - last_location_time (time)
  - check_in_time (time)
  - check_out_time (time)
  - total_hours (decimal)
  - total_locations_logged (integer)
  - status (choices: Present, Late, Half-Day, Absent)
  - remarks (text, optional)
  - created_at, updated_at

Add proper Meta classes with indexes and ordering.
Run makemigrations and migrate.
```

#### Step 1.3: Create API Serializers

**Prompt for Cursor AI:**
```
Create Django REST Framework serializers:

**employees/serializers.py:**
- EmployeeSerializer (all fields)
- EmployeeLoginSerializer (email, password)
- EmployeeProfileSerializer (exclude password)

**tracking/serializers.py:**
- LocationLogSerializer (all fields, include employee name)
- LocationCreateSerializer (for mobile app to send location)
- RouteHistorySerializer (employee route for specific date/time range)

**attendance/serializers.py:**
- AttendanceSerializer (all fields)
- AttendanceReportSerializer (with employee details)
- DailyAttendanceSummarySerializer

Use proper field validations and custom methods where needed.
```

#### Step 1.4: Create API Views & Endpoints

**Prompt for Cursor AI:**
```
Create Django REST API views with following endpoints:

**employees/views.py:**
- POST /api/auth/login/ - Employee login (return JWT token)
- POST /api/auth/register/ - Register new employee (admin only)
- GET /api/employees/me/ - Get current employee profile
- PUT /api/employees/me/ - Update profile
- GET /api/employees/ - List all employees (admin only)

**tracking/views.py:**
- POST /api/tracking/log-location/ - Log location from mobile app
  - Validate employee token
  - Save location with timestamp
  - Return success response
  
- GET /api/tracking/live-locations/ - Get latest locations (last 15 min)
  - Admin only
  - Return all active employees' last location
  - Format for Google Maps
  
- GET /api/tracking/employee-route/ - Get employee route history
  - Query params: employee_id, date, start_time, end_time
  - Return list of locations chronologically
  - Include route distance calculation
  
- GET /api/tracking/my-route-today/ - Employee's own today's route

**attendance/views.py:**
- GET /api/attendance/my-attendance/ - Employee's own attendance
  - Query params: start_date, end_date
  
- GET /api/attendance/all/ - All employees attendance (admin)
  - Query params: date, department
  - Filtering and pagination
  
- GET /api/attendance/report/ - Generate attendance report
  - Monthly/weekly reports
  - Export as JSON

Use ViewSets where appropriate. Add proper permissions (IsAuthenticated, IsAdmin).
Add pagination for list endpoints.
```

#### Step 1.5: Setup Celery Tasks for Automation

**Prompt for Cursor AI:**
```
Create Celery tasks for automated attendance calculation:

**config/celery.py:**
- Initialize Celery with Redis as broker
- Configure timezone (Asia/Dhaka)

**tracking/tasks.py:**
Create following Celery tasks:

1. @shared_task calculate_daily_attendance():
   - Run daily at 6:45 PM
   - For each employee:
     - Get all locations for today
     - If locations exist:
       - first_location = earliest location time
       - last_location = latest location time
       - check_in_time = first_location if before 9:45 AM else first_location
       - check_out_time = last_location
       - total_hours = calculate duration
       - status = "Late" if check_in > 9:30 AM else "Present"
       - total_locations_logged = count
     - Create/update Attendance record
   
2. @shared_task send_location_reminder():
   - Run every hour during work hours
   - Check employees who haven't logged location in last 30 minutes
   - (Future: send push notification)

3. @shared_task cleanup_old_locations():
   - Run weekly
   - Delete location logs older than 90 days (keep only recent data)

**config/settings.py:**
Add Celery Beat schedule:
- calculate_daily_attendance: 18:45 every day
- send_location_reminder: every hour from 9:30 to 18:30
- cleanup_old_locations: every Sunday at 2 AM
```

#### Step 1.6: Create Web Dashboard Views

**Prompt for Cursor AI:**
```
Create Django template views for web dashboard:

**tracking/views.py (add these):**
- dashboard_home(request) - Main dashboard
  - Show today's stats: total employees, present, absent, late
  - Recent activities
  - Template: dashboard/index.html

- live_tracking_view(request) - Real-time tracking page
  - Template: dashboard/live_tracking.html
  - Embed Google Maps
  - JavaScript to fetch live locations every 30 seconds

- route_history_view(request) - Route playback
  - Template: dashboard/route_history.html
  - Date picker, employee selector
  - Show route on map with timestamps

- attendance_reports_view(request) - Reports page
  - Template: dashboard/reports.html
  - Date range selector
  - Export to CSV/PDF options

Add login_required decorator. Add proper URL routing.
```

---

### **PHASE 2: Web Dashboard Frontend**

#### Step 2.1: Create Dashboard HTML Templates

**Prompt for Cursor AI:**
```
Create responsive HTML templates using Bootstrap 5 and Google Maps:

**templates/base.html:**
- Base template with navbar, sidebar
- Include Bootstrap 5 CSS/JS
- Include Google Maps API script
- Common header/footer

**templates/dashboard/index.html:**
- Extend base.html
- Dashboard cards showing:
  - Total employees
  - Present today (green card)
  - Late today (yellow card)
  - Absent today (red card)
- Recent location updates table
- Quick stats chart (Chart.js)

**templates/dashboard/live_tracking.html:**
- Extend base.html
- Full-width Google Maps div (height: 80vh)
- Sidebar with employee list (online/offline status)
- Auto-refresh every 30 seconds

**templates/dashboard/route_history.html:**
- Extend base.html
- Top filters: employee dropdown, date picker, time range
- Google Maps to show route polyline
- Timeline of locations below map
- Playback controls (play/pause/speed)

**templates/dashboard/reports.html:**
- Extend base.html
- Filters: date range, department, employee
- Data table with attendance records
- Export buttons (CSV, PDF)
- Charts: attendance trends, punctuality stats

Use modern, clean UI design. Make it mobile responsive.
```

#### Step 2.2: Create JavaScript for Maps & Real-time Updates

**Prompt for Cursor AI:**
```
Create JavaScript for real-time tracking and route playback:

**static/js/map_tracking.js:**

1. Live Tracking Functions:
   - initLiveMap() - Initialize Google Maps
   - fetchLiveLocations() - API call to get latest locations
   - updateMapMarkers(locations) - Update employee markers on map
   - Auto-refresh every 30 seconds using setInterval
   - Custom marker icons (different colors for different statuses)
   - Info windows showing employee name, last update time

2. Route History Functions:
   - initRouteMap() - Initialize map for route playback
   - fetchEmployeeRoute(employeeId, date) - Get route data
   - drawRoute(locations) - Draw polyline on map
   - addRouteMarkers(locations) - Add numbered markers
   - playbackRoute() - Animate marker along route
   - Playback controls: play, pause, stop, speed control

3. Helper Functions:
   - formatTimestamp(timestamp)
   - calculateDistance(locations)
   - fitMapBounds(markers)

Use async/await for API calls. Add error handling. Add loading indicators.
```

---

### **PHASE 3: Mobile App (Flutter)**

#### Step 3.1: Setup Flutter Project

**Prompt for Cursor AI:**
```
Create a Flutter project named "employee_tracking_app" with:

**pubspec.yaml dependencies:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Location tracking
  geolocator: ^10.1.0
  background_location: ^0.12.0
  permission_handler: ^11.0.1
  
  # Background service
  flutter_background_service: ^5.0.5
  workmanager: ^0.5.2
  
  # Networking
  http: ^1.1.0
  dio: ^5.4.0
  
  # Storage
  shared_preferences: ^2.2.2
  flutter_secure_storage: ^9.0.0
  
  # UI
  google_maps_flutter: ^2.5.0
  intl: ^0.18.1
  
  # Utils
  battery_plus: ^5.0.2

Setup Android and iOS permissions in respective manifest files:
- ACCESS_FINE_LOCATION
- ACCESS_COARSE_LOCATION
- ACCESS_BACKGROUND_LOCATION
- FOREGROUND_SERVICE
```

#### Step 3.2: Create Authentication Service

**Prompt for Cursor AI:**
```
Create Flutter authentication service:

**lib/services/auth_service.dart:**
- Class: AuthService (Singleton pattern)
- Methods:
  - Future<bool> login(String email, String password)
    - API call to /api/auth/login/
    - Save JWT token in secure storage
    - Save employee data
    - Return success/failure
  
  - Future<void> logout()
    - Clear all stored data
    - Stop location tracking
  
  - Future<bool> isLoggedIn()
    - Check if token exists and is valid
  
  - Future<String?> getToken()
    - Return stored JWT token
  
  - Future<Map<String, dynamic>?> getEmployeeData()
    - Return employee info from storage

Use flutter_secure_storage for token. Add proper error handling.
```

#### Step 3.3: Create Background Location Service

**Prompt for Cursor AI:**
```
Create Flutter background location tracking service:

**lib/services/location_service.dart:**

Class: LocationService (Singleton)

Methods:
1. Future<void> initializeService()
   - Request permissions (location, background location)
   - Initialize background service
   - Setup notification for foreground service (Android)

2. Future<void> startTracking()
   - Check if current time is within 9:30 AM - 6:30 PM
   - If yes, start background location updates
   - Listen to location changes every 5 minutes or 50 meters
   - Send location to backend API
   - Show persistent notification: "Attendance tracking active"

3. Future<void> stopTracking()
   - Stop location updates
   - Remove notification

4. Future<void> sendLocationToBackend(Position position)
   - Get current position (lat, lng, accuracy)
   - Get battery level
   - API POST to /api/tracking/log-location/
   - Include JWT token in headers
   - Retry on failure (store locally, sync later)

5. bool isWorkingHours()
   - Check if current time is 9:30 AM - 6:30 PM
   - Return true/false

6. void scheduleTracking()
   - Use WorkManager to schedule tasks
   - Check every 5 minutes if working hours
   - Auto-start tracking at 9:30 AM
   - Auto-stop at 6:30 PM

Use flutter_background_service for continuous background tracking.
Add battery optimization handling.
Handle location permission denied scenarios gracefully.
```

#### Step 3.4: Create API Service

**Prompt for Cursor AI:**
```
Create Flutter API service for backend communication:

**lib/services/api_service.dart:**

Class: ApiService (Singleton)

Properties:
- String baseUrl = "https://your-backend.com/api"
- Dio dio instance with interceptors

Methods:
1. Future<Map<String, dynamic>> login(String email, String password)
   - POST /auth/login/
   - Return response

2. Future<bool> logLocation(double lat, double lng, double accuracy, int battery)
   - POST /tracking/log-location/
   - Headers: Authorization: Bearer {token}
   - Body: {employee_id, latitude, longitude, accuracy, battery_level}
   - Return success

3. Future<List<dynamic>> getMyRouteToday()
   - GET /tracking/my-route-today/
   - Return list of locations

4. Future<Map<String, dynamic>> getMyAttendance(String startDate, String endDate)
   - GET /attendance/my-attendance/?start_date=X&end_date=Y
   - Return attendance records

Add Dio interceptors for:
- Adding auth token to all requests
- Error handling
- Retry logic
- Logging (in debug mode)
```

#### Step 3.5: Create Mobile App Screens

**Prompt for Cursor AI:**
```
Create Flutter screens for the mobile app:

**lib/screens/login_screen.dart:**
- Email and password input fields
- Login button
- Show loading indicator during login
- Navigate to HomeScreen on success
- Show error message on failure

**lib/screens/home_screen.dart:**
- AppBar with app name and logout button
- Card showing tracking status:
  - "Tracking Active" (green) or "Tracking Stopped" (red)
  - Current time
  - Locations logged today count
- Button: "View My Attendance"
- Button: "View Today's Route"
- Bottom info: "Your location is tracked 9:30 AM - 6:30 PM"

**lib/screens/attendance_screen.dart:**
- List of attendance records (last 30 days)
- Each item shows: date, check-in, check-out, total hours, status
- Color coding: green (present), yellow (late), red (absent)

**lib/screens/route_map_screen.dart:**
- Show Google Map with today's route
- Polyline connecting all logged locations
- Markers at each location with timestamp
- Distance traveled shown at bottom

**lib/screens/profile_screen.dart:**
- Display employee info (name, ID, department, email)
- Option to update profile picture
- Logout button

Use Material Design 3. Add proper navigation. Handle loading states.
```

#### Step 3.6: Setup Background Service Worker

**Prompt for Cursor AI:**
```
Create background worker for automatic tracking:

**lib/services/background_worker.dart:**

Setup background task using flutter_background_service:

1. Initialize service in main():
   - Configure service with notification
   - Title: "Attendance Tracking"
   - Message: "Your location is being tracked"

2. Background callback function:
   - Runs continuously in background
   - Every 5 minutes:
     - Check if working hours (9:30 AM - 6:30 PM)
     - If yes, get current location
     - Send to backend API
     - Update notification with last update time
   - If not working hours, sleep
   
3. Handle service stop/restart:
   - On app kill, restart service if working hours
   - On device reboot, restart if working hours

**lib/main.dart:**
- Call initializeService() on app start
- Check if logged in
- If yes, start tracking service
- Navigate to appropriate screen

Ensure service runs even when app is closed/killed (Android).
Handle iOS background limitations appropriately.
```

---

### **PHASE 4: Integration & Testing**

#### Step 4.1: Backend Testing

**Prompt for Cursor AI:**
```
Create API tests for Django backend:

**tests/test_api.py:**
- Test employee login (valid/invalid credentials)
- Test location logging (authenticated/unauthenticated)
- Test live locations endpoint
- Test route history endpoint
- Test attendance calculation
- Test API permissions

Run tests: python manage.py test
```

#### Step 4.2: Mobile App Testing

**Prompt for Cursor AI:**
```
Create test scenarios for Flutter app:

1. Test login flow
2. Test background location service
3. Test location sending to backend
4. Test working hours detection
5. Test notification display
6. Test app kill/restart scenarios

Add widget tests for screens.
```

---

### **PHASE 5: Deployment**

#### Step 5.1: Backend Deployment Guide

**Prompt for Cursor AI:**
```
Create deployment configuration:

**Docker setup:**
- Dockerfile for Django app
- docker-compose.yml with:
  - Django service
  - PostgreSQL + PostGIS
  - Redis for Celery
  - Nginx for static files

**Environment variables:**
- DATABASE_URL
- SECRET_KEY
- GOOGLE_MAPS_API_KEY
- ALLOWED_HOSTS
- CORS_ALLOWED_ORIGINS

**Deployment steps:**
1. Setup VPS (DigitalOcean/AWS)
2. Install Docker
3. Clone repository
4. Configure .env
5. Run docker-compose up
6. Run migrations
7. Create superuser
8. Setup SSL with Let's Encrypt
9. Configure domain

Create deployment documentation in docs/DEPLOYMENT_GUIDE.md
```

#### Step 5.2: Mobile App Build & Release

**Prompt for Cursor AI:**
```
Create build configuration:

**Android:**
- Configure app signing in android/app/build.gradle
- Update AndroidManifest.xml with permissions
- Generate signed APK
- Prepare for Play Store release

**iOS:**
- Configure Info.plist with location permissions
- Setup signing in Xcode
- Build for release
- Prepare for App Store

Create release documentation with screenshots and descriptions.
```

---

## 🎯 FINAL DELIVERABLES

After completing all phases, you will have:

✅ **Backend API** (Django + DRF + PostgreSQL + PostGIS)
   - RESTful APIs for authentication, location tracking, attendance
   - Automatic attendance calculation with Celery
   - Admin dashboard

✅ **Web Dashboard** (Django Templates + Google Maps)
   - Real-time employee tracking
   - Route history & playback
   - Attendance reports
   - Analytics

✅ **Mobile App** (Flutter)
   - Cross-platform (Android + iOS)
   - Background location tracking (9:30 AM - 6:30 PM)
   - Auto-start/stop
   - Employee attendance view

✅ **Documentation**
   - API documentation
   - Deployment guide
   - User manual

---

## 📝 TESTING CHECKLIST

Before going live, test:

- [ ] Employee can login via mobile app
- [ ] Location tracking starts at 9:30 AM automatically
- [ ] Location is sent every 5 minutes
- [ ] Location stops at 6:30 PM automatically
- [ ] Admin can see live locations on web dashboard
- [ ] Route history shows correct path
- [ ] Attendance is auto-calculated at 6:30 PM
- [ ] Late arrival is marked correctly
- [ ] App works in background even when closed
- [ ] App works after phone reboot
- [ ] Battery usage is optimized
- [ ] All APIs are secured with authentication

---

## 🚨 IMPORTANT NOTES FOR CURSOR AI

When implementing this system:

1. **Security**: Always use JWT authentication for API endpoints
2. **Privacy**: Store location data securely, implement data retention policy
3. **Battery**: Optimize location tracking to minimize battery drain
4. **Permissions**: Handle permission denials gracefully
5. **Error Handling**: Implement retry logic for failed location uploads
6. **Offline Support**: Store locations locally if backend is unreachable, sync later
7. **Time Zones**: Use UTC in database, convert to local time in UI
8. **Testing**: Test on both slow and fast network conditions
9. **Background Service**: Ensure it runs reliably on different Android versions
10. **iOS Limitations**: Handle iOS background location limitations properly

---

## 📞 NEXT STEPS

Copy each phase's prompt to Cursor AI step by step. After each phase is complete, test thoroughly before moving to the next phase.

Start with: **PHASE 1, Step 1.1** and proceed sequentially.

Good luck! 🚀
