import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../widgets/contact_us_footer.dart';
import 'login_screen.dart'; // FIX: import login screen for post-delete navigation

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final _user = FirebaseAuth.instance.currentUser!;
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  StreamSubscription? _devicesSub;

  // FIX: one live listener per device on devices/$deviceId/members, so
  // leaves/removals by OTHER users are reflected immediately, instead of
  // only refreshing when the owner's own users/uid/devices node changes.
  final Map<String, StreamSubscription> _memberSubs = {};

  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _loadUserPhone();
    _loadDevices();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _devicesSub?.cancel();
    _cancelAllMemberSubs();
    super.dispose();
  }

  void _loadUserPhone() async {
    final snap =
        await FirebaseDatabase.instance.ref('users/${_user.uid}/phone').get();
    if (mounted) {
      _phoneController.text = snap.value?.toString() ?? '';
    }
  }

  Future<Map<String, String>> _fetchMemberEmails(Map? members) async {
    final Map<String, String> memberEmails = {};
    if (members != null) {
      for (final uid in members.keys) {
        if (uid == _user.uid) continue;
        final emailSnap =
            await FirebaseDatabase.instance.ref('users/$uid/email').get();
        memberEmails[uid.toString()] =
            emailSnap.value?.toString() ?? uid.toString();
      }
    }
    return memberEmails;
  }

  void _cancelAllMemberSubs() {
    for (final sub in _memberSubs.values) {
      sub.cancel();
    }
    _memberSubs.clear();
  }

  // FIX: subscribes to live member changes for a single device. When
  // members are added/removed (e.g. someone leaves, or the owner removes
  // them), this fires immediately and updates just that device's entry.
  void _subscribeToMembers(String deviceId) {
    if (_memberSubs.containsKey(deviceId)) return;
    _memberSubs[deviceId] = FirebaseDatabase.instance
        .ref('devices/$deviceId/members')
        .onValue
        .listen((event) async {
      if (!mounted) return;
      final newMembers = event.snapshot.value as Map?;
      final newMemberEmails = await _fetchMemberEmails(newMembers);
      if (!mounted) return;
      setState(() {
        final idx = _devices.indexWhere((d) => d['deviceId'] == deviceId);
        if (idx != -1) {
          _devices[idx] = {
            ..._devices[idx],
            'members': newMembers,
            'memberEmails': newMemberEmails,
          };
        }
      });
    });
  }

  void _loadDevices() {
    final ref = FirebaseDatabase.instance.ref('users/${_user.uid}/devices');
    _devicesSub = ref.onValue.listen((event) async {
      final data = event.snapshot.value as Map?;
      if (!mounted) return;
      if (data == null) {
        _cancelAllMemberSubs();
        setState(() {
          _devices = [];
          _loading = false;
        });
        return;
      }

      final currentDeviceIds = data.keys.map((k) => k.toString()).toSet();

      // Drop member listeners for devices we no longer have (deleted /
      // left), so we don't leak subscriptions.
      final staleIds = _memberSubs.keys
          .where((id) => !currentDeviceIds.contains(id))
          .toList();
      for (final id in staleIds) {
        _memberSubs[id]?.cancel();
        _memberSubs.remove(id);
      }

      final List<Map<String, dynamic>> result = [];
      for (final entry in data.entries) {
        final deviceId = entry.key.toString();
        final deviceData = entry.value as Map?;

        final metaSnap =
            await FirebaseDatabase.instance.ref('devices/$deviceId/meta').get();
        final meta = metaSnap.value as Map?;

        final membersSnap = await FirebaseDatabase.instance
            .ref('devices/$deviceId/members')
            .get();
        final members = membersSnap.value as Map?;
        final memberEmails = await _fetchMemberEmails(members);

        result.add({
          'deviceId': deviceId,
          'name': deviceData?['name']?.toString() ?? deviceId,
          'role': deviceData?['role']?.toString() ?? 'member',
          'type': meta?['type']?.toString() ?? '',
          'ownerUid': meta?['owner_uid']?.toString() ?? '',
          'members': members,
          'memberEmails': memberEmails,
        });

        _subscribeToMembers(deviceId);
      }

      if (mounted) {
        setState(() {
          _devices = result;
          _loading = false;
        });
      }
    });
  }

  String _encodeEmailKey(String email) =>
      email.trim().toLowerCase().replaceAll('.', ',');

  bool _isOwner(Map<String, dynamic> device) =>
      device['ownerUid'] == _user.uid;

  Future<void> _savePhone() async {
    final phone = _phoneController.text.trim();
    await FirebaseDatabase.instance
        .ref('users/${_user.uid}/phone')
        .set(phone);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Phone number saved')));
  }

  Future<void> _leaveDevice(String deviceId) async {
    final confirm = await _confirmDialog(
        'Leave Device?', 'You will lose access to this device.');
    if (!confirm) return;
    await FirebaseDatabase.instance
        .ref('devices/$deviceId/members/${_user.uid}')
        .remove();
    await FirebaseDatabase.instance
        .ref('users/${_user.uid}/devices/$deviceId')
        .remove();
  }

  Future<void> _removeMember(String deviceId, String memberUid) async {
    final confirm = await _confirmDialog(
        'Remove Member?', 'This user will lose access to the device.');
    if (!confirm) return;
    await FirebaseDatabase.instance
        .ref('devices/$deviceId/members/$memberUid')
        .remove();
    await FirebaseDatabase.instance
        .ref('users/$memberUid/devices/$deviceId')
        .remove();
  }

  Future<void> _transferOwnership(
      String deviceId, Map? members, Map<String, String> memberEmails) async {
    final otherMembers = members?.entries
        .where((e) => e.key.toString() != _user.uid)
        .toList();

    if (otherMembers == null || otherMembers.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1B2838),
          title: const Text('No Other Members',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'You are the only user on this device.\n\nInvite someone first using the "Invite User" option before transferring ownership.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    String? selectedUid;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        title: const Text('Transfer Ownership',
            style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: otherMembers.map((e) {
              final uid = e.key.toString();
              final email = memberEmails[uid] ?? uid;
              return RadioListTile<String>(
                value: uid,
                groupValue: selectedUid,
                title:
                    Text(email, style: const TextStyle(color: Colors.white70)),
                onChanged: (v) => setS(() => selectedUid = v),
                activeColor: Colors.blueAccent,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: selectedUid == null ? null : () => Navigator.pop(context),
            child: const Text('Transfer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (selectedUid == null) return;

    final confirm = await _confirmDialog('Confirm Transfer',
        'You will lose ownership. The new owner will be responsible for this device.');
    if (!confirm) return;

    await FirebaseDatabase.instance
        .ref('devices/$deviceId/meta/owner_uid')
        .set(selectedUid);
    await FirebaseDatabase.instance
        .ref('users/$selectedUid/devices/$deviceId/role')
        .set('owner');
    await FirebaseDatabase.instance
        .ref('users/${_user.uid}/devices/$deviceId/role')
        .set('member');

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Ownership transferred.')));
  }

  Future<void> _inviteByEmail(String deviceId, String deviceName) async {
    final emailController = TextEditingController();
    String? errorMsg;
    bool isSending = false; // FIX: drives the button's loading/disabled state

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1B2838),
          title:
              const Text('Invite User', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the email address of the person you want to invite to this device.',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                enabled: !isSending,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Email address',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon:
                      const Icon(Icons.email_outlined, color: Colors.white38),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(errorMsg!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                disabledBackgroundColor:
                    Colors.blueAccent.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              // FIX: null onPressed while sending — button visibly disables
              // and shows a spinner immediately on tap, so it never feels
              // like the tap was ignored.
              onPressed: isSending
                  ? null
                  : () async {
                      final email = emailController.text.trim().toLowerCase();
                      if (email.isEmpty || !email.contains('@')) {
                        setS(() => errorMsg = 'Please enter a valid email.');
                        return;
                      }
                      if (email == _user.email?.toLowerCase()) {
                        setS(() => errorMsg = 'You cannot invite yourself.');
                        return;
                      }

                      // Capture the messenger BEFORE any awaits / navigator
                      // pops, so we never call ScaffoldMessenger.of(context)
                      // after the dialog element may have been deactivated.
                      final rootMessenger = ScaffoldMessenger.of(context);

                      setS(() {
                        isSending = true;
                        errorMsg = null;
                      });

                      try {
                        // Step 1: try fast userIndex lookup (written at
                        // login/signup)
                        final encodedEmail = _encodeEmailKey(email);
                        final indexSnap = await FirebaseDatabase.instance
                            .ref('userIndex/$encodedEmail')
                            .get();

                        String? targetUid;

                        if (indexSnap.exists) {
                          targetUid = indexSnap.value.toString();
                        } else {
                          // Step 2: fallback — scan users/ node for accounts
                          // that signed up before userIndex was introduced
                          final usersSnap = await FirebaseDatabase.instance
                              .ref('users')
                              .get();
                          final usersData = usersSnap.value as Map?;
                          if (usersData != null) {
                            for (final entry in usersData.entries) {
                              final userData = entry.value as Map?;
                              final userEmail = userData?['email']
                                      ?.toString()
                                      .toLowerCase() ??
                                  '';
                              if (userEmail == email) {
                                targetUid = entry.key.toString();
                                // Backfill userIndex so future lookups are
                                // fast
                                await FirebaseDatabase.instance
                                    .ref('userIndex/$encodedEmail')
                                    .set(targetUid);
                                break;
                              }
                            }
                          }
                        }

                        if (targetUid == null) {
                          if (!ctx.mounted) return;
                          setS(() {
                            isSending = false;
                            errorMsg =
                                'No account found with this email. They need to sign up first.';
                          });
                          return;
                        }

                        final memberSnap = await FirebaseDatabase.instance
                            .ref('devices/$deviceId/members/$targetUid')
                            .get();
                        if (memberSnap.exists) {
                          if (!ctx.mounted) return;
                          setS(() {
                            isSending = false;
                            errorMsg =
                                'This user already has access to this device.';
                          });
                          return;
                        }

                        // Check for existing pending invite without
                        // orderByChild (orderByChild needs a Firebase
                        // .indexOn rule to work reliably)
                        final existingInviteSnap = await FirebaseDatabase
                            .instance
                            .ref('users/$targetUid/notifications')
                            .get();
                        if (existingInviteSnap.exists) {
                          final existing = existingInviteSnap.value as Map?;
                          if (existing != null) {
                            final hasInvite = existing.values.any((v) =>
                                (v as Map?)?['type'] == 'device_invite' &&
                                (v as Map?)?['deviceId'] == deviceId &&
                                (v as Map?)?['status'] == 'pending');
                            if (hasInvite) {
                              if (!ctx.mounted) return;
                              setS(() {
                                isSending = false;
                                errorMsg =
                                    'An invite is already pending for this user.';
                              });
                              return;
                            }
                          }
                        }

                        await FirebaseDatabase.instance
                            .ref('users/$targetUid/notifications')
                            .push()
                            .set({
                          'type': 'device_invite',
                          'deviceId': deviceId,
                          'deviceName': deviceName,
                          'inviterUid': _user.uid,
                          'inviterEmail': _user.email ?? '',
                          'message':
                              '${_user.email} invited you to access $deviceName',
                          'status': 'pending',
                          'read': false,
                          'createdAt': ServerValue.timestamp,
                        });

                        if (ctx.mounted) Navigator.pop(ctx);

                        // Use the messenger captured before the pop — never
                        // call ScaffoldMessenger.of(context) again after
                        // popping.
                        rootMessenger.showSnackBar(
                          SnackBar(
                            content: Text('Invite sent to $email'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setS(() {
                          isSending = false;
                          errorMsg = 'Error: $e';
                        });
                      }
                    },
              child: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Send Invite',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
  }

  Future<void> _deleteDevice(String deviceId, Map? members) async {
    final confirm = await _confirmDialog('Delete Device?',
        'This will remove the device for all members permanently.');
    if (!confirm) return;

    if (members != null) {
      for (final uid in members.keys) {
        await FirebaseDatabase.instance
            .ref('users/$uid/devices/$deviceId')
            .remove();
      }
    }
    await FirebaseDatabase.instance
        .ref('users/${_user.uid}/devices/$deviceId')
        .remove();
    await FirebaseDatabase.instance
        .ref('devices/$deviceId/blocked')
        .set(true);
  }

  // ─── Delete account ──────────────────────────────────────────────────────
  // FIX: does NOT delete the device from Firebase — only removes the user's
  // membership and transfers ownership if needed. After deletion, navigates
  // to LoginScreen and shows a confirmation snackbar.
  Future<void> _deleteAccount() async {
    final confirm = await _confirmDialog('Delete Account?',
        'This action is permanent. All your data will be erased.');
    if (!confirm) return;

    final reAuthed = await _reAuth();
    if (!reAuthed) return;

    for (final device in _devices) {
      final deviceId = device['deviceId'] as String;

      if (_isOwner(device)) {
        final members = device['members'] as Map?;
        final otherMembers = members?.entries
            .where((e) => e.key != _user.uid)
            .toList();

        if (otherMembers != null && otherMembers.isNotEmpty) {
          // Transfer ownership to first remaining member — don't delete device
          final newOwnerUid = otherMembers.first.key.toString();
          await FirebaseDatabase.instance
              .ref('devices/$deviceId/meta/owner_uid')
              .set(newOwnerUid);
          await FirebaseDatabase.instance
              .ref('users/$newOwnerUid/devices/$deviceId/role')
              .set('owner');
        }
        // If no other members: device stays but becomes ownerless/blocked
        else {
          await FirebaseDatabase.instance
              .ref('devices/$deviceId/blocked')
              .set(true);
        }
      }

      // Always remove the user's own membership entries — never delete device data
      await FirebaseDatabase.instance
          .ref('users/${_user.uid}/devices/$deviceId')
          .remove();
      await FirebaseDatabase.instance
          .ref('devices/$deviceId/members/${_user.uid}')
          .remove();
    }

    // Remove user profile node and delete auth account
    await FirebaseDatabase.instance.ref('users/${_user.uid}').remove();
    await _user.delete();
    await FirebaseAuth.instance.signOut();

    // FIX: Navigate to LoginScreen and show confirmation — not just signOut()
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      // Show snackbar after navigation settles
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      });
    }
  }

  Future<bool> _reAuth() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser != null) {
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await _user.reauthenticateWithCredential(credential);
        return true;
      }
    } catch (_) {}

    final passwordController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        title: const Text('Confirm Password',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter your password',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (result != true) {
      passwordController.dispose();
      return false;
    }
    // Read the password BEFORE disposing the controller
    final password = passwordController.text;
    passwordController.dispose();
    try {
      final cred = EmailAuthProvider.credential(
          email: _user.email!, password: password);
      await _user.reauthenticateWithCredential(cred);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Re-authentication failed: $e')));
      }
      return false;
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B2838),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1923),
        title: const Text('Account Management',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionTitle('Profile'),
                      const SizedBox(height: 8),
                      Text(_user.email ?? '',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          labelStyle:
                              const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF1B2838),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _savePhone,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Save Phone'),
                      ),
                      const SizedBox(height: 28),

                      _sectionTitle('Your Devices'),
                      const SizedBox(height: 8),
                      if (_devices.isEmpty)
                        const Text('No devices linked.',
                            style: TextStyle(color: Colors.white54)),
                      ..._devices.map((device) {
                        final deviceId = device['deviceId'] as String;
                        final name = device['name'] as String;
                        final isOwn = _isOwner(device);
                        final members = device['members'] as Map?;
                        final memberEmails =
                            (device['memberEmails'] as Map<String, String>?) ??
                                {};
                        final otherMemberCount = members?.keys
                                .where((k) => k != _user.uid)
                                .length ??
                            0;

                        return Card(
                          color: const Color(0xFF1B2838),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: Icon(
                              isOwn
                                  ? Icons.shield_outlined
                                  : Icons.person_outline,
                              color:
                                  isOwn ? Colors.amber : Colors.blueAccent,
                            ),
                            title: Text(name,
                                style:
                                    const TextStyle(color: Colors.white)),
                            subtitle: Text(
                              isOwn
                                  ? otherMemberCount == 0
                                      ? 'Owner · Only you'
                                      : 'Owner · $otherMemberCount member${otherMemberCount > 1 ? 's' : ''}'
                                  : 'Member',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                            trailing: PopupMenuButton<String>(
                              color: const Color(0xFF1B2838),
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.white54),
                              onSelected: (v) {
                                switch (v) {
                                  case 'leave':
                                    _leaveDevice(deviceId);
                                    break;
                                  case 'invite':
                                    _inviteByEmail(deviceId, name);
                                    break;
                                  case 'transfer':
                                    _transferOwnership(
                                        deviceId, members, memberEmails);
                                    break;
                                  case 'delete':
                                    _deleteDevice(deviceId, members);
                                    break;
                                }
                              },
                              itemBuilder: (_) => [
                                if (!isOwn)
                                  const PopupMenuItem(
                                    value: 'leave',
                                    child: Text('Leave Device',
                                        style:
                                            TextStyle(color: Colors.white)),
                                  ),
                                if (isOwn)
                                  const PopupMenuItem(
                                    value: 'invite',
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_add_outlined,
                                            color: Colors.blueAccent,
                                            size: 18),
                                        SizedBox(width: 8),
                                        Text('Invite User',
                                            style: TextStyle(
                                                color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                if (isOwn)
                                  const PopupMenuItem(
                                    value: 'transfer',
                                    child: Text('Transfer Ownership',
                                        style:
                                            TextStyle(color: Colors.white)),
                                  ),
                                if (isOwn)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete Device',
                                        style: TextStyle(
                                            color: Colors.redAccent)),
                                  ),
                              ],
                            ),
                            onTap: isOwn && members != null
                                ? () => _showMembersSheet(
                                    deviceId, members, memberEmails)
                                : null,
                          ),
                        );
                      }),
                      const SizedBox(height: 32),

                      _sectionTitle('Danger Zone'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _deleteAccount,
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.red),
                        label: const Text('Delete Account',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
                const ContactUsFooter(),
              ],
            ),
    );
  }

  void _showMembersSheet(
      String deviceId, Map members, Map<String, String> memberEmails) {
    final otherMembers =
        members.entries.where((e) => e.key != _user.uid).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B2838),
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Members',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (otherMembers.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.person_outline, color: Colors.white38, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'You are the only user on this device.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ...otherMembers.map((e) {
              final uid = e.key.toString();
              final email = memberEmails[uid] ?? uid;
              return ListTile(
                leading: const Icon(Icons.person_outline,
                    color: Colors.white54),
                title: Text(email,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.redAccent),
                  onPressed: () {
                    Navigator.pop(context);
                    _removeMember(deviceId, uid);
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      );
}