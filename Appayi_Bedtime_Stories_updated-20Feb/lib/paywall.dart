// lib/splash_screen.dart
import 'dart:io';
import 'package:audio_story_app/main.dart';
import 'package:audio_story_app/services/subscription.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class RevenueCatSplashScreen extends StatefulWidget {
  const RevenueCatSplashScreen({super.key});

  @override
  State<RevenueCatSplashScreen> createState() => _RevenueCatSplashScreenState();
}

class _RevenueCatSplashScreenState extends State<RevenueCatSplashScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _navigationInProgress = false;
  bool _paywallShown = false;

  // Your actual entitlement identifier from RevenueCat
  static const String _entitlementId = "premium";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    try {
      // First configure RevenueCat
      await _configureRevenueCat();

      // Check if user is logged in
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        debugPrint("👤 User is logged in: ${user.uid}");

        // 🔥 STEP 1: Check RevenueCat FIRST (source of truth)
        debugPrint("🔍 Checking RevenueCat for subscription...");
        final customerInfo = await Purchases.getCustomerInfo();
        final hasActivePro =
            customerInfo.entitlements.active.containsKey(_entitlementId);

        debugPrint("📱 RevenueCat subscription status: $hasActivePro");
        debugPrint(
            "   Active entitlements: ${customerInfo.entitlements.active.keys}");
        debugPrint(
            "   All entitlements: ${customerInfo.entitlements.all.keys}");

        // 🔥 STEP 2: ALWAYS update Firestore with RevenueCat's data
        debugPrint("💾 Updating Firestore with RevenueCat status...");
        await SubscriptionService().updateSubscriptionInFirestore(
          userId: user.uid,
          customerInfo: customerInfo,
        );

        if (!mounted) return;

        // 🔥 STEP 3: Make decision based on RevenueCat status
        if (hasActivePro) {
          debugPrint("✅ RevenueCat says user HAS active subscription");
          _navigateToAuthGate();
        } else {
          debugPrint("❌ RevenueCat says user has NO active subscription");
          await _verifyAndShowPaywall();
        }
      } else {
        // No user logged in, go to auth flow
        debugPrint("👤 No user logged in, going to AuthGate");
        if (mounted) _navigateToAuthGate();
      }
    } catch (e) {
      debugPrint("❌ RevenueCat initialization error: $e");
      setState(() {
        _errorMessage = "Unable to check subscription status";
      });

      // Still navigate after delay to not block user completely
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _navigateToAuthGate();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _configureRevenueCat() async {
    try {
      // Check if already configured
      try {
        await Purchases.getOfferings();
        debugPrint("✅ RevenueCat already configured");
        return;
      } catch (_) {
        // Not configured, continue
      }

      final configuration = Platform.isAndroid
          ? PurchasesConfiguration('goog_hDJJIjRdZpkNoEMOMsGsYukoQMW')
          : Platform.isIOS
              ? PurchasesConfiguration('your_ios_key_here')
              : throw UnsupportedError("Unsupported platform");

      await Purchases.setDebugLogsEnabled(!kReleaseMode);
      await Purchases.configure(configuration);

      debugPrint("✅ RevenueCat configured successfully");

      // Log in if user exists
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final logInResult = await Purchases.logIn(user.uid);
        debugPrint("✅ User logged in to RevenueCat");
        debugPrint(
            "   - Active entitlements: ${logInResult.customerInfo.entitlements.active.keys}");
      }
    } catch (e) {
      debugPrint("❌ Config error: $e");
      rethrow;
    }
  }

  Future<void> _verifyAndShowPaywall() async {
    if (_paywallShown) {
      debugPrint("⚠️ Paywall already shown, skipping");
      return;
    }

    try {
      // Get offerings
      final offerings = await Purchases.getOfferings();

      if (offerings.current == null) {
        debugPrint("⚠️ No current offering available");
        _navigateToAuthGate();
        return;
      }

      if (offerings.current!.availablePackages.isEmpty) {
        debugPrint("⚠️ Current offering has no packages");
        _navigateToAuthGate();
        return;
      }

      _paywallShown = true;

      if (!mounted) return;

      // Add a small delay to ensure UI is ready
      await Future.delayed(const Duration(milliseconds: 500));

      try {
        // Show paywall
        await RevenueCatUI.presentPaywallIfNeeded(
          _entitlementId,
          offering: offerings.current!,
          displayCloseButton: true,
        );

        debugPrint("✅ Paywall dismissed");

        // Wait a moment for RevenueCat to process
        await Future.delayed(const Duration(seconds: 2));

        // 🔥 Check RevenueCat again after paywall and update Firestore
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final updatedInfo = await Purchases.getCustomerInfo();
          final nowHasPro =
              updatedInfo.entitlements.active.containsKey(_entitlementId);

          // Update Firestore with new status
          await SubscriptionService().updateSubscriptionInFirestore(
            userId: user.uid,
            customerInfo: updatedInfo,
          );

          debugPrint("After paywall - has pro: $nowHasPro");
        }
      } catch (e) {
        debugPrint("❌ Error showing paywall: $e");
      } finally {
        if (mounted && !_navigationInProgress) {
          _navigateToAuthGate();
        }
      }
    } catch (e) {
      debugPrint("❌ Error in paywall verification: $e");
      if (mounted) {
        _navigateToAuthGate();
      }
    }
  }

  void _navigateToAuthGate() {
    if (_navigationInProgress || !mounted) return;

    _navigationInProgress = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthGate(),
        transitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOut);
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
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
              errorBuilder: (_, __, ___) => Container(
                color: Colors.purple.shade900,
                child: const Center(
                  child:
                      Icon(Icons.auto_stories, color: Colors.white, size: 80),
                ),
              ),
            ),
          ),
          if (_isLoading)
            const Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (_errorMessage != null)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
