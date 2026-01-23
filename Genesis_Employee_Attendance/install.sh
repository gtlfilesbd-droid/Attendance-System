#!/bin/bash

echo "============================================================"
echo "Genesis Employee Attendance System - Installation (Linux/Mac)"
echo "============================================================"
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python3 is not installed"
    echo "Please install Python 3.11 or higher"
    exit 1
fi

echo "[1/8] Checking Python version..."
python3 --version

echo ""
echo "[2/8] Creating virtual environment..."
if [ -d "venv" ]; then
    echo "Virtual environment already exists"
else
    python3 -m venv venv
    echo "Virtual environment created"
fi

echo ""
echo "[3/8] Activating virtual environment..."
source venv/bin/activate

echo ""
echo "[4/8] Upgrading pip..."
pip install --upgrade pip

echo ""
echo "[5/8] Installing dependencies..."
pip install -r requirements.txt

echo ""
echo "[6/8] Copying environment file..."
if [ -f ".env" ]; then
    echo ".env file already exists"
else
    if [ -f "env.example" ]; then
        cp env.example .env
        echo ".env file created. Please update it with your settings."
    else
        echo "[WARNING] env.example not found"
    fi
fi

echo ""
echo "[7/8] Creating directories..."
mkdir -p static media logs
echo "Directories created"

echo ""
echo "[8/8] Making scripts executable..."
chmod +x install.sh
chmod +x setup.py

echo ""
echo "============================================================"
echo "Setup complete!"
echo "============================================================"
echo "Next Steps:"
echo "============================================================"
echo "1. Install PostgreSQL with PostGIS extension"
echo "2. Create database: genesis_attendance_db"
echo "3. Enable PostGIS: CREATE EXTENSION postgis;"
echo "4. Update .env file with your database credentials"
echo "5. Run: python setup.py"
echo "6. Start server: python manage.py runserver"
echo "============================================================"
echo ""
