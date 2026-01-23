@echo off
echo ============================================================
echo Starting Celery Beat for Genesis Employee Attendance
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

echo Starting Celery beat scheduler...
echo.
echo Press Ctrl+C to stop the scheduler
echo.

celery -A config beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler
