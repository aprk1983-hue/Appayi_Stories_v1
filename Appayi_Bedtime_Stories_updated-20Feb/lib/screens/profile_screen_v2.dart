import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:audio_story_app/services/auth_service.dart';
import 'package:audio_story_app/screens/onboarding_screen.dart';
import 'package:audio_story_app/screens/language_selection_screen.dart';
import 'package:audio_story_app/screens/onboarding_carousel_screen.dart';
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
  bool _notifyNewStories = false;
  bool _notifyBusy = false;

  String _displayName = 'Parent';
  String _emailOrPhone = '';

  String? _deviceModel;

  final bool _showDeviceTile = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadUser(), _loadDeviceModel(), _loadNotifyPref()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadNotifyPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('notify_new_stories') ?? false;
      if (!mounted) return;
      setState(() => _notifyNewStories = v);
    } catch (_) {
      // ignore - keep default false
    }
  }

  Future<void> _setNewStoryNotifications(bool enable) async {
    if (_notifyBusy) return;
    setState(() => _notifyBusy = true);

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
      // If something failed, revert the UI to a safe state
      if (mounted) setState(() => _notifyNewStories = !enable);
    } finally {
      if (mounted) setState(() => _notifyBusy = false);
    }
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
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LanguageSelectionScreen()));
  }

  void _goParentalControls() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ParentalControlsScreen()));
  }

  void _goAboutUs() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const _AboutUsPage()));
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.parse(urlString);
    if (!await canLaunchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $urlString')),
      );
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _goPrivacyPolicy() {
    _launchURL('https://your-website.com/privacy'); // <-- TODO: REPLACE URL
  }

  void _goTerms() {
    _launchURL('https://your-website.com/terms'); // <-- TODO: REPLACE URL
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
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          const _ContactUsPage(supportEmail: 'support@lalastories.app'),
    ));
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
    final textColor = theme.textTheme.bodyLarge?.color ??
        (isDark ? Colors.white : Colors.black);
    final secondaryTextColor = theme.textTheme.bodyMedium?.color ??
        (isDark ? Colors.white70 : Colors.black54);

    final cardColor =
        isDark ? (Colors.grey[900] ?? Colors.black) : Colors.white;
    const accentColor = Colors.orange;

    if (_loading) {
      return const Scaffold(
          // backgroundColor: scaffoldBg, // <-- REMOVED
          body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    }

    return Scaffold(
      // backgroundColor: scaffoldBg, // <-- REMOVED
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
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MasterProfileScreen()));
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
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),

          _buildSectionHeader('Settings'),

          // --- 2. ADD THE "MY REWARDS" TILE ---
          _ProfileNavTile(
            icon: Icons.star_rounded,
            title: 'My Rewards',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RewardsScreen()),
              );
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            },
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _ProfileNavSwitchTile(
            icon: Icons.play_circle_filled_rounded,
            title: 'Auto-play',
            value: _autoPlay,
            onChanged: _setAutoPlay,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
          ),

          _ProfileNavSwitchTile(
            icon: Icons.notifications_active_rounded,
            title: 'New Story Notifications',
            value: _notifyNewStories,
            onChanged: (v) async {
              await _setNewStoryNotifications(v);
            },
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
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

          _ProfileThemeTile(
            icon: Icons.brightness_6_rounded,
            title: 'Theme',
            value: ThemeController.instance.mode,
            onChanged: (m) => ThemeController.instance.setMode(m),
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
            title: 'Terms & Conditions',
            onTap: _goTerms,
            cardColor: cardColor,
            textColor: textColor,
            accentColor: accentColor,
            secondaryTextColor: secondaryTextColor,
          ),

          _buildSectionHeader('Account Actions'),

          _ProfileInfoTile(
            icon: Icons.receipt_long_rounded,
            title: 'My Plan',
            value: 'Coming soon',
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
                  fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Expanded(child: titleRow),
              const SizedBox(width: 8),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
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
    return _ProfileTileBase(
      onTap: onTap,
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded, color: secondaryTextColor),
      cardColor: cardColor,
      secondaryTextColor: secondaryTextColor,
      titleRow: Row(
        children: [
          Icon(icon, color: accentColor ?? Colors.orange, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: titleStyle ??
                  TextStyle(
                      fontSize: 18,
                      color: textColor,
                      fontWeight: FontWeight.w600),
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
          Icon(icon, color: accentColor, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                  fontSize: 18, color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(color: secondaryTextColor, fontSize: 16)),
        ],
      ),
      // No trailing widget
    );
  }
}

/// ---- Switch tile ----
class _ProfileNavSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;

  const _ProfileNavSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // <-- FIX WAS HERE
    return _ProfileTileBase(
      cardColor: cardColor,
      secondaryTextColor: textColor.withOpacity(0.7),
      titleRow: Row(
        children: [
          Icon(icon, color: accentColor, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                  fontSize: 18, color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: accentColor,
      ),
    );
  }
}

// --- NEW THEME TILE (using SegmentedButton) ---
class _ProfileThemeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final AppThemeMode value; // Use the enum
  final ValueChanged<AppThemeMode> onChanged;
  // Added color params
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
          Icon(icon, color: accentColor, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                  fontSize: 18, color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      trailing: SegmentedButton<AppThemeMode>(
        style: SegmentedButton.styleFrom(
          backgroundColor: isDark
              ? Colors.black.withOpacity(0.3)
              : Colors.black.withOpacity(0.05),
          selectedBackgroundColor: accentColor,
          selectedForegroundColor: isDark ? Colors.black : Colors.white,
          foregroundColor: secondaryTextColor,
        ),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: AppThemeMode.light,
            icon: Icon(Icons.light_mode_rounded, size: 18),
          ),
          ButtonSegment(
            value: AppThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded, size: 18),
          ),
          ButtonSegment(
            value: AppThemeMode.auto,
            icon: Icon(Icons.brightness_auto_rounded, size: 18),
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

  @override
  Widget build(BuildContext context) {
    // <-- FIX WAS HERE
    return Scaffold(
      appBar: AppBar(title: const Text('About Us')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Welcome to Little Kiko!',
            style: Theme.of(context).textTheme.headlineSmall, // <-- Fixed
          ),
          const SizedBox(height: 16),
          Text(
            'Your magical library of bedtime stories, adventures, and fairy tales, all designed to make listening an adventure.',
            style: Theme.of(context).textTheme.bodyLarge, // <-- Fixed
          ),
          const SizedBox(height: 24),
          Text(
            'Version 1.0.0 (Build 1)', // <-- TODO: Update this
            style: Theme.of(context).textTheme.bodyMedium, // <-- Fixed
          ),
        ],
      ),
    );
  }
}
