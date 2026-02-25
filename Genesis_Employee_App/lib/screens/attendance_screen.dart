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
  late DateTime _filterStartDate;
  late DateTime _filterEndDate;
  static final _dateFormat = DateFormat('yyyy-MM-dd');
  static final _dateDisplayFormat = DateFormat('EEEE, d MMM yyyy');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _filterEndDate = DateTime(now.year, now.month, now.day);
    _filterStartDate = _filterEndDate.subtract(const Duration(days: 30));
    _fetchAttendance();
  }

  Future<void> _fetchAttendance() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final result = await _apiService.getMyAttendance(
      startDate: _dateFormat.format(_filterStartDate),
      endDate: _dateFormat.format(_filterEndDate),
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

  Future<void> _onRefresh() async {
    ApiService().initialize();
    await _fetchAttendance();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterStartDate,
      firstDate: DateTime(2020),
      lastDate: _filterEndDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _filterStartDate = DateTime(picked.year, picked.month, picked.day);
      });
      _fetchAttendance();
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterEndDate,
      firstDate: _filterStartDate,
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null && mounted) {
      setState(() {
        _filterEndDate = DateTime(picked.year, picked.month, picked.day);
      });
      _fetchAttendance();
    }
  }

  void _applyPresetToday() {
    final today = DateTime.now();
    setState(() {
      _filterStartDate = DateTime(today.year, today.month, today.day);
      _filterEndDate = _filterStartDate;
    });
    _fetchAttendance();
  }

  void _applyPresetLast7() {
    final now = DateTime.now();
    setState(() {
      _filterEndDate = DateTime(now.year, now.month, now.day);
      _filterStartDate = _filterEndDate.subtract(const Duration(days: 6));
    });
    _fetchAttendance();
  }

  void _applyPresetLast30() {
    final now = DateTime.now();
    setState(() {
      _filterEndDate = DateTime(now.year, now.month, now.day);
      _filterStartDate = _filterEndDate.subtract(const Duration(days: 29));
    });
    _fetchAttendance();
  }

  /// Format ISO datetime string to time only (with seconds) in device local time; respects 12/24 hour format
  String _formatTime(BuildContext context, String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(iso);
      final local = dt.isUtc ? dt.toLocal() : dt;
      final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
      return use24
          ? DateFormat('HH:mm:ss').format(local)
          : DateFormat('h:mm:ss a').format(local);
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

  /// Compute session duration in seconds. Prefers duration_seconds; else from timestamps (rounded); else total_hours.
  int _sessionDurationSeconds(Map<String, dynamic> s) {
    final dur = s['duration_seconds'];
    if (dur is int) return dur;
    if (dur is num) return dur.round();

    final startStr = s['start_time'] as String?;
    final endStr = s['end_time'] as String?;
    if (startStr != null && startStr.isNotEmpty && endStr != null && endStr.isNotEmpty) {
      try {
        final start = DateTime.parse(startStr);
        final end = DateTime.parse(endStr);
        final startLocal = start.isUtc ? start.toLocal() : start;
        final endLocal = end.isUtc ? end.toLocal() : end;
        return ((endLocal.millisecondsSinceEpoch - startLocal.millisecondsSinceEpoch) / 1000).round();
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _isLoading ? null : _pickStartDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'From',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _dateDisplayFormat.format(_filterStartDate),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward, size: 20, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: _isLoading ? null : _pickEndDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'To',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _dateDisplayFormat.format(_filterEndDate),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('Today'),
                          selected: _filterStartDate == _filterEndDate &&
                              _dateFormat.format(_filterStartDate) ==
                                  _dateFormat.format(DateTime.now()),
                          onSelected: _isLoading ? null : (_) => _applyPresetToday(),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Last 7 days'),
                          selected: _filterEndDate.difference(_filterStartDate).inDays == 6,
                          onSelected: _isLoading ? null : (_) => _applyPresetLast7(),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Last 30 days'),
                          selected: _filterEndDate.difference(_filterStartDate).inDays == 29,
                          onSelected: _isLoading ? null : (_) => _applyPresetLast30(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
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
                      onRefresh: _onRefresh,
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
                                    dateStr.isNotEmpty
                                        ? _dateDisplayFormat.format(DateTime.parse(dateStr))
                                        : '—',
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
          ),
        ],
      ),
    );
  }
}
