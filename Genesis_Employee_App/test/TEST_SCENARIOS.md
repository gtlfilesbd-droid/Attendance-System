# Flutter App Test Scenarios

This document describes the test scenarios implemented and how to run them.

## 1. Test Login Flow

**Unit:** `test/unit/auth_service_test.dart`
- `isLoggedIn` returns false after logout
- `getToken` / `getEmployeeData` / `getRefreshToken` return null when not logged in
- `login` with invalid credentials returns false

**Widget:** `test/widget/login_screen_test.dart`
- Displays title, email and password fields, LOGIN button
- Validation: empty email → "Please enter email"
- Validation: invalid email → "Please enter a valid email"
- Validation: empty password → "Please enter password"

**Run:** `flutter test test/unit/auth_service_test.dart test/widget/login_screen_test.dart`

---

## 2. Test Background Location Service

**Unit:** `test/unit/location_service_test.dart`
- `startTracking` / `stopTracking` complete without throwing
- `scheduleTracking` does not throw
- `isWorkingHours` returns a boolean

**Run:** `flutter test test/unit/location_service_test.dart`

---

## 3. Test Location Sending to Backend

**Unit:** `test/unit/location_sending_test.dart`
- `logLocation` returns false when not authenticated
- `logLocation` accepts required parameters (lat, lng, accuracy, batteryLevel, optional speed)

**Run:** `flutter test test/unit/location_sending_test.dart`

---

## 4. Test Working Hours Detection

**Unit:** `test/unit/working_hours_test.dart` (uses pure Dart `lib/utils/working_hours.dart` — no plugins, runs fast)
- Time limit disabled: `isWorkingHours(DateTime)` returns true for all times (tracking runs whenever duty is active)
- `LocationService.isWorkingHoursStatic()` delegates to this utility

**Run:** `flutter test test/unit/working_hours_test.dart`

---

## 5. Test Notification Display

**Unit:** `test/unit/notification_display_test.dart`
- Notification channel ID is `genesis_tracking_channel`
- Notification ID is 888
- `startService` / `stopService` complete without throwing

**Run:** `flutter test test/unit/notification_display_test.dart`

---

## 6. App Kill / Restart Scenarios

**Integration:** `integration_test/app_test.dart`
- App launches, splash is shown, then either Login or Home is shown

**Manual scenario (app kill/restart):**
1. Log in on device/emulator.
2. Start tracking (START DUTY).
3. Force-kill the app (swipe away from recents / kill process).
4. Reopen the app.
5. **Expected:** User remains logged in (token in secure storage). Splash → Home. Tracking may need to be restarted depending on platform (WorkManager may reschedule).

**Run integration tests:**
```bash
flutter test integration_test/app_test.dart
```
Or on a device:
```bash
flutter test integration_test/ --device-id=<device_id>
```

---

## Widget Tests for Screens

| Screen            | File                           | Coverage                                      |
|-------------------|--------------------------------|-----------------------------------------------|
| LoginScreen       | `test/widget/login_screen_test.dart`  | Title, fields, validation, LOGIN button      |
| HomeScreen        | `test/widget/home_screen_test.dart`  | App bar, tracking status, START DUTY, actions |
| AttendanceScreen  | `test/widget/attendance_screen_test.dart` | App bar, loading, scaffold                  |
| RouteMapScreen    | `test/widget/route_map_screen_test.dart` | App bar, loading, distance/points labels   |
| ProfileScreen     | `test/widget/profile_screen_test.dart`  | Loading, app bar, logout, avatar            |

**Run all widget tests:** `flutter test test/widget/`

---

## Run All Tests

```bash
# Fast test only (pure Dart, no plugins) — use for quick CI check
flutter test test/unit/working_hours_test.dart

# Unit + widget tests (no device required; may be slow due to plugin init)
flutter test test/unit test/widget test/helpers

# Full suite
flutter test

# Integration tests (may require device)
flutter test integration_test/
```

**Note:** Tests that import `LocationService`, `AuthService`, or `BackgroundWorker` load native plugins and can be slow or require a device. The working-hours test imports only `lib/utils/working_hours.dart` and runs quickly.
