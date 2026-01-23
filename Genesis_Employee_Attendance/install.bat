@echo off
echo ============================================================
echo Genesis Employee Attendance System - Installation (Windows)
echo ============================================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo Please install Python 3.11 or higher from python.org
    pause
    exit /b 1
)

echo [1/8] Checking Python version...
python --version

echo.
echo [2/8] Creating virtual environment...
if exist venv (
    echo Virtual environment already exists
) else (
    python -m venv venv
    echo Virtual environment created
)

echo.
echo [3/8] Activating virtual environment...
call venv\Scripts\activate.bat

echo.
echo [4/8] Upgrading pip...
python -m pip install --upgrade pip

echo.
echo [5/8] Installing dependencies...
pip install -r requirements.txt

echo.
echo [6/8] Copying environment file...
if exist .env (
    echo .env file already exists
) else (
    if exist env.example (
        copy env.example .env
        echo .env file created. Please update it with your settings.
    ) else (
        echo [WARNING] env.example not found
    )
)

echo.
echo [7/8] Creating directories...
if not exist "static\" mkdir static
if not exist "media\" mkdir media
if not exist "logs\" mkdir logs
echo Directories created

echo.
echo [8/8] Setup complete!
echo.
echo ============================================================
echo Next Steps:
echo ============================================================
echo 1. Install PostgreSQL with PostGIS extension
echo 2. Create database: genesis_attendance_db
echo 3. Enable PostGIS: CREATE EXTENSION postgis;
echo 4. Update .env file with your database credentials
echo 5. Run: python setup.py
echo 6. Start server: python manage.py runserver
echo ============================================================
echo.
pause
