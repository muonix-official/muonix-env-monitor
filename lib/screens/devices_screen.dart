import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'qr_scanner_screen.dart';
import 'dashboard_screen.dart';
import 'relay_dashboard_screen.dart';
import 'about_screen.dart';
import 'account_management_screen.dart';
import '../widgets/contact_us_footer.dart';
import '../services/notification_service.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>> devices = [];
  List<Map<String, dynamic>> pendingRequests = [];
  List<Map<String, dynamic>> pendingInvites = [];
  List<Map<String, dynamic>> myPendingDevices = [];

  Map<String, bool> deviceOnlineStatus = {};
  Map<String, String> deviceTimestamps = {};
  Map<String, String> deviceTypes = {};

  final Map<String, StreamSubscription> _liveListeners = {};
  final Map<String, StreamSubscription> _requestListeners = {};
  final Map<String, bool> _previousOnlineStatus = {};
  StreamSubscription? _invitesSub;
  Timer? _onlineCheckTimer;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _loadPendingRequests();
    _loadInvites();
    _onlineCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {
          for (final deviceId in deviceTimestamps.keys) {
            final nowOnline = _checkIsOnline(deviceTimestamps[deviceId]);
            final wasOnline = _previousOnlineStatus[deviceId];
            if (wasOnline == true && !nowOnline) {
              _notifyOnlineChange(deviceId, online: false);
            } else if (wasOnline == false && nowOnline) {
              _notifyOnlineChange(deviceId, online: true);
            }
            deviceOnlineStatus[deviceId] = nowOnline;
            _previousOnlineStatus[deviceId] = nowOnline;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _onlineCheckTimer?.cancel();
    _invitesSub?.cancel();
    for (final sub in _liveListeners.values) sub.cancel();
    for (final sub in _requestListeners.values) sub.cancel();
    super.dispose();
  }

  bool _checkIsOnline(String? ts) {
    if (ts == null || ts.isEmpty) return false;
    try {
      final lastSeen = DateTime.parse(ts).toUtc();
      final diff = DateTime.now().toUtc().difference(lastSeen).inSeconds;
      return diff >= 0 && diff < 30;
    } catch (_) {
      return false;
    }
  }

  void _notifyOnlineChange(String deviceId, {required bool online}) {
    final name = devices
            .firstWhere((d) => d['deviceId'] == deviceId,
                orElse: () => {'name': deviceId})['name'] ??
        deviceId;
    if (online) {
      NotificationService.showLocalNotification('✅ Device Online', '$name is back online.');
    } else {
      NotificationService.showLocalNotification('📴 Device Offline', '$name has gone offline.');
    }
  }

  String _fallbackTypeFromId(String deviceId) =>
      deviceId.startsWith('REL-') ? 'relay' : 'sensor';

  void _loadDevices() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseDatabase.instance
        .ref('users/${user.uid}/devices')
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;

      List<Map<String, dynamic>> allDevices = [];
      List<Map<String, dynamic>> myPending = [];

      if (data != null) {
        for (final entry in data.entries) {
          final d = Map<String, dynamic>.from(entry.value as Map);
          allDevices.add(d);
          if (d['role'] == 'pending') myPending.add(d);
        }
      }

      setState(() {
        devices = allDevices;
        myPendingDevices = myPending;
        isLoading = false;
      });

      for (final sub in _liveListeners.values) sub.cancel();
      _liveListeners.clear();

      for (final device in devices) {
        final deviceId = device['deviceId'] ?? '';
        if (deviceId.isEmpty) continue;

        FirebaseDatabase.instance.ref('devices/$deviceId/meta/type').get().then((snap) {
          if (mounted) {
            setState(() {
              deviceTypes[deviceId] = snap.exists
                  ? (snap.value as String? ?? _fallbackTypeFromId(deviceId))
                  : _fallbackTypeFromId(deviceId);
            });
          }
        });

        final sub = FirebaseDatabase.instance
            .ref('devices/$deviceId/live')
            .onValue
            .listen((liveEvent) {
          final liveData = liveEvent.snapshot.value as Map?;
          final ts = liveData?['ts'] as String?;
          if (mounted) {
            final nowOnline = _checkIsOnline(ts);
            final wasOnline = _previousOnlineStatus[deviceId];
            if (wasOnline == true && !nowOnline) _notifyOnlineChange(deviceId, online: false);
            else if (wasOnline == false && nowOnline) _notifyOnlineChange(deviceId, online: true);
            setState(() {
              deviceTimestamps[deviceId] = ts ?? '';
              deviceOnlineStatus[deviceId] = nowOnline;
              _previousOnlineStatus[deviceId] = nowOnline;
            });
          }
        });
        _liveListeners[deviceId] = sub;
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

      final currentDeviceIds = data.keys.map((k) => k.toString()).toSet();

      final staleIds = _requestListeners.keys
          .where((id) => !currentDeviceIds.contains(id))
          .toList();
      for (final id in staleIds) {
        _requestListeners[id]?.cancel();
        _requestListeners.remove(id);
      }
      if (staleIds.isNotEmpty && mounted) {
        setState(() {
          pendingRequests = List.from(pendingRequests)
            ..removeWhere((r) => staleIds.contains(r['deviceId']));
        });
      }

      for (final deviceId in currentDeviceIds) {
        if (_requestListeners.containsKey(deviceId)) continue;

        FirebaseDatabase.instance
            .ref('devices/$deviceId/meta/owner_uid')
            .get()
            .then((ownerSnap) {
          final isOwner = ownerSnap.exists && ownerSnap.value == user.uid;
          if (!isOwner) return;

          final sub = FirebaseDatabase.instance
              .ref('devices/$deviceId/requests')
              .onValue
              .listen((reqEvent) {
            final reqData = reqEvent.snapshot.value as Map?;
            if (!mounted) return;

            List<Map<String, dynamic>> updated = List.from(pendingRequests)
              ..removeWhere((r) => r['deviceId'] == deviceId);

            if (reqData != null) {
              for (final entry in reqData.entries) {
                final req = Map<String, dynamic>.from(entry.value as Map);
                if (req['status'] == 'pending') {
                  updated.add({
                    ...req,
                    'deviceId': deviceId,
                    'requesterUid': entry.key.toString(),
                  });
                }
              }
            }
            setState(() => pendingRequests = updated);
          });
          _requestListeners[deviceId] = sub;
        });
      }
    });
  }

  void _loadInvites() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _invitesSub = FirebaseDatabase.instance
        .ref('users/${user.uid}/notifications')
        .onValue
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;

      final List<Map<String, dynamic>> invites = [];
      if (data != null) {
        for (final entry in data.entries) {
          final notif = Map<String, dynamic>.from(entry.value as Map);
          if (notif['type'] == 'device_invite' && notif['status'] == 'pending') {
            invites.add({...notif, 'notifKey': entry.key.toString()});
          }
        }
      }
      setState(() => pendingInvites = invites);
    });
  }

  Future<void> _acceptInvite(Map<String, dynamic> invite) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final deviceId = invite['deviceId'] as String;
    final deviceName = invite['deviceName'] as String? ?? deviceId;
    final notifKey = invite['notifKey'] as String;

    final typeSnap =
        await FirebaseDatabase.instance.ref('devices/$deviceId/meta/type').get();
    final deviceType =
        typeSnap.exists ? (typeSnap.value as String? ?? 'sensor') : 'sensor';

    await FirebaseDatabase.instance.ref('users/${user.uid}/devices/$deviceId').set({
      'deviceId': deviceId,
      'addedAt': DateTime.now().toIso8601String(),
      'name': deviceName,
      'type': deviceType,
      'role': 'member',
    });

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/members/${user.uid}')
        .set('approved');

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/memberInfo/${user.uid}/email')
        .set(user.email ?? '');

    await FirebaseDatabase.instance
        .ref('users/${user.uid}/notifications/$notifKey/status')
        .set('accepted');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You now have access to $deviceName'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _declineInvite(Map<String, dynamic> invite) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final notifKey = invite['notifKey'] as String;
    final deviceName = invite['deviceName'] as String? ?? 'device';

    await FirebaseDatabase.instance
        .ref('users/${user.uid}/notifications/$notifKey/status')
        .set('declined');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invite for $deviceName declined'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _cancelPendingRequest(Map<String, dynamic> device) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final deviceId = device['deviceId'] as String;
    final deviceName = device['name'] ?? deviceId;

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/requests/${user.uid}')
        .remove();
    await FirebaseDatabase.instance
        .ref('users/${user.uid}/devices/$deviceId')
        .remove();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Request cancelled for $deviceName'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  Future<void> _approveRequest(
      String deviceId, String requesterUid, String requesterEmail) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ownerSnap =
        await FirebaseDatabase.instance.ref('devices/$deviceId/meta/owner_uid').get();
    if (!ownerSnap.exists || ownerSnap.value != user.uid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Only the device owner can approve requests.'),
            backgroundColor: Colors.red));
      }
      return;
    }

    final settingsSnap = await FirebaseDatabase.instance
        .ref('devices/$deviceId/settings/deviceName')
        .get();
    final deviceName =
        settingsSnap.exists ? (settingsSnap.value as String? ?? deviceId) : deviceId;

    final typeSnap =
        await FirebaseDatabase.instance.ref('devices/$deviceId/meta/type').get();
    final deviceType =
        typeSnap.exists ? (typeSnap.value as String? ?? 'sensor') : 'sensor';

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/members/$requesterUid')
        .set('approved');

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/requests/$requesterUid/status')
        .set('approved');

    // Write member email so account_management_screen can show it by uid
    await FirebaseDatabase.instance
        .ref('devices/$deviceId/memberInfo/$requesterUid/email')
        .set(requesterEmail);

    // FIX: set role to 'member' so requester's pending device entry is cleared
    // and they stop appearing in their own "Your Pending Requests" section
    await FirebaseDatabase.instance
        .ref('users/$requesterUid/devices/$deviceId')
        .set({
      'deviceId': deviceId,
      'addedAt': DateTime.now().toIso8601String(),
      'name': deviceName,
      'type': deviceType,
      'role': 'member',
    });

    await FirebaseDatabase.instance
        .ref('users/$requesterUid/notifications/${deviceId}_approved')
        .set({
      'type': 'access_approved',
      'deviceId': deviceId,
      'message': 'Your access request for $deviceName has been approved!',
      'read': false,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$requesterEmail approved for $deviceName'),
        backgroundColor: Colors.green,
      ));
    }
  }

  Future<void> _denyRequest(
      String deviceId, String requesterUid, String requesterEmail) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ownerSnap =
        await FirebaseDatabase.instance.ref('devices/$deviceId/meta/owner_uid').get();
    if (!ownerSnap.exists || ownerSnap.value != user.uid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Only the device owner can deny requests.'),
            backgroundColor: Colors.red));
      }
      return;
    }

    // FIX: also remove the pending device entry from the requester's list
    // so it disappears from their screen immediately on denial
    await FirebaseDatabase.instance
        .ref('devices/$deviceId/requests/$requesterUid/status')
        .set('denied');

    await FirebaseDatabase.instance
        .ref('users/$requesterUid/devices/$deviceId')
        .remove();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$requesterEmail denied for $deviceId'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _showNotificationsDialog() {
    final totalCount =
        pendingRequests.length + pendingInvites.length + myPendingDevices.length;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B2838),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Notifications', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: totalCount == 0
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No notifications', style: TextStyle(color: Colors.grey)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      // ── Section 1: Access Requests (you are owner) ────
                      if (pendingRequests.isNotEmpty) ...[
                        _sectionHeader('Access Requests', Icons.person_add_alt_1, Colors.orange),
                        const SizedBox(height: 6),
                        ...pendingRequests.map((req) => _notifCard(
                              borderColor: Colors.orange,
                              icon: Icons.person_outline,
                              iconColor: Colors.orange,
                              title: req['email'] ?? 'Unknown',
                              subtitle: 'Wants access to device ${req['deviceId']}',
                              actions: Row(children: [
                                Expanded(
                                  child: _actionButton(
                                    label: 'Approve',
                                    color: Colors.green,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _approveRequest(req['deviceId'],
                                          req['requesterUid'], req['email'] ?? '');
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _actionButton(
                                    label: 'Deny',
                                    color: Colors.red,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _denyRequest(req['deviceId'],
                                          req['requesterUid'], req['email'] ?? '');
                                    },
                                  ),
                                ),
                              ]),
                            )),
                        const SizedBox(height: 8),
                      ],

                      // ── Section 2: Device Invites (someone invited you) ─
                      if (pendingInvites.isNotEmpty) ...[
                        _sectionHeader('Device Invites', Icons.mail_outline, Colors.blue),
                        const SizedBox(height: 6),
                        ...pendingInvites.map((invite) => _notifCard(
                              borderColor: Colors.blue,
                              icon: Icons.devices_other,
                              iconColor: Colors.blue,
                              title: invite['deviceName'] ?? 'Device',
                              subtitle: '${invite['inviterEmail'] ?? 'Someone'} invited you',
                              actions: Row(children: [
                                Expanded(
                                  child: _actionButton(
                                    label: 'Accept',
                                    color: Colors.blue,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _acceptInvite(invite);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _actionButton(
                                    label: 'Decline',
                                    color: Colors.grey.shade700,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _declineInvite(invite);
                                    },
                                  ),
                                ),
                              ]),
                            )),
                        const SizedBox(height: 8),
                      ],

                      // ── Section 3: Your pending requests ──────────────
                      if (myPendingDevices.isNotEmpty) ...[
                        _sectionHeader('Your Pending Requests',
                            Icons.hourglass_top, Colors.amber),
                        const SizedBox(height: 6),
                        ...myPendingDevices.map((device) => _notifCard(
                              borderColor: Colors.amber,
                              icon: Icons.hourglass_top,
                              iconColor: Colors.amber,
                              title: device['name'] ?? device['deviceId'],
                              subtitle:
                                  'Request sent to ${device['ownerEmail'] ?? 'owner'} · Awaiting approval',
                              actions: _actionButton(
                                label: 'Cancel Request',
                                color: Colors.red.shade700,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _cancelPendingRequest(device);
                                },
                              ),
                            )),
                      ],
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      ],
    );
  }

  Widget _notifCard({
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget actions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          ),
          const SizedBox(height: 10),
          actions,
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.zero,
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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

    // FIX: previously this only removed the device from the current user's
    // own list (users/uid/devices/$deviceId), leaving the shared
    // devices/$deviceId/members/$uid entry untouched. That meant the
    // owner's device-management screen never saw this user leave, since
    // nothing under devices/$deviceId/members ever changed. Now we also
    // clean up members/memberInfo so the owner's live listener picks it
    // up immediately.
    final ownerSnap = await FirebaseDatabase.instance
        .ref('devices/$deviceId/meta/owner_uid')
        .get();
    final isOwner = ownerSnap.exists && ownerSnap.value == user.uid;

    await FirebaseDatabase.instance
        .ref('users/${user.uid}/devices/$deviceId')
        .remove();

    if (!isOwner) {
      await FirebaseDatabase.instance
          .ref('devices/$deviceId/members/${user.uid}')
          .remove();
      await FirebaseDatabase.instance
          .ref('devices/$deviceId/memberInfo/${user.uid}')
          .remove();
    }
    // Note: if the current user IS the owner, this "Remove Device" action
    // only removes it from their own list and leaves the device orphaned
    // for other members — owners should use "Delete Device" in Account
    // Management instead, which handles blocking/transferring properly.
  }

  void _showDeviceOptions(String deviceId, String currentName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(currentName, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Rename Device', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(deviceId, currentName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove Device', style: TextStyle(color: Colors.red)),
              onTap: () {
                _removeDevice(deviceId);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(String deviceId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Device', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Device Name',
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 1.5),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseDatabase.instance
                    .ref('users/${user.uid}/devices/$deviceId/name')
                    .set(newName);
                await FirebaseDatabase.instance
                    .ref('devices/$deviceId/settings/deviceName')
                    .set(newName);
              }
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openDevice(String deviceId) {
    final isPending = myPendingDevices.any((d) => d['deviceId'] == deviceId);
    if (isPending) {
      _showNotificationsDialog();
      return;
    }

    final type = deviceTypes[deviceId] ?? _fallbackTypeFromId(deviceId);
    if (type == 'relay') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => RelayDashboardScreen(deviceId: deviceId)));
    } else {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => DashboardScreen(deviceId: deviceId)));
    }
  }

  int get _totalNotifCount =>
      pendingRequests.length + pendingInvites.length + myPendingDevices.length;

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
            Text('Muonix EnvGuard',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            Text('Muonix Electrosystems LLP',
                style: TextStyle(color: Colors.blue, fontSize: 12)),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                onPressed: _showNotificationsDialog,
                tooltip: 'Notifications',
              ),
              if (_totalNotifCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text('$_totalNotifCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined, color: Colors.white),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AccountManagementScreen())),
            tooltip: 'Account',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AboutScreen())),
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
              child: const Icon(Icons.sensors_off, size: 56, color: Colors.blue),
            ),
            const SizedBox(height: 24),
            const Text('No Devices Yet',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              'Scan the QR code on your\nMuonix EnvGuard device to get started',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        final online = deviceOnlineStatus[deviceId] ?? false;
        final type = deviceTypes[deviceId] ?? _fallbackTypeFromId(deviceId);
        final isRelay = type == 'relay';
        final isPending = device['role'] == 'pending';

        return GestureDetector(
          onTap: () => _openDevice(deviceId),
          onLongPress: isPending ? null : () => _showDeviceOptions(deviceId, deviceName),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPending
                    ? Colors.amber.withValues(alpha: 0.5)
                    : isRelay
                        ? Colors.orange.withValues(alpha: 0.3)
                        : Colors.blue.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.amber.withValues(alpha: 0.15)
                        : isRelay
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isPending
                          ? Colors.amber.withValues(alpha: 0.4)
                          : isRelay
                              ? Colors.orange.withValues(alpha: 0.3)
                              : Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    isPending
                        ? Icons.hourglass_top
                        : isRelay
                            ? Icons.electrical_services
                            : Icons.sensors,
                    color: isPending ? Colors.amber : isRelay ? Colors.orange : Colors.blue,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deviceName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      const SizedBox(height: 4),
                      if (isPending)
                        Text(
                          'Pending · ${device['ownerEmail'] ?? 'awaiting approval'}',
                          style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        )
                      else
                        Row(
                          children: [
                            Text(deviceId,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 12)),
                            const SizedBox(width: 8),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: online ? const Color(0xFF00C853) : Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (online ? const Color(0xFF00C853) : Colors.red)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              online ? 'Online' : 'Offline',
                              style: TextStyle(
                                  color: online ? const Color(0xFF00C853) : Colors.red,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.amber.withValues(alpha: 0.1)
                        : isRelay
                            ? Colors.orange.withValues(alpha: 0.1)
                            : Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPending ? Icons.notifications_outlined : Icons.arrow_forward_ios,
                    color: isPending ? Colors.amber : isRelay ? Colors.orange : Colors.blue,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}