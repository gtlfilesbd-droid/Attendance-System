@echo off
setlocal
cd /d "%~dp0"

echo ========================================================
echo Genesis Employee App - Release Build
echo ========================================================

where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    if exist "E:\flutter\bin\flutter.bat" set "PATH=E:\flutter\bin;%PATH%"
)

echo.
echo Choose platform:
echo   1 = Android (signed APK)
echo   2 = Android (App Bundle for Play Store)
echo   3 = iOS (release build; then archive in Xcode)
set /p choice="Enter 1, 2, or 3: "

if "%choice%"=="1" goto apk
if "%choice%"=="2" goto bundle
if "%choice%"=="3" goto ios
echo Invalid choice.
pause
exit /b 1

:apk
echo.
echo Building signed APK...
if not exist "android\key.properties" (
    echo [WARN] android\key.properties not found. APK will be signed with debug key.
    echo For release signing, copy android\key.properties.example to android\key.properties
    echo and add your keystore details. See docs\BUILD_AND_RELEASE.md
    echo.
)
call flutter build apk --release
if %ERRORLEVEL% equ 0 (
    echo.
    echo [OK] APK: build\app\outputs\flutter-apk\app-release.apk
    echo For production HTTPS, run: flutter build apk --release --dart-define=BASE_URL=https://your-domain.com/api
)
goto end

:bundle
echo.
echo Building App Bundle for Play Store...
if not exist "android\key.properties" (
    echo [WARN] android\key.properties not found. Bundle will be signed with debug key.
    echo For Play Store, create android\key.properties from android\key.properties.example
    echo See docs\BUILD_AND_RELEASE.md
    echo.
)
call flutter build appbundle --release
if %ERRORLEVEL% equ 0 (
    echo.
    echo [OK] AAB: build\app\outputs\bundle\release\app-release.aab
    echo Upload this file to Google Play Console.
    echo For production HTTPS, run: flutter build appbundle --release --dart-define=BASE_URL=https://your-domain.com/api
)
goto end

:ios
echo.
echo Building iOS release...
call flutter build ios --release
if %ERRORLEVEL% equ 0 (
    echo.
    echo [OK] Open ios\Runner.xcworkspace in Xcode, then Product -^> Archive and Distribute.
    echo See docs\BUILD_AND_RELEASE.md for signing and App Store steps.
)
goto end

:end
echo.
pause
