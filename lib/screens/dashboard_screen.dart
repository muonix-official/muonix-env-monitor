import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import '../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  final String deviceId;
  const DashboardScreen({super.key, required this.deviceId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double temp = 0;
  double humidity = 0;
  bool gasDetected = false;
  bool alert = false;
  bool isLoading = true;
  String lastUpdated = '';

  double minTemp = 18;
  double maxTemp = 35;
  double minHum = 30;
  double maxHum = 80;

  late DatabaseReference _liveRef;
  late DatabaseReference _settingsRef;

  @override
  void initState() {
    super.initState();
    _liveRef =
        FirebaseDatabase.instance.ref('devices/${widget.deviceId}/live');
    _settingsRef =
        FirebaseDatabase.instance.ref('devices/${widget.deviceId}/settings');
    _listenToData();
    _loadSettings();
  }

  void _listenToData() {
    _liveRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        bool newAlert = data['alert'] ?? false;

        if (newAlert && !alert) {
          NotificationService.showAlertNotification(
            (data['temp'] ?? 0).toDouble(),
            (data['humidity'] ?? 0).toDouble(),
            gasDetected: data['gasDetected'] ?? false,
          );
        }

        final now = TimeOfDay.now();
        setState(() {
          temp = (data['temp'] ?? 0).toDouble();
          humidity = (data['humidity'] ?? 0).toDouble();
          gasDetected = data['gasDetected'] ?? false;
          alert = newAlert;
          isLoading = false;
          lastUpdated =
              'Updated at ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        });
      }
    });
  }

  void _loadSettings() {
    _settingsRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          minTemp = (data['minTemp'] ?? 18).toDouble();
          maxTemp = (data['maxTemp'] ?? 35).toDouble();
          minHum = (data['minHumidity'] ?? 30).toDouble();
          maxHum = (data['maxHumidity'] ?? 80).toDouble();
        });
      }
    });
  }

  Color _getTempColor() {
    if (temp < minTemp || temp > maxTemp) return Colors.red;
    if (temp > maxTemp - 3 || temp < minTemp + 3) return Colors.orange;
    return const Color(0xFF00C853);
  }

  Color _getHumColor() {
    if (humidity < minHum || humidity > maxHum) return Colors.red;
    if (humidity > maxHum - 5 || humidity < minHum + 5) return Colors.orange;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.deviceId,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryScreen(deviceId: widget.deviceId),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(deviceId: widget.deviceId),
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (alert)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.red, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '⚠️ Alert! Values outside safe range!',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: alert
                            ? [
                                Colors.red.withValues(alpha: 0.2),
                                Colors.red.withValues(alpha: 0.05),
                              ]
                            : [
                                const Color(0xFF00C853).withValues(alpha: 0.2),
                                const Color(0xFF00C853)
                                    .withValues(alpha: 0.05),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: alert
                            ? Colors.red.withValues(alpha: 0.4)
                            : const Color(0xFF00C853).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          alert ? Icons.dangerous : Icons.check_circle,
                          color: alert ? Colors.red : const Color(0xFF00C853),
                          size: 36,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert ? 'UNSAFE CONDITIONS' : 'ALL SAFE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: alert
                                      ? Colors.red
                                      : const Color(0xFF00C853),
                                ),
                              ),
                              if (lastUpdated.isNotEmpty)
                                Text(
                                  lastUpdated,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: alert
                                ? Colors.red
                                : const Color(0xFF00C853),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (alert
                                        ? Colors.red
                                        : const Color(0xFF00C853))
                                    .withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  _buildSensorCard(
                    title: 'Temperature',
                    value: temp.toStringAsFixed(1),
                    unit: '°C',
                    icon: Icons.thermostat,
                    color: _getTempColor(),
                    subtitle:
                        'Safe: ${minTemp.toInt()}°C — ${maxTemp.toInt()}°C',
                    progress: ((temp - minTemp) / (maxTemp - minTemp))
                        .clamp(0.0, 1.0),
                  ),

                  const SizedBox(height: 12),

                  _buildSensorCard(
                    title: 'Humidity',
                    value: humidity.toStringAsFixed(1),
                    unit: '%',
                    icon: Icons.water_drop,
                    color: _getHumColor(),
                    subtitle:
                        'Safe: ${minHum.toInt()}% — ${maxHum.toInt()}%',
                    progress: (humidity / 100).clamp(0.0, 1.0),
                  ),

                  const SizedBox(height: 12),

                  _buildGasCard(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildGasCard() {
    final color = gasDetected ? Colors.red : const Color(0xFF00C853);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.air, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gas (MQ-6)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                Text(
                  gasDetected ? 'Gas detected!' : 'No gas detected',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              gasDetected ? 'YES' : 'NO',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
    required String subtitle,
    required double progress,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    TextSpan(
                      text: unit,
                      style: TextStyle(
                        fontSize: 16,
                        color: color.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}