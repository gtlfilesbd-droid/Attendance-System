# Genesis Employee Attendance System - API Documentation

## Authentication

All API endpoints require JWT authentication. First, obtain a token:

### Get JWT Token
```http
POST /api/auth/token/
Content-Type: application/json

{
    "username": "admin",
    "password": "admin123"
}
```

Response:
```json
{
    "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc...",
    "access": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

### Refresh Token
```http
POST /api/auth/token/refresh/
Content-Type: application/json

{
    "refresh": "eyJ0eXAiOiJKV1QiLCJhbGc..."
}
```

### Use Token in Requests
```http
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...
```

## Employee Management API

### List Employees
```http
GET /api/employees/
Authorization: Bearer {token}
```

Query Parameters:
- `department`: Filter by department (IT, HR, FIN, OPS, MKT, SLS)
- `role`: Filter by role (STAFF, MANAGER, ADMIN, EXECUTIVE)
- `is_active_employee`: Filter by active status (true/false)
- `search`: Search by employee_id, name, email
- `ordering`: Sort by field (e.g., `-date_joined_company`)

### Get Current Employee
```http
GET /api/employees/me/
Authorization: Bearer {token}
```

### Create Employee
```http
POST /api/employees/
Authorization: Bearer {token}
Content-Type: application/json

{
    "employee_id": "EMP002",
    "username": "john.doe",
    "email": "john.doe@genesis.com",
    "password": "securepass123",
    "password2": "securepass123",
    "first_name": "John",
    "last_name": "Doe",
    "phone_number": "+1234567890",
    "department": "IT",
    "role": "STAFF",
    "designation": "Software Developer"
}
```

### Get Employee Details
```http
GET /api/employees/{id}/
Authorization: Bearer {token}
```

### Update Employee
```http
PUT /api/employees/{id}/
Authorization: Bearer {token}
Content-Type: application/json

{
    "first_name": "John",
    "last_name": "Doe",
    "phone_number": "+1234567890"
}
```

### Deactivate Employee
```http
POST /api/employees/{id}/deactivate/
Authorization: Bearer {token}
```

## Attendance API

### Check-In
```http
POST /api/attendance/records/check_in/
Authorization: Bearer {token}
Content-Type: application/json

{
    "latitude": 37.7749,
    "longitude": -122.4194,
    "zone_id": 1,
    "is_remote": false,
    "notes": "Checked in from office"
}
```

### Check-Out
```http
POST /api/attendance/records/check_out/
Authorization: Bearer {token}
Content-Type: application/json

{
    "latitude": 37.7749,
    "longitude": -122.4194,
    "zone_id": 1,
    "notes": "Completed work for the day"
}
```

### Get My Attendance
```http
GET /api/attendance/records/my_attendance/?days=30
Authorization: Bearer {token}
```

### Get Attendance Statistics
```http
GET /api/attendance/records/statistics/?days=30
Authorization: Bearer {token}
```

Response:
```json
{
    "period_days": 30,
    "total_days": 22,
    "present_days": 20,
    "absent_days": 1,
    "late_days": 1,
    "total_hours": 176.5,
    "average_hours": 8.03
}
```

### List Attendance Records
```http
GET /api/attendance/records/
Authorization: Bearer {token}
```

Query Parameters:
- `employee`: Filter by employee ID
- `date`: Filter by specific date (YYYY-MM-DD)
- `status`: Filter by status (PRESENT, ABSENT, LATE, etc.)
- `is_remote`: Filter by remote status

## Leave Management API

### Request Leave
```http
POST /api/attendance/leaves/
Authorization: Bearer {token}
Content-Type: application/json

{
    "leave_type": "SICK",
    "start_date": "2026-02-01",
    "end_date": "2026-02-03",
    "reason": "Medical appointment",
    "supporting_documents": null
}
```

Leave Types: `SICK`, `CASUAL`, `ANNUAL`, `MATERNITY`, `PATERNITY`, `UNPAID`, `COMPENSATORY`

### Get My Leaves
```http
GET /api/attendance/leaves/my_leaves/
Authorization: Bearer {token}
```

### Get Leave Balance
```http
GET /api/attendance/leave-balances/my_balance/?year=2026
Authorization: Bearer {token}
```

Response:
```json
{
    "id": 1,
    "employee": 1,
    "employee_name": "John Doe",
    "year": 2026,
    "sick_leave_total": 10,
    "sick_leave_used": 2,
    "sick_leave_remaining": 8,
    "casual_leave_total": 12,
    "casual_leave_used": 3,
    "casual_leave_remaining": 9,
    "annual_leave_total": 20,
    "annual_leave_used": 5,
    "annual_leave_remaining": 15
}
```

### Approve Leave (Admin/Manager)
```http
POST /api/attendance/leaves/{id}/approve/
Authorization: Bearer {token}
```

### Reject Leave (Admin/Manager)
```http
POST /api/attendance/leaves/{id}/reject/
Authorization: Bearer {token}
Content-Type: application/json

{
    "reason": "Insufficient leave balance"
}
```

## Location Tracking API

### Submit Location
```http
POST /api/tracking/locations/
Authorization: Bearer {token}
Content-Type: application/json

{
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy": 10.5,
    "altitude": 15.2,
    "speed": 0.0,
    "heading": 0.0,
    "battery_level": 85,
    "is_mock_location": false,
    "provider": "GPS"
}
```

### Get My Location History
```http
GET /api/tracking/locations/my_locations/?days=7
Authorization: Bearer {token}
```

### Get Latest Locations
```http
GET /api/tracking/locations/latest/
Authorization: Bearer {token}
```

Returns the latest location for all employees.

### Find Nearby Employees
```http
GET /api/tracking/locations/nearby/?latitude=37.7749&longitude=-122.4194&radius=1000
Authorization: Bearer {token}
```

Parameters:
- `latitude`: Your latitude
- `longitude`: Your longitude
- `radius`: Search radius in meters (default: 1000)

## Geofence API

### List Geofence Zones
```http
GET /api/tracking/geofence-zones/
Authorization: Bearer {token}
```

### Create Geofence Zone (Admin)
```http
POST /api/tracking/geofence-zones/
Authorization: Bearer {token}
Content-Type: application/json

{
    "name": "Main Office",
    "zone_type": "OFFICE",
    "description": "Main office building",
    "center_point": {
        "type": "Point",
        "coordinates": [-122.4194, 37.7749]
    },
    "radius": 100,
    "is_active": true,
    "requires_checkin": true,
    "allowed_departments": ["IT", "HR", "FIN"]
}
```

Zone Types: `OFFICE`, `WAREHOUSE`, `SITE`, `BRANCH`, `OTHER`

### Check if Point is Inside Geofence
```http
POST /api/tracking/geofence-zones/{id}/check_inside/
Authorization: Bearer {token}
Content-Type: application/json

{
    "latitude": 37.7749,
    "longitude": -122.4194
}
```

Response:
```json
{
    "zone": "Main Office",
    "is_inside": true
}
```

### Get Geofence Events
```http
GET /api/tracking/geofence-events/my_events/?days=7
Authorization: Bearer {token}
```

## Movement & Routes API

### Get My Movement Summary
```http
GET /api/tracking/movements/my_movements/?days=30
Authorization: Bearer {token}
```

### Get Movement Statistics
```http
GET /api/tracking/movements/statistics/?days=30
Authorization: Bearer {token}
```

Response:
```json
{
    "total_days": 22,
    "total_distance_km": 245.8,
    "avg_distance_km": 11.17,
    "total_locations": 1584
}
```

### Get My Routes
```http
GET /api/tracking/routes/my_routes/?days=30
Authorization: Bearer {token}
```

## Holidays API

### List Holidays
```http
GET /api/attendance/holidays/
Authorization: Bearer {token}
```

### Get Upcoming Holidays
```http
GET /api/attendance/holidays/upcoming/
Authorization: Bearer {token}
```

### Create Holiday (Admin)
```http
POST /api/attendance/holidays/
Authorization: Bearer {token}
Content-Type: application/json

{
    "name": "New Year's Day",
    "date": "2026-01-01",
    "description": "Public Holiday",
    "is_mandatory": true
}
```

## Alerts API

### Get My Alerts
```http
GET /api/attendance/alerts/my_alerts/
Authorization: Bearer {token}
```

### List All Alerts
```http
GET /api/attendance/alerts/
Authorization: Bearer {token}
```

Query Parameters:
- `employee`: Filter by employee
- `alert_type`: Filter by type (LATE, EARLY_EXIT, ABSENT, MISSING_CHECKOUT, OVERTIME, GEOFENCE_VIOLATION)
- `severity`: Filter by severity (LOW, MEDIUM, HIGH)
- `is_resolved`: Filter by resolution status

### Resolve Alert
```http
POST /api/attendance/alerts/{id}/resolve/
Authorization: Bearer {token}
Content-Type: application/json

{
    "notes": "Issue resolved with employee"
}
```

## Error Responses

All endpoints may return the following error responses:

### 400 Bad Request
```json
{
    "error": "Invalid request parameters",
    "details": {
        "field": ["Error message"]
    }
}
```

### 401 Unauthorized
```json
{
    "detail": "Authentication credentials were not provided."
}
```

### 403 Forbidden
```json
{
    "detail": "You do not have permission to perform this action."
}
```

### 404 Not Found
```json
{
    "detail": "Not found."
}
```

### 500 Internal Server Error
```json
{
    "error": "Internal server error"
}
```

## Pagination

List endpoints return paginated results:

```json
{
    "count": 100,
    "next": "http://api.example.com/api/employees/?page=2",
    "previous": null,
    "results": [...]
}
```

Query Parameters:
- `page`: Page number (default: 1)
- `page_size`: Items per page (default: 50, max: 100)

## Rate Limiting

API endpoints are rate-limited to prevent abuse. Default limits:
- Authenticated users: 1000 requests per hour
- Anonymous users: 100 requests per hour

Rate limit headers:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1640000000
```
