import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'qr_scanner_screen.dart';
import 'dashboard_screen.dart';
import 'about_screen.dart';
import '../widgets/contact_us_footer.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>> devices = [];
  List<Map<String, dynamic>> pendingRequests = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadPendingRequests();
  }

  void _loadDevices() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance
        .ref('users/${user.uid}/devices')
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (mounted) {
        setState(() {
          if (data != null) {
            devices = data.values
                .map((d) => Map<String, dynamic>.from(d as Map))
                .toList();
          } else {
            devices = [];
          }
          isLoading = false;
        });
      }
    });
  }

  void _loadPendingRequests() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance
        .ref('users/${user.uid}/devices')
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return;

      for (final deviceId in data.keys) {
        FirebaseDatabase.instance
            .ref('devices/$deviceId/requests')
            .onValue
            .listen((reqEvent) {
          final reqData = reqEvent.snapshot.value as Map?;
          if (!mounted) return;

          List<Map<String, dynamic>> updated = List.from(pendingRequests)
            ..removeWhere((r) => r['deviceId'] == deviceId.toString());

          if (reqData != null) {
            for (final entry in reqData.entries) {
              final req = Map<String, dynamic>.from(entry.value as Map);
              if (req['status'] == 'pending') {
                updated.add({
                  ...req,
                  'deviceId': deviceId.toString(),
                  'requesterUid': entry.key.toString(),
                });
              }
            }
          }

          setState(() => pendingRequests = updated);
        });
      }
    });
  }

  Future<void> _approveRequest(
      String deviceId, String requesterUid, String requesterEmail) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/members/$requesterUid')
        .set('approved');

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/requests/$requesterUid/status')
        .set('approved');

    await FirebaseDatabase.instance
        .ref('users/$requesterUid/devices/$deviceId')
        .set({
      'deviceId': deviceId,
      'addedAt': DateTime.now().toIso8601String(),
      'name': deviceId,
    });

    await FirebaseDatabase.instance
        .ref('users/$requesterUid/notifications/${deviceId}_approved')
        .set({
      'type': 'access_approved',
      'deviceId': deviceId,
      'message': 'Your access request for $deviceId has been approved!',
      'read': false,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$requesterEmail approved for $deviceId'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _denyRequest(
      String deviceId, String requesterUid, String requesterEmail) async {
    await FirebaseDatabase.instance
        .ref('devices/$deviceId/requests/$requesterUid/status')
        .set('denied');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$requesterEmail denied for $deviceId'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showRequestsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Access Requests',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: pendingRequests.isEmpty
              ? const Text(
                  'No pending requests',
                  style: TextStyle(color: Colors.grey),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: pendingRequests.length,
                  itemBuilder: (context, index) {
                    final req = pendingRequests[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req['email'] ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Wants access to ${req['deviceId']}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _approveRequest(
                                      req['deviceId'],
                                      req['requesterUid'],
                                      req['email'] ?? '',
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Approve'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _denyRequest(
                                      req['deviceId'],
                                      req['requesterUid'],
                                      req['email'] ?? '',
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Deny'),
                                ),
                              ),
                            ],
                          ),
                        ],
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

  Future<void> _scanQR() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result != null) _loadDevices();
  }

  Future<void> _removeDevice(String deviceId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseDatabase.instance
        .ref('users/${user.uid}/devices/$deviceId')
        .remove();
  }

  void _showRemoveDialog(String deviceId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Device',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove $deviceId from your account?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              _removeDevice(deviceId);
              Navigator.pop(context);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Muonix EnvGuard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              'Muonix Electrosystems LLP',
              style: TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: Colors.white),
                onPressed: _showRequestsDialog,
                tooltip: 'Access Requests',
              ),
              if (pendingRequests.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${pendingRequests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
            tooltip: 'About',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => FirebaseAuth.instance.signOut(),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : devices.isEmpty
                    ? _buildEmptyState()
                    : _buildDeviceList(),
          ),
          const ContactUsFooter(),
        ],
      ),
      floatingActionButton: devices.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _scanQR,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Add Device'),
              backgroundColor: Colors.blue,
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child:
                  const Icon(Icons.sensors_off, size: 56, color: Colors.blue),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Devices Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan the QR code on your\nMuonix EnvGuard device to get started',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text(
                  'Scan QR Code',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _scanQR,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        final deviceId = device['deviceId'] ?? '';
        final deviceName = device['name'] ?? deviceId;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DashboardScreen(deviceId: deviceId),
              ),
            );
          },
          onLongPress: () => _showRemoveDialog(deviceId),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.sensors,
                      color: Colors.blue, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deviceId,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_forward_ios,
                      color: Colors.blue, size: 14),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}