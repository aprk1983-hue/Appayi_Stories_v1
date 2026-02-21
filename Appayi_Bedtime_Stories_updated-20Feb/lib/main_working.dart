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
            home: const _AppLifecycle(child: AuthGate()),
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
