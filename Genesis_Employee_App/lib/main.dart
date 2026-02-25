import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Initialize API Service
  ApiService().initialize();

  // Initialize Background Service
  await LocationService().initializeService();

  // Initialize Firebase for FCM (duty reminder push when app is closed)
  try {
    await PushNotificationService.initialize();
  } catch (e) {
    // If google-services.json is missing, app still runs; add file for push
    assert(true, 'Firebase init skipped: $e');
  }

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _handleResumed();
    }
  }

  Future<void> _handleResumed() async {
    final isLoggedIn = await AuthService().isLoggedIn();
    if (!isLoggedIn) return;

    final result = await ForegroundRefreshService().onAppResumed();
    if (!mounted) return;
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
    return GenesisEmployeeApp(scaffoldMessengerKey: _scaffoldKey);
  }
}

class GenesisEmployeeApp extends StatelessWidget {
  const GenesisEmployeeApp({super.key, this.scaffoldMessengerKey});

  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: const SplashScreen(),
    );
  }
}


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

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

  _checkLoginStatus() async {
    await Future.delayed(const Duration(seconds: 2));
    final isLoggedIn = await _authService.isLoggedIn();
    
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
