@echo off
setlocal EnableDelayedExpansion

echo ========================================================
echo Genesis Employee App - Run Tests
echo ========================================================

:: 1. Check if flutter is in PATH
where flutter >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [INFO] Flutter found in PATH.
    goto :run_tests
)

:: 2. Use E:\flutter if present
if exist "E:\flutter\bin\flutter.bat" (
    echo [INFO] Using Flutter from E:\flutter
    set "PATH=E:\flutter\bin;%PATH%"
    goto :run_tests
)

echo [ERROR] Flutter not found. Run install_and_run.bat first or add Flutter to PATH.
pause
exit /b 1

:run_tests
cd /d "%~dp0"

echo.
echo [1/2] Getting dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] flutter pub get failed.
    pause
    exit /b 1
)

echo.
echo [2/2] Running unit and widget tests...
call flutter test test/unit test/widget test/helpers
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Some tests failed.
    pause
    exit /b 1
)

echo.
echo [OK] All tests passed.
echo.
echo To run integration tests (device/emulator): flutter test integration_test/
echo To run only fast tests: flutter test test/unit/working_hours_test.dart
pause
