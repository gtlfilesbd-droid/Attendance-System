# Genesis Employee Attendance - API Views Documentation

## ✅ All API Endpoints Created

Complete Django REST Framework API views with JWT authentication, proper permissions, and pagination.

---

## 🔐 Authentication Endpoints

### **POST** `/api/auth/login/`
**Employee login with JWT token generation**

**Permission:** `AllowAny`

**Request Body:**
```json
{
    "email": "john@example.com",
    "password": "password123"
}
```

**Response (200):**
```json
{
    "success": true,
    "message": "Login successful",
    "data": {
        "access": "eyJ0eXAiOiJKV1QiLCJhbGc...",
        "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc...",
        "employee": {
            "id": "uuid",
            "employee_id": "EMP001",
            "name": "John Doe",
            "email": "john@example.com",
            ...
        }
    }
}
```

---

### **POST** `/api/auth/register/`
**Register new employee (Admin only)**

**Permission:** `IsAdminUser`

**Request Body:**
```json
{
    "employee_id": "EMP002",
    "name": "Jane Smith",
    "email": "jane@example.com",
    "password": "password123",
    "phone": "+1234567890",
    "department": "IT",
    "designation": "Developer",
    "join_date": "2024-01-15",
    "is_active": true
}
```

**Response (201):**
```json
{
    "success": true,
    "message": "Employee registered successfully",
    "data": {
        "id": "uuid",
        "employee_id": "EMP002",
        ...
    }
}
```

---

## 👥 Employee Management Endpoints

### **GET** `/api/employees/me/`
**Get current employee profile**

**Permission:** `IsAuthenticated`

**Response (200):**
```json
{
    "success": true,
    "data": {
        "id": "uuid",
        "employee_id": "EMP001",
        "name": "John Doe",
        "email": "john@example.com",
        "phone": "+1234567890",
        "department": "IT",
        "designation": "Developer",
        "account_age_days": 45,
        "is_new_employee": true,
        ...
    }
}
```

---

### **PUT/PATCH** `/api/employees/me/`
**Update current employee profile**

**Permission:** `IsAuthenticated`

**Request Body:**
```json
{
    "phone": "+1987654321",
    "designation": "Senior Developer"
}
```

**Response (200):**
```json
{
    "success": true,
    "message": "Profile updated successfully",
    "data": {
        ...
    }
}
```

---

### **GET** `/api/employees/employees/`
**List all employees (Admin only)**

**Permission:** `IsAdminUser`

**Query Parameters:**
- `department` - Filter by department
- `designation` - Filter by designation
- `is_active` - Filter by active status
- `page` - Page number
- `page_size` - Items per page (default: 50, max: 100)

**Response (200):**
```json
{
    "success": true,
    "data": [
        {
            "id": "uuid",
            "employee_id": "EMP001",
            "name": "John Doe",
            ...
        },
        ...
    ],
    "count": 100,
    "next": "http://api/employees/employees/?page=2",
    "previous": null
}
```

---

## 📍 Location Tracking Endpoints

### **POST** `/api/tracking/log-location/`
**Log location from mobile app**

**Permission:** `IsAuthenticated`

**Request Body:**
```json
{
    "employee": "uuid",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "timestamp": "2024-01-15T10:30:00Z",
    "accuracy": 10.5,
    "battery_level": 85,
    "speed": 2.5,
    "address": "123 Main St, San Francisco"
}
```

**Features:**
- ✅ Validates employee token
- ✅ Validates coordinates
- ✅ Validates timestamp (not future)
- ✅ Converts lat/lng to PostGIS Point
- ✅ Auto-sets employee from JWT if not provided

**Response (201):**
```json
{
    "success": true,
    "message": "Location logged successfully",
    "data": {
        "id": 123,
        "employee": "uuid",
        "employee_name": "John Doe",
        "latitude": 37.7749,
        "longitude": -122.4194,
        ...
    }
}
```

---

### **GET** `/api/tracking/live-locations/`
**Get latest locations (last 15 minutes) - Admin only**

**Permission:** `IsAdminUser`

**Features:**
- ✅ Returns all active employees' last location
- ✅ Format optimized for Leaflet.js/OpenStreetMap
- ✅ Includes employee details
- ✅ Calculates minutes since last update

**Response (200):**
```json
{
    "success": true,
    "data": {
        "locations": [
            {
                "employee_id": "uuid",
                "employee_name": "John Doe",
                "employee_code": "EMP001",
                "department": "IT",
                "designation": "Developer",
                "latitude": 37.7749,
                "longitude": -122.4194,
                "accuracy": 10.5,
                "battery_level": 85,
                "speed": 2.5,
                "address": "123 Main St",
                "timestamp": "2024-01-15T10:30:00Z",
                "minutes_ago": 5
            },
            ...
        ],
        "count": 10,
        "last_updated": "2024-01-15T10:45:00Z",
        "time_window_minutes": 15
    }
}
```

---

### **GET** `/api/tracking/employee-route/`
**Get employee route history**

**Permission:** `IsAuthenticated` (own route) or `IsAdminUser` (any employee)

**Query Parameters:**
- `employee_id` (UUID, required)
- `date` (YYYY-MM-DD, optional - default: today)
- `start_time` (HH:MM:SS, optional - default: 00:00:00)
- `end_time` (HH:MM:SS, optional - default: 23:59:59)

**Features:**
- ✅ Returns chronological list of locations
- ✅ Calculates total distance traveled
- ✅ Calculates total duration
- ✅ Returns first and last location
- ✅ Permission check (admin or self)

**Response (200):**
```json
{
    "success": true,
    "data": {
        "employee": "uuid",
        "employee_name": "John Doe",
        "employee_email": "john@example.com",
        "start_datetime": "2024-01-15T00:00:00Z",
        "end_datetime": "2024-01-15T23:59:59Z",
        "total_locations": 45,
        "first_location": {
            "timestamp": "2024-01-15T09:00:00Z",
            "latitude": 37.7749,
            "longitude": -122.4194
        },
        "last_location": {
            "timestamp": "2024-01-15T17:30:00Z",
            "latitude": 37.7850,
            "longitude": -122.4300
        },
        "locations": [...],
        "total_distance_meters": 5420.5,
        "total_distance_km": 5.42,
        "duration_minutes": 510.0
    }
}
```

---

### **GET** `/api/tracking/my-route-today/`
**Get employee's own today's route**

**Permission:** `IsAuthenticated`

**Response (200):**
Same format as `/employee-route/` but automatically for current employee and today's date.

---

### **GET** `/api/tracking/location-logs/my-logs/`
**Get own location logs**

**Permission:** `IsAuthenticated`

**Query Parameters:**
- `days` (int, optional - default: 7)
- `start_date` (YYYY-MM-DD, optional)
- `end_date` (YYYY-MM-DD, optional)
- `page` - Page number
- `page_size` - Items per page (default: 100, max: 500)

**Response (200):**
```json
{
    "success": true,
    "data": [
        {
            "id": 123,
            "employee": "uuid",
            "employee_name": "John Doe",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "timestamp": "2024-01-15T10:30:00Z",
            ...
        },
        ...
    ],
    "count": 500,
    "next": "...",
    "previous": null
}
```

---

## 📊 Attendance Endpoints

### **GET** `/api/attendance/my-attendance/`
**Get employee's own attendance records**

**Permission:** `IsAuthenticated`

**Query Parameters:**
- `start_date` (YYYY-MM-DD, optional - default: 30 days ago)
- `end_date` (YYYY-MM-DD, optional - default: today)
- `status` (optional - PRESENT, LATE, HALF_DAY, ABSENT)

**Response (200):**
```json
{
    "success": true,
    "data": {
        "records": [
            {
                "id": 1,
                "employee": "uuid",
                "employee_name": "John Doe",
                "date": "2024-01-15",
                "check_in_time": "09:00:00",
                "check_out_time": "17:30:00",
                "total_hours": 8.5,
                "status": "PRESENT",
                ...
            },
            ...
        ],
        "summary": {
            "total_days": 20,
            "present_count": 18,
            "late_count": 1,
            "half_day_count": 0,
            "absent_count": 1,
            "total_hours": 153.5,
            "average_hours": 7.675
        },
        "date_range": {
            "start_date": "2023-12-15",
            "end_date": "2024-01-15"
        }
    }
}
```

---

### **GET** `/api/attendance/all/`
**Get all employees' attendance (Admin only)**

**Permission:** `IsAdminUser`

**Query Parameters:**
- `date` (YYYY-MM-DD, optional) - Specific date
- `start_date` (YYYY-MM-DD, optional)
- `end_date` (YYYY-MM-DD, optional)
- `department` (optional) - Filter by department
- `status` (optional) - Filter by status
- `employee_id` (UUID, optional) - Specific employee
- `page` - Page number
- `page_size` - Items per page (default: 50, max: 200)

**Features:**
- ✅ Filtering by date, department, status, employee
- ✅ Pagination
- ✅ Includes employee details
- ✅ Quality assessments (location tracking, overtime, etc.)

**Response (200):**
```json
{
    "success": true,
    "data": [
        {
            "id": 1,
            "employee": "uuid",
            "employee_details": {
                "id": "uuid",
                "name": "John Doe",
                "email": "john@example.com",
                "department": "IT",
                ...
            },
            "date": "2024-01-15",
            "status": "PRESENT",
            "duration_hours": "8h 30m",
            "location_tracking_quality": "Good",
            "is_complete": true,
            "is_overtime": true,
            ...
        },
        ...
    ],
    "count": 100,
    "next": "...",
    "previous": null
}
```

---

### **GET** `/api/attendance/report/`
**Generate attendance reports (Admin only)**

**Permission:** `IsAdminUser`

**Query Parameters:**
- `report_type` (required) - 'daily', 'weekly', or 'monthly'
- `date` (YYYY-MM-DD, optional - default: today)
- `department` (optional) - Filter by department
- `format` (optional) - 'json' (default) or 'summary'

#### Daily Report
**Query:** `?report_type=daily&date=2024-01-15`

**Response:**
```json
{
    "success": true,
    "report_type": "daily",
    "date": "2024-01-15",
    "summary": {
        "total_employees": 100,
        "present_count": 85,
        "late_count": 5,
        "half_day_count": 3,
        "absent_count": 7,
        "present_percentage": 85.0,
        "average_hours_worked": 8.25,
        "total_hours_worked": 701.25,
        "overtime_count": 12,
        "total_location_logs": 2125
    },
    "records": [...]
}
```

#### Weekly Report
**Query:** `?report_type=weekly&date=2024-01-15`

**Response:**
```json
{
    "success": true,
    "report_type": "weekly",
    "summary": {
        "start_date": "2024-01-09",
        "end_date": "2024-01-15",
        "total_working_days": 7,
        "average_present_percentage": 87.5,
        "total_hours_worked": 4908.75,
        "average_daily_hours": 8.15,
        "total_overtime_instances": 84
    },
    "daily_breakdowns": [...]
}
```

#### Monthly Report
**Query:** `?report_type=monthly&date=2024-01-15`

**Response:**
```json
{
    "success": true,
    "report_type": "monthly",
    "summary": {
        "month": "January 2024",
        "start_date": "2024-01-01",
        "end_date": "2024-01-31",
        "working_days": 31,
        "total_employees": 100,
        "total_attendance_records": 2170,
        "present_count": 1850,
        "late_count": 105,
        "half_day_count": 65,
        "absent_count": 150,
        "total_hours_worked": 15127.5,
        "average_hours_per_day": 6.97
    }
}
```

---

## 🔒 Permissions Summary

### Authentication Endpoints
- `POST /api/auth/login/` - **AllowAny**
- `POST /api/auth/register/` - **IsAdminUser**

### Employee Endpoints
- `GET /api/employees/me/` - **IsAuthenticated**
- `PUT /api/employees/me/` - **IsAuthenticated**
- `GET /api/employees/employees/` - **IsAdminUser**
- `POST /api/employees/employees/` - **IsAdminUser**
- `PUT /api/employees/employees/{id}/` - **IsAdminUser** or **Self**
- `DELETE /api/employees/employees/{id}/` - **IsAdminUser**

### Tracking Endpoints
- `POST /api/tracking/log-location/` - **IsAuthenticated**
- `GET /api/tracking/live-locations/` - **IsAdminUser**
- `GET /api/tracking/employee-route/` - **IsAuthenticated** (own) or **IsAdminUser** (any)
- `GET /api/tracking/my-route-today/` - **IsAuthenticated**
- `GET /api/tracking/location-logs/my-logs/` - **IsAuthenticated**

### Attendance Endpoints
- `GET /api/attendance/my-attendance/` - **IsAuthenticated**
- `GET /api/attendance/all/` - **IsAdminUser**
- `GET /api/attendance/report/` - **IsAdminUser**
- `POST /api/attendance/attendance/` - **IsAdminUser**
- `PUT /api/attendance/attendance/{id}/` - **IsAdminUser**
- `DELETE /api/attendance/attendance/{id}/` - **IsAdminUser**

---

## 📄 Pagination

All list endpoints support pagination:

**Query Parameters:**
- `page` - Page number (default: 1)
- `page_size` - Items per page

**Default Page Sizes:**
- Employees: 50 items (max: 100)
- Locations: 100 items (max: 500)
- Attendance: 50 items (max: 200)

**Response Format:**
```json
{
    "success": true,
    "data": [...],
    "count": 500,
    "next": "http://api/endpoint/?page=2",
    "previous": null
}
```

---

## 🔧 Error Responses

### 400 Bad Request
```json
{
    "success": false,
    "message": "Invalid request",
    "errors": {
        "field": ["Error message"]
    }
}
```

### 401 Unauthorized
```json
{
    "success": false,
    "message": "Authentication credentials were not provided"
}
```

### 403 Forbidden
```json
{
    "success": false,
    "message": "You do not have permission to perform this action"
}
```

### 404 Not Found
```json
{
    "success": false,
    "message": "Not found"
}
```

---

## 📝 Response Format

All API responses follow a consistent format:

**Success:**
```json
{
    "success": true,
    "data": {...} or [...]
}
```

**Error:**
```json
{
    "success": false,
    "message": "Error message",
    "errors": {...}
}
```

---

## 🚀 Usage Examples

### Login
```bash
curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"john@example.com","password":"password123"}'
```

### Log Location (Mobile App)
```bash
curl -X POST http://localhost:8000/api/tracking/log-location/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 37.7749,
    "longitude": -122.4194,
    "timestamp": "2024-01-15T10:30:00Z",
    "accuracy": 10.5,
    "battery_level": 85
  }'
```

### Get My Route Today
```bash
curl -X GET http://localhost:8000/api/tracking/my-route-today/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Get My Attendance
```bash
curl -X GET http://localhost:8000/api/attendance/my-attendance/?start_date=2024-01-01&end_date=2024-01-31 \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### Generate Daily Report (Admin)
```bash
curl -X GET http://localhost:8000/api/attendance/report/?report_type=daily&date=2024-01-15 \
  -H "Authorization: Bearer ADMIN_ACCESS_TOKEN"
```

---

## ✅ Features Summary

### Authentication ✓
- JWT token-based authentication
- Login with email/password
- Employee registration (admin only)
- Token validation on all protected endpoints

### Employee Management ✓
- View own profile
- Update own profile
- List all employees (admin)
- Filter by department, designation, status
- Pagination support

### Location Tracking ✓
- Log location from mobile app
- Real-time live locations (admin)
- Employee route history with distance calculation
- My route today
- Location logs with pagination
- PostGIS Point storage
- Leaflet.js/OpenStreetMap compatible format

### Attendance Management ✓
- My attendance with summary
- All attendance (admin with filters)
- Daily/Weekly/Monthly reports
- Department-wise filtering
- Status filtering
- Date range queries
- Statistics and calculations

### Permissions ✓
- IsAuthenticated
- IsAdminUser
- Self-only access checks
- Proper 403 responses

### Pagination ✓
- Configurable page sizes
- Next/Previous links
- Total count
- Applied to all list endpoints

---

## 📊 Total Endpoints Created

- **Authentication:** 2 endpoints
- **Employee Management:** 5 endpoints
- **Location Tracking:** 5 endpoints
- **Attendance:** 4 endpoints

**Total: 16 API endpoints** 🎉

All endpoints are production-ready with proper error handling, validation, permissions, and documentation!
