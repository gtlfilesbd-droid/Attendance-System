@echo off
echo ============================================================
echo Starting Celery Worker for Genesis Employee Attendance
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

echo Starting Celery worker with solo pool (Windows compatible)...
echo.
echo Worker will process tasks from Redis queue
echo Press Ctrl+C to stop the worker
echo.

celery -A config worker -l info --pool=solo
