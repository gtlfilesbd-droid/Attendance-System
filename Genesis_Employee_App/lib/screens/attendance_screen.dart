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

  /// Format hours decimal to "Xh Ym"
  String _formatHours(num? hours) {
    if (hours == null) return '0h 0m';
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Attendance'),
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
              ? Center(child: Text(_errorMessage))
              : _byDate.isEmpty
                  ? const Center(child: Text('No attendance records found'))
                  : RefreshIndicator(
                      onRefresh: _fetchAttendance,
                      child: ListView.builder(
                        itemCount: _byDate.length,
                        padding: const EdgeInsets.all(8.0),
                        itemBuilder: (context, index) {
                          final day = _byDate[index];
                          final dateStr = day['date'] as String? ?? '';
                          final sessions = day['sessions'] is List
                              ? List<dynamic>.from(day['sessions'] as List)
                              : <dynamic>[];
                          final totalHours = (day['total_hours'] is num)
                              ? (day['total_hours'] as num).toDouble()
                              : 0.0;

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
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
                                    final sessionHours = (s['total_hours'] is num)
                                        ? (s['total_hours'] as num).toDouble()
                                        : 0.0;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (i > 0) const Divider(height: 16),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.play_arrow, size: 18, color: Colors.green),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Start: $startTime',
                                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                                    ),
                                                    Text(
                                                      startLoc,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
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
                                              const Icon(Icons.stop, size: 18, color: Colors.red),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'End: ${endTime == '--:--' ? '—' : endTime}',
                                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                                    ),
                                                    Text(
                                                      endLoc,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[600],
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Session: ${_formatHours(sessionHours)}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.blue[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Total: ${_formatHours(totalHours)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
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
