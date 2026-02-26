// lib/screens/onboarding_carousel_screen.dart

import 'package:audio_story_app/services/app_audio_service.dart';
import 'package:flutter/material.dart';
import 'package:audio_story_app/widgets/background_container.dart';
import 'package:audio_story_app/utils/app_theme.dart';
import 'package:audio_story_app/screens/login_screen.dart' as auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smooth fade route to avoid flashing default route backgrounds while heavy
/// widgets (like big images) are decoding.
PageRouteBuilder<T> _fadeRoute<T>(
  Widget page, {
  Duration duration = const Duration(milliseconds: 220),
}) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class OnboardingCarouselScreen extends StatefulWidget {
  const OnboardingCarouselScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingCarouselScreen> createState() =>
      _OnboardingCarouselScreenState();
}

class _OnboardingCarouselScreenState extends State<OnboardingCarouselScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _imagesPrecached = false; // Flag to prevent repeated precaching
  bool _notificationPopupChecked = false;

  // By the way, this color 0xFFFF6700 is a vibrant orange, not blue!
  // You might want to rename it to _vibrantOrange for clarity :)
  static const _vibrantBlue = Color(0xFFFF6700);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ✨ FIX IS HERE: Precache images to prevent flicker on swipe
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imagesPrecached) {
      precacheImage(
          const AssetImage('assets/backgrounds/onboarding_1.jpg'), context);

      // ✨ FIX: Changed '.jpg' to '.png' to match the PageView
      precacheImage(
          const AssetImage('assets/backgrounds/onboarding_2.png'), context);

      // ✨ FIX: Changed '.jpg' to '.png' to match the PageView
      precacheImage(
          const AssetImage('assets/backgrounds/onboarding_3.png'), context);

      _imagesPrecached = true;
    }
  }

  // ... (Rest of your file is unchanged) ...

  /// Show a notification enablement popup *before* navigating to Login.
  ///
  /// Aligns with Profile screen behavior:
  /// - SharedPreferences key: `notify_new_stories`
  /// - Default: ON (true)
  /// - User can disable later in Profile
  Future<void> _maybePromptForNotifications() async {
    if (_notificationPopupChecked) return;
    _notificationPopupChecked = true;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('notify_new_stories');
    final notifyEnabled = saved ?? true;
    if (saved == null) {
      // Persist the default ON state to match Profile screen.
      await prefs.setBool('notify_new_stories', true);
    }

    // If user has turned it OFF in Profile (or previously tapped "Not now"),
    // never prompt again here.
    if (!notifyEnabled) return;

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final status = settings.authorizationStatus;

    // If already allowed (including provisional on iOS), no need to prompt.
    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      // Ensure topic subscription matches toggle.
      await FirebaseMessaging.instance.subscribeToTopic('new_stories');
      return;
    }

    if (!mounted) return;

    // Only show the *system* notification permission prompt (no custom dialog).
    final req = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final granted = req.authorizationStatus == AuthorizationStatus.authorized ||
        req.authorizationStatus == AuthorizationStatus.provisional;

    if (granted) {
      await prefs.setBool('notify_new_stories', true);
      await FirebaseMessaging.instance.subscribeToTopic('new_stories');
    } else {
      // If user denies, align with Profile by turning the toggle OFF.
      await prefs.setBool('notify_new_stories', false);
      await FirebaseMessaging.instance.unsubscribeFromTopic('new_stories');
    }
  }

  Future<void> _goLogin() async {
    // Show notification popup BEFORE going to login screen.
    await _maybePromptForNotifications();

    // Warm up login assets so the next screen paints immediately (no gray flash).
    await Future.wait<void>([
      precacheImage(const AssetImage('assets/backgrounds/signin.png'), context),
      precacheImage(
          const AssetImage('assets/backgrounds/login_bg_purple.png'), context),
      precacheImage(const AssetImage('assets/google_logo.png'), context),
    ]);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      _fadeRoute(const auth.LoginScreen()),
    );
  }

  Widget _skipButton() {
    return SizedBox(
      width: 140,
      child: ElevatedButton(
        onPressed: _goLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black.withOpacity(0.85),
          foregroundColor: Colors.orangeAccent, // ✨ NEW: Sets text color
          elevation: 6,
          shadowColor: Colors.black45,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          'Skip',
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            // color: _vibrantBlue, // ✨ REMOVED: No longer needed here
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _dots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          height: 8,
          width: active ? 22 : 8,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withOpacity(0.35),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    const slideCount = 3;

    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: [
          // ---------------- Slide 1: Welcome ----------------
          BackgroundContainer(
            imagePath: 'assets/backgrounds/onboarding_1.jpg',
            dimOpacity: 0.28,
            child: SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 72, 22, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'WELCOME TO',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'APPAYI \nBedTime Stories',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Bedtime made magical,\nevery night.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 18,
                                height: 1.35,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dots(slideCount),
                          const SizedBox(height: 14),
                          _skipButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // -------- Slide 2 --------
          BackgroundContainer(
            imagePath: 'assets/backgrounds/onboarding_2.png', // <-- Uses .png
            dimOpacity: 0.28,
            child: SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 72, 22, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ADVENTURE, FAIRY TALES,\nBEDTIME & MORE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'A treasure chest of\nadventures and fairytales\.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 18,
                                height: 1.35,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dots(slideCount),
                          const SizedBox(height: 14),
                          _skipButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------------- Slide 3 ----------------
          BackgroundContainer(
            imagePath: 'assets/backgrounds/onboarding_3.png', // <-- Uses .png
            dimOpacity: 0.28,
            child: SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 72, 22, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Listen',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 46,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              'to Amazing',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.02,
                              ),
                            ),
                            Text(
                              'short Stories',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.02,
                              ),
                            ),
                            Text(
                              'tailored for',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.02,
                              ),
                            ),
                            Text(
                              'Kids!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTheme.headingFont,
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.02,
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dots(slideCount),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _goLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black.withOpacity(0.85),
                                foregroundColor: Colors.orangeAccent,
                                elevation: 6,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                textStyle: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              child: const Text('Create Account'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _goLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black.withOpacity(0.85),
                                foregroundColor: Colors.orangeAccent,
                                elevation: 6,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                textStyle: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              child: const Text('Sign In'),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _index < slideCount - 1
          ? FloatingActionButton(
              onPressed: () => _controller.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              ),
              backgroundColor: Colors.black.withOpacity(0.85),
              child: const Icon(Icons.chevron_right, color: Colors.white),
            )
          : null,
    );
  }
}
