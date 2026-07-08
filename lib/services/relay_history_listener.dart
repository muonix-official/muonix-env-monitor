import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'notification_service.dart';

class RelayHistoryListener {
  static bool _started = false;
  static StreamSubscription? _devicesSub;
  static final Map<String, StreamSubscription> _historySubs = {};
  static final Map<String, String> _deviceNames = {};

  static void start() {
    if (_started) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _started = true;

    final devicesRef = FirebaseDatabase.instance.ref('users/$uid/devices');
    _devicesSub = devicesRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return;
      for (final entry in data.entries) {
        final deviceId = entry.key.toString();
        final deviceData = entry.value is Map ? entry.value as Map : null;
        final nameVal = deviceData?['name']?.toString();
        _deviceNames[deviceId] = (nameVal == null || nameVal.isEmpty)
            ? deviceId
            : nameVal;

        // FIX: only attach listener for relay devices
        // BOX devices have sensor history entries, not relay actions —
        // attaching to them caused wrong "turned ON/OFF" notifications
        final type = deviceData?['type']?.toString() ?? '';
        final isRelay = type == 'relay' || deviceId.startsWith('REL-');
        if (!isRelay) continue;

        _attachHistoryListener(deviceId, uid);
      }
    });
  }

  static void _attachHistoryListener(String deviceId, String myUid) {
    if (_historySubs.containsKey(deviceId)) return;

    String? _lastKnownKey;
    bool _initialized = false;

    // Step 1: read the current last entry's key so we don't notify for old history
    FirebaseDatabase.instance
        .ref('devices/$deviceId/history')
        .orderByKey()
        .limitToLast(1)
        .get()
        .then((snapshot) {
      if (snapshot.exists) {
        final children = snapshot.children.toList();
        if (children.isNotEmpty) {
          _lastKnownKey = children.last.key;
        }
      }
      _initialized = true;
    });

    // Step 2: listen for new entries
    final ref = FirebaseDatabase.instance
        .ref('devices/$deviceId/history')
        .orderByKey()
        .limitToLast(1);

    _historySubs[deviceId] = ref.onChildAdded.listen((event) {
      if (!_initialized) return;

      final incomingKey = event.snapshot.key ?? '';

      if (_lastKnownKey != null && incomingKey.compareTo(_lastKnownKey!) <= 0) {
        return;
      }

      final data = event.snapshot.value as Map?;
      if (data == null) return;

      final by = data['by']?.toString();
      if (by == myUid) return; // skip own actions

      final action = data['action']?.toString() ?? '';
      final byEmail = data['byEmail']?.toString() ?? 'Someone';
      final deviceName = _deviceNames[deviceId] ?? deviceId;

      NotificationService.showRelayActionNotification(
        deviceName: deviceName,
        byEmail: byEmail,
        action: action,
      );

      _lastKnownKey = incomingKey;
    });
  }

  static void stop() {
    _started = false;
    _devicesSub?.cancel();
    _devicesSub = null;
    for (final s in _historySubs.values) {
      s.cancel();
    }
    _historySubs.clear();
  }
}