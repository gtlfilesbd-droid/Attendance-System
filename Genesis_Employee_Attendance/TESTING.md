# Backend Testing Guide

This project includes a comprehensive test suite for the Django backend API. The tests cover authentication, location logging, live tracking, route history, and attendance calculations.

## Prerequisites

*   **Docker**: The tests are designed to run inside the Docker container to ensure all dependencies (GDAL, PostGIS) are correctly configured.
*   **Running Containers**: The Docker containers must be running.

## Running Tests

### 1. Start Docker Containers
If your containers are not running:
```powershell
.\docker-start.bat
```

### 2. Execute Tests
Run the tests inside the `web` container:
```powershell
docker compose run --rm web python manage.py test tests/
```

## What is Tested?

The test suite (`tests/test_api.py`) covers the following scenarios:

1.  **Authentication**:
    *   `test_employee_login_valid`: Verifies successful login with correct credentials.
    *   `test_employee_login_invalid`: Verifies rejection of incorrect credentials.

2.  **Location Tracking**:
    *   `test_log_location_authenticated`: Verifies an employee can log their location.
    *   `test_log_location_unauthenticated`: Verifies unauthorized requests are rejected.

3.  **Permissions**:
    *   `test_live_locations_admin_only`: Verifies only Admins can access live location data.

4.  **Data Retrieval**:
    *   `test_route_history`: Verifies employees can retrieve their own route history.

5.  **Logic**:
    *   `test_attendance_calculation`: Verifies the daily attendance calculation logic based on first and last location logs.

## Troubleshooting

*   **GDAL Errors**: If you try to run `python manage.py test` directly on Windows without Docker, you will likely see a "Could not find the GDAL library" error. Always use the Docker command above.
*   **Database Errors**: The test runner creates a temporary separate database. If you see connection errors, ensure the `db` container is healthy (`docker ps`).
