@echo off
echo ============================================================
echo Starting Genesis Employee Attendance System (Development)
echo ============================================================
echo.

REM Activate virtual environment
if exist venv\Scripts\activate.bat (
    call venv\Scripts\activate.bat
) else (
    echo [ERROR] Virtual environment not found
    echo Please run install.bat first
    pause
    exit /b 1
)

echo Starting Django development server...
echo.
echo Server will be available at: http://localhost:8000
echo Admin panel: http://localhost:8000/admin
echo API root: http://localhost:8000/api/
echo.
echo Press Ctrl+C to stop the server
echo.

python manage.py runserver
