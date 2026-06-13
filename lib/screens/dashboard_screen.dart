import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import '../services/notification_service.dart';
import '../widgets/contact_us_footer.dart';

class DashboardScreen extends StatefulWidget {
  final String deviceId;
  const DashboardScreen({super.key, required this.deviceId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double temp = 0;
  double humidity = 0;
  double gasLevel = 0;
  bool gasAlert = false;
  bool alert = false;
  bool isLoading = true;
  bool accessDenied = false;
  String _accessStatus = '';
  String lastUpdated = '';

  double minTemp = 18;
  double maxTemp = 35;
  double minHum = 30;
  double maxHum = 80;
  double maxGas = 70;

  late DatabaseReference _liveRef;
  late DatabaseReference _settingsRef;

  @override
  void initState() {
    super.initState();
    _liveRef = FirebaseDatabase.instance.ref('devices/${widget.deviceId}/live');
    _settingsRef = FirebaseDatabase.instance.ref('devices/${widget.deviceId}/settings');
    _checkAccessThenLoad();
  }

  Future<void> _checkAccessThenLoad() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pop(context);
      return;
    }

    final snap = await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/members/${user.uid}')
        .get();

    if (!snap.exists || snap.value != 'approved') {
      final reqSnap = await FirebaseDatabase.instance
          .ref('devices/${widget.deviceId}/requests/${user.uid}/status')
          .get();

      if (mounted) {
        setState(() {
          isLoading = false;
          accessDenied = true;
          _accessStatus = reqSnap.exists ? 'pending' : 'none';
        });
      }
      return;
    }

    _listenToData();
    _loadSettings();
  }

  Future<void> _sendAccessRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ownerSnap = await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/meta/owner_uid')
        .get();

    if (!ownerSnap.exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find device owner. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final ownerUid = ownerSnap.value as String;

    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/requests/${user.uid}')
        .set({
      'uid': user.uid,
      'email': user.email,
      'requestedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    });

    await FirebaseDatabase.instance
        .ref('users/$ownerUid/notifications/${user.uid}_${widget.deviceId}')
        .set({
      'type': 'access_request',
      'deviceId': widget.deviceId,
      'requesterUid': user.uid,
      'requesterEmail': user.email,
      'requestedAt': DateTime.now().toIso8601String(),
      'read': false,
    });

    if (mounted) {
      setState(() => _accessStatus = 'pending');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access request sent to owner!'),
          backgroundColor: Colors.green,
        ),
      );
    }
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
            gasDetected: data['gasAlert'] ?? false,
          );
        }

        final now = TimeOfDay.now();
        setState(() {
          temp = (data['temp'] ?? 0).toDouble();
          humidity = (data['humidity'] ?? 0).toDouble();
          gasLevel = (data['gasLevel'] ?? 0).toDouble();
          gasAlert = data['gasAlert'] ?? false;
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
          maxGas = (data['maxGas'] ?? 70).toDouble();
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

  Color _getGasColor() {
    if (gasAlert || gasLevel > maxGas) return Colors.red;
    if (gasLevel > maxGas * 0.75) return Colors.orange;
    return const Color(0xFF00C853);
  }

  @override
  Widget build(BuildContext context) {
    // Loading screen
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        body: Column(
          children: [
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
            const ContactUsFooter(),
          ],
        ),
      );
    }

    // Access denied screen
    if (accessDenied) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D1B2A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Access Required',
              style: TextStyle(color: Colors.white)),
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4)),
                        ),
                        child: Icon(
                          _accessStatus == 'pending'
                              ? Icons.pending_actions
                              : Icons.lock_outline,
                          size: 52,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _accessStatus == 'pending'
                            ? 'Request Pending'
                            : 'Access Required',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _accessStatus == 'pending'
                            ? 'Your request is waiting for owner approval.\n\nYou\'ll get access once the owner approves.'
                            : 'You don\'t have access to this device.\nSend a request to the owner.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_accessStatus != 'pending')
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.send),
                            label: const Text(
                              'Send Access Request',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _sendAccessRequest,
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white10,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Go Back'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const ContactUsFooter(),
          ],
        ),
      );
    }

    // Main dashboard
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
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
                                const Color(0xFF00C853).withValues(alpha: 0.05),
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
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: alert ? Colors.red : const Color(0xFF00C853),
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
                    subtitle: 'Safe: ${minTemp.toInt()}°C — ${maxTemp.toInt()}°C',
                    progress:
                        ((temp - minTemp) / (maxTemp - minTemp)).clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 12),
                  _buildSensorCard(
                    title: 'Humidity',
                    value: humidity.toStringAsFixed(1),
                    unit: '%',
                    icon: Icons.water_drop,
                    color: _getHumColor(),
                    subtitle: 'Safe: ${minHum.toInt()}% — ${maxHum.toInt()}%',
                    progress: (humidity / 100).clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 12),
                  _buildGasCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          const ContactUsFooter(),
        ],
      ),
    );
  }

  Widget _buildGasCard() {
    final color = _getGasColor();
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
                      'Safe: below ${maxGas.toInt()}%',
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
                      text: gasLevel.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    TextSpan(
                      text: '%',
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
              value: (gasLevel / 100).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
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