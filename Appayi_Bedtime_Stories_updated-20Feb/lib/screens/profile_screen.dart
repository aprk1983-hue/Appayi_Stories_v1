import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:audio_story_app/services/auth_service.dart';
import 'package:audio_story_app/services/device_id_service.dart';
import 'package:audio_story_app/services/device_limit_service.dart';
import 'package:audio_story_app/screens/onboarding_screen.dart';
import 'package:audio_story_app/screens/language_selection_screen.dart';
import 'package:audio_story_app/screens/master_profile_screen.dart';
import 'package:audio_story_app/screens/parental_controls_screen.dart';

// --- 1. ADD NEW IMPORTS ---
import 'package:audio_story_app/theme_controller.dart';
import 'package:audio_story_app/screens/rewards_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = FirebaseAuth.instance;

  bool _loading = true;
  bool _autoPlay = true;

  // New Story push notifications (opt-in, parent-controlled)
  // Default ON (user can turn OFF)
  bool _notifyNewStories = true;
  bool _notifyBusy = false;

  String _displayName = 'Parent';
  String _emailOrPhone = '';

  String? _deviceModel;

  final bool _showDeviceTile = false;
// Add these variables
  bool _isLoadingSubscription = true;
  String _currentPlan = 'Free';
  String _planPeriod = '';
  String _expirationDate = '';
  bool _hasSubscription = false;
  Future<void> _loadSubscriptionData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoadingSubscription = false;
          _currentPlan = 'Free';
        });
        return;
      }

      // Get customer info from RevenueCat
      final customerInfo = await Purchases.getCustomerInfo();
      final active = customerInfo.entitlements.active;

      if (active.isEmpty) {
        setState(() {
          _isLoadingSubscription = false;
          _currentPlan = 'Free';
          _hasSubscription = false;
        });
        return;
      }

      // Check for your entitlement (adjust ID as needed)
      final entitlement =
          active['premium'] ?? active['premium_tier'] ?? active.values.first;

      if (entitlement != null) {
        final productId = entitlement.productIdentifier.toLowerCase();
        String period = '';

        // Determine if monthly or yearly
        if (productId.contains('month') || productId.contains('monthly')) {
          period = 'Monthly';
        } else if (productId.contains('year') ||
            productId.contains('annual') ||
            productId.contains('yearly')) {
          period = 'Yearly';
        } else {
          period = '';
        }

        String planName = 'Premium';
        if (productId.contains('basic')) {
          planName = 'Basic';
        } else if (productId.contains('pro')) {
          planName = 'Pro';
        }

        setState(() {
          _isLoadingSubscription = false;
          _currentPlan = planName;
          _planPeriod = period;
          // _expirationDate = expiration;
          _hasSubscription = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading subscription: $e');
      setState(() {
        _isLoadingSubscription = false;
        _currentPlan = 'Free';
        _hasSubscription = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadSubscriptionData();
  }

  // ---------------------------------------------------------------------------
  // Smooth navigation to reduce flicker across Profile -> Settings pages
  // (UI-only; no business logic changes)
  // ---------------------------------------------------------------------------
  Route<T> _smoothRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      opaque: true,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0.0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<T?> _pushSmooth<T>(Widget page) {
    // IMPORTANT: keep this on the *nearest* Navigator so we return back to Profile,
    // not the root/home route (fixes "back goes to home" behavior in nested nav setups).
    return Navigator.of(context, rootNavigator: false)
        .push<T>(_smoothRoute<T>(page));
  }

  Future<void> _loadData() async {
    // Sequential awaits avoids type issues if any loader returns void.
    await _loadUser();
    await _loadDeviceModel();
    await _loadNotifyPref();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snap.data() ?? {};

    final guardian = (data['guardian'] is Map) ? data['guardian'] as Map : null;
    final firstName = (guardian?['firstName'])?.toString();

    _displayName = (firstName != null && firstName.trim().isNotEmpty)
        ? _titleCase(firstName.trim())
        : 'Parent';

    _emailOrPhone = (user.email?.isNotEmpty ?? false)
        ? user.email!
        : (user.phoneNumber ?? '');

    final settings = (data['settings'] is Map) ? data['settings'] as Map : {};
    _autoPlay =
        settings['autoPlay'] is bool ? settings['autoPlay'] as bool : true;
  }

  Future<void> _loadDeviceModel() async {
    try {
      if (kIsWeb) {
        _deviceModel = 'Web Browser';
        return;
      }
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final brand = (a.brand ?? '').trim();
        final model = (a.model ?? '').trim();
        _deviceModel = [brand, model].where((s) => s.isNotEmpty).join(' ');
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _deviceModel = i.utsname.machine ?? 'iOS Device';
      } else if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        _deviceModel = m.model ?? 'macOS';
      } else if (Platform.isWindows) {
        final w = await info.windowsInfo;
        _deviceModel = w.computerName ?? 'Windows';
      } else if (Platform.isLinux) {
        final l = await info.linuxInfo;
        _deviceModel = l.prettyName ?? 'Linux';
      } else {
        _deviceModel = 'Unknown Device';
      }
    } catch (_) {
      _deviceModel = _fallbackDeviceString();
    }
  }

  Future<void> _loadNotifyPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasKey = prefs.containsKey('notify_new_stories');
      final v = prefs.getBool('notify_new_stories') ?? true;

      // Persist default ON the first time, so UI remains consistent across sessions.
      if (!hasKey) {
        await prefs.setBool('notify_new_stories', true);
      }

      // Best-effort keep topic subscription aligned with the saved preference.
      // (Permission prompt happens at Login screen as requested.)
      try {
        final fcm = FirebaseMessaging.instance;
        if (v) {
          await fcm.subscribeToTopic('new_stories');
        } else {
          await fcm.unsubscribeFromTopic('new_stories');
        }
      } catch (_) {
        // ignore
      }

      if (!mounted) return;
      setState(() => _notifyNewStories = v);
    } catch (_) {
      // ignore - keep default true
    }
  }

  Future<void> _setNewStoryNotifications(bool enable) async {
    if (_notifyBusy) return;
    if (mounted) setState(() => _notifyBusy = true);

    final fcm = FirebaseMessaging.instance;

    try {
      if (enable) {
        final settings = await fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        final authorized =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;

        if (!authorized) {
          if (mounted) setState(() => _notifyNewStories = false);
        } else {
          await fcm.subscribeToTopic('new_stories');
          if (mounted) setState(() => _notifyNewStories = true);
        }
      } else {
        await fcm.unsubscribeFromTopic('new_stories');
        if (mounted) setState(() => _notifyNewStories = false);
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notify_new_stories', _notifyNewStories);
      } catch (_) {
        // ignore
      }
    } catch (_) {
      // If something failed, revert UI to a safe state
      if (mounted) setState(() => _notifyNewStories = !enable);
    } finally {
      if (mounted) setState(() => _notifyBusy = false);
    }
  }

  String _fallbackDeviceString() {
    if (kIsWeb) return 'Web Browser';
    if (Platform.isAndroid) return 'Android Device';
    if (Platform.isIOS) return 'iOS Device';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  String _titleCase(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  Future<void> _setAutoPlay(bool value) async {
    setState(() => _autoPlay = value);
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'settings': {'autoPlay': value},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _goLanguage() {
    _pushSmooth(const LanguageSelectionScreen());
  }

  void _goParentalControls() {
    _pushSmooth(const ParentalControlsScreen());
  }

  void _goAboutUs() {
    _pushSmooth(const _AboutUsPage());
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link')),
      );
      return;
    }

    // Prefer opening inside the app (Custom Tabs / SFSafariViewController) for a smoother experience.
    // Fallback to external browser if in-app view isn't available.
    bool success = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!success) {
      success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $urlString')),
      );
    }
  }

  void _goPrivacyPolicy() {
    _launchURL('https://appayistories.com/privacy'); // <-- TODO: REPLACE URL
  }

  void _goTerms() {
    _launchURL('https://appayistories.com/terms'); // <-- TODO: REPLACE URL
  }

  void _goRateApp() {
    if (Platform.isAndroid) {
      _launchURL(
          'https://play.google.com/store/apps/details?id=com.app.audiostoryapp');
    } else if (Platform.isIOS) {
      _launchURL('https://apps.apple.com/app/your-app-id');
    }
  }

  void _openContact() {
    _pushSmooth(
        const _ContactUsPage(supportEmail: 'support@appayistories.com'));
  }

  Future<void> _shareApp() async {
    const link =
        'https://play.google.com/store/apps/details?id=com.app.audiostoryapp';
    await Clipboard.setData(const ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App link copied! Share it anywhere.'),
        backgroundColor: Colors.grey,
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: dialogBg,
        title: Text('Delete Account?', style: TextStyle(color: textColor)),
        content: Text(
          'This will permanently delete your account and kid profile data. '
          'This action cannot be undone.',
          style: TextStyle(color: textColor.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: textColor))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final String uid = user.uid;
    try {
      await user.delete();
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = (e.code == 'requires-recent-login')
          ? 'Please sign in again, then try deleting your account.'
          : (e.message ?? e.code);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('An error occurred: $e')));
    }
  }

  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: isDark ? Colors.white54 : Colors.black54,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // final scaffoldBg = theme.scaffoldBackgroundColor; // <-- No longer needed
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFFB7C7E3);

    final cardColor = const Color(0xFF0F2B52);
    const accentColor = Color(0xFFFF8A00); // orange accent

    if (_loading) {
      return const Scaffold(
          backgroundColor: Color(0xFF071A33),
          body: Center(
              child: CircularProgressIndicator(color: Color(0xFF5AC8FA))));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF071A33),
      appBar: null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, MediaQuery.of(context).padding.top + 8, 16, 120),
        children: [
          const SizedBox(height: 8),

          Column(
            children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: accentColor.withOpacity(0.2),
                child: Icon(Icons.admin_panel_settings_rounded,
                    size: 60, color: accentColor),
              ),
              const SizedBox(height: 10),
              Text(_displayName,
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: textColor)),
              if (_emailOrPhone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_emailOrPhone,
                    style: TextStyle(color: secondaryTextColor)),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  _pushSmooth(const MasterProfileScreen());
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text('Edit Profile',
                    style: TextStyle(fontWeight: FontWeight.w400)),
              ),
            ],
          ),

          _buildSectionHeader('Settings'),

          // --- 2. ADD THE "MY REWARDS" TILE ---
          _ProfileNavTile(
            icon: Icons.star_rounded,
            title: 'My Rewards',
            onTap: () {
              _pushSmooth(const RewardsScreen());
            },
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.child_care_rounded,
            title: 'Edit Child Profile',
            onTap: () {
              _pushSmooth(const OnboardingScreen());
            },
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.translate_rounded,
            title: 'Language',
            onTap: _goLanguage,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavSwitchTile(
            icon: Icons.notifications_active_rounded,
            title: 'New Story Notifications',
            value: _notifyNewStories,
            busy: _notifyBusy,
            onChanged: _setNewStoryNotifications,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _buildSectionHeader('About & Support'),

          if (_showDeviceTile)
            _ProfileInfoTile(
              icon: Icons.devices_other_rounded,
              title: 'Device',
              value: _deviceModel ?? _fallbackDeviceString(),
              cardColor: cardColor,
              textColor: textColor,
              accentColor: accentColor,
              secondaryTextColor: secondaryTextColor,
            ),

          _ProfileNavTile(
            icon: Icons.lock_person_rounded,
            title: 'Parental Controls',
            onTap: _goParentalControls,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.support_agent_rounded,
            title: 'Contact Us',
            onTap: _openContact,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.info_outline_rounded,
            title: 'About Us',
            onTap: _goAboutUs,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.ios_share_rounded,
            title: 'Share App',
            onTap: _shareApp,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.star_rate_rounded,
            title: 'Rate App',
            onTap: _goRateApp,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _buildSectionHeader('Legal'),

          _ProfileNavTile(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy Policy',
            onTap: _goPrivacyPolicy,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.gavel_rounded,
            title: 'Terms of Use',
            onTap: _goTerms,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _buildSectionHeader('Account Actions'),

          // Replace the existing _ProfileInfoTile for 'My Plan' with this:
          _ProfileInfoTile(
            icon: Icons.receipt_long_rounded,
            title: 'My Plan',
            value: _isLoadingSubscription
                ? 'Loading...'
                : _hasSubscription
                    ? _planPeriod.isEmpty
                        ? _currentPlan
                        : '$_currentPlan • $_planPeriod'
                    : 'Free',
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),
          _ProfileNavTile(
            icon: Icons.password_rounded,
            title: 'Change Password',
            onTap: () {
              _pushSmooth(const _ChangePasswordPage());
            },
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.devices_rounded,
            title: 'Manage Devices',
            onTap: () {
              _pushSmooth(const _ManageDevicesPage());
            },
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavTile(
            icon: Icons.delete_forever_rounded,
            title: 'Delete Account',
            onTap: _deleteAccount,
            trailing:
                const Icon(Icons.chevron_right_rounded, color: Colors.red),
            titleStyle: const TextStyle(
                color: Colors.red, fontWeight: FontWeight.w600, fontSize: 18),
            accentColor: Colors.red,
            cardColor: cardColor,
            textColor: textColor,
            secondaryTextColor: secondaryTextColor,
          ),

          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64.0),
            child: ElevatedButton(
              onPressed: () async {
                await AuthService().signOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 16,
                ),
              ),
              child: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Change Password (email/password users only)
// ---------------------------------------------------------------------------
class _ChangePasswordPage extends StatefulWidget {
  const _ChangePasswordPage();

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  final _auth = FirebaseAuth.instance;

  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _busy = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  Color get _bg => const Color(0xFF06142C); // vibrant dark blue
  Color get _card => const Color(0xFF0A1F44).withOpacity(0.55);
  Color get _orange => const Color(0xFFFF8A00);

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _isPasswordUser {
    final u = _auth.currentUser;
    if (u == null) return false;
    return u.providerData.any((p) => p.providerId == 'password');
  }

  Future<void> _sendResetEmail() async {
    final u = _auth.currentUser;
    final email = u?.email;
    if (email == null || email.trim().isEmpty) {
      _snack('No email found for this account.');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      _snack('Password reset email sent to $email');
    } catch (e) {
      _snack('Could not send reset email.');
    }
  }

  Future<void> _changePassword() async {
    if (_busy) return;
    final u = _auth.currentUser;
    final email = u?.email;

    if (u == null || email == null || email.isEmpty) {
      _snack('Unable to change password for this account.');
      return;
    }
    if (!_isPasswordUser) {
      _snack('This account does not use a password sign-in method.');
      return;
    }

    final current = _currentCtrl.text.trim();
    final newPass = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _snack('Please fill all fields.');
      return;
    }
    if (newPass.length < 6) {
      _snack('New password must be at least 6 characters.');
      return;
    }
    if (newPass != confirm) {
      _snack('New passwords do not match.');
      return;
    }
    if (newPass == current) {
      _snack('New password must be different.');
      return;
    }

    setState(() => _busy = true);
    try {
      // Re-authenticate
      final cred =
          EmailAuthProvider.credential(email: email.trim(), password: current);
      await u.reauthenticateWithCredential(cred);

      // Update password
      await u.updatePassword(newPass);

      _snack('Password updated successfully.');
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        _snack('Current password is incorrect.');
      } else if (e.code == 'requires-recent-login') {
        _snack('Please sign in again and retry.');
      } else {
        _snack('Could not update password.');
      }
    } catch (_) {
      _snack('Could not update password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  InputDecoration _dec(String label, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: _card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF173A6A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _orange, width: 1.4),
      ),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Change Password'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFF173A6A)),
            ),
            child: Text(
              _isPasswordUser
                  ? 'Update the password for $email'
                  : 'You are signed in using a provider that does not support password changes here. '
                      'If you have an email account, you can request a reset link.',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 16),
          if (_isPasswordUser) ...[
            TextField(
              controller: _currentCtrl,
              obscureText: !_showCurrent,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(
                'Current password',
                suffix: IconButton(
                  onPressed: () => setState(() => _showCurrent = !_showCurrent),
                  icon: Icon(
                    _showCurrent ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: !_showNew,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(
                'New password',
                suffix: IconButton(
                  onPressed: () => setState(() => _showNew = !_showNew),
                  icon: Icon(
                    _showNew ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: !_showConfirm,
              style: const TextStyle(color: Colors.white),
              decoration: _dec(
                'Confirm new password',
                suffix: IconButton(
                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                  icon: Icon(
                    _showConfirm ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _busy ? null : _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update Password'),
            ),
          ] else ...[
            const SizedBox(height: 6),
            ElevatedButton(
              onPressed: _busy ? null : _sendResetEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Send password reset email'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manage Devices (shows active devices, allows logging out a device)
// ---------------------------------------------------------------------------
class _ManageDevicesPage extends StatefulWidget {
  const _ManageDevicesPage();

  @override
  State<_ManageDevicesPage> createState() => _ManageDevicesPageState();
}

class _ManageDevicesPageState extends State<_ManageDevicesPage> {
  final _auth = FirebaseAuth.instance;

  String? _currentDeviceId;
  bool _loadingId = true;

  Color get _bg => const Color(0xFF06142C); // vibrant dark blue
  Color get _card => const Color(0xFF0A1F44).withOpacity(0.55);
  Color get _orange => const Color(0xFFFF8A00);

  @override
  void initState() {
    super.initState();
    _initDeviceId();
  }

  Future<void> _initDeviceId() async {
    try {
      final id = await DeviceIdService.getOrCreate();
      if (mounted) {
        setState(() {
          _currentDeviceId = id;
          _loadingId = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingId = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _devicesStream(String uid) {
    // Keep query simple (no extra indexes). Sort client-side if needed.
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices')
        .where('active', isEqualTo: true)
        .snapshots();
  }

  String _fmtTs(dynamic ts) {
    try {
      if (ts is Timestamp) {
        final d = ts.toDate();
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    return '';
  }

  Future<void> _logoutDevice({
    required String uid,
    required String deviceId,
    required bool isCurrent,
  }) async {
    try {
      await DeviceLimitService().deactivateDevice(uid: uid, deviceId: deviceId);

      if (isCurrent) {
        // This will trigger app auth listener to redirect to sign-in.
        await AuthService().signOut();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device logged out.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Manage Devices'),
        ),
        body: const Center(
          child:
              Text('Not signed in.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Manage Devices'),
      ),
      body: _loadingId
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _devicesStream(uid),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text('Could not load devices.',
                        style: TextStyle(color: Colors.white70)),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;

                // Sort by lastSeen desc, fallback createdAt desc.
                docs.sort((a, b) {
                  final ad = a.data();
                  final bd = b.data();
                  final aTs = ad['lastSeen'] ?? ad['createdAt'];
                  final bTs = bd['lastSeen'] ?? bd['createdAt'];
                  DateTime aD = DateTime.fromMillisecondsSinceEpoch(0);
                  DateTime bD = DateTime.fromMillisecondsSinceEpoch(0);
                  if (aTs is Timestamp) aD = aTs.toDate();
                  if (bTs is Timestamp) bD = bTs.toDate();
                  return bD.compareTo(aD);
                });

                // In normal operation this will be <= 2, but we still cap UI at 2.
                final visible = docs.take(2).toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Color(0xFF173A6A)),
                      ),
                      child: const Text(
                        'These are the currently logged-in devices. '
                        'You can log out a device anytime.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (visible.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Text('No active devices found.',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                    for (final d in visible) ...[
                      const SizedBox(height: 10),
                      _DeviceCard(
                        bg: _card,
                        orange: _orange,
                        deviceId: d.id,
                        isCurrent: d.id == _currentDeviceId,
                        deviceName:
                            (d.data()['deviceName'] ?? 'Device').toString(),
                        lastSeen: _fmtTs(d.data()['lastSeen']),
                        onLogout: () => _logoutDevice(
                          uid: uid,
                          deviceId: d.id,
                          isCurrent: d.id == _currentDeviceId,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Color bg;
  final Color orange;
  final String deviceId;
  final bool isCurrent;
  final String deviceName;
  final String lastSeen;
  final VoidCallback onLogout;

  const _DeviceCard({
    required this.bg,
    required this.orange,
    required this.deviceId,
    required this.isCurrent,
    required this.deviceName,
    required this.lastSeen,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF173A6A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_iphone_rounded,
              color: isCurrent ? orange : Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        deviceName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: orange.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: orange.withOpacity(0.6)),
                        ),
                        child: Text(
                          'This device',
                          style: TextStyle(
                            color: orange,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                if (lastSeen.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Last active: $lastSeen',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: onLogout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(isCurrent ? 'Logout here' : 'Logout'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---- Base tile ----
class _ProfileTileBase extends StatelessWidget {
  final Widget titleRow;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color cardColor;
  final Color secondaryTextColor;

  const _ProfileTileBase({
    required this.titleRow,
    required this.cardColor,
    required this.secondaryTextColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF173A6A).withOpacity(0.65)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Row(
                children: [
                  Expanded(child: titleRow),
                  const SizedBox(width: 10),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left circular icon like the Settings mock (filled circle + white icon)
class _TileIcon extends StatelessWidget {
  final IconData icon;
  final Color accentColor;

  const _TileIcon({
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? accentColor.withOpacity(0.22) : accentColor;
    final fg = isDark ? accentColor : Colors.white;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: 26),
    );
  }
}

/// ---- Nav tile ----
class _ProfileNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final Color? accentColor;
  final Color cardColor;
  final Color textColor;
  final Color secondaryTextColor;

  const _ProfileNavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.cardColor,
    required this.textColor,
    required this.secondaryTextColor,
    this.trailing,
    this.titleStyle,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final ac = accentColor ?? const Color(0xFF5AC8FA);

    return _ProfileTileBase(
      onTap: onTap,
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded,
              color: ac.withOpacity(0.85), size: 28),
      cardColor: cardColor,
      secondaryTextColor: secondaryTextColor,
      titleRow: Row(
        children: [
          _TileIcon(icon: icon, accentColor: ac),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle ??
                  TextStyle(
                    fontSize: 18,
                    color: textColor,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---- Info tile ----
class _ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;
  final Color secondaryTextColor;

  const _ProfileInfoTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileTileBase(
      cardColor: cardColor,
      secondaryTextColor: secondaryTextColor,
      titleRow: Row(
        children: [
          _TileIcon(icon: icon, accentColor: accentColor),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                color: textColor,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---- Switch tile ----
class _ProfileNavSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool busy;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;
  final Color? secondaryTextColor;

  const _ProfileNavSwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.busy = false,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
    this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfileTileBase(
      cardColor: cardColor,
      secondaryTextColor: (secondaryTextColor ?? textColor.withOpacity(0.7)),
      titleRow: Row(
        children: [
          _TileIcon(icon: icon, accentColor: accentColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    color: textColor,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: (secondaryTextColor ?? textColor.withOpacity(0.7)),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: busy ? null : onChanged,
        activeColor: Colors.white,
        activeTrackColor: accentColor,
      ),
    );
  }
}

// --- NEW THEME TILE (using SegmentedButton) ---
class _ProfileThemeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;
  final Color secondaryTextColor;

  const _ProfileThemeTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _ProfileTileBase(
      cardColor: cardColor,
      secondaryTextColor: secondaryTextColor,
      titleRow: Row(
        children: [
          _TileIcon(icon: icon, accentColor: accentColor),
          const SizedBox(width: 12),
          if (title.trim().isNotEmpty) ...[
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  color: textColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            )
          ] else ...[
            const Spacer(),
          ],
        ],
      ),
      trailing: SegmentedButton<AppThemeMode>(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          backgroundColor: isDark
              ? Colors.black.withOpacity(0.25)
              : Colors.white.withOpacity(0.55),
          selectedBackgroundColor: accentColor,
          selectedForegroundColor: isDark ? Colors.black : Colors.white,
          foregroundColor: secondaryTextColor,
        ),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: AppThemeMode.light,
            icon: Icon(Icons.light_mode_rounded, size: 16),
          ),
          ButtonSegment(
            value: AppThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded, size: 16),
          ),
          ButtonSegment(
            value: AppThemeMode.auto,
            icon: Icon(Icons.brightness_auto_rounded, size: 16),
          ),
        ],
        selected: {value},
        onSelectionChanged: (Set<AppThemeMode> newSelection) {
          onChanged(newSelection.first);
        },
      ),
    );
  }
}

/// ---- Contact page ----
class _ContactUsPage extends StatelessWidget {
  final String supportEmail;
  const _ContactUsPage({required this.supportEmail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Us')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('We’d love to hear from you!',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 12),
          Text('Email: $supportEmail', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: supportEmail));
              ScaffoldMessenger.of(context).showSnackBar(
                // <-- FIX WAS HERE
                const SnackBar(content: Text('Email copied')),
              );
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy email'),
          ),
        ]),
      ),
    );
  }
}

// --- NEW ABOUT US PAGE WIDGET ---
class _AboutUsPage extends StatelessWidget {
  const _AboutUsPage();

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link')),
      );
      return;
    }
    bool success = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!success) {
      success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF141B2A) : const Color(0xFFF5F8FF);
    final border = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);

    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );

    final accent = const Color(0xFF5AC8FA);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? accent.withOpacity(0.22) : accent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon,
                      color: isDark ? accent : Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(title, style: titleStyle)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? Colors.white.withOpacity(0.92) : const Color(0xFF0B1220);
    final secondary = isDark
        ? Colors.white.withOpacity(0.70)
        : Colors.black.withOpacity(0.70);

    return Scaffold(
      appBar: AppBar(title: const Text('About Us')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
        children: [
          Text(
            'About Appayi Stories',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Screen-free bedtime stories for peaceful sleep.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: secondary),
          ),
          const SizedBox(height: 18),
          _sectionCard(
            context,
            title: 'What it is',
            icon: Icons.nights_stay_rounded,
            child: Text(
              'Appayi Stories is an audio-first bedtime stories app designed for kids aged 3–8. '
              'It helps children relax, become better listeners, and build English vocabulary — without needing to watch the screen.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: textColor),
            ),
          ),
          _sectionCard(
            context,
            title: 'Parent-first safety',
            icon: Icons.lock_rounded,
            child: Text(
              '''• Profile/Settings are protected by a Parent PIN
• Chat uses predefined messages and requires Parent PIN
• Sharing stories (e.g., WhatsApp) requires Parent PIN
• Parents can set allowed usage times to support bedtime routines''',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: secondary, height: 1.35),
            ),
          ),
          _sectionCard(
            context,
            title: 'Offline listening',
            icon: Icons.download_rounded,
            child: Text(
              'Stories can be downloaded for offline playback inside the app only. '
              'Downloaded stories are shown with a badge and can be found in “Downloaded Stories”.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: secondary, height: 1.35),
            ),
          ),
          _sectionCard(
            context,
            title: 'Support',
            icon: Icons.support_agent_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email: support@appayistories.com',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: secondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Country: India',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: secondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          _open(context, 'https://appayistories.com'),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Visit Website'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _open(context, 'mailto:support@appayistories.com'),
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email Support'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Privacy Policy: https://appayistories.com/privacy\nTerms of Use: https://appayistories.com/terms',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }
}
