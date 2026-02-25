@echo off
cd /d "%~dp0"
echo Starting Celery Beat (schedule loads from config.settings)...
celery -A config beat -l info
pause
