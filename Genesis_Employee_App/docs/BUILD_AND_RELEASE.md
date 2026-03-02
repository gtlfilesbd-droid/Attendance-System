# Genesis Employee App — Build & Release Guide

This guide covers signing, building, and releasing the app for **Google Play Store** (Android) and **App Store** (iOS), plus store listing content (screenshots and descriptions).

---

## Table of Contents

1. [Android Build & Play Store](#android-build--play-store)
2. [iOS Build & App Store](#ios-build--app-store)
3. [Store Listing: Screenshots & Descriptions](#store-listing-screenshots--descriptions)

---

## Android Build & Play Store

### 0. Windows: Avoid shader build error (optional)

On Windows, the release build can fail with `ShaderCompilerException: Could not write file ... ink_sparkle.frag`. If that happens:

1. **Manual build:** Create the folder `build\app\intermediates\flutter\release\flutter_assets\shaders` if needed, then run:
   ```bat
   flutter clean
   flutter pub get
   flutter build apk --release
   ```
   APK output: `build\app\outputs\flutter-apk\app-release.apk`
2. **If it still fails:** Turn off **Controlled folder access** (Windows Security → Virus & threat protection → Manage settings) for your project folder, or move the project to a shorter path without spaces (e.g. `E:\GenesisApp`).

### 1. Configure App Signing

Release builds must be signed with a keystore. The project is already set up to use `key.properties`.

**Create a keystore (one-time):**

```bash
cd android/app
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Enter a **keystore password** and **key password** (store securely).
- Fill in name, org, city, etc. as prompted.
- Keep `upload-keystore.jks` in a safe place and **never commit it** (it’s in `.gitignore`).

**Create `key.properties`** (in the `android/` folder):

```bash
cd android
cp key.properties.example key.properties
```

Edit `android/key.properties` and set:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
```

`storeFile` is relative to `android/app/`. Place the keystore at `android/app/upload-keystore.jks` and use `storeFile=upload-keystore.jks`.

**Signing in `build.gradle`:**  
Already configured in `android/app/build.gradle`:

- Reads `android/key.properties` if present.
- Uses `signingConfigs.release` for release builds when `key.properties` exists.
- Falls back to debug signing if `key.properties` is missing (for local/dev only).

---

### 2. AndroidManifest.xml & Permissions

Permissions in `android/app/src/main/AndroidManifest.xml` are set for:

- **Location:** `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` — for attendance and route tracking.
- **Foreground service:** `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` — for background tracking.
- **Network:** `INTERNET`, `ACCESS_NETWORK_STATE`.
- **Other:** `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

No code changes needed for release; ensure your **Play Console** “App content” declarations (e.g. sensitive permissions) match how the app uses location and background usage.

---

### 3. Generate Signed APK / App Bundle

**Quick build (optional):** Run from the project root:
- **Windows:** `build-release.bat` — choose 1 (APK) or 2 (App Bundle).
- **macOS/Linux:** `./build-release.sh` — same options.

**Version:** Set in `pubspec.yaml`:

```yaml
version: 1.0.0+1   # 1.0.0 = versionName, 1 = versionCode
```

**Signed APK (for testing or sideload):**

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

**Install on your phone (sideload for testing):**

You **cannot** copy the project folder to your mobile and run it. You must:

1. **Build the APK on your PC** (as above): run `build-release.bat` → choose **1** (APK), or run `flutter build apk --release`.
2. **Copy the APK file** to your phone (USB cable, email, cloud, or shared folder). The file is:  
   `build\app\outputs\flutter-apk\app-release.apk`
3. **On your phone:** Open the APK file (you may need to allow “Install from unknown sources” in Settings) and install.
4. **For the app to work:** Your **backend must be running** on your PC (e.g. at `http://192.168.1.104:8000`), and the phone must be on the **same Wi‑Fi network**. The app’s default `baseUrl` is in `lib/config/app_config.dart`; to point to a different server, rebuild with `--dart-define=BASE_URL=http://YOUR_PC_IP:8000/api` (see “API base URL and HTTPS” below).

Yes — once you build the APK, copy that **single APK file** to your mobile and install it; the app will work as long as the backend is running and the phone can reach it on the network.

**App Bundle (recommended for Play Store):**

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Upload the **AAB** to Google Play Console; Play will generate optimized APKs for devices.

**API base URL and HTTPS (Phase 6):**  
The app’s API base URL is **configurable at build time**. By default it uses the dev URL in `lib/config/app_config.dart`. For **production**, use HTTPS and your real domain by passing `BASE_URL`:

```bash
flutter build apk --release --dart-define=BASE_URL=https://your-api-domain.com/api
flutter build appbundle --release --dart-define=BASE_URL=https://your-api-domain.com/api
```

- Use **https** in production; do not use **http** for live traffic.
- The value must include the path up to and including `/api` (no trailing slash after `api`).
- Example: `https://api.genesis.com/api` — the app then calls e.g. `https://api.genesis.com/api/employees/auth/login/`.

---

### 4. Prepare for Play Store Release

- [ ] **Google Play Console:** Create app, fill store listing (see [Store Listing](#store-listing-screenshots--descriptions)).
- [ ] **App signing by Google Play:** Enroll in “Play App Signing” and upload your upload key (or let Play manage the key). Keep your upload keystore backed up.
- [ ] **Content rating:** Complete questionnaire (e.g. location, no sensitive content).
- [ ] **Target audience:** Set age group and target countries.
- [ ] **Privacy policy:** Add URL (required if you collect location/data).
- [ ] **Sensitive permissions:** Declare and justify location and background usage in “App content” (e.g. “This app uses location for attendance while duty is active”).
- [ ] **Release:** Create a release, upload the AAB, add release notes, and roll out to production (or testing track first).

---

## iOS Build & App Store

### 1. Info.plist — Location Permissions

Location and background usage are already set in `ios/Runner/Info.plist`:

- **NSLocationWhenInUseUsageDescription** — “Genesis Employee uses your location to record check-in/check-out and attendance while duty is active.”
- **NSLocationAlwaysAndWhenInUseUsageDescription** — “Genesis Employee needs background location access to continuously track your attendance while duty is active.”
- **NSLocationAlwaysUsageDescription** — Same as above.
- **UIBackgroundModes** — `location`, `fetch`, `processing` for background tracking.

These strings are shown in the system permission dialog and in App Store Connect; no further changes needed for release.

---

### 2. Signing in Xcode

1. Open the iOS project in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Select the **Runner** project in the left sidebar, then the **Runner** target.
3. Open **Signing & Capabilities**.
4. Check **Automatically manage signing**.
5. Choose your **Team** (Apple Developer account).
6. Set **Bundle Identifier** (e.g. `com.genesis.employeeapp`) — must be unique and match App Store Connect.
7. Ensure a valid **Provisioning Profile** is selected for Release.

If you use manual signing, create a Distribution certificate and provisioning profile in the Apple Developer portal and select them here.

---

### 3. Build for Release

**From command line:**

```bash
flutter build ios --release
```

Then in Xcode:

1. Select **Any iOS Device (arm64)** or a connected device (not a simulator).
2. **Product → Archive**.
3. When the archive is created, **Distribute App** → **App Store Connect** → upload.

**Or** use **Product → Archive** only (Xcode will build release by default when archiving).

---

### 4. Prepare for App Store

- [ ] **App Store Connect:** Create the app, set bundle ID and name.
- [ ] **Store listing:** Use the [screenshots and descriptions](#store-listing-screenshots--descriptions) below.
- [ ] **Privacy:** Add Privacy Policy URL; declare “Location” and “Identifiers” (e.g. for login) in App Privacy.
- [ ] **App Review:** Explain that location is used for attendance tracking; background location is used only while the user has started duty (Start Duty / End Duty).
- [ ] **TestFlight (optional):** Upload build, add internal/external testers, then submit for review.

---

## Store Listing: Screenshots & Descriptions

Use these for both **Google Play** and **App Store** (adjust length per store limits).

---

### Short description (e.g. 80 chars)

**Genesis Employee — Clock in with GPS, view attendance and your daily route.**

---

### Full description (example)

**Genesis Employee** is the official attendance app for employees. Log in once, start your duty, and your location is used to record your attendance and route.

**Features:**
- **One-tap duty** — Start/stop tracking with a single button; location is recorded while duty is active.
- **Attendance history** — See check-in/check-out times and total hours for each day.
- **Today’s route** — View your logged route on a map and distance traveled.
- **Profile** — View your details and stay signed in securely.

**How it works:**  
Sign in with your company email. Turn on “Start Duty” when you begin work; the app records your location in the background while duty is active. Your employer uses this data for attendance and route reporting. You can view your own attendance and route anytime.

**Permissions:**  
The app needs **location** (including in the background while duty is active) to record your attendance and route. Notifications are used to show that tracking is active.

---

### Screenshots to capture

Capture on a **phone** (and optionally tablet for Play). Use **light theme** and **realistic sample data**. Suggested order:

| # | Screen            | What to show |
|---|-------------------|--------------|
| 1 | **Login**         | Email and password fields, “Genesis Employee” title, “Sign in to start tracking” subtitle. |
| 2 | **Home / Dashboard** | “Hello, [Name]”, current time, “Online” or “Offline”, “START DUTY” or “END DUTY”, “X locations logged today”, and the two action cards: “View My Attendance” and “View Today’s Route”. |
| 3 | **Attendance list** | List of attendance cards with date, check-in/check-out, total hours, and status (e.g. Present/Late). |
| 4 | **Route map**      | Map with route polyline and “Distance Traveled” / “Points Logged” at the bottom. |
| 5 | **Profile**        | Name, Employee ID, email, department, designation, and Logout button. |

**Tips:**
- Use a **neutral name** (e.g. “Demo User”) and **sample dates/times**.
- Ensure **no real personal data** or internal URLs in screenshots.
- **Resolution:** At least 1080px on the long side; 16:9 or 9:16 is fine. Follow store requirements (e.g. Play: 320–3840 px; App Store: device-specific sizes).

---

### Optional: Feature graphic (Play) / Promo (App Store)

- **Play:** 1024×500 px feature graphic (no text required; app icon + “Genesis Employee” is enough).
- **App Store:** Optional promo image; use same branding as screenshots.

---

### Version / What’s New (example)

**1.0.0**
- Initial release.
- Sign in with company email.
- Start/stop duty and track location while duty is active.
- View attendance history and today’s route on a map.
- Profile and secure logout.

---

## Quick reference

| Platform   | Signing / config              | Build command                  | Output / next step          |
|-----------|--------------------------------|--------------------------------|-----------------------------|
| Android   | `android/key.properties` + `.jks` | `flutter build appbundle --release` | Upload AAB to Play Console |
| iOS       | Xcode → Signing & Capabilities | `flutter build ios` then **Product → Archive** | Upload via Xcode to App Store Connect |

For more detail, see the Android and iOS sections above and each store’s current documentation.
