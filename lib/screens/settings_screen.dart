import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class SettingsScreen extends StatefulWidget {
  final String deviceId;
  const SettingsScreen({super.key, required this.deviceId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DatabaseReference _settingsRef;

  double minTemp = 18;
  double maxTemp = 35;
  double minHum = 30;
  double maxHum = 80;
  double maxGas = 70;
  bool notifyEnabled = true;
  bool isLoading = true;

  final _deviceNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settingsRef = FirebaseDatabase.instance
        .ref('devices/${widget.deviceId}/settings');
    _loadSettings();
  }

  void _loadSettings() {
    _settingsRef.once().then((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          minTemp = (data['minTemp'] ?? 18).toDouble();
          maxTemp = (data['maxTemp'] ?? 35).toDouble();
          minHum = (data['minHumidity'] ?? 30).toDouble();
          maxHum = (data['maxHumidity'] ?? 80).toDouble();
          maxGas = (data['maxGas'] ?? 70).toDouble();
          notifyEnabled = data['notifyEnabled'] ?? true;
          _deviceNameController.text = data['deviceName'] ?? 'My SensorBox';
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    });
  }

  void _saveSettings() {
    _settingsRef.update({
      'minTemp': minTemp,
      'maxTemp': maxTemp,
      'minHumidity': minHum,
      'maxHumidity': maxHum,
      'maxGas': maxGas,
      'notifyEnabled': notifyEnabled,
      'deviceName': _deviceNameController.text.trim(),
    }).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Device Name
                  _buildSectionTitle('Device'),
                  _buildCard(
                    child: TextField(
                      controller: _deviceNameController,
                      decoration: const InputDecoration(
                        labelText: 'Device Name',
                        prefixIcon: Icon(Icons.sensors),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Temperature
                  _buildSectionTitle('Temperature Safe Range'),
                  _buildCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Min Temp'),
                            Text(
                              '${minTemp.toInt()}°C',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: minTemp,
                          min: 0,
                          max: 40,
                          divisions: 40,
                          onChanged: (val) {
                            if (val < maxTemp) {
                              setState(() => minTemp = val);
                            }
                          },
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Max Temp'),
                            Text(
                              '${maxTemp.toInt()}°C',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: maxTemp,
                          min: 0,
                          max: 60,
                          divisions: 60,
                          onChanged: (val) {
                            if (val > minTemp) {
                              setState(() => maxTemp = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Humidity
                  _buildSectionTitle('Humidity Safe Range'),
                  _buildCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Min Humidity'),
                            Text(
                              '${minHum.toInt()}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: minHum,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (val) {
                            if (val < maxHum) {
                              setState(() => minHum = val);
                            }
                          },
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Max Humidity'),
                            Text(
                              '${maxHum.toInt()}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: maxHum,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (val) {
                            if (val > minHum) {
                              setState(() => maxHum = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Gas
                  _buildSectionTitle('Gas Level Safe Threshold (MQ-6)'),
                  _buildCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Max Gas Level'),
                            Text(
                              '${maxGas.toInt()}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: maxGas,
                          min: 10,
                          max: 100,
                          divisions: 90,
                          activeColor: Colors.purple,
                          onChanged: (val) {
                            setState(() => maxGas = val);
                          },
                        ),
                        const Text(
                          'Alert triggers when gas level exceeds this value',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Notifications
                  _buildSectionTitle('Notifications'),
                  _buildCard(
                    child: SwitchListTile(
                      title: const Text('Enable Alerts'),
                      subtitle:
                          const Text('Get notified when values are unsafe'),
                      value: notifyEnabled,
                      onChanged: (val) =>
                          setState(() => notifyEnabled = val),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Reset
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Reset to Defaults'),
                      onPressed: () {
                        setState(() {
                          minTemp = 18;
                          maxTemp = 35;
                          minHum = 30;
                          maxHum = 80;
                          maxGas = 70;
                          notifyEnabled = true;
                          _deviceNameController.text = 'My SensorBox';
                        });
                      },
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }
}