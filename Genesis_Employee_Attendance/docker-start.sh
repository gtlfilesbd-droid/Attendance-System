#!/bin/bash

echo "========================================"
echo "Genesis Employee Attendance - Docker Setup"
echo "========================================"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed!"
    echo ""
    echo "Please install Docker from:"
    echo "https://www.docker.com/products/docker-desktop/"
    echo ""
    exit 1
fi

echo "[1/5] Checking Docker installation..."
docker --version
docker compose version
echo ""

echo "[2/5] Checking if .env file exists..."
if [ ! -f .env ]; then
    echo "Creating .env file from env.example..."
    cp env.example .env
    echo ".env file created. Please edit it if needed."
    echo ""
else
    echo ".env file already exists."
    echo ""
fi

echo "[3/5] Building and starting Docker containers..."
docker compose up -d --build
if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Failed to start Docker containers!"
    echo "Check the error messages above."
    exit 1
fi

echo ""
echo "[4/5] Waiting for services to be ready..."
sleep 15

echo ""
echo "[5/5] Running database migrations..."
docker compose exec web python manage.py migrate
if [ $? -ne 0 ]; then
    echo ""
    echo "WARNING: Migrations may have failed. Services are still starting."
    echo "Wait 30 seconds and run: docker compose exec web python manage.py migrate"
    echo ""
else
    echo "Migrations completed successfully!"
    echo ""
fi

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Services are running:"
echo "- Web Dashboard: http://localhost:8000/dashboard/"
echo "- Admin Panel: http://localhost:8000/admin/"
echo "- API: http://localhost:8000/api/"
echo ""
echo "Next steps:"
echo "1. Create superuser: docker compose exec web python manage.py createsuperuser"
echo "2. Access dashboard: http://localhost:8000/dashboard/"
echo ""
echo "To stop services: docker compose down"
echo "To view logs: docker compose logs -f"
echo ""
