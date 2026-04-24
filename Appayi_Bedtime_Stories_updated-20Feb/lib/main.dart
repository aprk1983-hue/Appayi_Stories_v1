import 'dart:io';
import 'package:audio_story_app/services/SubProvider.dart';
import 'package:audio_story_app/services/subscription.dart';
import 'package:audio_story_app/services/trialService.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/views/paywall_view.dart';
import 'firebase_options.dart';
import 'package:audio_story_app/screens/onboarding_carousel_screen.dart';
import 'package:audio_story_app/screens/onboarding_screen.dart';
import 'package:audio_story_app/screens/language_selection_screen.dart';
import 'package:audio_story_app/screens/main_tabs.dart';
import 'package:audio_story_app/utils/app_theme.dart';
import 'package:audio_story_app/theme_controller.dart';
import 'package:audio_story_app/widgets/background_container.dart';
import 'package:audio_story_app/services/app_audio_service.dart';
import 'package:audio_story_app/screens/story_player_screen.dart'
    show appRouteObserver;

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
    precacheImage(img, context);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await AppAudioService.init();
  await ThemeController.instance.init();

  // Initialize RevenueCat early
  await _configureRevenueCat();

  runApp(const MyApp());
}

Future<void> _configureRevenueCat() async {
  try {
    final configuration = Platform.isAndroid
        ? PurchasesConfiguration('goog_hDJJIjRdZpkNoEMOMsGsYukoQMW')
        : Platform.isIOS
            ? PurchasesConfiguration('appl_QDuWPPIbgWbMlVvyZpTxIQcMeRd')
            : throw UnsupportedError("Unsupported platform");

    await Purchases.setDebugLogsEnabled(!kReleaseMode);
    await Purchases.configure(configuration);
    debugPrint("✅ RevenueCat configured successfully");
  } catch (e) {
    debugPrint("❌ RevenueCat config error: $e");
  }
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
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
            ],
            child: MaterialApp(
              navigatorKey: _navKey,
              navigatorObservers: [appRouteObserver],
              title: 'Kiko Stories',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeController.instance.materialMode,
              builder: (context, child) {
                return AppBackground(
                  animated: true,
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const _AppLifecycle(
                child: IntroSplashScreen(), // Simple splash, no RevenueCat
              ),
            ),
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _warmUpNextScreens(context);
    });

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

class _AppLifecycleState extends State<_AppLifecycle>
    with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.detached) {
      try {
        await AppAudioService.handler.stop();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// lib/main.dart - Updated AuthGate
// lib/main.dart - Enhanced AuthGate

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TrialService _trialService = TrialService();
  bool _isCheckingAccess = true;
  bool _hasAccess = false;
  bool _shouldShowPaywall = false;
  int _remainingTrialDays = 0;

  @override
  void initState() {
    super.initState();
    _initializeAndCheckAccess();
  }

  Future<void> _initializeAndCheckAccess() async {
    try {
      // Ensure services are initialized
      await _subscriptionService.initialize();
      await _trialService.initialize();

      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Sync with RevenueCat
        await Purchases.logIn(user.uid);

        // Force refresh subscription status
        await _subscriptionService.checkSubscriptionStatus(forceRefresh: true);

        // Check access
        final hasAccess = await _subscriptionService.hasAccess();
        final shouldShowPaywall =
            await _subscriptionService.shouldShowPaywall();
        final remainingDays = await _trialService.getRemainingTrialDays();

        debugPrint('🔍 AuthGate - User: ${user.uid}');
        debugPrint('   Has Access: $hasAccess');
        debugPrint('   Should Show Paywall: $shouldShowPaywall');
        debugPrint('   Remaining Trial Days: $remainingDays');

        if (mounted) {
          setState(() {
            _hasAccess = hasAccess;
            _shouldShowPaywall = shouldShowPaywall;
            _remainingTrialDays = remainingDays;
            _isCheckingAccess = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isCheckingAccess = false);
        }
      }
    } catch (e) {
      debugPrint('❌ Error in _initializeAndCheckAccess: $e');
      if (mounted) {
        setState(() {
          _isCheckingAccess = false;
          _shouldShowPaywall = true; // Show paywall on error as fallback
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }

        final user = authSnap.data;

        // Not logged in - go to onboarding
        if (user == null) {
          return const OnboardingCarouselScreen();
        }

        // Logged in - ensure RevenueCat is synced
        return FutureBuilder<LogInResult>(
          future: Purchases.logIn(user.uid),
          builder: (context, loginSnap) {
            if (loginSnap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }

            // Now check Firestore profile
            final userRef =
                FirebaseFirestore.instance.collection('users').doc(user.uid);

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userRef.snapshots(),
              builder: (context, profSnap) {
                if (profSnap.connectionState == ConnectionState.waiting) {
                  return const _Loading();
                }

                // No profile or profile incomplete
                if (!profSnap.hasData || !(profSnap.data?.exists ?? false)) {
                  return const OnboardingScreen();
                }

                final data = profSnap.data!.data() ?? {};
                final isProfileComplete = data['isProfileComplete'] == true;

                if (!isProfileComplete) {
                  return const OnboardingScreen();
                }

                // Check languages
                final List<String> languages =
                    (data['selectedLanguages'] is List)
                        ? List<String>.from(data['selectedLanguages'] as List)
                        : [];

                if (languages.isEmpty) {
                  return const LanguageSelectionScreen();
                }

                // ALL prerequisites met - check access
                if (_isCheckingAccess) {
                  return const _Loading();
                }

                // Show paywall if trial expired and no subscription
                if (_shouldShowPaywall) {
                  debugPrint("🚫 Showing paywall - no access");
                  return PaywallView();
                }

                // Has access (either paid or in trial) - go to main app
                debugPrint("✅ User has access (paid or trial)");
                return MainTabs();
              },
            );
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
