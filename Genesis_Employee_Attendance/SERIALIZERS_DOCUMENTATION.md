# Genesis Employee Attendance - Serializers Documentation

## ✅ All Serializers Created

Complete Django REST Framework serializers with proper validations, custom methods, and field handling.

---

## 📦 employees/serializers.py

### 1. **EmployeeSerializer**
Complete serializer with all Employee model fields.

**Fields:**
- `id` (UUID, read-only)
- `employee_id` (unique, validated)
- `name`
- `email` (unique, validated)
- `phone`
- `password` (write-only, auto-hashed)
- `department`
- `designation`
- `join_date`
- `is_active`
- `profile_picture`
- `created_at`, `updated_at` (read-only)

**Features:**
- ✅ Automatic password hashing on create/update
- ✅ Email uniqueness validation
- ✅ Employee ID uniqueness validation
- ✅ Password write-only field
- ✅ Handles both create and update operations

**Usage:**
```python
# Create employee
data = {
    'employee_id': 'EMP001',
    'name': 'John Doe',
    'email': 'john@example.com',
    'password': 'securepass123',
    'phone': '+1234567890',
    'department': 'IT',
    'designation': 'Developer',
    'join_date': '2024-01-15',
    'is_active': True
}
serializer = EmployeeSerializer(data=data)
if serializer.is_valid():
    employee = serializer.save()  # Password auto-hashed
```

---

### 2. **EmployeeLoginSerializer**
Serializer for employee authentication.

**Fields:**
- `email` (required)
- `password` (required, write-only)

**Features:**
- ✅ Validates email and password
- ✅ Checks if employee exists
- ✅ Verifies password hash
- ✅ Checks if employee is active
- ✅ Returns employee object in validated data

**Usage:**
```python
# Login validation
data = {
    'email': 'john@example.com',
    'password': 'securepass123'
}
serializer = EmployeeLoginSerializer(data=data)
if serializer.is_valid():
    employee = serializer.validated_data['employee']
    # Generate token or session
```

---

### 3. **EmployeeProfileSerializer**
Employee profile without password (for public/safe display).

**Fields:**
- All employee fields except `password`
- `account_age_days` (computed)
- `is_new_employee` (computed - joined within 90 days)

**Features:**
- ✅ Excludes sensitive password field
- ✅ Calculates account age in days
- ✅ Identifies new employees (<90 days)
- ✅ Read-only for critical fields (id, employee_id, email)

**Usage:**
```python
# Get employee profile
employee = Employee.objects.get(id=employee_id)
serializer = EmployeeProfileSerializer(employee)
return Response(serializer.data)
```

---

## 📍 tracking/serializers.py

### 1. **LocationLogSerializer**
Complete serializer with all LocationLog fields including employee details.

**Fields:**
- `id` (read-only)
- `employee`
- `employee_name` (from employee.name, read-only)
- `employee_email` (from employee.email, read-only)
- `location` (PostGIS Point)
- `latitude` (computed from location, read-only)
- `longitude` (computed from location, read-only)
- `timestamp`
- `accuracy` (validated: 0-1000 meters)
- `battery_level` (validated: 0-100)
- `speed` (optional, validated: >= 0)
- `address` (optional)
- `created_at` (read-only)

**Features:**
- ✅ GeoJSON support via GeoFeatureModelSerializer
- ✅ Automatic lat/lng extraction from Point
- ✅ Accuracy validation (0-1000 meters)
- ✅ Battery level validation (0-100%)
- ✅ Speed validation (non-negative)
- ✅ Employee name and email included

**Usage:**
```python
# Get location logs with employee info
locations = LocationLog.objects.filter(employee=employee_id)
serializer = LocationLogSerializer(locations, many=True)
return Response(serializer.data)
```

---

### 2. **LocationCreateSerializer**
Optimized for mobile app to send location data.

**Input Fields:**
- `employee` (UUID, required)
- `latitude` (required, -90 to 90)
- `longitude` (required, -180 to 180)
- `timestamp` (required, cannot be future)
- `accuracy` (required, >= 0)
- `battery_level` (required, 0-100)
- `speed` (optional, >= 0)
- `address` (optional)

**Features:**
- ✅ Accepts lat/lng and converts to PostGIS Point
- ✅ Validates employee exists and is active
- ✅ Validates coordinate ranges
- ✅ Validates timestamp is not in future
- ✅ Returns LocationLogSerializer format on success

**Usage:**
```python
# Mobile app sends location
data = {
    'employee': 'uuid-here',
    'latitude': 37.7749,
    'longitude': -122.4194,
    'timestamp': '2024-01-15T10:30:00Z',
    'accuracy': 10.5,
    'battery_level': 85,
    'speed': 0.0,
    'address': '123 Main St, San Francisco'
}
serializer = LocationCreateSerializer(data=data)
if serializer.is_valid():
    location_log = serializer.save()
    # Returns full LocationLogSerializer representation
```

---

### 3. **RouteHistorySerializer**
Aggregated route data for a specific date/time range.

**Fields:**
- `employee` (UUID, input)
- `employee_name` (read-only)
- `employee_email` (read-only)
- `start_datetime` (input, required)
- `end_datetime` (input, required)
- `total_locations` (computed)
- `first_location` (dict with timestamp, lat, lng)
- `last_location` (dict with timestamp, lat, lng)
- `locations` (array of LocationLogSerializer)
- `total_distance_meters` (computed)
- `total_distance_km` (computed)
- `duration_minutes` (computed)

**Features:**
- ✅ Validates date range (max 7 days)
- ✅ Calculates total distance traveled
- ✅ Calculates duration between first and last location
- ✅ Returns all location logs in range
- ✅ Static method `get_route_history()` for easy usage

**Usage:**
```python
# Get employee route for a day
from datetime import datetime

data = RouteHistorySerializer.get_route_history(
    employee_id='uuid-here',
    start_datetime=datetime(2024, 1, 15, 0, 0),
    end_datetime=datetime(2024, 1, 15, 23, 59)
)
serializer = RouteHistorySerializer(data=data)
return Response(serializer.data)
```

---

## 📊 attendance/serializers.py

### 1. **AttendanceSerializer**
Complete serializer with all Attendance model fields.

**Fields:**
- `id` (read-only)
- `employee`
- `employee_name` (from employee.name, read-only)
- `employee_email` (from employee.email, read-only)
- `date` (validated: not in future)
- `first_location_time`
- `last_location_time`
- `check_in_time`
- `check_out_time`
- `total_hours`
- `hours_worked` (alias for total_hours)
- `total_locations_logged`
- `status` (Present, Late, Half-Day, Absent)
- `remarks`
- `created_at`, `updated_at` (read-only)

**Features:**
- ✅ Date validation (not in future)
- ✅ Check-out must be after check-in
- ✅ Last location must be after first location
- ✅ Auto-calculates hours on create if check-in/out present
- ✅ Includes employee name and email

**Usage:**
```python
# Create attendance record
data = {
    'employee': 'uuid-here',
    'date': '2024-01-15',
    'check_in_time': '09:00:00',
    'check_out_time': '17:30:00',
    'first_location_time': '08:55:00',
    'last_location_time': '17:35:00',
    'total_locations_logged': 25,
    'status': 'PRESENT',
    'remarks': 'Regular work day'
}
serializer = AttendanceSerializer(data=data)
if serializer.is_valid():
    attendance = serializer.save()  # Hours auto-calculated
```

---

### 2. **AttendanceReportSerializer**
Detailed attendance report with employee details and computed fields.

**Fields:**
- All AttendanceSerializer fields
- `employee_details` (full EmployeeProfileSerializer)
- `duration_hours` (formatted as "8h 30m")
- `location_tracking_quality` (Poor/Fair/Good/Excellent)
- `is_complete` (boolean - has check-in/out/hours)
- `is_overtime` (boolean - worked >8 hours)

**Features:**
- ✅ Includes full employee profile
- ✅ Human-readable duration format
- ✅ Assesses location tracking quality
- ✅ Identifies complete records
- ✅ Flags overtime work

**Usage:**
```python
# Generate attendance report
attendances = Attendance.objects.filter(date='2024-01-15')
serializer = AttendanceReportSerializer(attendances, many=True)
return Response(serializer.data)
```

**Sample Output:**
```json
{
    "id": 1,
    "employee": "uuid",
    "employee_details": {
        "name": "John Doe",
        "email": "john@example.com",
        "department": "IT",
        ...
    },
    "date": "2024-01-15",
    "duration_hours": "8h 30m",
    "location_tracking_quality": "Good",
    "is_complete": true,
    "is_overtime": true,
    "total_locations_logged": 42,
    ...
}
```

---

### 3. **DailyAttendanceSummarySerializer**
Statistical summary for daily attendance.

**Fields:**
- `date` (input)
- `total_employees` (all active employees)
- `present_count`
- `late_count`
- `half_day_count`
- `absent_count`
- `present_percentage`
- `average_hours_worked`
- `total_hours_worked`
- `overtime_count` (employees who worked >8 hours)
- `total_location_logs`

**Features:**
- ✅ Aggregates data from all attendance records
- ✅ Calculates percentages
- ✅ Computes averages and totals
- ✅ Counts overtime workers
- ✅ Static method `get_daily_summary()` for easy usage

**Usage:**
```python
# Get daily summary
from datetime import date

summary_data = DailyAttendanceSummarySerializer.get_daily_summary(
    date=date(2024, 1, 15)
)
serializer = DailyAttendanceSummarySerializer(data=summary_data)
return Response(serializer.data)
```

**Sample Output:**
```json
{
    "date": "2024-01-15",
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
}
```

---

## 🔒 Validation Summary

### Employee Serializers
- ✅ Email format and uniqueness
- ✅ Employee ID uniqueness
- ✅ Password strength (on creation)
- ✅ Active account check (login)

### Location Serializers
- ✅ Coordinate range validation (-90/90, -180/180)
- ✅ Accuracy range (0-1000 meters)
- ✅ Battery level (0-100%)
- ✅ Speed non-negative
- ✅ Timestamp not in future
- ✅ Employee existence and active status
- ✅ Date range limits (max 7 days for routes)

### Attendance Serializers
- ✅ Date not in future
- ✅ Check-out after check-in
- ✅ Last location after first location
- ✅ Non-negative location counts
- ✅ Proper time formatting

---

## 🎯 Custom Methods

### Employee Serializers
- `create()` - Hash password on employee creation
- `update()` - Hash password on update if provided
- `validate_email()` - Check email uniqueness
- `validate_employee_id()` - Check ID uniqueness
- `get_account_age_days()` - Calculate days since joining
- `get_is_new_employee()` - Check if joined within 90 days

### Location Serializers
- `create()` - Convert lat/lng to PostGIS Point
- `get_route_history()` - Calculate route with distance and duration
- Various validators for coordinates, accuracy, battery

### Attendance Serializers
- `create()` - Auto-calculate hours if check-in/out present
- `get_duration_hours()` - Format hours as "Xh Ym"
- `get_location_tracking_quality()` - Assess tracking quality
- `get_is_complete()` - Check if record is complete
- `get_is_overtime()` - Check if >8 hours worked
- `get_daily_summary()` - Calculate daily statistics

---

## 📝 Usage Examples

### Employee Registration
```python
from employees.serializers import EmployeeSerializer

data = {
    'employee_id': 'EMP001',
    'name': 'Jane Smith',
    'email': 'jane@company.com',
    'password': 'secure123',
    'phone': '+1234567890',
    'department': 'HR',
    'designation': 'HR Manager',
    'join_date': '2024-01-01',
    'is_active': True
}

serializer = EmployeeSerializer(data=data)
if serializer.is_valid():
    employee = serializer.save()
    print(f"Employee created: {employee.id}")
else:
    print(serializer.errors)
```

### Employee Login
```python
from employees.serializers import EmployeeLoginSerializer

data = {
    'email': 'jane@company.com',
    'password': 'secure123'
}

serializer = EmployeeLoginSerializer(data=data)
if serializer.is_valid():
    employee = serializer.validated_data['employee']
    # Generate JWT token or create session
else:
    print(serializer.errors)
```

### Track Location
```python
from tracking.serializers import LocationCreateSerializer

data = {
    'employee': str(employee.id),
    'latitude': 37.7749,
    'longitude': -122.4194,
    'timestamp': timezone.now(),
    'accuracy': 15.0,
    'battery_level': 75,
    'speed': 2.5
}

serializer = LocationCreateSerializer(data=data)
if serializer.is_valid():
    location_log = serializer.save()
    print(f"Location logged: {location_log.id}")
```

### Create Attendance
```python
from attendance.serializers import AttendanceSerializer

data = {
    'employee': str(employee.id),
    'date': date.today(),
    'check_in_time': '09:00:00',
    'check_out_time': '17:30:00',
    'first_location_time': '08:55:00',
    'last_location_time': '17:35:00',
    'total_locations_logged': 30,
    'status': 'PRESENT'
}

serializer = AttendanceSerializer(data=data)
if serializer.is_valid():
    attendance = serializer.save()
    print(f"Total hours: {attendance.total_hours}")  # Auto-calculated
```

### Get Daily Summary
```python
from attendance.serializers import DailyAttendanceSummarySerializer

summary = DailyAttendanceSummarySerializer.get_daily_summary(date.today())
print(f"Present: {summary['present_count']}/{summary['total_employees']}")
print(f"Attendance rate: {summary['present_percentage']}%")
print(f"Average hours: {summary['average_hours_worked']}")
```

---

## ✅ Features Checklist

### Employee Serializers
- ✅ All fields included
- ✅ Password hashing
- ✅ Login validation
- ✅ Profile without password
- ✅ Proper field validations
- ✅ Custom computed fields

### Tracking Serializers
- ✅ All fields with employee name
- ✅ Mobile-optimized create serializer
- ✅ Route history with calculations
- ✅ GeoJSON support
- ✅ Distance and duration calculations
- ✅ Proper validations

### Attendance Serializers
- ✅ All fields included
- ✅ Report with employee details
- ✅ Daily summary with statistics
- ✅ Auto-calculate hours
- ✅ Quality assessments
- ✅ Overtime detection

---

## 🚀 Next Steps

All serializers are ready for use in ViewSets and API endpoints!

**To Use:**
1. Import serializers in views.py
2. Create ViewSets using these serializers
3. Test with actual data
4. Deploy API endpoints

**Files Created:**
- ✅ `employees/serializers.py` - 3 serializers
- ✅ `tracking/serializers.py` - 3 serializers
- ✅ `attendance/serializers.py` - 3 serializers

**Total: 9 Complete Serializers** 🎉
