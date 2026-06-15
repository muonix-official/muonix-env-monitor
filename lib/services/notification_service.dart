import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'sensorbox_alerts',
      'SensorBox Alerts',
      description: 'Alerts when temperature or humidity is unsafe',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    final plugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(channel);

    await _saveToken();
    _fcm.onTokenRefresh.listen(_saveTokenString);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      showLocalNotification(
        message.notification?.title ?? 'SensorBox Alert',
        message.notification?.body ?? 'Check your sensor readings',
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
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'sensorbox_alerts',
      'SensorBox Alerts',
      channelDescription: 'Alerts when temperature or humidity is unsafe',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static Future<void> showAlertNotification(
      double temp, double humidity,
      {bool gasDetected = false,
      String deviceName = 'Device'}) async {

    String body;

    if (gasDetected && temp == 0 && humidity == 0) {
      body = '⚠️ Gas detected by MQ-6 sensor!';
    } else if (gasDetected) {
      body = 'Temp: ${temp.toStringAsFixed(1)}°C, '
          'Humidity: ${humidity.toStringAsFixed(1)}%, '
          'Gas: DETECTED!';
    } else {
      body = 'Temp: ${temp.toStringAsFixed(1)}°C, '
          'Humidity: ${humidity.toStringAsFixed(1)}%';
    }

    await showLocalNotification(
      '⚠️ Alert: $deviceName',
      body,
    );
  }
}