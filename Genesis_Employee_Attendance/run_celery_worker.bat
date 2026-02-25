@echo off
cd /d "%~dp0"
echo Starting Celery Worker...
celery -A config worker -l info
pause
