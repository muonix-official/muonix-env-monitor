import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:app_links/app_links.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/devices_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/relay_history_listener.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  try {
    await NotificationService.initialize();
    await BackgroundService.init();
    await BackgroundService.registerPeriodicTask();
  } catch (e) {
    debugPrint('Service init failed: $e');
  }
  runApp(const MyApp());
}

// ─── Navigator key ────────────────────────────────────────────────────────
// Shared so the deep-link handler can navigate from outside the widget tree.
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  // ── Deep link handler ───────────────────────────────────────────────────
  // Handles Firebase email action links that open the app.
  // Flow:
  //   1. User signs up → sendEmailVerification(ActionCodeSettings) sends
  //      a link to the user's email that contains mode=verifyEmail&oobCode=…
  //   2. User taps link → Android App Link opens the app (via intent filter
  //      in AndroidManifest.xml for sensorbox-6ccc8.firebaseapp.com)
  //   3. _handleEmailActionLink extracts the oobCode and calls applyActionCode
  //   4. authStateChanges fires → StreamBuilder rebuilds → user lands on
  //      DevicesScreen automatically (no "I have verified" button needed)
  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();

      // Check for the link that launched the app cold
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleEmailActionLink(initialUri);
      }

      // Listen for links while the app is already running
      _linkSub = appLinks.uriLinkStream.listen(
        _handleEmailActionLink,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // app_links not available on this platform / in debug — safe to ignore
    }
  }

  Future<void> _handleEmailActionLink(Uri uri) async {
    final mode    = uri.queryParameters['mode'];
    final oobCode = uri.queryParameters['oobCode'];

    if (mode == 'verifyEmail' && oobCode != null && oobCode.isNotEmpty) {
      try {
        // Complete the email verification on the Firebase side
        await FirebaseAuth.instance.applyActionCode(oobCode);

        // Reload so emailVerified flips to true in the cached user object
        await FirebaseAuth.instance.currentUser?.reload();

        // authStateChanges will fire and the StreamBuilder at '/' will
        // rebuild — moving the user past _VerifyEmailScreen automatically.
        // We also push '/' explicitly in case the stream doesn't fire
        // (e.g. if the user was already signed out).
        _navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/', (_) => false);
      } catch (e) {
        // Link expired or already used — show a snackbar and let the user
        // tap "I have verified" manually as a fallback.
        debugPrint('[DeepLink] applyActionCode failed: $e');
        final ctx = _navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text(
                'Verification link expired or already used. '
                'Please log in — your email may already be verified.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }
  // ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Muonix EnvGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasData) {
                  final user = snapshot.data!;
                  if (!user.emailVerified) {
                    return _VerifyEmailScreen(user: user);
                  }
                  return _PhoneGate(user: user);
                }
                return const LoginScreen();
              },
            ),
      },
    );
  }
}

// ─── Phone number gate ────────────────────────────────────────────────────
class _PhoneGate extends StatefulWidget {
  final User user;
  const _PhoneGate({required this.user});

  @override
  State<_PhoneGate> createState() => _PhoneGateState();
}

class _PhoneGateState extends State<_PhoneGate> {
  bool _loading    = true;
  bool _needsPhone = false;

  @override
  void initState() {
    super.initState();
    _checkPhone();
  }

  Future<void> _checkPhone() async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/${widget.user.uid}/phone')
          .get();
      final hasPhone = snap.exists &&
          snap.value != null &&
          snap.value.toString().trim().isNotEmpty;
      if (mounted) {
        setState(() { _needsPhone = !hasPhone; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1B2A),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_needsPhone) {
      return _CompleteProfileScreen(
        uid:     widget.user.uid,
        onSaved: () => setState(() => _needsPhone = false),
      );
    }
    RelayHistoryListener.start();
    return DevicesScreen();
  }
}

// ─── Complete profile screen ──────────────────────────────────────────────
class _CompleteProfileScreen extends StatefulWidget {
  final String uid;
  final VoidCallback onSaved;
  const _CompleteProfileScreen({required this.uid, required this.onSaved});

  @override
  State<_CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<_CompleteProfileScreen> {
  final _phoneController = TextEditingController();
  bool   _saving       = false;
  String _errorMessage = '';

  @override
  void dispose() { _phoneController.dispose(); super.dispose(); }

  Future<void> _save() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      setState(() => _errorMessage = 'Enter a valid 10-digit phone number');
      return;
    }
    setState(() { _saving = true; _errorMessage = ''; });
    try {
      await FirebaseDatabase.instance
          .ref('users/${widget.uid}/phone')
          .set(phone);
      widget.onSaved();
    } catch (e) {
      setState(() =>
          _errorMessage = 'Could not save. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.phone_outlined, size: 52, color: Colors.blue),
              ),
              const SizedBox(height: 24),
              const Text('One Last Step',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              Text(
                'Please add your phone number to finish setting up your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _phoneController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '10-digit phone number',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  prefixIcon: Icon(Icons.phone_outlined,
                      color: Colors.blue.withValues(alpha: 0.8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.15)),
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
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(_errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Continue',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: Text('Sign out',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Email verification screen ────────────────────────────────────────────
// Shown while emailVerified == false. The user can also tap the button as
// a manual fallback if the deep link didn't fire for some reason.
class _VerifyEmailScreen extends StatefulWidget {
  final User user;
  const _VerifyEmailScreen({required this.user});

  @override
  State<_VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<_VerifyEmailScreen> {
  bool _isChecking = false;

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;
      if (updatedUser != null && updatedUser.emailVerified) {
        // authStateChanges will rebuild the root StreamBuilder automatically
      } else {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Email not verified yet. Please verify and login again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.mark_email_unread,
                    size: 52, color: Colors.orange),
              ),
              const SizedBox(height: 24),
              const Text('Verify Your Email',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to\n${widget.user.email}\n\n'
                'Tap the link in the email — the app will open and log you in automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _checkVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Already verified? Continue manually',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  await widget.user.sendEmailVerification(
                    ActionCodeSettings(
                      url: 'https://sensorbox-6ccc8.firebaseapp.com/',
                      androidPackageName: 'com.example.sensorbox',
                      androidInstallApp: false,
                      handleCodeInApp: true,
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Verification email resent!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: Text('Resend verification email',
                    style: TextStyle(
                        color: Colors.orange.withValues(alpha: 0.8))),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: Text('Sign out',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}