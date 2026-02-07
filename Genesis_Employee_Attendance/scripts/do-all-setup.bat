@echo off
REM Do full setup: Docker up, superuser, link employees, then build Flutter APK
setlocal
set ROOT=%~dp0
set BACKEND=%ROOT%..
set APP=%ROOT%..\..\Genesis_Employee_App

echo ============================================================
echo 1. Starting Docker stack (Genesis_Employee_Attendance)
echo ============================================================
cd /d "%BACKEND%"
docker compose up -d
if errorlevel 1 (
  echo Docker compose failed. Is Docker running?
  exit /b 1
)

echo Waiting for web container to be ready (60s)...
timeout /t 60 /nobreak >nul

echo.
echo ============================================================
echo 2. Creating Django superuser (admin / admin@example.com)
echo ============================================================
docker compose exec -T -e DJANGO_SUPERUSER_USERNAME=admin -e DJANGO_SUPERUSER_EMAIL=admin@example.com -e DJANGO_SUPERUSER_PASSWORD=Admin@123 web python manage.py createsuperuser --noinput 2>nul
if errorlevel 1 (
  echo Superuser may already exist, or container not ready. Continuing.
) else (
  echo Superuser created: username=admin password=Admin@123
)

echo.
echo ============================================================
echo 3. Linking employees to Django users
echo ============================================================
docker compose exec -T web python manage.py link_employees_to_users --password Test@123 2>nul
if errorlevel 1 (
  echo link_employees_to_users failed or no employees. Continuing.
)

echo.
echo ============================================================
echo 4. Building Flutter release APK
echo ============================================================
if not exist "%APP%\pubspec.yaml" (
  echo Genesis_Employee_App not found at %APP%. Skip APK build.
  goto :done
)
cd /d "%APP%"
set SHADERS=%APP%\build\app\intermediates\flutter\release\flutter_assets\shaders
if not exist "%SHADERS%" mkdir "%SHADERS%"
call flutter clean
call flutter pub get
call flutter build apk --release
if exist "build\app\outputs\flutter-apk\app-release.apk" (
  echo.
  echo SUCCESS: APK at %APP%\build\app\outputs\flutter-apk\app-release.apk
) else (
  echo APK build may have failed. Check output above.
)

:done
echo.
echo ============================================================
echo Done. Dashboard: http://localhost:8000/dashboard/
echo         or http://YOUR_PC_IP:8000/dashboard/ (replace with your PC IP)
echo Login: admin / Admin@123
echo ============================================================
pause
