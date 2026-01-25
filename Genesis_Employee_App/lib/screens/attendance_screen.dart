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
  List<dynamic> _attendanceRecords = [];
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
        // API returns { "summary": {...}, "records": [...] } or similar depending on implementation
        // Based on previous checks, it returns Map<String, dynamic>. 
        // Let's assume the API structure from export_csv view logic which implies list of records.
        // Wait, getMyAttendance in ApiService returns Map<String, dynamic>.
        // Let's inspect what the API returns. The export_csv view logic suggests it iterates over queryset.
        // The ViewSet for attendance likely returns a list or paginated list.
        // If ApiService.getMyAttendance returns the 'data' field of the response, check if it's a List or Map.
        // The previous step implemented `getMyAttendance` returning `response.data['data']`.
        // If the backend `AttendanceViewSet` returns a list, then `data` is a list.
        // If it's paginated, it might be `{ "results": [...] }`.
        
        // Let's safely handle if it's a list or map containing list.
        if (result is List) {
           _attendanceRecords = result;
        } else if (result.containsKey('results')) {
           _attendanceRecords = result['results'];
        } else if (result.containsKey('records')) {
           _attendanceRecords = result['records'];
        } else {
           // Fallback or empty
           _attendanceRecords = [];
        }
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PRESENT':
        return Colors.green;
      case 'LATE':
        return Colors.orange;
      case 'ABSENT':
        return Colors.red;
      case 'HALF_DAY':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Attendance'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage))
              : _attendanceRecords.isEmpty
                  ? const Center(child: Text('No attendance records found'))
                  : ListView.builder(
                      itemCount: _attendanceRecords.length,
                      padding: const EdgeInsets.all(8.0),
                      itemBuilder: (context, index) {
                        final record = _attendanceRecords[index];
                        final date = record['date'] ?? '';
                        final checkIn = record['check_in_time'] ?? '--:--';
                        final checkOut = record['check_out_time'] ?? '--:--';
                        final totalHours = record['total_hours'] ?? '0';
                        final status = record['status'] ?? 'UNKNOWN';

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      date,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: _getStatusColor(status)),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: _getStatusColor(status),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Column(
                                      children: [
                                        const Text('Check In',
                                            style: TextStyle(
                                                color: Colors.grey, fontSize: 12)),
                                        Text(checkIn,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    Column(
                                      children: [
                                        const Text('Check Out',
                                            style: TextStyle(
                                                color: Colors.grey, fontSize: 12)),
                                        Text(checkOut,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    Column(
                                      children: [
                                        const Text('Total Hours',
                                            style: TextStyle(
                                                color: Colors.grey, fontSize: 12)),
                                        Text('${totalHours}h',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
