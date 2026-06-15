import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController cameraController = MobileScannerController();
  bool isScanned = false;
  bool isLoading = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (isScanned) return;
    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;
    if (code == null) return;

    setState(() {
      isScanned = true;
      isLoading = true;
    });

    cameraController.stop();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final ownerSnap = await FirebaseDatabase.instance
          .ref('devices/$code/meta/owner_uid')
          .get();

      if (!ownerSnap.exists) {
        await _askNameThenAdd(user, code, isOwner: true, ownerUid: null);
      } else {
        final ownerUid = ownerSnap.value as String;
        if (ownerUid == user.uid) {
          await _askNameThenAdd(user, code, isOwner: true, ownerUid: ownerUid);
        } else {
          await _sendAccessRequest(user, code, ownerUid);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() {
          isScanned = false;
          isLoading = false;
        });
        cameraController.start();
      }
    }
  }

  // Show name dialog before adding device
  Future<void> _askNameThenAdd(User user, String deviceId,
      {required bool isOwner, String? ownerUid}) async {
    setState(() => isLoading = false);

    final nameController = TextEditingController(text: deviceId);

    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Name Your Device',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sensors, color: Colors.blue, size: 40),
            const SizedBox(height: 16),
            Text(
              'Give a name to this device so you can identify it easily.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Device Name',
                labelStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                hintText: 'e.g. Warehouse Unit 1',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: const Icon(Icons.edit, color: Colors.blue),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Colors.blue, width: 1.5),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, deviceId),
            child:
                const Text('Skip', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final n = nameController.text.trim();
              Navigator.pop(context, n.isEmpty ? deviceId : n);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    final finalName = name ?? deviceId;

    if (isOwner && ownerUid == null) {
      await _addAsOwner(user, deviceId, finalName);
    } else {
      await _addToUserDeviceList(user, deviceId, 'owner', finalName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Device $finalName added!'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context, deviceId);
      }
    }
  }

  Future<void> _addAsOwner(User user, String deviceId, String name) async {
    await _addToUserDeviceList(user, deviceId, 'owner', name);

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/meta/owner_uid')
        .set(user.uid);

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/members/${user.uid}')
        .set('approved');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name added! You are the owner.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, deviceId);
    }
  }

  Future<void> _addToUserDeviceList(
      User user, String deviceId, String role, String name) async {
    await FirebaseDatabase.instance
        .ref('users/${user.uid}/devices/$deviceId')
        .set({
      'deviceId': deviceId,
      'addedAt': DateTime.now().toIso8601String(),
      'name': name,
      'role': role,
    });
  }

  Future<void> _sendAccessRequest(
      User user, String deviceId, String ownerUid) async {
    await _addToUserDeviceList(user, deviceId, 'pending', deviceId);

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/requests/${user.uid}')
        .set({
      'uid': user.uid,
      'email': user.email,
      'requestedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    });

    await FirebaseDatabase.instance
        .ref('users/$ownerUid/notifications/${user.uid}_$deviceId')
        .set({
      'type': 'access_request',
      'deviceId': deviceId,
      'requesterUid': user.uid,
      'requesterEmail': user.email,
      'requestedAt': DateTime.now().toIso8601String(),
      'read': false,
    });

    if (mounted) {
      setState(() => isLoading = false);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1B2838),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Access Requested',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pending_actions,
                  color: Colors.orange, size: 48),
              const SizedBox(height: 16),
              Text(
                'Your access request has been sent to the owner.\n\nThe device will appear in your list. Tap it to check your request status.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, deviceId);
              },
              child: const Text('OK',
                  style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Device QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: _onDetect,
          ),
          Container(
            decoration:
                BoxDecoration(color: Colors.black.withValues(alpha: 0.5)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue, width: 3),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Point camera at the QR code\non your Muonix EnvGuard device',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(color: Colors.blue),
                    const SizedBox(height: 8),
                    const Text('Processing...',
                        style: TextStyle(color: Colors.white)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}