import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../widgets/contact_us_footer.dart';

class HistoryScreen extends StatefulWidget {
  final String deviceId;
  const HistoryScreen({super.key, required this.deviceId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _allHistory = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  DateTime? _selectedDate;

  double _minTemp = 18;
  double _maxTemp = 35;
  double _minHumidity = 30;
  double _maxHumidity = 70;
  double _maxGas = 20;

  StreamSubscription? _historySub;
  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadHistory();
  }

  @override
  void dispose() {
    _historySub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  void _loadSettings() {
    _settingsSub = FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/settings')
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null || !mounted) return;
      setState(() {
        _minTemp     = (data['minTemp']     as num?)?.toDouble() ?? 18;
        _maxTemp     = (data['maxTemp']     as num?)?.toDouble() ?? 35;
        _minHumidity = (data['minHumidity'] as num?)?.toDouble() ?? 30;
        _maxHumidity = (data['maxHumidity'] as num?)?.toDouble() ?? 70;
        _maxGas      = (data['maxGas']      as num?)?.toDouble() ?? 20;
      });
    });
  }

  void _loadHistory() {
    _historySub = FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/history')
        .orderByKey()
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;

      if (data == null) {
        setState(() {
          _allHistory = [];
          _filtered = [];
          _loading = false;
        });
        return;
      }

      final List<Map<String, dynamic>> entries = [];
      for (final e in data.entries) {
        final val = e.value as Map?;
        if (val == null) continue;

        // FIX: ts from firmware is an ISO string e.g. "2024-01-01T12:00:00Z"
        // Parse it to a DateTime then to milliseconds for sorting/display.
        // Also handle the case where ts might already be an int (millis).
        final rawTs = val['ts'];
        int? tsMillis;
        if (rawTs is int) {
          tsMillis = rawTs;
        } else if (rawTs is String && rawTs.isNotEmpty) {
          try {
            tsMillis = DateTime.parse(rawTs).millisecondsSinceEpoch;
          } catch (_) {
            tsMillis = null;
          }
        }

        entries.add({
          'key': e.key,
          'temp':     (val['temp']     as num?)?.toDouble(),
          'humidity': (val['humidity'] as num?)?.toDouble(),
          'gasLevel': (val['gasLevel'] as num?)?.toDouble(),
          'tsMillis': tsMillis,  // always an int or null
          'tsRaw':    rawTs,
        });
      }

      // Sort descending — newest first
      entries.sort((a, b) {
        final ta = a['tsMillis'] as int? ?? 0;
        final tb = b['tsMillis'] as int? ?? 0;
        return tb.compareTo(ta);
      });

      if (mounted) {
        setState(() {
          _allHistory = entries;
          _loading = false;
          _applyFilter();
        });
      }
    });
  }

  void _applyFilter() {
    if (_selectedDate == null) {
      _filtered = List.from(_allHistory);
      return;
    }
    _filtered = _allHistory.where((e) {
      final ts = e['tsMillis'] as int?;
      if (ts == null) return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      return dt.year == _selectedDate!.year &&
          dt.month == _selectedDate!.month &&
          dt.day == _selectedDate!.day;
    }).toList();
  }

  Color _getTempColor(double? v) {
    if (v == null) return Colors.grey;
    if (v < _minTemp || v > _maxTemp) return Colors.red;
    if (v > _maxTemp - 3 || v < _minTemp + 3) return Colors.orange;
    return Colors.green;
  }

  Color _getHumColor(double? v) {
    if (v == null) return Colors.grey;
    if (v < _minHumidity || v > _maxHumidity) return Colors.red;
    if (v > _maxHumidity - 5 || v < _minHumidity + 5) return Colors.orange;
    return Colors.blue;
  }

  Color _getGasColor(double? v) {
    if (v == null) return Colors.grey;
    if (v > _maxGas) return Colors.red;
    if (v > _maxGas * 0.8) return Colors.orange;
    return Colors.green;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _applyFilter();
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _selectedDate = null;
      _applyFilter();
    });
  }

  Map<String, double?> _computeAverages() {
    if (_filtered.isEmpty) {
      return {'temp': null, 'humidity': null, 'gas': null};
    }
    double tSum = 0, hSum = 0, gSum = 0;
    int tC = 0, hC = 0, gC = 0;
    for (final e in _filtered) {
      if (e['temp'] != null)     { tSum += e['temp'];     tC++; }
      if (e['humidity'] != null) { hSum += e['humidity']; hC++; }
      if (e['gasLevel'] != null) { gSum += e['gasLevel']; gC++; }
    }
    return {
      'temp':     tC > 0 ? tSum / tC : null,
      'humidity': hC > 0 ? hSum / hC : null,
      'gas':      gC > 0 ? gSum / gC : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy, hh:mm a');
    final avgs = _computeAverages();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text('Sensor History',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _pickDate,
            tooltip: 'Filter by date',
          ),
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearFilter,
              tooltip: 'Clear filter',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_selectedDate != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Row(children: [
                      const Icon(Icons.filter_list,
                          color: Colors.blueAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Showing: ${DateFormat('dd MMM yyyy').format(_selectedDate!)}',
                        style: const TextStyle(
                            color: Colors.blueAccent, fontSize: 13),
                      ),
                    ]),
                  ),
                if (_filtered.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(children: [
                      _avgChip(
                          'Avg Temp',
                          avgs['temp'] != null
                              ? '${avgs['temp']!.toStringAsFixed(1)}°C'
                              : '—',
                          _getTempColor(avgs['temp'])),
                      const SizedBox(width: 8),
                      _avgChip(
                          'Avg Hum',
                          avgs['humidity'] != null
                              ? '${avgs['humidity']!.toStringAsFixed(1)}%'
                              : '—',
                          _getHumColor(avgs['humidity'])),
                      const SizedBox(width: 8),
                      _avgChip(
                          'Avg Gas',
                          avgs['gas'] != null
                              ? '${avgs['gas']!.toStringAsFixed(1)}%'
                              : '—',
                          _getGasColor(avgs['gas'])),
                    ]),
                  ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            _selectedDate != null
                                ? 'No records for this date.'
                                : 'No history yet.',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final e = _filtered[i];
                            final tsMillis = e['tsMillis'] as int?;
                            final dt = tsMillis != null
                                ? DateTime.fromMillisecondsSinceEpoch(
                                        tsMillis)
                                    .toLocal()
                                : null;

                            return Card(
                              color: const Color(0xFF1B2838),
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (dt != null)
                                      Text(
                                        fmt.format(dt),
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11),
                                      ),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      _statChip(
                                        Icons.thermostat,
                                        '${e['temp']?.toStringAsFixed(1) ?? '—'}°C',
                                        _getTempColor(
                                            e['temp'] as double?),
                                      ),
                                      const SizedBox(width: 8),
                                      _statChip(
                                        Icons.water_drop,
                                        '${e['humidity']?.toStringAsFixed(1) ?? '—'}%',
                                        _getHumColor(
                                            e['humidity'] as double?),
                                      ),
                                      const SizedBox(width: 8),
                                      _statChip(
                                        Icons.gas_meter_outlined,
                                        '${e['gasLevel']?.toStringAsFixed(1) ?? '—'}%',
                                        _getGasColor(
                                            e['gasLevel'] as double?),
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const ContactUsFooter(),
              ],
            ),
    );
  }

  Widget _avgChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, Color color) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(value,
          style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    ]);
  }
}