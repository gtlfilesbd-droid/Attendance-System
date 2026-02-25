# Genesis Attendance System — Comprehensive Audit Report

**Document version:** 1.4  
**Date:** February 2025  
**Audience:** CTO, Team Leads, Engineering  
**Scope:** Web (Django dashboard) + Flutter Mobile App (Attendance & Employee Management)

**Plan alignment:** This report is aligned with the Comprehensive Audit Report Plan (attendance_system_audit_report_aed691eb.plan.md). All seven scopes and deliverables have been audited and documented.

---

## Executive Summary

**System context (per plan):** **Backend + Web** — Genesis_Employee_Attendance: Django 4.2, DRF, PostGIS, Celery, JWT (Employee + Django User), web dashboard at `/dashboard/`. **Mobile** — Genesis_Employee_App: Flutter app (Android minSdk 29, targetSdk 36), JWT, foreground/background location, offline queue, FCM.

This report presents a **seven-scope audit** of the Genesis Attendance System, covering security, performance, enterprise testing, full lifecycle behavior, Web–App integration, Android compatibility, and user experience and stability. The system comprises a **Django backend** (REST API, JWT auth, PostGIS, Celery) with a web dashboard, and a **Flutter mobile app** (Android/iOS) for employee attendance, duty management, and location tracking with offline support.

**Methodology:** Static code review, architecture and configuration analysis, and trace of data flows across backend and app. No live penetration testing or load testing was performed; recommendations include adding such checks.

**High-level risk summary:**

| Severity | Count | Primary areas |
|----------|-------|----------------|
| High    | 2     | Security (HTTP in production, unencrypted offline location queue) |
| Medium  | 8     | Security (rate limiting, CORS, SECRET_KEY), performance (sync, debounce), lifecycle (dispose, race conditions), integration (docs, idempotency) |
| Low     | 7     | Logging, UX messaging, controller disposal, documentation, deprecations, dependency audit |

**Top priorities:** (1) Move to HTTPS and make API base URL configurable; (2) Encrypt or secure the offline location queue; (3) Add backend rate limiting and harden production settings; (4) Add controller disposal and request-ordering guards where needed; (5) Establish CI/CD and expand test coverage.

---

## 1. Security Review

### 1.1 Approach

- Reviewed API authentication and authorization (JWT, Employee vs Django User).
- Traced token storage, refresh, and expiry handling on the app and backend.
- Checked sensitive data storage (secure storage, SharedPreferences, backend cache).
- Reviewed encryption at rest and in transit, backend endpoint security, and location permission and storage safety.

### 1.2 Findings

**Strengths**

- **API authentication:** Bearer JWT; backend uses `EmployeeJWTAuthentication` (Employee UUID) then `JWTAuthentication` (Django User). Protected endpoints use `IsAuthenticated`; login is `AllowAny` only for the employee login endpoint.
- **Token handling:** Access and refresh tokens stored in **Flutter Secure Storage** (platform secure storage), not SharedPreferences. On 401, the app attempts token refresh and retries the request; on refresh failure, it logs out.
- **Token expiry:** Backend enforces JWT expiry; the app does not check expiry client-side. Expired access tokens result in 401; the API interceptor then attempts refresh or logout. There is no proactive refresh before expiry (acceptable for many deployments; optional improvement: refresh shortly before expiry if expiry claim is available).
- **Logout:** Backend logout endpoint called for audit; then app clears secure storage and stops background location service and duty reminders.
- **Location permissions:** Foreground then background location requested via `permission_handler`; Android manifest declares `FOREGROUND_SERVICE_LOCATION` and required permissions appropriately.

**Vulnerabilities and risk**

| ID   | Finding | Severity | Risk | Mitigation |
|------|---------|----------|------|------------|
| S1   | **HTTP in production:** App `baseUrl` is hardcoded to `http://103.29.60.233:8000/api` in `Genesis_Employee_App/lib/config/app_config.dart`. Tokens and all API data travel unencrypted. | High | Interception, tampering, credential theft | Use HTTPS only. Make base URL configurable (e.g. env, build flavor, or runtime config). |
| S2   | **Offline location queue in plain text:** `offline_locations` stored in SharedPreferences (unencrypted) in `location_service.dart`. Contains lat/lng, timestamp, accuracy, battery. | High | Theft of device exposes location history | Encrypt queue (e.g. encrypt JSON before write) or store in secure storage; keep 1000-cap and clear after successful sync. |
| S3   | **No backend rate limiting:** API documentation mentions rate limiting; no DRF throttle classes or per-view throttling in `config/settings.py` or views. | Medium | DoS, brute-force on login, log-location abuse | Add DRF throttling (e.g. `AnonRateThrottle`, `UserRateThrottle`) and/or stricter limits for login and log-location. |
| S4   | **CORS:** `CORS_ALLOW_ALL_ORIGINS` defaults to `DEBUG`. Production could allow all origins if DEBUG is mis-set. | Medium | Cross-origin abuse | Ensure production sets `CORS_ALLOW_ALL_ORIGINS=False` and uses explicit `CORS_ALLOWED_ORIGINS`. |
| S5   | **SECRET_KEY:** Default fallback in settings; must be overridden in production. | Medium | Token/session forgery if default is used | Require `SECRET_KEY` from environment in production; fail startup if missing. |
| S6   | **Debug logging:** `employees/views.py` writes to a debug file path; can leak data in production. | Low | Info disclosure in logs | Remove or guard with `DEBUG`; avoid logging PII. |
| S7   | **Sensitive data in responses:** Serializers exclude sensitive fields; ensure error messages and logs do not expose PII. | Low | PII leakage | Audit error responses and log format; keep PII out of client messages and logs. |

### 1.3 Crash/exploit vectors and dependencies

**Dependencies (insecure versions, known CVEs)**

- **Backend:** `requirements.txt` uses `Django==4.2` (no patch pin; recommend e.g. `Django==4.2.x` and bump for security fixes). DRF, SimpleJWT, and other packages are unpinned; production should pin exact versions and run `pip audit` (or equivalent) regularly. No obvious use of known vulnerable patterns (raw SQL, unchecked mass assignment) in reviewed views; serializers use explicit fields.
- **Flutter:** `pubspec.yaml` uses caret ranges (e.g. `dio ^5.4.0`, `flutter_secure_storage ^9.0.0`). Run `dart pub outdated` and monitor for security advisories. No obvious misuse of native or plugin APIs that would open exploit vectors.
- **Recommendation:** Pin backend versions; add `pip audit` and dependency-check to CI; document a process for updating dependencies and reviewing CVEs.

**Permission misuse**

- **App:** Location permissions (foreground + background) are used only for duty tracking and route logging; no access to contacts, SMS, or other sensitive APIs beyond location, network, notifications, and battery (for context in logs). Permission requests are appropriate for the feature set.
- **Backend:** API requires authentication for protected endpoints; admin-only views (e.g. live locations) use role checks. No obvious privilege-escalation paths in reviewed code.

### 1.4 Success Criteria

- All production API traffic over HTTPS; base URL not hardcoded for production.
- Offline location data encrypted at rest or in secure storage.
- Rate limiting active on auth and high-frequency endpoints; production CORS and SECRET_KEY locked down.
- Dependencies pinned and audited; no known high/critical CVEs in production stack.

---

## 2. Performance Optimization Review

### 2.1 Approach

- Analyzed API call patterns (foreground refresh, pull-to-refresh).
- Reviewed debounce and request-ordering logic.
- Considered memory use, offline sync behavior, and background service impact.
- **Memory and leak detection:** No formal profiling (e.g. Flutter DevTools memory snapshot or backend profiling) was run; findings are from code review (controller disposal, large lists in state, sequential sync). Recommend periodic memory profiling and leak checks in QA or CI where feasible.

### 2.2 Findings

**Current behavior**

- **Foreground refresh:** `ForegroundRefreshService` runs on app resume with 30s debounce and connectivity check; syncs offline queue then notifies registered screens. Home, Attendance, Profile, and RouteMap register in `initState` and remove in `dispose`.
- **Pull-to-refresh:** All main screens use `RefreshIndicator`; RouteMap and others call `syncOfflineData()` and refetch.
- **Route fetch:** `RouteMapScreen` uses `_fetchRouteRequestId` to ignore stale responses when multiple fetches are in flight.
- **Background:** Position stream plus Timer (interval from `AppConfig.locationUpdateIntervalSecondsWhenDuty`); sends location and calls `syncOfflineData()` periodically.

**Bottlenecks and recommendations**

| ID   | Bottleneck | Root cause | Impact | Recommendation |
|------|------------|------------|--------|-----------------|
| P1   | Offline sync blocks on large queue | Sequential POST per location; up to 1000 items | Long sync time, UI can feel stuck | Add batch upload endpoint or limited parallel concurrency; show sync progress in UI. |
| P2   | No request debounce on Route Map | Date/time filter changes trigger immediate `_fetchRoute()` | Extra API calls, possible jank | Debounce filter changes (e.g. 300–500 ms) before calling `_fetchRoute()`. |
| P3   | Very long routes in memory | Full list of points held in state | Higher memory for 10k+ points | Consider pagination or time-window for timeline/map; already using `ListView.builder` in timeline. |
| P4   | Backend serializer cache | In-memory cache in attendance serializers | Stale data if keys/invalidation wrong | Verify cache keys and invalidation (e.g. on duty start/end) to avoid stale attendance. |
| P5   | Battery | 60s interval when on duty is documented | Acceptable if not over-waking | Document; optionally make interval configurable per build; ensure WorkManager does not over-wake. |

### 2.3 Success Criteria

- Offline sync completes in reasonable time for typical queue sizes or shows clear progress.
- Route Map filter changes do not cause request storms.
- No unnecessary wake-ups; battery impact documented and configurable where needed.

---

## 3. Enterprise-Grade Testing Plan

### 3.1 Current State

- **Flutter:** Unit tests (auth, location, working_hours, notification_display), widget tests (login, home, attendance, profile, route_map), integration test (splash → login/home). `run_tests.bat` runs unit + widget.
- **Backend:** Docker-based tests in `tests/test_api.py` (login, log_location, permissions, route history, attendance calculation). No CI; no contract or E2E tests.

### 3.2 Gaps

- No CI/CD (e.g. GitHub Actions); tests run manually.
- No E2E for critical flows (login → start duty → location → end duty).
- No contract/schema tests for Web vs App API.
- Limited backend coverage for start-duty, end-duty, my-attendance, auto-end-duty.
- No load/performance tests; no structured logging or alerting.

### 3.3 Proposed Testing Strategy

**Manual test matrix (by feature)**

Detailed steps for each scenario should be maintained in `Genesis_Employee_App/test/TEST_SCENARIOS.md` or a dedicated test-case repository; the table below summarizes scope and expected outcomes.

| Feature | Test cases (summary) | Expected results |
|---------|------------------------|------------------|
| Login | Valid/invalid credentials, empty fields, network off | Correct errors; on success navigate to Home. |
| Home/Duty | Start duty, end duty, tracking state, place name refresh | Duty state and tracking match backend; SnackBars appropriate. |
| Attendance | Date range, presets, load error, retry | Data matches API; errors and retry work. |
| Profile | Load, logout | Profile data correct; logout clears state and returns to Login. |
| Route Map | Date/time filters, playback, empty/error, refresh | Route loads; playback and retry work. |
| Offline | Go offline, queue locations, come online | Queue syncs; UI reflects success/failure. |
| Permissions | Deny/grant location, background | Graceful messaging; tracking only when allowed. |

**Automation**

- **Unit/widget:** Expand coverage for API service, auth, and location; keep widget tests for all main screens.
- **Integration:** Add flows that hit real or mocked API (login, fetch attendance, start/end duty) and key screen transitions.
- **Contract tests:** Define and validate request/response shape for app-used endpoints (e.g. login, my-attendance, start-duty, end-duty, log-location) via OpenAPI or JSON schema.
- **Backend:** Add tests for attendance views (start-duty, end-duty, my-attendance) and Celery auto-end-duty; run in CI.

**Edge cases**

- Offline → online sync (partial failure, retry).
- API failure and retry (including 401 + refresh).
- Duplicate actions (e.g. start duty twice).
- Empty route, no data, and permission denied.

**Monitoring and alerting**

- Centralized logging (backend + app).
- Error/crash reporting (e.g. Firebase Crashlytics).
- Alerts on auth failure rate, API error rate, and latency.

### 3.4 Tools and coverage

- **Tools:** Flutter test, pytest, Docker (backend tests), optional Postman/OpenAPI for contracts, Crashlytics.
- **Coverage targets:** Backend critical paths >80%; Flutter unit + widget for services and screens; at least one integration path per critical user journey.

### 3.5 Regression tests

- **Strategy:** Re-run full test suite (Flutter unit + widget + integration, backend Django tests) before each release and on every PR targeting main/develop. Tag critical-path tests (login, start/end duty, log location, my-attendance) and run them in CI on every commit.
- **Scope:** All manual test matrix scenarios (Section 3.3) plus automated unit/widget and integration tests. After any change to auth, attendance, or location logic, run attendance calculation and API tests.
- **Deliverable:** CI pipeline that runs regression suite and fails the build on test failure; optional nightly run with extended coverage or on-device tests.

---

## 4. Full Lifecycle Audit

### 4.1 Approach

- Traced app and screen lifecycle (cold start, background, foreground, logout, termination).
- **Validated refresh triggers:** Foreground refresh is triggered by `AppLifecycleWrapper` when the app returns to foreground (debounced 30s, with connectivity check); it syncs offline data and notifies all registered screens. Pull-to-refresh is triggered by the user via each screen’s `RefreshIndicator`; it runs `syncOfflineData()` and refetches that screen’s data. Both paths are implemented and used consistently across Home, Attendance, Profile, and Route Map.
- Checked listener subscription and disposal; looked for race conditions and overlapping API calls.

### 4.2 Lifecycle scenarios

| Scenario | Behavior | Status |
|----------|----------|--------|
| Cold start | ApiService.initialize(), LocationService.initializeService(), Firebase; Splash then Login or Home based on token | Implemented |
| Background | App paused; background service continues if duty active; timers/streams in app process may be throttled by OS | Implemented |
| Resume (foreground) | AppLifecycleWrapper → ForegroundRefreshService.onAppResumed(); debounce, connectivity, sync offline, notify listeners; SnackBar when skippedOffline | Implemented |
| Home on resume | WidgetsBindingObserver; if duty started but service not running, restart tracking and show SnackBar | Implemented |
| Logout | ApiService.logout() → clear storage → stop background service, cancel reminders | Implemented |
| Termination (process kill) | Token persists in secure storage. On next launch: Splash → Home if logged in; tracking may be stopped; HomeScreen detects duty-without-service and can restart tracking with SnackBar | Implemented |
| Screens (Attendance, Profile, RouteMap) | Register ForegroundRefreshService in initState, remove in dispose; RouteMap pauses playback in dispose | Implemented |

### 4.2.1 Screen-level lifecycle (init/dispose/refresh)

| Screen | initState | dispose | Foreground refresh trigger |
|--------|-----------|---------|----------------------------|
| Home | WidgetsBindingObserver, ForegroundRefreshService listener, _loadData, timers (duty card, place name), scheduleTracking, stopTracking | removeListener, removeObserver, _timer?.cancel(), _placeRefreshTimer?.cancel() | _onForegroundRefresh → _loadData + _loadTodayDutyTime |
| Attendance | ForegroundRefreshService listener, _fetchAttendance | removeListener | _onForegroundRefresh → _fetchAttendance |
| Profile | ForegroundRefreshService listener, load profile | removeListener | _onForegroundRefresh → reload profile |
| RouteMap | ForegroundRefreshService listener, _fetchRoute | _playbackController.pause(), removeListener (no controller dispose) | _onForegroundRefresh → pause playback, reset, _fetchRoute |

### 4.3 Issues and recommendations

| ID   | Issue | Reproduction | Recommendation |
|------|--------|--------------|----------------|
| L1   | **RouteMapScreen controller disposal:** `dispose()` calls `_playbackController.pause()` but does not call `dispose()` on `_animationController` or `_playbackController`. | Open Route Map, navigate away repeatedly. | Implement and call `dispose()` on both controllers (and ensure they cancel timers/subscriptions). |
| L2   | **FCM listeners:** PushNotificationService subscriptions are never cancelled. | N/A (app-lifetime singleton). | Acceptable; document as intentional. |
| L3   | **Overlapping API calls:** Home and Attendance do not use a request-id or single-flight pattern; rapid refresh can reorder responses. | Pull-to-refresh and foreground refresh in quick succession. | Use request-id or single-flight for data fetches where order matters. |
| L4   | **State consistency:** Each screen refreshes independently after foreground refresh; no shared “duty state.” | Start duty on Home, switch to Attendance before it refreshes. | Consider lightweight shared state (e.g. InheritedWidget/Provider) for current duty status. |

### 4.4 Success Criteria

- All screens that register listeners or create controllers remove/cancel them in `dispose()`.
- No setState after dispose; request ordering documented or enforced for critical fetches.
- Duty state consistent across Home and Attendance after refresh.

---

## 5. Web + App Integration Review

### 5.1 Approach

- Compared app API usage to backend URLs and response shapes.
- Checked documentation vs implementation.
- Reviewed sync and conflict handling for offline and duty state.

### 5.2 API contract alignment

| Endpoint | App usage | Backend | Match |
|----------|-----------|---------|--------|
| Login | POST `/api/employees/auth/login/`; expects `{ success, data: { access, refresh, employee } }` | Same path; returns same shape | Yes |
| Token refresh | POST `/api/auth/token/refresh/` with `refresh`; expects `access` (and optionally `refresh`) | SimpleJWT TokenRefreshView | Yes |
| My attendance | GET `/api/attendance/my-attendance/` with start/end date | Same | Yes |
| Start/End duty | POST `/api/attendance/start-duty/`, `end-duty/` | Same | Yes |
| Log location | POST `/api/tracking/log-location/` | Same | Yes |

### 5.3 Documentation and integration gaps

- **API_DOCUMENTATION.md** describes `/api/attendance/records/my_attendance/?days=30` and admin JWT; app uses `/api/attendance/my-attendance/` with start/end date. Documentation is out of date for app-facing API.
- **Sync/conflicts:** Offline queue sends each location in order; backend has no idempotency key. Partial sync failure and retry can resend same locations. Start/End duty: backend is source of truth; app should disable “Start Duty” when already started (e.g. from my-attendance or start-duty response).
- **Real-time and versioning:** No WebSocket; dashboard and app poll. No API version header or path for future breaking changes.
- **Consistent experience across platforms:** Web dashboard and mobile app both use the same REST API; behavior and data are consistent. Neither platform has real-time push (both poll), so experience is aligned. Differences are limited to UI (web vs native) and offline support (app has location queue; web relies on connectivity).

### 5.4 Improvement plan

1. **Contract document:** Maintain a single “App API” spec (OpenAPI or markdown) for app-used endpoints and keep it in sync with code.
2. **Idempotency:** Introduce client-generated idempotency key (e.g. UUID per log) for log-location or backend deduplication by employee + timestamp window.
3. **Versioning:** Add API version (header or path) for future breaking changes.
4. **Conflict handling:** Document and enforce “single active duty” and disable Start Duty when a session is already active.

---

## 6. Android Compatibility Testing

### 6.1 Configuration

- **minSdkVersion:** 29 (Android 10).
- **targetSdkVersion / compileSdkVersion:** 36.
- **coreLibraryDesugaring:** enabled; Java 1.8.
- **Manifest:** ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, ACCESS_BACKGROUND_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION, POST_NOTIFICATIONS (targetApi 33), REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, WAKE_LOCK. Foreground service type `location` declared.

### 6.2 Compatibility matrix

| API level | Recommended testing | Notes |
|-----------|--------------------|--------|
| 29 | Yes | minSdk; background location behavior. |
| 30 | Yes | - |
| 31 | Yes | - |
| 32 | Yes | Android 12L. |
| 33 | Yes | POST_NOTIFICATIONS runtime. |
| 34–36 | Yes if available | targetSdk 36. |

### 6.3 Findings and recommendations

- **Permissions:** Appropriate for foreground and background location; POST_NOTIFICATIONS and foreground service type are correctly declared.
- **Deprecations:** No obvious deprecated API usage in reviewed code; run `flutter analyze` and Android lint per API level.
- **Behavior:** Android 10+ background location and “Always allow”; Android 12+ exact alarm; Android 13+ notification permission. Verify permission_handler flows on API 29, 31, 33.

### 6.4 Deliverables

- Android OS matrix (29–36) with test result placeholders for QA.
- Permission and foreground-service checklist.
- Recommendation: run automated or manual smoke tests on at least API 29 and 33 (and 34+ if targeting latest).

### 6.5 Issues by version (code-review and QA)

No version-specific code defects were identified in static review. The following table is for QA to populate after running the compatibility matrix (runtime crashes, UI glitches, permission flows).

| API level | Runtime crashes | UI glitches | Permission / foreground notes | QA status |
|-----------|-----------------|-------------|-------------------------------|-----------|
| 29 | — | — | Background location “Always allow” flow | To be tested |
| 30 | — | — | — | To be tested |
| 31 | — | — | — | To be tested |
| 32 | — | — | Android 12L | To be tested |
| 33 | — | — | POST_NOTIFICATIONS runtime prompt | To be tested |
| 34–36 | — | — | targetSdk 36 behavior | To be tested |

**Compatibility fixes from code review:** None required for minimum API 29; ensure `foregroundServiceType="location"` and POST_NOTIFICATIONS (API 33+) are declared and that permission_handler flows are tested on 29, 31, and 33.

---

## 7. User Experience and Stability Review

### 7.1 Loading and errors

- **Loading:** Login, Home (duty card), Attendance, Profile, and Route Map use `_isLoading` and disable actions during load; duty start/end use a loading dialog.
- **Errors:** Login shows inline message; Attendance shows `_errorMessage` and retry; Route Map has RouteErrorView with retry. Many API errors surface as generic “Connection error” or similar.
- **SnackBars:** Used consistently for “Tracking resumed,” “No internet…,” “Location refreshed,” duty success/failure, and permission messages.

### 7.2 Offline and consistency

- On resume without connectivity, SnackBar: “No internet. Data will refresh when connected.” Offline queue syncs when back online. No persistent “offline mode” banner on screens.
- UI patterns (loading, error, retry) are consistent across main screens.

### 7.3 Stability

- **Route Map:** Uses `_fetchRouteRequestId` to avoid applying stale results and setState after dispose.
- **Route Map:** Controllers not disposed (see Lifecycle L1).
- **Other screens:** Should ensure `mounted` checks after async calls before setState.
- **Crashes:** No global crash handler or Crashlytics referenced; recommend adding.

### 7.4 UX and stability recommendations

| Area | Recommendation |
|------|----------------|
| Error messages | Differentiate network, auth, and server errors with user-friendly, non-technical messages. |
| Offline | Consider a small persistent indicator (e.g. banner or icon) when offline. |
| Crash reporting | Integrate Firebase Crashlytics (or similar) and route uncaught errors. |
| Stability | Add controller disposal (Route Map); add `mounted` checks after all async gaps before setState. |

### 7.5 Navigation and session handling

- **Navigation:** Splash (2s delay) → Login or Home based on token; Home is the hub. From Home, user can push to Profile, Attendance, or Route Map via actions; back returns to Home. Logout (Profile) uses `pushAndRemoveUntil` to Login and clears all auth data and background tracking.
- **Session:** Session is token-based; token stored in Flutter Secure Storage. Every authenticated API call sends Bearer token; 401 triggers refresh or logout. No server-side session store for the app; JWT expiry is enforced by backend. On logout, token and employee data are removed, backend logout endpoint is called for audit, and background service and duty reminders are stopped. Session survives process kill and app restart until logout or token expiry.

---

## Risk Matrix (Summary)

| ID | Finding | Severity | Scope |
|----|---------|----------|--------|
| S1 | HTTP in production | High | Security |
| S2 | Offline queue unencrypted | High | Security |
| S3 | No rate limiting | Medium | Security |
| S4 | CORS in production | Medium | Security |
| S5 | SECRET_KEY default | Medium | Security |
| S6 | Debug logging | Low | Security |
| S7 | PII in responses/logs | Low | Security |
| S8 | Unpinned dependencies / no CVE audit | Low | Security |
| P1 | Offline sync sequential | Medium | Performance |
| P2 | No debounce Route Map | Medium | Performance |
| P3 | Long routes in memory | Low | Performance |
| L1 | Controller disposal Route Map | Medium | Lifecycle |
| L3 | Overlapping API calls | Medium | Lifecycle |
| L4 | Duty state consistency | Low | Lifecycle |
| I1 | API docs drift | Low | Integration |
| I2 | No idempotency log-location | Medium | Integration |
| U1 | Generic error messages | Low | UX |
| U2 | No Crashlytics | Medium | UX/Stability |

---

## Prioritized Enterprise Roadmap

1. **Security (immediate)**  
   - Switch app to HTTPS and make base URL configurable.  
   - Encrypt offline location queue or move to secure storage.  
   - Set production CORS and SECRET_KEY via env; require SECRET_KEY in prod.

2. **Security (short term)**  
   - Add DRF rate limiting (auth and log-location).  
   - Remove or guard debug logging; audit PII in responses and logs.  
   - Pin backend dependencies; add `pip audit` / dependency-check and CVE review process.

3. **Lifecycle and stability**  
   - Add `dispose()` for Route Map animation and playback controllers.  
   - Add `mounted` checks after async before setState where missing.  
   - Optionally add request-id/single-flight for Home/Attendance refresh.

4. **Performance**  
   - Debounce Route Map filter changes.  
   - Improve offline sync (batch or parallel with progress).  
   - Verify backend attendance cache invalidation.

5. **Testing and CI/CD**  
   - Add CI (e.g. GitHub Actions) for Flutter and Django tests.  
   - Add backend tests for start-duty, end-duty, my-attendance, auto-end-duty.  
   - Add contract tests for app API; expand integration tests for critical flows.

6. **Integration**  
   - Publish and maintain App API contract (OpenAPI or markdown).  
   - Add idempotency or deduplication for log-location.  
   - Add API versioning for future changes.

7. **Android and QA**  
   - Execute compatibility matrix (API 29, 31, 33, 34+).  
   - Document permission and foreground-service checks.

8. **UX and observability**  
   - Integrate Crashlytics (or equivalent).  
   - Improve error messaging; consider offline indicator.  
   - Add logging/alerting for errors and latency.

---

## Appendices

### A. Key file references

| Area | Paths |
|------|--------|
| Security | `Genesis_Employee_App/lib/config/app_config.dart`, `Genesis_Employee_App/lib/services/auth_service.dart`, `Genesis_Employee_App/lib/services/api_service.dart`, `Genesis_Employee_App/lib/services/location_service.dart`, `Genesis_Employee_Attendance/employees/authentication.py`, `Genesis_Employee_Attendance/config/settings.py` |
| Performance | `Genesis_Employee_App/lib/services/foreground_refresh_service.dart`, `Genesis_Employee_App/lib/services/background_worker.dart`, `Genesis_Employee_App/lib/screens/route_map_screen.dart` |
| Testing | `Genesis_Employee_App/test/TEST_SCENARIOS.md`, `Genesis_Employee_Attendance/TESTING.md`, `Genesis_Employee_Attendance/tests/test_api.py` |
| Lifecycle | `Genesis_Employee_App/lib/main.dart`, `Genesis_Employee_App/lib/screens/home_screen.dart`, `Genesis_Employee_App/lib/screens/route_map_screen.dart` |
| Integration | `Genesis_Employee_Attendance/API_DOCUMENTATION.md`, `Genesis_Employee_Attendance/config/urls.py`, `Genesis_Employee_Attendance/attendance/urls.py` |
| Android | `Genesis_Employee_App/android/app/build.gradle`, `Genesis_Employee_App/android/app/src/main/AndroidManifest.xml` |
| UX | `Genesis_Employee_App/lib/screens/home_screen.dart`, `Genesis_Employee_App/lib/screens/attendance_screen.dart`, `Genesis_Employee_App/lib/screens/login_screen.dart`, `Genesis_Employee_App/lib/screens/route/widgets/route_error_view.dart` |

### B. Test commands

**Flutter (from repo root)**

```bash
cd Genesis_Employee_App
flutter pub get
flutter test test/unit test/widget test/helpers
flutter test integration_test/
```

Alternatively, from `Genesis_Employee_App`, run `run_tests.bat` to execute unit and widget tests (as referenced in TEST_SCENARIOS.md and the plan).

**Backend (Docker)**

```bash
cd Genesis_Employee_Attendance
docker compose run --rm web python manage.py test tests/
```

### C. Production config checklist

- [ ] `DEBUG=False`
- [ ] `SECRET_KEY` from environment
- [ ] `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` set
- [ ] `CORS_ALLOW_ALL_ORIGINS=False` and `CORS_ALLOWED_ORIGINS` set
- [ ] HTTPS for API and dashboard
- [ ] App base URL points to HTTPS API
- [ ] Rate limiting enabled
- [ ] No debug file logging in production

### D. Measurable success criteria (examples)

The following are example metrics to verify that audit recommendations have been implemented successfully. Adjust targets to match organizational policy.

| Area | Criterion | Example target |
|------|-----------|----------------|
| Security | HTTPS only in production | 100% of API traffic over TLS; no HTTP base URL in release build. |
| Security | Offline queue protected | Offline location entries encrypted or in secure storage; zero plain-text location lists in SharedPreferences. |
| Security | Rate limiting active | Login endpoint rejects &gt; N requests per IP per minute (e.g. 10); log-location accepts &lt; M per user per minute (e.g. 120). |
| Performance | Offline sync | Sync of 100 queued locations completes in &lt; 60 s or shows progress; no UI freeze &gt; 2 s. |
| Performance | Route Map filters | Debounce 300–500 ms; no more than one request per user action. |
| Lifecycle | Controller disposal | Zero controller/timer leaks on Route Map after 10 open/close cycles (DevTools or leak detector). |
| Testing | Regression | CI runs full Flutter and Django test suites on every PR; critical-path tests run on every commit. |
| Integration | API contract | App API spec (OpenAPI or markdown) exists and is updated with every endpoint change. |
| UX | Crash reporting | Uncaught errors and fatal crashes reported to Crashlytics or equivalent; &gt; 95% of sessions without crash. |

---

*End of report.*
