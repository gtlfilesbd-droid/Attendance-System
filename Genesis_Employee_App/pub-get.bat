@echo off
REM Run from Genesis_Employee_App folder to fetch dependencies (e.g. geocoding).
cd /d "%~dp0"
echo Running flutter pub get...
flutter pub get
if %ERRORLEVEL% neq 0 (
  echo.
  echo If this failed due to network, try again or check your internet/proxy.
  echo If geocoding fails, ensure Dart SDK is 3.0+ (flutter --version).
  pause
  exit /b 1
)
echo Done.
pause
