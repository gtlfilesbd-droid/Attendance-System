# Genesis Employee App

Flutter mobile application for Genesis Employee Attendance System.

## Features

- Real-time location tracking
- Background location updates
- Employee attendance check-in/check-out
- Route history viewing
- Secure authentication with JWT
- Offline data storage

## Setup

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. Configure API endpoint in `lib/config/app_config.dart`

3. Run the app:
```bash
flutter run
```

## Permissions

### Android
- ACCESS_FINE_LOCATION
- ACCESS_COARSE_LOCATION
- ACCESS_BACKGROUND_LOCATION
- FOREGROUND_SERVICE

### iOS
- Location Always and When In Use
- Background Location Updates

## API Integration

The app connects to the Django backend at:
- Base URL: `http://your-server:8000/api/`

## Build

### Android
```bash
flutter build apk
```

### iOS
```bash
flutter build ios
```
