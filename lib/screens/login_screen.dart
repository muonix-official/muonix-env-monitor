import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../widgets/contact_us_footer.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ── userIndex helpers ──────────────────────────────────────────────────
  String _encodeEmailKey(String email) {
    return email.trim().toLowerCase().replaceAll('.', ',');
  }

  Future<void> _writeUserIndex(String uid, String? email) async {
    if (email == null || email.trim().isEmpty) return;
    try {
      final key = _encodeEmailKey(email);
      await FirebaseDatabase.instance.ref('userIndex/$key').set(uid);
    } catch (_) {}
  }
  // ────────────────────────────────────────────────────────────────────────

  // After a successful sign-in, the authStateChanges StreamBuilder in
  // main.dart *should* rebuild automatically. But after an account deletion
  // in the same app session, the stream can get stuck and never fire for
  // the next sign-in. To guarantee navigation always happens, we call this
  // helper right after any successful sign-in — it pushes away from
  // LoginScreen explicitly so we never depend solely on the stream.
  void _navigateAfterSignIn() {
    if (!mounted) return;
    // Pop everything and let main.dart's StreamBuilder take over from root.
    // Using pushNamedAndRemoveUntil with '/' would require named routes,
    // so instead we just pop to root — if LoginScreen was pushed on top of
    // something, pop it; if it IS the root (normal case), the StreamBuilder
    // will have already rebuilt by the time this runs, so we force it by
    // calling setState on the nearest ancestor via a post-frame callback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Trigger the root StreamBuilder to re-evaluate by signing in again
      // isn't needed — just tell Flutter to rebuild from root.
      final nav = Navigator.of(context, rootNavigator: true);
      nav.pushNamedAndRemoveUntil('/', (route) => false);
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = '';
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut(); // clear any cached account
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the picker
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final user = userCredential.user;
      if (user != null) {
        // Backfill email into DB
        try {
          await FirebaseDatabase.instance
              .ref('users/${user.uid}')
              .update({'email': user.email ?? ''});
        } catch (_) {}

        // Keep userIndex in sync
        await _writeUserIndex(user.uid, user.email);
      }

      // FIX: explicitly navigate after Google sign-in instead of relying
      // solely on the authStateChanges stream, which can get stuck after
      // an account deletion earlier in the same app session.
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _errorMessage = 'Google sign in failed. Try again.';
        });
      }
    }
    // Note: we don't set _isGoogleLoading = false on success because
    // the screen is navigating away — setting state on an unmounting
    // widget causes an error.
  }

  Future<void> _authenticate() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty ||
        (_isSignUp && _phoneController.text.trim().isEmpty)) {
      setState(() => _errorMessage = 'Please fill in all fields');
      return;
    }

    if (_isSignUp && _phoneController.text.trim().length < 10) {
      setState(() => _errorMessage = 'Enter a valid 10-digit phone number');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_isSignUp) {
        final credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        final uid = credential.user?.uid;
        if (uid != null) {
          try {
            await FirebaseDatabase.instance.ref('users/$uid').update({
              'email': _emailController.text.trim(),
              'phone': _phoneController.text.trim(),
            });
          } catch (_) {}

          await _writeUserIndex(uid, _emailController.text.trim());
        }

        await credential.user?.sendEmailVerification();
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1B2838),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Verify Your Email',
                  style: TextStyle(color: Colors.white)),
              content: Text(
                'A verification link has been sent to ${_emailController.text.trim()}\n\nPlease verify your email before logging in.\n\n⚠️ If not in inbox, check your spam/junk folder.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK', style: TextStyle(color: Colors.blue)),
                ),
              ],
            ),
          );
        }
      } else {
        final credential =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (credential.user != null && !credential.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          setState(() => _errorMessage =
              'Please verify your email before logging in.\nCheck your inbox or spam/junk folder for the verification link.');
        } else if (credential.user != null) {
          try {
            await FirebaseDatabase.instance
                .ref('users/${credential.user!.uid}')
                .update({'email': _emailController.text.trim()});
          } catch (_) {}

          await _writeUserIndex(
              credential.user!.uid, _emailController.text.trim());

          // FIX: same explicit navigation as Google sign-in, for consistency
          // and to handle the post-deletion stream-stuck case.
          if (mounted) {
            Navigator.of(context, rootNavigator: true)
                .pushNamedAndRemoveUntil('/', (route) => false);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'No account found with this email';
            break;
          case 'wrong-password':
            _errorMessage = 'Incorrect password';
            break;
          case 'email-already-in-use':
            _errorMessage = 'Email already registered';
            break;
          case 'weak-password':
            _errorMessage = 'Password must be at least 6 characters';
            break;
          case 'invalid-email':
            _errorMessage = 'Invalid email address';
            break;
          default:
            _errorMessage = e.message ?? 'An error occurred';
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() =>
          _errorMessage = 'Enter your email first then tap forgot password');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1B2838),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Email Sent!',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'Password reset link sent to ${_emailController.text.trim()}\n\nIf not in inbox, please check your spam/junk folder.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Error sending reset email');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B2838),
              Color(0xFF0D1B2A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(Icons.sensors,
                              size: 52, color: Colors.blue),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Muonix EnvGuard',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isSignUp
                              ? 'Create your account'
                              : 'Monitor your environment',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed:
                                _isGoogleLoading ? null : _signInWithGoogle,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: _isGoogleLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.blue, strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Image.network(
                                        'https://www.google.com/favicon.ico',
                                        width: 20,
                                        height: 20,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.g_mobiledata,
                                                color: Colors.red, size: 24),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Continue with Google',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                                child: Divider(
                                    color: Colors.white.withValues(alpha: 0.15))),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'or',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 13),
                              ),
                            ),
                            Expanded(
                                child: Divider(
                                    color: Colors.white.withValues(alpha: 0.15))),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Column(
                            children: [
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6)),
                                  prefixIcon: Icon(Icons.email_outlined,
                                      color: Colors.blue.withValues(alpha: 0.8)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.15)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: Colors.blue, width: 1.5),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              if (_isSignUp) ...[
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  maxLength: 10,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Phone Number',
                                    counterText: '',
                                    labelStyle: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6)),
                                    prefixIcon: Icon(Icons.phone_outlined,
                                        color: Colors.blue.withValues(alpha: 0.8)),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Colors.blue, width: 1.5),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.05),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: _isSignUp
                                      ? 'Create Password'
                                      : 'Password',
                                  labelStyle: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6)),
                                  prefixIcon: Icon(Icons.lock_outline,
                                      color: Colors.blue.withValues(alpha: 0.8)),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: Colors.white.withValues(alpha: 0.4),
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.white.withValues(alpha: 0.15)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: Colors.blue, width: 1.5),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (!_isSignUp)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GestureDetector(
                                    onTap: _forgotPassword,
                                    child: Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: Colors.blue.withValues(alpha: 0.8),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              if (_errorMessage.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.red.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    _errorMessage,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 13),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _authenticate,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : Text(
                                          _isSignUp
                                              ? 'Create Account'
                                              : 'Login',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isSignUp
                                  ? 'Already have an account? '
                                  : 'New user? ',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5)),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _isSignUp = !_isSignUp),
                              child: Text(
                                _isSignUp ? 'Login' : 'Create account',
                                style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Muonix Electrosystems LLP • Jaipur',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const ContactUsFooter(),
            ],
          ),
        ),
      ),
    );
  }
}