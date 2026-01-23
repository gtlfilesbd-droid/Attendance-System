@echo off
echo ========================================
echo Genesis Employee Attendance - Docker Setup
echo ========================================
echo.

REM Refresh PATH to include Docker
set "PATH=%PATH%;C:\Program Files\Docker\Docker\resources\bin"

REM Check if Docker is installed
docker --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Docker is not installed or not in PATH!
    echo.
    echo Docker Desktop may need to be started first.
    echo Please:
    echo 1. Start Docker Desktop from Start Menu
    echo 2. Wait for it to fully start (1-2 minutes)
    echo 3. Close and reopen this window
    echo 4. Try again
    echo.
    pause
    exit /b 1
)

echo [1/5] Checking Docker installation...
docker --version
docker compose version
echo.

echo [2/5] Checking if .env file exists...
if not exist .env (
    echo Creating .env file from env.example...
    copy env.example .env
    echo .env file created. Please edit it if needed.
    echo.
) else (
    echo .env file already exists.
    echo.
)

echo [3/5] Building and starting Docker containers...
docker compose up -d --build
if errorlevel 1 (
    echo.
    echo ERROR: Failed to start Docker containers!
    echo Check the error messages above.
    pause
    exit /b 1
)

echo.
echo [4/5] Waiting for services to be ready...
timeout /t 10 /nobreak >nul

echo.
echo [5/5] Waiting for database to be ready...
timeout /t 15 /nobreak >nul

echo Running database migrations...
docker compose exec web python manage.py migrate
if errorlevel 1 (
    echo.
    echo WARNING: Migrations may have failed. Services are still starting.
    echo Wait 30 seconds and run: docker compose exec web python manage.py migrate
    echo.
) else (
    echo Migrations completed successfully!
    echo.
)

echo.
echo ========================================
echo Setup Complete!
echo ========================================
echo.
echo Services are running:
echo - Web Dashboard: http://localhost:8000/dashboard/
echo - Admin Panel: http://localhost:8000/admin/
echo - API: http://localhost:8000/api/
echo.
echo Next steps:
echo 1. Create superuser: docker compose exec web python manage.py createsuperuser
echo 2. Access dashboard: http://localhost:8000/dashboard/
echo.
echo To stop services: docker compose down
echo To view logs: docker compose logs -f
echo.
pause
