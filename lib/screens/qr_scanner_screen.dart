import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dashboard_screen.dart';
import 'relay_dashboard_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _processing = false;
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    _processing = true;
    if (mounted) setState(() {});
    _handleQr(raw.trim());
  }

  void _done() {
    _processing = false;
    if (mounted) setState(() {});
  }

  String? _extractDeviceId(String raw) {
    final upper = raw.toUpperCase();
    for (final prefix in ['BOX-', 'REL-']) {
      final idx = upper.lastIndexOf(prefix);
      if (idx != -1) {
        return raw.substring(idx).trim().replaceAll(RegExp(r'\s+'), '');
      }
    }
    return null;
  }

  Future<void> _handleQr(String raw) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _done(); return; }

    final deviceId = _extractDeviceId(raw);
    if (deviceId == null) {
      _done();
      _showSnack('Invalid QR code. Scanned: "$raw"');
      return;
    }

    final upper = deviceId.toUpperCase();
    final String deviceType;
    if (upper.startsWith('BOX-')) {
      deviceType = 'sensor';
    } else if (upper.startsWith('REL-')) {
      deviceType = 'relay';
    } else {
      _done();
      _showSnack('Invalid QR code. Scanned: "$raw"');
      return;
    }

    try {
      final db = FirebaseDatabase.instance;

      // Read meta — allowed for any auth != null user
      final metaSnap = await db.ref('devices/$deviceId/meta').get();
      final meta = metaSnap.value as Map?;
      final ownerUid = meta?['owner_uid']?.toString();
      // Store owner email in meta so we never need to read another user's node
      final ownerEmail = meta?['owner_email']?.toString() ?? 'the owner';

      if (ownerUid == null || ownerUid.isEmpty) {
        // No owner — become owner
        await _addAsOwner(deviceId, deviceType, user, db);
        return;
      }

      if (ownerUid == user.uid) {
        // Already owner — just open dashboard
        await _addAsOwner(deviceId, deviceType, user, db);
        return;
      }

      // Someone else owns it — send request
      // We no longer read users/$ownerUid (permission denied risk)
      // Owner email comes from devices/$deviceId/meta/owner_email
      await _sendAccessRequest(
          deviceId, deviceType, user, db, ownerUid, ownerEmail);
    } catch (e) {
      _done();
      _showSnack('Error: $e');
    }
  }

  Future<void> _addAsOwner(
    String deviceId,
    String deviceType,
    User user,
    FirebaseDatabase db,
  ) async {
    await db.ref('devices/$deviceId/blocked').remove();

    // Store owner_email in meta so other users can see who owns the device
    // without needing to read the users/ node
    await db.ref('devices/$deviceId/meta').update({
      'owner_uid': user.uid,
      'owner_email': user.email ?? '',
      'type': deviceType,
    });

    await db.ref('users/${user.uid}/devices/$deviceId').set({
      'deviceId': deviceId,
      'name': deviceId,
      'role': 'owner',
      'addedAt': ServerValue.timestamp,
      'type': deviceType,
    });

    await db.ref('devices/$deviceId/members/${user.uid}').set('approved');

    // Record the owner's own email under memberInfo too. account_management
    // and any other screen that lists all members (owner included) reads
    // emails from here — without this the owner would show up by uid
    // instead of email whenever a full member list is displayed.
    await db
        .ref('devices/$deviceId/memberInfo/${user.uid}/email')
        .set(user.email ?? '');

    _done();
    if (!mounted) return;
    _navigateToDashboard(deviceId, deviceType);
  }

  Future<void> _sendAccessRequest(
    String deviceId,
    String deviceType,
    User user,
    FirebaseDatabase db,
    String ownerUid,
    String ownerEmail,
  ) async {
    // Already an approved member — just open dashboard
    final memberSnap =
        await db.ref('devices/$deviceId/members/${user.uid}').get();
    if (memberSnap.exists) {
      _done();
      if (!mounted) return;
      _navigateToDashboard(deviceId, deviceType);
      return;
    }

    // Get device name from settings (allowed by rules)
    final nameSnap =
        await db.ref('devices/$deviceId/settings/deviceName').get();
    final deviceName =
        nameSnap.exists ? (nameSnap.value as String? ?? deviceId) : deviceId;

    // Check if request already exists
    final reqSnap =
        await db.ref('devices/$deviceId/requests/${user.uid}').get();
    if (reqSnap.exists) {
      final status =
          (reqSnap.value as Map?)?['status']?.toString() ?? 'pending';
      if (status == 'pending') {
        await _addPendingDeviceToUserList(
            deviceId, deviceName, deviceType, ownerEmail, user, db);
        _done();
        if (!mounted) return;
        _showSnack('Request already sent to $ownerEmail.');
        Navigator.pop(context);
        return;
      }
    }

    // Write access request under device (allowed: requests write = auth != null)
    await db.ref('devices/$deviceId/requests/${user.uid}').set({
      'uid': user.uid,
      'email': user.email ?? '',
      'requestedAt': ServerValue.timestamp,
      'status': 'pending',
    });

    // Notify owner (allowed: users/$uid/notifications write = auth != null)
    await db.ref('users/$ownerUid/notifications').push().set({
      'type': 'access_request',
      'deviceId': deviceId,
      'requesterUid': user.uid,
      'requesterEmail': user.email ?? '',
      'message': '${user.email} wants access to $deviceName',
      'read': false,
      'createdAt': ServerValue.timestamp,
    });

    // Add pending device to requester's own list
    // (allowed: users/$uid/devices write = auth != null)
    await _addPendingDeviceToUserList(
        deviceId, deviceName, deviceType, ownerEmail, user, db);

    _done();
    if (!mounted) return;
    _showSnack('Request sent to $ownerEmail for "$deviceName".');
    Navigator.pop(context);
  }

  Future<void> _addPendingDeviceToUserList(
    String deviceId,
    String deviceName,
    String deviceType,
    String ownerEmail,
    User user,
    FirebaseDatabase db,
  ) async {
    final existing =
        await db.ref('users/${user.uid}/devices/$deviceId').get();
    if (!existing.exists) {
      await db.ref('users/${user.uid}/devices/$deviceId').set({
        'deviceId': deviceId,
        'name': deviceName,
        'role': 'pending',
        'type': deviceType,
        'ownerEmail': ownerEmail,
        'addedAt': ServerValue.timestamp,
      });
    }
  }

  void _navigateToDashboard(String deviceId, String deviceType) {
    if (!mounted) return;
    if (deviceType == 'relay') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => RelayDashboardScreen(deviceId: deviceId)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => DashboardScreen(deviceId: deviceId)),
      );
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Device QR',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Point the camera at the device QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}