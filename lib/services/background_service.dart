import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

const _taskName = 'muonix_bg_check';
const _taskTag = 'muonix_background';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return true;

      await _checkAllDevices(uid);
    } catch (e) {
      if (kDebugMode) print('[BackgroundService] error: $e');
    }
    return true;
  });
}

Future<void> _checkAllDevices(String uid) async {
  final devicesSnap =
      await FirebaseDatabase.instance.ref('users/$uid/devices').get();
  final devices = devicesSnap.value as Map?;
  if (devices == null) return;

  for (final entry in devices.entries) {
    final deviceId = entry.key.toString();
    final deviceData = entry.value as Map?;
    final nameVal = deviceData?['name']?.toString();
    final deviceName =
        (nameVal == null || nameVal.isEmpty) ? deviceId : nameVal;

    // Determine device type from meta (with prefix fallback)
    String deviceType = deviceData?['type']?.toString() ?? '';
    if (deviceType.isEmpty) {
      // Fallback: infer from ID prefix
      if (deviceId.startsWith('BOX-')) {
        deviceType = 'sensor';
      } else if (deviceId.startsWith('REL-')) {
        deviceType = 'relay';
      }
    }

    if (deviceType == 'sensor') {
      await _checkSensorAlerts(uid, deviceId, deviceName);
    } else if (deviceType == 'relay') {
      // FIX: only run relay-history check for relay devices,
      // not for sensor/box devices (previously ran for all devices)
      await _checkRelayHistory(uid, deviceId, deviceName);
    }
    // Unknown type: skip both checks to avoid wasted reads
  }
}

Future<void> _checkSensorAlerts(
    String uid, String deviceId, String deviceName) async {
  final liveSnap =
      await FirebaseDatabase.instance.ref('devices/$deviceId/live').get();
  final live = liveSnap.value as Map?;
  if (live == null) return;

  final gasAlert = live['gasAlert'] as bool? ?? false;
  final ackBy = live['ackBy'] as Map?;
  final alreadyAcked = ackBy?.containsKey(uid) ?? false;

  if (gasAlert && !alreadyAcked) {
    final temp = (live['temp'] as num?)?.toDouble();
    final humidity = (live['humidity'] as num?)?.toDouble();
    final gasLevel = (live['gasLevel'] as num?)?.toDouble();

    await NotificationService.showAlertNotification(
      temp ?? 0,
      humidity ?? 0,
      gasDetected: (gasLevel != null && gasLevel > 0),
      deviceName: deviceName,
      deviceId: deviceId,
    );
  }
}

Future<void> _checkRelayHistory(
    String uid, String deviceId, String deviceName) async {
  // Read the marker for the last history key we already notified about
  final markerSnap = await FirebaseDatabase.instance
      .ref('users/$uid/notifyMarkers/$deviceId')
      .get();
  final lastNotifiedKey = markerSnap.value?.toString();

  final histRef = FirebaseDatabase.instance
      .ref('devices/$deviceId/history')
      .orderByKey()
      .limitToLast(1);
  final histSnap = await histRef.get();
  if (!histSnap.exists) return;

  final children = histSnap.children.toList();
  if (children.isEmpty) return;

  final latest = children.last;
  final latestKey = latest.key ?? '';
  if (latestKey == lastNotifiedKey) return; // already notified

  final data = latest.value as Map?;
  if (data == null) return;

  final by = data['by']?.toString();
  if (by == uid) return; // skip own actions

  final action = data['action']?.toString() ?? '';
  final byEmail = data['byEmail']?.toString() ?? 'Someone';

  await NotificationService.showRelayActionNotification(
    deviceName: deviceName,
    byEmail: byEmail,
    action: action,
  );

  // Update marker so we don't notify again for this entry
  await FirebaseDatabase.instance
      .ref('users/$uid/notifyMarkers/$deviceId')
      .set(latestKey);
}

class BackgroundService {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher,
        isInDebugMode: kDebugMode);
  }

  static Future<void> registerPeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      _taskTag,
      _taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}