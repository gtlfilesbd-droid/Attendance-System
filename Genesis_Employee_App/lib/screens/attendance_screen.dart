import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _byDate = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchAttendance();
  }

  Future<void> _fetchAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 30));
    final dateFormat = DateFormat('yyyy-MM-dd');

    final result = await _apiService.getMyAttendance(
      startDate: dateFormat.format(startDate),
      endDate: dateFormat.format(now),
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.containsKey('by_date') && result['by_date'] is List) {
          _byDate = List<dynamic>.from(result['by_date'] as List);
        } else {
          _byDate = [];
        }
      });
    }
  }

  /// Format ISO datetime string to time only in device local time; respects 12/24 hour format
  String _formatTime(BuildContext context, String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(iso);
      final local = dt.isUtc ? dt.toLocal() : dt;
      return TimeOfDay.fromDateTime(local).format(context);
    } catch (_) {
      return '--:--';
    }
  }

  /// Format duration in seconds as "Xh Ym Zs" (always show hours, minutes, seconds for accuracy)
  String _formatDurationHMS(int totalSeconds) {
    if (totalSeconds < 0) return '0h 0m 0s';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  bool _isToday(String dateStr) {
    if (dateStr.isEmpty) return false;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return dateStr == today;
  }

  /// Compute session duration in seconds from start_time and end_time (ISO); fallback to total_hours if parse fails
  int _sessionDurationSeconds(Map<String, dynamic> s) {
    final startStr = s['start_time'] as String?;
    final endStr = s['end_time'] as String?;
    if (startStr != null && startStr.isNotEmpty && endStr != null && endStr.isNotEmpty) {
      try {
        final start = DateTime.parse(startStr);
        final end = DateTime.parse(endStr);
        final startLocal = start.isUtc ? start.toLocal() : start;
        final endLocal = end.isUtc ? end.toLocal() : end;
        return endLocal.difference(startLocal).inSeconds;
      } catch (_) {}
    }
    final hours = (s['total_hours'] is num) ? (s['total_hours'] as num).toDouble() : 0.0;
    return (hours * 3600).round();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('My Attendance'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchAttendance,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Text(
                    _errorMessage,
                    style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.error),
                  ),
                )
              : _byDate.isEmpty
                  ? Center(
                      child: Text(
                        'No attendance records found',
                        style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchAttendance,
                      child: ListView.builder(
                        itemCount: _byDate.length + 1,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Times are as recorded when duty started/ended.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            );
                          }
                          final day = _byDate[index - 1];
                          final dateStr = day['date'] as String? ?? '';
                          final sessions = day['sessions'] is List
                              ? List<dynamic>.from(day['sessions'] as List)
                              : <dynamic>[];
                          int dayTotalSeconds = 0;
                          for (final s in sessions) {
                            if (s is Map<String, dynamic>) {
                              dayTotalSeconds += _sessionDurationSeconds(s);
                            }
                          }

                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            color: colorScheme.surface,
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateStr,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...sessions.asMap().entries.map((entry) {
                                    final i = entry.key;
                                    final s = entry.value as Map<String, dynamic>;
                                    final startTime = _formatTime(context, s['start_time'] as String?);
                                    final startLoc = s['start_location'] as String? ?? '—';
                                    final endTime = _formatTime(context, s['end_time'] as String?);
                                    final endLoc = s['end_location'] as String? ?? '—';
                                    final sessionSecs = _sessionDurationSeconds(s);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (i > 0) Divider(height: 20, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.play_arrow, size: 20, color: colorScheme.primary),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Start: $startTime',
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: colorScheme.onSurface,
                                                      ),
                                                    ),
                                                    Text(
                                                      startLoc,
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: colorScheme.onSurfaceVariant,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.stop, size: 20, color: colorScheme.error),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'End: ${endTime == '--:--' ? '—' : endTime}',
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: colorScheme.onSurface,
                                                      ),
                                                    ),
                                                    Text(
                                                      endLoc,
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: colorScheme.onSurfaceVariant,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Session: ${_formatDurationHMS(sessionSecs)}',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  Divider(height: 24, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        _isToday(dateStr)
                                            ? "Today's Duty Time: ${_formatDurationHMS(dayTotalSeconds)}"
                                            : 'Total: ${_formatDurationHMS(dayTotalSeconds)}',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
