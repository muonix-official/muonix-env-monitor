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

      // Save device to user's device list
      await FirebaseDatabase.instance
          .ref('users/${user.uid}/devices/$code')
          .set({
        'deviceId': code,
        'addedAt': DateTime.now().toIso8601String(),
        'name': code,
      });

      // Set device owner
      await FirebaseDatabase.instance
          .ref('devices/$code/meta/owner_uid')
          .set(user.uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device $code added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, code);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding device: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          isScanned = false;
          isLoading = false;
        });
        cameraController.start();
      }
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
          // Overlay
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
            ),
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
                    'Point camera at the QR code\non your SensorBox device',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(color: Colors.blue),
                    const SizedBox(height: 8),
                    const Text(
                      'Adding device...',
                      style: TextStyle(color: Colors.white),
                    ),
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