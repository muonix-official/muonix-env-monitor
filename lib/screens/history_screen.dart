import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  final String deviceId;
  const HistoryScreen({super.key, required this.deviceId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> allReadings = [];
  List<Map<String, dynamic>> filteredReadings = [];
  bool isLoading = true;
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/history')
        .orderByChild('ts')
        .limitToLast(200)
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (mounted) {
        if (data != null) {
          List<Map<String, dynamic>> readings = [];
          data.forEach((key, value) {
            readings.add({
              'key': key,
              'temp': (value['temp'] ?? 0).toDouble(),
              'humidity': (value['humidity'] ?? 0).toDouble(),
              'gasLevel': (value['gasLevel'] ?? 0).toDouble(),
              'ts': value['ts'] ?? '',
            });
          });
          readings.sort((a, b) => b['ts'].compareTo(a['ts']));
          setState(() {
            allReadings = readings;
            filteredReadings = readings;
            isLoading = false;
          });
        } else {
          setState(() => isLoading = false);
        }
      }
    });
  }

  void _filterByDate(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    setState(() {
      selectedDate = date;
      filteredReadings = allReadings
          .where((r) => r['ts'].toString().startsWith(dateStr))
          .toList();
    });
  }

  void _clearFilter() {
    setState(() {
      selectedDate = null;
      filteredReadings = allReadings;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _filterByDate(picked);
    }
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      return DateFormat('dd MMM yyyy  hh:mm a').format(dt);
    } catch (e) {
      return ts.isNotEmpty ? ts : 'No timestamp';
    }
  }

  Color _getTempColor(double temp) {
    if (temp < 18 || temp > 35) return Colors.red;
    return Colors.green;
  }

  Color _getHumColor(double hum) {
    if (hum < 30 || hum > 80) return Colors.red;
    return Colors.blue;
  }

  Color _getGasColor(double gas) {
    if (gas > 70) return Colors.red;
    if (gas > 55) return Colors.orange;
    return Colors.purple;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickDate,
            tooltip: 'Filter by date',
          ),
          if (selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearFilter,
              tooltip: 'Clear filter',
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (selectedDate != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.blue.withValues(alpha: 0.1),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_alt,
                            color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Showing: ${DateFormat('dd MMM yyyy').format(selectedDate!)}  (${filteredReadings.length} records)',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                  ),

                if (filteredReadings.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryChip(
                          'Avg Temp',
                          '${(filteredReadings.map((r) => r['temp'] as double).reduce((a, b) => a + b) / filteredReadings.length).toStringAsFixed(1)}°C',
                          Colors.orange,
                        ),
                        _buildSummaryChip(
                          'Avg Humidity',
                          '${(filteredReadings.map((r) => r['humidity'] as double).reduce((a, b) => a + b) / filteredReadings.length).toStringAsFixed(1)}%',
                          Colors.blue,
                        ),
                        _buildSummaryChip(
                          'Avg Gas',
                          '${(filteredReadings.map((r) => r['gasLevel'] as double).reduce((a, b) => a + b) / filteredReadings.length).toStringAsFixed(1)}%',
                          Colors.purple,
                        ),
                        _buildSummaryChip(
                          'Total',
                          '${filteredReadings.length}',
                          Colors.grey,
                        ),
                      ],
                    ),
                  ),

                const Divider(height: 1),

                filteredReadings.isEmpty
                    ? const Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history,
                                  size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No records found',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Expanded(
                        child: ListView.builder(
                          itemCount: filteredReadings.length,
                          itemBuilder: (context, index) {
                            final r = filteredReadings[index];
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatTimestamp(r['ts']),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      // Temp
                                      _buildTag(
                                        '${r['temp'].toStringAsFixed(1)}°C',
                                        Icons.thermostat,
                                        _getTempColor(r['temp']),
                                      ),
                                      const SizedBox(width: 8),
                                      // Humidity
                                      _buildTag(
                                        '${r['humidity'].toStringAsFixed(1)}%',
                                        Icons.water_drop,
                                        _getHumColor(r['humidity']),
                                      ),
                                      const SizedBox(width: 8),
                                      // Gas
                                      _buildTag(
                                        '${r['gasLevel'].toStringAsFixed(1)}%',
                                        Icons.air,
                                        _getGasColor(r['gasLevel']),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ],
            ),
    );
  }

  Widget _buildTag(String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}