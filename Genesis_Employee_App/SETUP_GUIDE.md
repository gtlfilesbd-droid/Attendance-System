# Genesis Employee App - Setup Guide

## Prerequisites

1. **Flutter SDK** (3.0.0 or higher)
   - Download from: https://flutter.dev/docs/get-started/install
   - Verify installation: `flutter doctor`

2. **Android Studio** (for Android development)
   - Download from: https://developer.android.com/studio

3. **Xcode** (for iOS development - macOS only)
   - Available on Mac App Store

## Installation Steps

### 1. Install Dependencies

```bash
cd Genesis_Employee_App
flutter pub get
```

### 2. Configure API Endpoint (Phase 6: configurable + HTTPS)

The API base URL is **configurable at build time** (default is in `lib/config/app_config.dart`).

**Option A – Use the default:**  
Edit `lib/config/app_config.dart` and change the `defaultValue` in `baseUrl` (used when you don’t pass `BASE_URL`):

```dart
defaultValue: 'http://your-server-ip:8000/api',
```

**Option B – Set URL when building:**  
```bash
flutter run --dart-define=BASE_URL=http://192.168.x.x:8000/api
flutter build apk --release --dart-define=BASE_URL=https://your-api.com/api
```

For local development:
- Android Emulator: `http://10.0.2.2:8000/api`
- iOS Simulator: `http://localhost:8000/api`
- Physical device (same Wi‑Fi): your PC’s IP, e.g. `http://192.168.x.x:8000/api`

**Production:** Use **HTTPS** only: build with `--dart-define=BASE_URL=https://your-domain.com/api`. See `docs/BUILD_AND_RELEASE.md`.

### 3. Android Setup

#### Minimum SDK Version
The app requires Android API level 21 (Android 5.0) or higher.

#### Permissions
All required permissions are already configured in `android/app/src/main/AndroidManifest.xml`:
- ✅ ACCESS_FINE_LOCATION
- ✅ ACCESS_COARSE_LOCATION
- ✅ ACCESS_BACKGROUND_LOCATION
- ✅ FOREGROUND_SERVICE

#### Build Configuration
1. Open `android/app/build.gradle`
2. Verify `minSdkVersion` is set to 21
3. Update `applicationId` if needed

### 4. iOS Setup

#### Minimum iOS Version
The app requires iOS 12.0 or higher.

#### Permissions
All required permissions are already configured in `ios/Runner/Info.plist`:
- ✅ NSLocationWhenInUseUsageDescription
- ✅ NSLocationAlwaysAndWhenInUseUsageDescription
- ✅ NSLocationAlwaysUsageDescription
- ✅ UIBackgroundModes (location, fetch, processing)

#### Additional Steps
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select your development team in Signing & Capabilities
3. Run `pod install` in the `ios` directory:
   ```bash
   cd ios
   pod install
   cd ..
   ```

### 5. Run the App

#### Android
```bash
flutter run
```

Or select an Android device/emulator:
```bash
flutter devices
flutter run -d <device-id>
```

#### iOS (macOS only)
```bash
flutter run
```

Or select an iOS device/simulator:
```bash
flutter devices
flutter run -d <device-id>
```

## Testing Location Permissions

### Android
1. Run the app on a device or emulator
2. The app will request location permissions
3. Grant "Allow all the time" for background location

### iOS
1. Run the app on a device or simulator
2. The app will request location permissions
3. Grant "Always" permission for background location

## Troubleshooting

### Issue: "flutter: command not found"
**Solution**: Add Flutter to your PATH environment variable.

### Issue: Location permissions not working
**Solution**: 
- Android: Check that `ACCESS_BACKGROUND_LOCATION` is granted
- iOS: Verify Info.plist has all location permission descriptions

### Issue: Cannot connect to API
**Solution**:
- Check that Django backend is running
- Verify the API base URL (default in `app_config.dart` or `--dart-define=BASE_URL=...`)
- For Android Emulator, use `10.0.2.2` instead of `localhost`
- Check firewall settings

### Issue: Build errors
**Solution**:
```bash
flutter clean
flutter pub get
flutter run
```

## Next Steps

1. ✅ Project structure created
2. ✅ Dependencies configured
3. ✅ Permissions set up
4. ⏭️ Implement authentication screen
5. ⏭️ Implement location tracking service
6. ⏭️ Implement API integration
7. ⏭️ Implement attendance check-in/out
8. ⏭️ Implement route history view

## Project Structure

```
Genesis_Employee_App/
├── lib/
│   ├── main.dart              # App entry point
│   └── config/
│       └── app_config.dart    # App configuration
├── android/                   # Android configuration
│   └── app/src/main/
│       └── AndroidManifest.xml
├── ios/                       # iOS configuration
│   └── Runner/
│       └── Info.plist
└── pubspec.yaml              # Dependencies
```

## Dependencies Installed

- **geolocator**: Location tracking
- **background_location**: Background location updates
- **permission_handler**: Permission management
- **flutter_background_service**: Background service
- **workmanager**: Background tasks
- **http & dio**: HTTP client for API calls
- **shared_preferences**: Local storage
- **flutter_secure_storage**: Secure token storage
- **flutter_map**: Map display
- **battery_plus**: Battery level monitoring

## Support

For issues or questions, refer to:
- Flutter Documentation: https://flutter.dev/docs
- Package Documentation: Check each package's pub.dev page
