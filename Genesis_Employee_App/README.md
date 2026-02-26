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
   If that fails (network or timeout), run `pub-get.bat` from the app folder, or try again with a working internet connection. The app uses the `geocoding` package (^3.0.0) for current-location place names.

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

## Build & Release

- **Scripts:** Run `build-release.bat` (Windows) or `./build-release.sh` (macOS/Linux) to build APK, App Bundle, or iOS release.
- **Signed APK:** Configure `android/key.properties` from `android/key.properties.example`, then `flutter build apk --release`
- **Play Store:** `flutter build appbundle --release` and upload the AAB
- **iOS:** Open `ios/Runner.xcworkspace` in Xcode, set signing, then **Product → Archive**
- **Screenshots:** Add store listing screenshots to `docs/screenshots/` (see [BUILD_AND_RELEASE.md](docs/BUILD_AND_RELEASE.md)).

See **[docs/BUILD_AND_RELEASE.md](docs/BUILD_AND_RELEASE.md)** for signing setup, Play Store and App Store checklists, and store listing (screenshots and descriptions).

## Testing

- **Unit & widget tests:** `flutter test test/unit test/widget`
- **All tests (including integration):** `flutter test`
- **Integration tests on device:** `flutter test integration_test/`

**Android 10+ and long background:** To verify stability after long background (e.g. 30+ minutes), test on Android 10, 11, 12, 13, 14: put the app in background (no duty, Start Duty visible), wait 30+ minutes, then bring to foreground — scroll, pull-to-refresh, and Start Duty should respond. Optionally enable "Don't keep activities" in Developer options to stress activity restore.

See [test/TEST_SCENARIOS.md](test/TEST_SCENARIOS.md) for scenario descriptions and app kill/restart steps.

## Build

### Android
```bash
flutter build apk
```

### iOS
```bash
flutter build ios
```
