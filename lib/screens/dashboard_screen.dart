import 'dart:async';
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
  bool isOnline = false;
  bool isWarmingUp = false;
  String _accessStatus = '';
  String lastUpdated = '';
  String deviceName = '';
  String _lastTs = '';
  Timer? _onlineCheckTimer;

  double minTemp = 18;
  double maxTemp = 35;
  double minHum = 30;
  double maxHum = 70;
  double maxGas = 20;

  bool _settingsLoaded = false;

  late DatabaseReference _liveRef;
  late DatabaseReference _settingsRef;

  @override
  void initState() {
    super.initState();
    _liveRef = FirebaseDatabase.instance.ref('devices/${widget.deviceId}/live');
    _settingsRef = FirebaseDatabase.instance.ref('devices/${widget.deviceId}/settings');
    _checkAccessThenLoad();
    _onlineCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {
          isOnline = _checkIsOnline(_lastTs);
        });
      }
    });
  }

  @override
  void dispose() {
    _onlineCheckTimer?.cancel();
    super.dispose();
  }

  bool _checkIsOnline(String? ts) {
    if (ts == null || ts.isEmpty) return false;
    try {
      final lastSeen = DateTime.parse(ts).toUtc();
      final diff = DateTime.now().toUtc().difference(lastSeen).inSeconds;
      return diff >= 0 && diff < 30;
    } catch (_) {
      return false;
    }
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

    await _loadSettingsFirst();
    _listenToData();
    _listenToSettings();
  }

  Future<void> _loadSettingsFirst() async {
    try {
      final snap = await _settingsRef.get();
      final data = snap.value as Map?;
      if (data != null && mounted) {
        setState(() {
          deviceName = data['deviceName'] ?? widget.deviceId;
          minTemp = (data['minTemp'] ?? 18).toDouble();
          maxTemp = (data['maxTemp'] ?? 35).toDouble();
          minHum = (data['minHumidity'] ?? 30).toDouble();
          maxHum = (data['maxHumidity'] ?? 70).toDouble();
          maxGas = (data['maxGas'] ?? 20).toDouble();
          _settingsLoaded = true;
        });
      } else {
        await _settingsRef.set({
          'minTemp': 18,
          'maxTemp': 35,
          'minHumidity': 30,
          'maxHumidity': 70,
          'maxGas': 20,
          'notifyEnabled': true,
          'deviceName': widget.deviceId,
        });
        if (mounted) {
          setState(() {
            deviceName = widget.deviceId;
            minTemp = 18;
            maxTemp = 35;
            minHum = 30;
            maxHum = 70;
            maxGas = 20;
            _settingsLoaded = true;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _settingsLoaded = true);
    }
  }

  void _listenToSettings() {
    _settingsRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          deviceName = data['deviceName'] ?? widget.deviceId;
          minTemp = (data['minTemp'] ?? 18).toDouble();
          maxTemp = (data['maxTemp'] ?? 35).toDouble();
          minHum = (data['minHumidity'] ?? 30).toDouble();
          maxHum = (data['maxHumidity'] ?? 70).toDouble();
          maxGas = (data['maxGas'] ?? 20).toDouble();
        });
        _recalculateAlert();
      }
    });
  }

  void _recalculateAlert() {
    if (isWarmingUp) return;
    bool newAlert = (temp < minTemp ||
        temp > maxTemp ||
        humidity < minHum ||
        humidity > maxHum ||
        gasAlert);
    if (mounted) setState(() => alert = newAlert);
  }

  void _listenToData() {
    _liveRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (mounted) {
        if (data != null) {
          double currentTemp = (data['temp'] ?? 0).toDouble();
          double currentHum = (data['humidity'] ?? 0).toDouble();
          double currentGas = (data['gasLevel'] ?? 0).toDouble();
          bool currentGasAlert = data['gasAlert'] ?? false;
          bool currentWarmingUp = data['warmingUp'] ?? false;
          String ts = data['ts'] ?? '';

          // Only calculate alert if not warming up
          bool newAlert = currentWarmingUp
              ? false
              : (currentTemp < minTemp ||
                  currentTemp > maxTemp ||
                  currentHum < minHum ||
                  currentHum > maxHum ||
                  currentGasAlert);

          if (newAlert && !alert && _settingsLoaded && !currentWarmingUp) {
            NotificationService.showAlertNotification(
              currentTemp,
              currentHum,
              gasDetected: currentGasAlert,
              deviceName: deviceName.isNotEmpty ? deviceName : widget.deviceId,
            );
          }

          final now = TimeOfDay.now();
          setState(() {
            temp = currentTemp;
            humidity = currentHum;
            gasLevel = currentGas;
            gasAlert = currentGasAlert;
            alert = newAlert;
            isWarmingUp = currentWarmingUp;
            _lastTs = ts;
            isOnline = _checkIsOnline(ts);
            isLoading = false;
            lastUpdated =
                'Updated at ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          });
        } else {
          setState(() {
            isLoading = false;
            isOnline = false;
          });
        }
      }
    });
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

  Color _getTempColor() {
    if (isWarmingUp) return Colors.orange;
    if (temp < minTemp || temp > maxTemp) return Colors.red;
    if (temp > maxTemp - 3 || temp < minTemp + 3) return Colors.orange;
    return const Color(0xFF00C853);
  }

  Color _getHumColor() {
    if (isWarmingUp) return Colors.orange;
    if (humidity < minHum || humidity > maxHum) return Colors.red;
    if (humidity > maxHum - 5 || humidity < minHum + 5) return Colors.orange;
    return Colors.blue;
  }

  Color _getGasColor() {
    if (isWarmingUp) return Colors.orange;
    if (gasAlert || gasLevel > maxGas) return Colors.red;
    if (gasLevel > maxGas * 0.5) return Colors.orange;
    return const Color(0xFF00C853);
  }

  Widget _buildOnlineBadge() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isOnline ? const Color(0xFF00C853) : Colors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isOnline ? const Color(0xFF00C853) : Colors.red)
                    .withValues(alpha: 0.6),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            color: isOnline ? const Color(0xFF00C853) : Colors.red,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildWarmupBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Colors.orange,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔥 Sensor Warming Up...',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Gas sensor needs ~30 sec to stabilize. Readings and alerts will begin shortly.',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        body: Column(
          children: [
            const Expanded(child: Center(child: CircularProgressIndicator())),
            const ContactUsFooter(),
          ],
        ),
      );
    }

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
            Text(
              deviceName.isNotEmpty ? deviceName : widget.deviceId,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Row(
              children: [
                Text(
                  widget.deviceId,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                _buildOnlineBadge(),
              ],
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
                  // Warmup banner — shown instead of alert banner during warmup
                  if (isWarmingUp) _buildWarmupBanner(),

                  if (!isWarmingUp && alert)
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
                        colors: isWarmingUp
                            ? [
                                Colors.orange.withValues(alpha: 0.2),
                                Colors.orange.withValues(alpha: 0.05),
                              ]
                            : alert
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
                        color: isWarmingUp
                            ? Colors.orange.withValues(alpha: 0.4)
                            : alert
                                ? Colors.red.withValues(alpha: 0.4)
                                : const Color(0xFF00C853).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isWarmingUp
                              ? Icons.hourglass_top
                              : alert
                                  ? Icons.dangerous
                                  : Icons.check_circle,
                          color: isWarmingUp
                              ? Colors.orange
                              : alert
                                  ? Colors.red
                                  : const Color(0xFF00C853),
                          size: 36,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isWarmingUp
                                    ? 'WARMING UP'
                                    : alert
                                        ? 'UNSAFE CONDITIONS'
                                        : 'ALL SAFE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isWarmingUp
                                      ? Colors.orange
                                      : alert
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
                            color: isWarmingUp
                                ? Colors.orange
                                : alert
                                    ? Colors.red
                                    : const Color(0xFF00C853),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (isWarmingUp
                                        ? Colors.orange
                                        : alert
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
                    progress: ((temp - minTemp) / (maxTemp - minTemp)).clamp(0.0, 1.0),
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
                      isWarmingUp ? 'Warming up...' : 'Safe: below ${maxGas.toInt()}%',
                      style: TextStyle(
                        color: isWarmingUp
                            ? Colors.orange.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              isWarmingUp
                  ? const Text(
                      '—',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    )
                  : RichText(
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
              value: isWarmingUp ? null : (gasLevel / 100).clamp(0.0, 1.0),
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