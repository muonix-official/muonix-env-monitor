import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

const String alertCheckTask = 'alertCheckTask';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true;

      final devicesSnap = await FirebaseDatabase.instance
          .ref('users/${user.uid}/devices')
          .once();

      final devicesData = devicesSnap.snapshot.value as Map?;
      if (devicesData == null) return true;

      for (final deviceId in devicesData.keys) {
        final snap = await FirebaseDatabase.instance
            .ref('devices/$deviceId/live')
            .once();

        final data = snap.snapshot.value as Map?;
        if (data == null) continue;

        final alert = data['alert'] ?? false;

        if (alert == true) {
          await NotificationService.initialize();
          await NotificationService.showAlertNotification(
            (data['temp'] ?? 0).toDouble(),
            (data['humidity'] ?? 0).toDouble(),
          );
        }
      }
    } catch (e) {
      debugPrint('Background task error: $e');
    }
    return true;
  });
}

class BackgroundService {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  static Future<void> startPeriodicCheck() async {
    await Workmanager().registerPeriodicTask(
      alertCheckTask,
      alertCheckTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> stop() async {
    await Workmanager().cancelAll();
  }
}