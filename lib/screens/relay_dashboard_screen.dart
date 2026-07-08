import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class RelayDashboardScreen extends StatefulWidget {
  final String deviceId;
  const RelayDashboardScreen({super.key, required this.deviceId});

  @override
  State<RelayDashboardScreen> createState() => _RelayDashboardScreenState();
}

class _RelayDashboardScreenState extends State<RelayDashboardScreen> {
  bool relayState = false;
  bool isOnline = false;
  String deviceName = '';
  bool isLoading = true;

  bool timerActive = false;
  int? timerEndsAtEpoch;
  Timer? _countdownTicker;
  Duration remaining = Duration.zero;

  bool scheduleOnEnabled = false;
  bool scheduleOffEnabled = false;
  TimeOfDay? scheduleOnTime;
  TimeOfDay? scheduleOffTime;

  List<Map<String, dynamic>> history = [];

  StreamSubscription? _liveSub;
  StreamSubscription? _timerSub;
  StreamSubscription? _scheduleSub;
  StreamSubscription? _historySub;
  StreamSubscription? _nameSub;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timerActive && timerEndsAtEpoch != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final secsLeft = timerEndsAtEpoch! - now;
        if (mounted) {
          setState(() {
            remaining = secsLeft > 0 ? Duration(seconds: secsLeft) : Duration.zero;
            if (secsLeft <= 0) timerActive = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _timerSub?.cancel();
    _scheduleSub?.cancel();
    _historySub?.cancel();
    _nameSub?.cancel();
    _countdownTicker?.cancel();
    super.dispose();
  }

  void _loadAll() {
    final ref = FirebaseDatabase.instance.ref('devices/${widget.deviceId}');

    _nameSub = FirebaseDatabase.instance
        .ref('users/${FirebaseAuth.instance.currentUser?.uid}/devices/${widget.deviceId}/name')
        .onValue
        .listen((event) {
      if (mounted && event.snapshot.value != null) {
        setState(() => deviceName = event.snapshot.value.toString());
      }
    });

    _liveSub = ref.child('live').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;
      final ts = data?['ts'] as String?;
      bool online = false;
      if (ts != null && ts.isNotEmpty) {
        try {
          final lastSeen = DateTime.parse(ts).toUtc();
          final diff = DateTime.now().toUtc().difference(lastSeen).inSeconds;
          online = diff >= 0 && diff < 30;
        } catch (_) {}
      }
      setState(() {
        relayState = data?['relayState'] == true;
        isOnline = online;
        isLoading = false;
      });
    });

    _timerSub = ref.child('autoOffTimer').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;
      setState(() {
        timerActive = data?['enabled'] == true;
        timerEndsAtEpoch = data?['endsAt'] != null
            ? int.tryParse(data!['endsAt'].toString())
            : null;
      });
    });

    _scheduleSub = ref.child('schedule').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;
      setState(() {
        scheduleOnEnabled = data?['onEnabled'] == true;
        scheduleOffEnabled = data?['offEnabled'] == true;
        scheduleOnTime = _parseTime(data?['onTime']?.toString());
        scheduleOffTime = _parseTime(data?['offTime']?.toString());
      });
    });

    _historySub = ref.child('history').limitToLast(50).onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;
      final List<Map<String, dynamic>> items = [];
      if (data != null) {
        for (final entry in data.entries) {
          items.add(Map<String, dynamic>.from(entry.value as Map));
        }
      }
      items.sort((a, b) => (b['at'] ?? '').compareTo(a['at'] ?? ''));
      setState(() => history = items);
    });
  }

  TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null || hhmm.length != 5) return null;
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _logHistory(String action, String source) async {
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/history')
        .push()
        .set({
      'action': action,
      'source': source,
      'by': user?.uid ?? 'unknown',
      'byEmail': user?.email ?? 'unknown',
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _toggleRelay(bool newState, {bool cancelTimer = true}) async {
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/live/relayState')
        .set(newState);
    await _logHistory(newState ? 'on' : 'off', 'manual');
    if (cancelTimer && timerActive) {
      await FirebaseDatabase.instance
          .ref('devices/${widget.deviceId}/autoOffTimer/enabled')
          .set(false);
    }
  }

  Future<void> _setAutoOffTimer(int totalSeconds) async {
    final endsAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + totalSeconds;
    if (!relayState) {
      await _toggleRelay(true, cancelTimer: false);
    }
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/autoOffTimer')
        .set({'enabled': true, 'endsAt': endsAt});

    if (mounted) {
      final h = totalSeconds ~/ 3600;
      final m = (totalSeconds % 3600) ~/ 60;
      final s = totalSeconds % 60;
      final parts = [
        if (h > 0) '${h}h',
        if (m > 0) '${m}m',
        if (s > 0) '${s}s',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-off in ${parts.join(' ')}'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _cancelTimer() async {
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/autoOffTimer/enabled')
        .set(false);
  }

  Future<void> _saveSchedule({
    required bool onEnabled,
    required bool offEnabled,
    TimeOfDay? onTime,
    TimeOfDay? offTime,
  }) async {
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/schedule')
        .set({
      'onEnabled': onEnabled,
      'offEnabled': offEnabled,
      'onTime': onTime != null ? _fmtTime(onTime) : '',
      'offTime': offTime != null ? _fmtTime(offTime) : '',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (!onEnabled && !offEnabled) ? 'Schedule cleared' : 'Schedule saved',
          ),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  String _scheduleSubtitle() {
    if (!scheduleOnEnabled && !scheduleOffEnabled) return 'Not configured';
    final parts = <String>[];
    if (scheduleOnEnabled && scheduleOnTime != null) {
      parts.add('ON ${_fmtTime(scheduleOnTime!)}');
    }
    if (scheduleOffEnabled && scheduleOffTime != null) {
      parts.add('OFF ${_fmtTime(scheduleOffTime!)}');
    }
    return parts.isEmpty ? 'Not configured' : parts.join(' → ');
  }

  void _showTimerDialog() {
    final presets = [
      {'label': '5 minutes', 'seconds': 300},
      {'label': '15 minutes', 'seconds': 900},
      {'label': '30 minutes', 'seconds': 1800},
      {'label': '1 hour', 'seconds': 3600},
      {'label': '2 hours', 'seconds': 7200},
    ];

    int customHours = 0;
    int customMinutes = 0;
    int customSeconds = 0;
    bool showCustom = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: const Color(0xFF1B2838),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Set Auto-Off Timer', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...presets.map((p) => ListTile(
                      leading: const Icon(Icons.timer_outlined, color: Colors.blue),
                      title: Text(p['label'] as String,
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        _setAutoOffTimer(p['seconds'] as int);
                      },
                    )),
                const Divider(color: Colors.white24, height: 24),
                ListTile(
                  leading: Icon(
                    Icons.edit_outlined,
                    color: showCustom ? Colors.orange : Colors.white54,
                  ),
                  title: Text(
                    'Custom duration',
                    style: TextStyle(
                      color: showCustom ? Colors.orange : Colors.white,
                    ),
                  ),
                  trailing: Icon(
                    showCustom ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                  ),
                  onTap: () => setLocalState(() => showCustom = !showCustom),
                ),
                if (showCustom) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildNumberField(
                            label: 'HH',
                            value: customHours,
                            max: 23,
                            onChanged: (v) => setLocalState(() => customHours = v),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text(':', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: _buildNumberField(
                            label: 'MM',
                            value: customMinutes,
                            max: 59,
                            onChanged: (v) => setLocalState(() => customMinutes = v),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text(':', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: _buildNumberField(
                            label: 'SS',
                            value: customSeconds,
                            max: 59,
                            onChanged: (v) => setLocalState(() => customSeconds = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final total = customHours * 3600 +
                              customMinutes * 60 +
                              customSeconds;
                          if (total == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a duration'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          Navigator.pop(context);
                          _setAutoOffTimer(total);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Set Custom Timer',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required String label,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 2,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            counterText: '',
            hintText: '00',
            hintStyle: TextStyle(color: Colors.white24, fontSize: 20),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.orange, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (v) {
            final parsed = int.tryParse(v) ?? 0;
            onChanged(parsed.clamp(0, max));
          },
        ),
      ],
    );
  }

  void _showScheduleDialog() {
    bool tempOnEnabled = scheduleOnEnabled;
    bool tempOffEnabled = scheduleOffEnabled;
    TimeOfDay? tempOn = scheduleOnTime;
    TimeOfDay? tempOff = scheduleOffTime;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: const Color(0xFF1B2838),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Daily Schedule', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Auto Turn ON', style: TextStyle(color: Colors.white)),
                  subtitle: tempOnEnabled
                      ? Text(
                          tempOn != null ? 'at ${_fmtTime(tempOn!)}' : 'Tap below to pick a time',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        )
                      : null,
                  value: tempOnEnabled,
                  activeColor: Colors.orange,
                  onChanged: (v) => setLocalState(() => tempOnEnabled = v),
                ),
                if (tempOnEnabled)
                  ListTile(
                    leading: const Icon(Icons.wb_sunny_outlined, color: Colors.orange),
                    title: const Text('Turn ON at', style: TextStyle(color: Colors.white)),
                    trailing: Text(
                      tempOn != null ? _fmtTime(tempOn!) : 'Not set',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: tempOn ?? const TimeOfDay(hour: 8, minute: 0),
                      );
                      if (picked != null) setLocalState(() => tempOn = picked);
                    },
                  ),
                const Divider(color: Colors.white24, height: 24),
                SwitchListTile(
                  title: const Text('Auto Turn OFF', style: TextStyle(color: Colors.white)),
                  subtitle: tempOffEnabled
                      ? Text(
                          tempOff != null ? 'at ${_fmtTime(tempOff!)}' : 'Tap below to pick a time',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        )
                      : null,
                  value: tempOffEnabled,
                  activeColor: Colors.indigo,
                  onChanged: (v) => setLocalState(() => tempOffEnabled = v),
                ),
                if (tempOffEnabled)
                  ListTile(
                    leading: const Icon(Icons.nightlight_outlined, color: Colors.indigo),
                    title: const Text('Turn OFF at', style: TextStyle(color: Colors.white)),
                    trailing: Text(
                      tempOff != null ? _fmtTime(tempOff!) : 'Not set',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: tempOff ?? const TimeOfDay(hour: 20, minute: 0),
                      );
                      if (picked != null) setLocalState(() => tempOff = picked);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (tempOnEnabled && tempOn == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please pick a time for Auto Turn ON'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (tempOffEnabled && tempOff == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please pick a time for Auto Turn OFF'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                _saveSchedule(
                  onEnabled: tempOnEnabled,
                  offEnabled: tempOffEnabled,
                  onTime: tempOn,
                  offTime: tempOff,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Usage History', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: history.isEmpty
              ? const Text('No activity yet', style: TextStyle(color: Colors.grey))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final h = history[index];
                    final isOn = h['action'] == 'on';
                    String whenStr = '';
                    try {
                      final dt = DateTime.parse(h['at']).toLocal();
                      whenStr =
                          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    } catch (_) {}
                    return ListTile(
                      leading: Icon(
                        isOn ? Icons.power : Icons.power_off,
                        color: isOn ? Colors.green : Colors.red,
                      ),
                      title: Text(
                        '${isOn ? 'Turned ON' : 'Turned OFF'} (${h['source'] ?? 'manual'})',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: Text(
                        '${h['byEmail'] ?? 'unknown'} • $whenStr',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        // FIX: removed duplicate history icon from app bar —
        // history is already accessible via the Usage History tile below
        title: Text(
          deviceName.isEmpty ? widget.deviceId : deviceName,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildStatusBadge(),
                  const SizedBox(height: 28),
                  _buildMainSwitch(),
                  const SizedBox(height: 28),
                  if (timerActive) _buildActiveTimerCard(),
                  _buildActionTile(
                    icon: Icons.timer_outlined,
                    title: 'Auto-Off Timer',
                    subtitle: timerActive
                        ? 'Active — turning off soon'
                        : 'Turn off automatically after a set time',
                    onTap: _showTimerDialog,
                  ),
                  _buildActionTile(
                    icon: Icons.schedule,
                    title: 'Daily Schedule',
                    subtitle: _scheduleSubtitle(),
                    onTap: _showScheduleDialog,
                  ),
                  _buildActionTile(
                    icon: Icons.history,
                    title: 'Usage History',
                    subtitle: '${history.length} recent events',
                    onTap: _showHistoryDialog,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBadge() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isOnline ? const Color(0xFF00C853) : Colors.red,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            color: isOnline ? const Color(0xFF00C853) : Colors.red,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildMainSwitch() {
    return Column(
      children: [
        GestureDetector(
          onTap: isOnline ? () => _toggleRelay(!relayState) : null,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: relayState
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: relayState
                    ? Colors.green
                    : Colors.white.withValues(alpha: 0.2),
                width: 3,
              ),
            ),
            child: Icon(
              Icons.power_settings_new,
              size: 64,
              color: relayState
                  ? Colors.green
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          relayState ? 'ON' : 'OFF',
          style: TextStyle(
            color: relayState ? Colors.green : Colors.white.withValues(alpha: 0.6),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        if (!isOnline)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Device offline — control unavailable',
              style: TextStyle(
                  color: Colors.red.withValues(alpha: 0.7), fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveTimerCard() {
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final s = remaining.inSeconds % 60;
    final parts = [
      if (h > 0) '${h}h',
      if (m > 0) '${m}m',
      '${s}s',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Turning off in ${parts.join(' ')}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: _cancelTimer,
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.blue, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}