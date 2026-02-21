import 'dart:async';
import 'package:audio_story_app/services/app_audio_service.dart';
import 'package:flutter/material.dart'; // <-- This is the import it can't find
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:audio_story_app/services/device_limit_service.dart';
import 'package:audio_story_app/services/device_id_service.dart';
import 'package:audio_story_app/services/device_info_service.dart';

import 'package:audio_story_app/services/auth_service.dart';
import 'package:audio_story_app/widgets/background_container.dart';
import 'package:audio_story_app/utils/app_theme.dart';
import 'package:audio_story_app/main.dart' show AuthGate;
import 'package:audio_story_app/screens/master_profile_screen.dart';

/// ---------------------- LOGIN ----------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _auth = FirebaseAuth.instance;

  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _assetsPrecached = false;

  bool _isLoading = false;
  // --- REMOVED StreamSubscription ---

  // @override
  // void initState() async {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assetsPrecached) return;
    _assetsPrecached = true;

    // Pre-decode background + icons to prevent a gray/blank frame on navigation.
    precacheImage(const AssetImage('assets/backgrounds/signin.png'), context);
    precacheImage(
        const AssetImage('assets/backgrounds/login_bg_purple.png'), context);
    precacheImage(const AssetImage('assets/google_logo.png'), context);
  }

  @override
  void dispose() {
    // --- REMOVED authSub?.cancel() ---
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }
  // -------------------- DEVICE LIMIT (max 2 devices) --------------------
  static const Color _vibrantBlue = Color(0xFF061B3A); // dark vibrant blue
  static const Color _accentOrange = Color(0xFFFF9800);

  Future<bool> _ensureDeviceSlot(User user) async {
    final uid = user.uid;
    final deviceId = await DeviceIdService.getOrCreate();
    final svc = DeviceLimitService();

    final active = await svc.getActiveDevices(uid);
    final isThisDeviceActive = active.any((d) => d.deviceId == deviceId);

    // Build current device info once. Used for registration and for
    // best-effort physical-device matching (reinstall should not consume
    // an extra slot if it's the same device).
    final currentInfo = await DeviceInfoService.buildFirestoreInfo();
    final currentHardwareId = currentInfo['hardwareId']?.toString().trim();

    // If already active, just refresh/touch registration (best effort) and proceed.
    if (isThisDeviceActive) {
      final platform = kIsWeb
          ? 'web'
          : (Platform.isAndroid
              ? 'android'
              : (Platform.isIOS ? 'ios' : 'other'));
      await svc.registerThisDevice(
        uid: uid,
        deviceId: deviceId,
        info: {
          ...currentInfo,
          'platform': platform,
        },
      );
      return true;
    }

    // If we have room (<2), register and proceed.
    if (active.length < 2) {
      final platform = kIsWeb
          ? 'web'
          : (Platform.isAndroid
              ? 'android'
              : (Platform.isIOS ? 'ios' : 'other'));
      await svc.registerThisDevice(
        uid: uid,
        deviceId: deviceId,
        info: {
          ...currentInfo,
          'platform': platform,
        },
      );
      return true;
    }

    // If there are already 2 active devices, but one of them is the same
    // physical device (e.g., user uninstalled/reinstalled and got a new
    // per-install deviceId), automatically free the older session.
    if (currentHardwareId != null && currentHardwareId.isNotEmpty) {
      final match = active.where((d) => (d.hardwareId ?? '').trim() == currentHardwareId).toList();
      if (match.isNotEmpty) {
        // Deactivate the old install session, then register current install.
        await svc.deactivateDevice(uid: uid, deviceId: match.first.deviceId);

        final platform = kIsWeb
            ? 'web'
            : (Platform.isAndroid
                ? 'android'
                : (Platform.isIOS ? 'ios' : 'other'));
        await svc.registerThisDevice(
          uid: uid,
          deviceId: deviceId,
          info: {
            ...currentInfo,
            'platform': platform,
          },
        );
        return true;
      }
    }

    // Otherwise, ask the user which device to log out.
    // Requirement: show only 2 devices in the chooser (the active ones).
    final selectedDeviceId = await _showDeviceChooser(_topTwo(active));
    if (selectedDeviceId == null) {
      // User backed out -> do not keep partial login session.
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      return false;
    }

    // Deactivate selected device, then register current one.
    await svc.deactivateDevice(uid: uid, deviceId: selectedDeviceId);
    final platform = kIsWeb
        ? 'web'
        : (Platform.isAndroid
            ? 'android'
            : (Platform.isIOS ? 'ios' : 'other'));
    await svc.registerThisDevice(
      uid: uid,
      deviceId: deviceId,
      info: {
        ...currentInfo,
        'platform': platform,
      },
    );

    return true;
  }

  List<DeviceSession> _topTwo(List<DeviceSession> devices) {
    final copy = List<DeviceSession>.from(devices);
    copy.sort((a, b) {
      final ta = a.lastSeen?.millisecondsSinceEpoch ?? -1;
      final tb = b.lastSeen?.millisecondsSinceEpoch ?? -1;
      return tb.compareTo(ta);
    });
    return copy.take(2).toList();
  }

  Future<String?> _showDeviceChooser(List<DeviceSession> devices) async {
    if (!mounted) return null;

    // Sort: most recently seen first (nulls last)
    devices.sort((a, b) {
      final ta = a.lastSeen?.millisecondsSinceEpoch ?? -1;
      final tb = b.lastSeen?.millisecondsSinceEpoch ?? -1;
      return tb.compareTo(ta);
    });

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: _vibrantBlue,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Device limit reached',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFamily: AppTheme.headingFont,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your account is already active on 2 devices.\n'
                    'Select one device to log out so you can sign in here.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.3,
                      fontFamily: AppTheme.bodyFont,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final d = devices[i];
                        final name = (d.deviceName?.trim().isNotEmpty == true)
                            ? d.deviceName!.trim()
                            : (d.model?.trim().isNotEmpty == true ? d.model!.trim() : 'Device');
                        final platform = (d.platform ?? '').toUpperCase();
                        final lastSeen = d.lastSeen == null
                            ? 'Last seen: unknown'
                            : 'Last seen: ${_formatTime(d.lastSeen!)}';
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(context, d.deviceId),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.devices, color: Colors.white70),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: AppTheme.bodyFont,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [platform.isEmpty ? null : platform, lastSeen]
                                            .where((e) => e != null && e!.isNotEmpty)
                                            .join(' • '),
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                          fontFamily: AppTheme.bodyFont,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _accentOrange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _accentOrange.withOpacity(0.6)),
                                  ),
                                  child: const Text(
                                    'Log out',
                                    style: TextStyle(
                                      color: _accentOrange,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      fontFamily: AppTheme.bodyFont,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withOpacity(0.35)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    // Simple local format: 19 Feb, 10:45 PM
    final d = dt.toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final day = d.day.toString().padLeft(2, '0');
    final mon = months[d.month - 1];
    final hour24 = d.hour;
    final hour12 = ((hour24 + 11) % 12) + 1;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = hour24 >= 12 ? 'PM' : 'AM';
    return '$day $mon, $hour12:$min $ampm';
  }


  

  InputDecoration _darkInput(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.black.withOpacity(0.65), // same dark as requested
      hintStyle:
          const TextStyle(color: Colors.white60, fontFamily: AppTheme.bodyFont),
      labelStyle:
          const TextStyle(color: Colors.white70, fontFamily: AppTheme.bodyFont),
      floatingLabelStyle:
          const TextStyle(color: Colors.white70, fontFamily: AppTheme.bodyFont),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white54),
      ),
    );
  }

  Future<void> _emailSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      // This is for existing users, so navigate to AuthGate
      final cred = await _auth.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwdCtrl.text,
      );

      final user = cred.user;
      if (user == null) {
        _toast('Login failed. Please try again.');
        return;
      }

      final ok = await _ensureDeviceSlot(user);
      if (!ok) return;

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (r) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    // Assume _authService.signInWithGoogle() returns UserCredential?
    final cred = await _authService.signInWithGoogle();

    if (mounted) setState(() => _isLoading = false);

    if (cred == null) {
      _toast('Google Sign-In failed or cancelled.');
      return;
    }

    // --- ADDED EXPLICIT NAVIGATION ---
    // Check if the user is new (we have to assume 'cred' is UserCredential)
    final bool isNewUser = cred.additionalUserInfo?.isNewUser ?? false;

    if (mounted) {
      if (isNewUser) {
        // New user -> Go to Master Profile
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MasterProfileScreen()),
          (r) => false,
        );
      } else {
        // Existing user -> Go to AuthGate
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (r) => false,
        );
      }
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        title:
            const Text('Reset password', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            labelText: 'Email',
            filled: true,
            fillColor: Colors.black.withOpacity(0.65),
            labelStyle: const TextStyle(color: Colors.white70),
            floatingLabelStyle: const TextStyle(color: Colors.white70),
            hintStyle: const TextStyle(color: Colors.white60),
            border: const OutlineInputBorder(borderSide: BorderSide.none),
            enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white54)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _auth.sendPasswordResetEmail(email: emailCtrl.text.trim());
        _toast('Reset email sent.');
      } on FirebaseAuthException catch (e) {
        _toast(e.message ?? e.code);
      }
    }
  }

  // Age gate when tapping TOS/Privacy
  Future<void> _ageGateAndShow(String title) async {
    final yearCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('For parents',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  fontFamily: AppTheme.headingFont)),
          const SizedBox(height: 8),
          const Text('Enter your year of birth to continue',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          TextField(
            controller: yearCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'e.g. 1985',
              hintStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.black.withOpacity(0.65),
              border: const OutlineInputBorder(borderSide: BorderSide.none),
              enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54)),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              final y = int.tryParse(yearCtrl.text.trim());
              final nowYear = DateTime.now().year;
              final age = (y == null) ? 0 : (nowYear - y);
              Navigator.pop(context, age >= 13);
            },
            child: const Text('Continue'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (ok == true) {
      final uri = (title.toLowerCase().contains('terms'))
          ? Uri.parse('https://appayistories.com/terms')
          : Uri.parse('https://appayistories.com/privacy');

      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.inAppBrowserView,
        );
        if (!launched) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        _toast('Could not open the link.');
      }
    } else {
      _toast('Only parents can view $title.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundContainer(
      imagePath: 'assets/backgrounds/signin.png',
      dimOpacity: 0.12,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App name
                    Text('APPAYI',
                        style: TextStyle(
                            fontFamily: AppTheme.headingFont,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    Text('BedTime Stories',
                        style: TextStyle(
                            fontFamily: AppTheme.headingFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70)),

                    const SizedBox(height: 24),

                    // Email/Password form
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: AppTheme.bodyFont),
                            cursorColor: Colors.white,
                            decoration: _darkInput('Email'),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _pwdCtrl,
                            obscureText: true,
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: AppTheme.bodyFont),
                            cursorColor: Colors.white,
                            decoration: _darkInput('Password'),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Min 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _emailSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black.withOpacity(0.88),
                                foregroundColor: Colors.orangeAccent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Text('Sign in with Email'),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text('Or',
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),

                    // Google
                    InkWell(
                      onTap: _isLoading ? null : _handleGoogle,
                      borderRadius: BorderRadius.circular(28),
                      child: Ink(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black38,
                                blurRadius: 10,
                                offset: Offset(0, 6))
                          ],
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Image.asset('assets/google_logo.png',
                                fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // TOS / Privacy with age gate
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => _ageGateAndShow('Terms of Service'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          child: const Text('Terms of Service'),
                        ),
                        Text('•', style: TextStyle(color: Colors.white70)),
                        TextButton(
                          onPressed: () => _ageGateAndShow('Privacy Policy'),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          child: const Text('Privacy Policy'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Forgot + Sign up
                    TextButton(
                      onPressed: _forgotPassword,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Forgot password?  Reset now'),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? ",
                            style: TextStyle(color: Colors.white70)),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SignUpScreen()));
                          },
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          child: const Text('Sign up'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------- SIGN UP ----------------------
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({Key? key}) : super(key: key);

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _creating = false;

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  InputDecoration _darkInput(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.black.withOpacity(0.65), // same dark
      hintStyle:
          const TextStyle(color: Colors.white60, fontFamily: AppTheme.bodyFont),
      labelStyle:
          const TextStyle(color: Colors.white70, fontFamily: AppTheme.bodyFont),
      floatingLabelStyle:
          const TextStyle(color: Colors.white70, fontFamily: AppTheme.bodyFont),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white54),
      ),
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _creating = true);
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwdCtrl.text,
      );
      final u = cred.user!;
      await _db.collection('users').doc(u.uid).set({
        'uid': u.uid,
        'email': u.email,
        'displayName': _nameCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'settings': {
          'homeThemeMode': 'auto',
          'autoPlay': true,
          'commentsEnabled': false, // default off for kids
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MasterProfileScreen()),
        (r) => false,
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundContainer(
      imagePath: 'assets/backgrounds/login_bg_purple.png',
      dimOpacity: 0.12,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Create Account',
              style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: AppTheme.bodyFont),
                      cursorColor: Colors.white,
                      decoration: _darkInput('Name'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: AppTheme.bodyFont),
                      cursorColor: Colors.white,
                      decoration: _darkInput('Email'),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pwdCtrl,
                      obscureText: true,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: AppTheme.bodyFont),
                      cursorColor: Colors.white,
                      decoration: _darkInput('Password'),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Min 6 characters'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _create,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.88),
                          foregroundColor: Colors.orangeAccent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _creating
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Create account'),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()));
                      },
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Have an account? Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
