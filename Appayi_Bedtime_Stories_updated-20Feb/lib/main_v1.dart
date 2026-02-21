// lib/main.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';


// Flow screens
import 'package:audio_story_app/screens/onboarding_carousel_screen.dart';
import 'package:audio_story_app/screens/onboarding_screen.dart';
import 'package:audio_story_app/screens/language_selection_screen.dart';

// Tabs (bottom navigation with Home/Search/Category/PlayLists/Profile)
import 'package:audio_story_app/screens/main_tabs.dart';

// Theme
import 'package:audio_story_app/utils/app_theme.dart';
import 'package:audio_story_app/theme_controller.dart';
import 'package:audio_story_app/services/app_audio_service.dart';

// Route observer (used by StoryPlayerScreen to hide/show mini player correctly)
import 'package:audio_story_app/screens/story_player_screen.dart' show appRouteObserver;

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


void _warmUpNextScreens(BuildContext context) {
  const images = <ImageProvider>[
    AssetImage('assets/backgrounds/onboarding_1.jpg'),
    AssetImage('assets/backgrounds/onboarding_2.png'),
    AssetImage('assets/backgrounds/onboarding_3.png'),
    AssetImage('assets/backgrounds/signin.png'),
    AssetImage('assets/backgrounds/login_bg_purple.png'),
    AssetImage('assets/google_logo.png'),
  ];

  for (final img in images) {
    // Fire-and-forget: we only want to warm the cache.
    precacheImage(img, context);
  }
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Init background audio/notification controls.
  await AppAudioService.init();

  await ThemeController.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<bool>? _notifClickSub;

  @override
  void initState() {
    super.initState();
// When the user taps the media notification, go to HOME (root) and keep playing.
    _notifClickSub = AudioService.notificationClicked.listen((clicked) {
      if (!clicked) return;
      _navKey.currentState?.popUntil((r) => r.isFirst);
    });
  }

  @override
  void dispose() {
    _notifClickSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return Container(
          color: Colors.black,
          child: MaterialApp(
            navigatorKey: _navKey,
            navigatorObservers: [appRouteObserver],
            title: 'Kiko Stories',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeController.instance.materialMode,
            home: const _AppLifecycle(child: IntroSplashScreen()),
          ),
        );
      },
    );
  }
}

class _AppLifecycle extends StatefulWidget {
  final Widget child;
  const _AppLifecycle({required this.child});

  @override
  State<_AppLifecycle> createState() => _AppLifecycleState();
}


class IntroSplashScreen extends StatefulWidget {
  const IntroSplashScreen({super.key});

  @override
  State<IntroSplashScreen> createState() => _IntroSplashScreenState();
}

class _IntroSplashScreenState extends State<IntroSplashScreen> {
  static const Duration _minShowTime = Duration(milliseconds: 1500);
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    
    // Pre-decode the next screens' big assets so the first frame doesn't flash gray.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _warmUpNextScreens(context);
    });

// Show the full-screen intro image briefly, then continue to AuthGate.
    _timer = Timer(_minShowTime, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(_fadeRoute(const AuthGate()));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 👉 Put your 9:16 splash/intro image in: assets/splash/intro.png
    // and ensure it's added under flutter assets in pubspec.yaml.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/splash/intro.png',
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                // Fallback (if asset missing) so the app still runs.
                return Container(
                  color: Theme.of(context).colorScheme.surface,
                  alignment: Alignment.center,
                  child: const Icon(Icons.auto_stories, size: 64),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppLifecycleState extends State<_AppLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // When the app is fully closed (detached), stop playback and clear the notification.
    if (state == AppLifecycleState.detached) {
      try {
        await AppAudioService.handler.stop();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }

        final user = authSnap.data;
        if (user == null) {
          return const OnboardingCarouselScreen();
        }

        final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userRef.snapshots(),
          builder: (context, profSnap) {
            if (profSnap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }

            if (!profSnap.hasData || !(profSnap.data?.exists ?? false)) {
              return const OnboardingScreen();
            }

            final data = profSnap.data!.data() ?? {};
            final isProfileComplete = data['isProfileComplete'] == true;

            // Check for 'selectedLanguages' list
            final List<String> languages = (data['selectedLanguages'] is List)
                ? List<String>.from(data['selectedLanguages'] as List)
                : [];

            if (!isProfileComplete) {
              return const OnboardingScreen();
            }

            if (languages.isEmpty) {
              return const LanguageSelectionScreen();
            }

            return const MainTabs();
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}