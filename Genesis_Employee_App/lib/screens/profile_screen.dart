import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/foreground_refresh_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _employeeData;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    ForegroundRefreshService().addListener(_onForegroundRefresh);
    _loadProfile();
  }

  @override
  void dispose() {
    ForegroundRefreshService().removeListener(_onForegroundRefresh);
    super.dispose();
  }

  void _onForegroundRefresh() {
    if (!mounted) return;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final data = await ApiService().getMyProfile();
    final profile = data ?? await _authService.getEmployeeData();
    if (data != null) {
      try {
        await _authService.saveEmployeeData(data);
      } catch (_) {
        // e.g. secure storage unavailable (tests); still show profile
      }
    }
    if (mounted) {
      setState(() {
        _employeeData = profile;
        _isLoading = false;
        _loadError = (data == null && profile == null)
            ? "Could not load profile. Check connection."
            : null;
      });
    }
  }

  Future<void> _onRefresh() async {
    ApiService().initialize();
    await _loadProfile();
  }

  Future<void> _logout() async {
    await _authService.logout(reason: 'MANUAL_LOGOUT');
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null && _employeeData == null) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(title: const Text('My Profile'), elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.error),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _loadError = null);
                    _loadProfile();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final name = _employeeData?['name'] ?? 'Employee Name';
    final email = _employeeData?['email'] ?? 'email@example.com';
    final id = _employeeData?['employee_id'] ?? 'ID';
    final department = _employeeData?['department_name'] ?? '—';
    final designation = _employeeData?['designation_name'] ?? '—';
    final phone = _employeeData?['phone'] as String?;
    final joinDateRaw = _employeeData?['join_date'] as String?;
    final accountAgeDays = _employeeData?['account_age_days'];
    final isNewEmployee = _employeeData?['is_new_employee'] == true;
    final profilePictureUrl = _employeeData?['profile_picture_url'] as String?;

    String joinDateFormatted = '—';
    if (joinDateRaw != null && joinDateRaw.isNotEmpty) {
      try {
        final d = DateTime.parse(joinDateRaw);
        joinDateFormatted = DateFormat('EEEE, d MMM yyyy').format(d);
      } catch (_) {}
    }
    final accountAgeStr = accountAgeDays is int
        ? 'With us for $accountAgeDays days'
        : (accountAgeDays is num ? 'With us for ${accountAgeDays.toInt()} days' : '—');

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('My Profile'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  backgroundImage: (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
                      ? NetworkImage(profilePictureUrl)
                      : null,
                  child: (profilePictureUrl == null || profilePictureUrl.isEmpty)
                      ? Icon(
                          Icons.person,
                          size: 80,
                          color: colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (isNewEmployee) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'New employee',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                designation,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              _buildInfoCard(context, Icons.badge, 'Employee ID', id),
              _buildInfoCard(context, Icons.email, 'Email', email),
              _buildInfoCard(context, Icons.business, 'Department', department),
              if (phone != null && phone.isNotEmpty)
                _buildInfoCard(context, Icons.phone_outlined, 'Phone', phone),
              _buildInfoCard(context, Icons.calendar_today_outlined, 'Join date', joinDateFormatted),
              _buildInfoCard(context, Icons.schedule_outlined, 'Account', accountAgeStr),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Logout'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      color: colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: colorScheme.primary, size: 24),
        title: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        subtitle: Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
