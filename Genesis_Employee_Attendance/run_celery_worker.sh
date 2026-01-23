#!/bin/bash

echo "============================================================"
echo "Starting Celery Worker for Genesis Employee Attendance"
echo "============================================================"
echo ""

# Activate virtual environment
if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo "[ERROR] Virtual environment not found"
    echo "Please run ./install.sh first"
    exit 1
fi

echo "Starting Celery worker..."
echo ""
echo "Worker will process tasks from Redis queue"
echo "Press Ctrl+C to stop the worker"
echo ""

celery -A config worker -l info
