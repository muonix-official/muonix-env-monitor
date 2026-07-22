import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../widgets/contact_us_footer.dart';

class SettingsScreen extends StatefulWidget {
  final String deviceId;
  const SettingsScreen({super.key, required this.deviceId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _deviceNameController;

  double _minTemp = 18;
  double _maxTemp = 35;
  double _minHumidity = 30;
  double _maxHumidity = 80;  // FIXED: was 80
  double _maxGas = 20;        // FIXED: was 80
  bool _notifyEnabled = true;
  bool _loading = true;
  bool _saving = false;

  StreamSubscription? _settingsSub;

  @override
  void initState() {
    super.initState();
    _deviceNameController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  void _loadSettings() {
    final ref = FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/settings');
    _settingsSub = ref.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (data == null) return;
        _minTemp      = (data['minTemp']      as num?)?.toDouble() ?? 18;
        _maxTemp      = (data['maxTemp']      as num?)?.toDouble() ?? 35;
        _minHumidity  = (data['minHumidity']  as num?)?.toDouble() ?? 30;
        _maxHumidity  = (data['maxHumidity']  as num?)?.toDouble() ?? 80; // FIXED
        _maxGas       = (data['maxGas']       as num?)?.toDouble() ?? 20; // FIXED
        _notifyEnabled = data['notifyEnabled'] as bool? ?? true;
        final name = data['deviceName']?.toString() ?? '';
        if (_deviceNameController.text != name) {
          _deviceNameController.text = name;
        }
      });
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/settings')
        .update({
      'minTemp':      _minTemp,
      'maxTemp':      _maxTemp,
      'minHumidity':  _minHumidity,
      'maxHumidity':  _maxHumidity,
      'maxGas':       _maxGas,
      'notifyEnabled': _notifyEnabled,
      'deviceName':   _deviceNameController.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        title: const Text('Reset to defaults?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will restore all thresholds to factory values.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _minTemp      = 18;
      _maxTemp      = 35;
      _minHumidity  = 30;
      _maxHumidity  = 80; // FIXED: was 80
      _maxGas       = 20; // FIXED: was 70
      _notifyEnabled = true;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text('Device Settings',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Reset',
                style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionTitle('Device Name'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _deviceNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter device name',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF1B2838),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('Temperature Range (°C)'),
                      _rangeSlider(
                        values: RangeValues(_minTemp, _maxTemp),
                        min: -10,
                        max: 80,
                        onChanged: (v) => setState(() {
                          _minTemp = v.start;
                          _maxTemp = v.end;
                        }),
                        labelStart: '${_minTemp.toStringAsFixed(0)}°C',
                        labelEnd:   '${_maxTemp.toStringAsFixed(0)}°C',
                      ),
                      const SizedBox(height: 16),

                      _sectionTitle('Humidity Range (%)'),
                      _rangeSlider(
                        values: RangeValues(_minHumidity, _maxHumidity),
                        min: 0,
                        max: 100,
                        onChanged: (v) => setState(() {
                          _minHumidity = v.start;
                          _maxHumidity = v.end;
                        }),
                        labelStart: '${_minHumidity.toStringAsFixed(0)}%',
                        labelEnd:   '${_maxHumidity.toStringAsFixed(0)}%',
                      ),
                      const SizedBox(height: 16),

                      _sectionTitle('Gas Alert Threshold (%)'),
                      Slider(
                        value: _maxGas,
                        min: 5,
                        max: 100,      // FIXED: was 200
                        divisions: 95, // FIXED: was 190
                        label: '${_maxGas.toStringAsFixed(0)}%',
                        activeColor: Colors.orangeAccent,
                        onChanged: (v) => setState(() => _maxGas = v),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Alert when gas ≥ ${_maxGas.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 24),

                      SwitchListTile(
                        title: const Text('Push Notifications',
                            style: TextStyle(color: Colors.white)),
                        subtitle: const Text(
                            'Receive alerts for dangerous readings',
                            style: TextStyle(color: Colors.white54)),
                        value: _notifyEnabled,
                        activeColor: Colors.blueAccent,
                        tileColor: const Color(0xFF1B2838),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        onChanged: (v) => setState(() => _notifyEnabled = v),
                      ),
                      const SizedBox(height: 32),

                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save Settings',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const ContactUsFooter(),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );

  Widget _rangeSlider({
    required RangeValues values,
    required double min,
    required double max,
    required ValueChanged<RangeValues> onChanged,
    required String labelStart,
    required String labelEnd,
  }) {
    return Column(
      children: [
        RangeSlider(
          values: values,
          min: min,
          max: max,
          activeColor: Colors.blueAccent,
          labels: RangeLabels(labelStart, labelEnd),
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Min: $labelStart',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text('Max: $labelEnd',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}