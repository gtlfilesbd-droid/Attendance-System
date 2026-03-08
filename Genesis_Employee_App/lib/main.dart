import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_navigator.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';
import 'services/foreground_refresh_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize API Service (lightweight, sync)
  ApiService().initialize();

  // Run app immediately so first frame (splash) shows without blocking.
  // LocationService + PushNotification (permissions) run after first frame in AppLifecycleWrapper.
  runApp(const AppLifecycleWrapper());
}

/// Wraps the app to observe lifecycle and trigger foreground refresh when
/// the app returns from background (logged-in only), with debounce and offline handling.
class AppLifecycleWrapper extends StatefulWidget {
  const AppLifecycleWrapper({super.key});

  @override
  State<AppLifecycleWrapper> createState() => _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends State<AppLifecycleWrapper>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initFuture => _initCompleter.future;

  @override
  void initState() {
    super.initState();
    rootNavigatorKey = _navigatorKey;
    WidgetsBinding.instance.addObserver(this);
    ApiService.onSessionExpired = _navigateToLogin;
    WidgetsBinding.instance.addPostFrameCallback((_) => _runInitAfterFirstFrame());
  }

  Future<void> _runInitAfterFirstFrame() async {
    try {
      await Future.wait([
        LocationService().initializeService(),
        PushNotificationService.initialize(),
      ]);
    } catch (e) {
      // e.g. Firebase init skipped if google-services.json missing
      assert(true, 'Init skipped: $e');
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  void _navigateToLogin() {
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // Record when app truly goes to background so ForegroundRefreshService can
      // compute the correct backgroundDuration on resume.  We intentionally do NOT
      // record AppLifecycleState.inactive here: on Android the lifecycle sequence
      // when RETURNING from background is paused → inactive → resumed, so
      // notifyAppPaused() on inactive would reset _lastPausedAt to DateTime.now()
      // just milliseconds before onAppResumed() runs, making isLongBackground
      // always false regardless of how long the app was really in the background.
      ForegroundRefreshService().notifyAppPaused();
    }
    if (state == AppLifecycleState.resumed) {
      // Run resume work after first frame so UI paints and responds first (avoids hang after long background).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleResumed();
      });
    }
  }

  Future<void> _handleResumed() async {
    final isLoggedIn = await AuthService().isLoggedIn();
    if (!isLoggedIn) return;

    final result = await ForegroundRefreshService().onAppResumed();
    if (!mounted) return;
    // Only show "No internet" when we actually detected no connectivity; not on token refresh failure.
    if (result == ForegroundRefreshResult.skippedOffline) {
      _scaffoldKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('No internet. Data will refresh when connected.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GenesisEmployeeApp(
      scaffoldMessengerKey: _scaffoldKey,
      navigatorKey: _navigatorKey,
      initFuture: initFuture,
    );
  }
}

class GenesisEmployeeApp extends StatelessWidget {
  const GenesisEmployeeApp({
    super.key,
    this.scaffoldMessengerKey,
    this.navigatorKey,
    this.initFuture,
  });

  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;
  final GlobalKey<NavigatorState>? navigatorKey;
  final Future<void>? initFuture;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Genesis Employee',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        textTheme: Typography.material2021().black,
        cardTheme: CardThemeData(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 2,
          ),
        ),
      ),
      home: SplashScreen(initFuture: initFuture),
    );
  }
}


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.initFuture});

  final Future<void>? initFuture;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    // Wait for both: min splash time (2s) and permissions + services init (before login).
    await Future.wait([
      Future.delayed(const Duration(seconds: 2)),
      widget.initFuture ?? Future.value(),
    ]);
    final isLoggedIn = await _authService.isLoggedIn();

    // Proactive token refresh before Home so first API calls rarely hit 401 (e.g. after app kill).
    if (isLoggedIn) {
      var result = await _authService.refreshToken();
      if (result == RefreshResult.networkOrTransientError) {
        await Future.delayed(const Duration(seconds: 2));
        result = await _authService.refreshToken();
      }
      // Refresh token is genuinely invalid (expired >30 days or storage corrupt).
      // Clear session and send user to login rather than flashing HomeScreen with
      // a dead session, which triggers a second TOKEN_REFRESH_FAILED immediately.
      if (result == RefreshResult.invalidToken) {
        await _authService.logout(reason: 'SESSION_EXPIRED');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
        return;
      }
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              isLoggedIn ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business_center,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Genesis Employee',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
