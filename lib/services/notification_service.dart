import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Fixed IDs so cancelNotification: true can actually find them
  static const int _alertNotifId  = 1001;
  static const int _relayNotifId  = 1002; // single ID, replaces previous relay notif each time

  // Guard so initialize() is safe to call multiple times (background task calls it each run)
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
    );

    const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
      'sensorbox_alerts',
      'SensorBox Alerts',
      description: 'Alerts when temperature or humidity is unsafe',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel dangerChannel = AndroidNotificationChannel(
      'sensorbox_danger',
      'SensorBox Danger',
      description: 'Critical danger alerts with action buttons',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel relayChannel = AndroidNotificationChannel(
      'relay_actions',
      'Relay Activity',
      description: 'Notifies when a relay/switch is turned on or off',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    final plugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(alertChannel);
    await plugin?.createNotificationChannel(dangerChannel);
    await plugin?.createNotificationChannel(relayChannel);

    await _saveToken();
    _fcm.onTokenRefresh.listen(_saveTokenString);

    // Only register FCM foreground listener once
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      showLocalNotification(
        message.notification?.title ?? 'SensorBox Alert',
        message.notification?.body  ?? 'Check your sensor readings',
      );
    });
  }

  static Future<void> _saveToken() async {
    final token = await _fcm.getToken();
    if (token != null) await _saveTokenString(token);
  }

  static Future<void> _saveTokenString(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance
          .ref('users/${user.uid}/fcm_token')
          .set(token);
    }
  }

  static Future<void> showLocalNotification(String title, String body) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sensorbox_alerts',
      'SensorBox Alerts',
      channelDescription: 'Alerts when temperature or humidity is unsafe',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
    );

    await _localNotifications.show(
      _alertNotifId, // fixed ID
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  // ── Danger notification — device name + warning only, no action buttons ──
  static Future<void> showAlertNotification(
    double temp,
    double humidity, {
    bool gasDetected = false,
    String deviceName = 'Device',
    String deviceId = '',
  }) async {
    String body;
    if (gasDetected && temp == 0 && humidity == 0) {
      body = '⚠️ Gas detected by MQ-6 sensor!';
    } else if (gasDetected) {
      body = 'Temp: ${temp.toStringAsFixed(1)}°C, '
          'Humidity: ${humidity.toStringAsFixed(1)}%, Gas: DETECTED!';
    } else {
      body = 'Temp: ${temp.toStringAsFixed(1)}°C, '
          'Humidity: ${humidity.toStringAsFixed(1)}%';
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sensorbox_danger',
      'SensorBox Danger',
      channelDescription: 'Critical danger alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 300, 1000]),
      ongoing: false,
    );

    await _localNotifications.show(
      _alertNotifId, // fixed ID — so cancelNotification: true always finds it
      '🚨 DANGER: $deviceName',
      body,
      NotificationDetails(android: androidDetails),
      payload: deviceId,
    );
  }

  // ── Dismiss the danger notification (call after user acks in-app) ────────
  static Future<void> dismissAlertNotification() async {
    await _localNotifications.cancel(_alertNotifId);
  }

  // ── Relay on/off notification ────────────────────────────────────────────
  static Future<void> showRelayActionNotification({
    required String deviceName,
    required String byEmail,
    required String action,
  }) async {
    final isOn = action == 'on';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'relay_actions',
      'Relay Activity',
      channelDescription: 'Notifies when a relay/switch is turned on or off',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications.show(
      _relayNotifId, // fixed ID — replaces previous relay notif instead of stacking
      '$deviceName turned ${isOn ? 'ON' : 'OFF'}',
      'by $byEmail', 
      NotificationDetails(android: androidDetails),
    );
  }
}