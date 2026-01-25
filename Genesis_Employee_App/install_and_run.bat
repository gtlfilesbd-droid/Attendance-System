@echo off
setlocal EnableDelayedExpansion

echo ========================================================
echo Genesis Employee App - Setup and Run
echo ========================================================

:: 1. Check if flutter is in PATH
where flutter >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [INFO] Flutter found in PATH.
    goto :dependencies
)

:: 2. Check if Flutter is already installed in E:\flutter
if exist "E:\flutter\bin\flutter.bat" (
    echo [INFO] Flutter found in E:\flutter
    set "PATH=E:\flutter\bin;%PATH%"
    goto :dependencies
)

:: 3. Install Flutter if not found
echo [INFO] Flutter not found. Installing via Git...
echo [INFO] Cloning Flutter stable channel to E:\flutter...
mkdir "E:\" 2>nul
cd /d "E:\"
git clone https://github.com/flutter/flutter.git -b stable
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to clone Flutter. Please install Git and try again.
    pause
    exit /b 1
)

set "PATH=E:\flutter\bin;%PATH%"
echo [INFO] Flutter installed successfully.

:dependencies
echo.
echo [1/3] Checking Flutter installation...
call flutter doctor

echo.
echo [2/3] Installing dependencies...
cd /d "E:\Attendance System\Genesis_Employee_App"
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to install dependencies.
    pause
    exit /b 1
)

echo.
echo [3/3] Running the app...
echo Please ensure you have an Android Emulator running or a device connected.
echo.
call flutter run

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [NOTE] App finished or failed to run.
    pause
)
