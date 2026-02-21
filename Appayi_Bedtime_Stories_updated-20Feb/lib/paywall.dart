// // lib/splash_screen.dart
// import 'dart:io';
// import 'package:audio_story_app/main.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:purchases_flutter/purchases_flutter.dart';
// import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

// class RevenueCatSplashScreen extends StatefulWidget {
//   const RevenueCatSplashScreen({super.key});

//   @override
//   State<RevenueCatSplashScreen> createState() => _RevenueCatSplashScreenState();
// }

// class _RevenueCatSplashScreenState extends State<RevenueCatSplashScreen> {
//   bool _isLoading = true;
//   String? _errorMessage;
//   bool _navigationInProgress = false;
//   bool _paywallShown = false;

//   // Your actual entitlement identifier from RevenueCat
//   static const String _entitlementId = "premium";

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _initializeRevenueCat();
//     });
//     _completeDiagnostic();
//   }

//   Future<void> _completeDiagnostic() async {
//     debugPrint("\n🔍 ===== COMPLETE REVENUECAT DIAGNOSTIC =====\n");

//     try {
//       // 1. Check RevenueCat Configuration

//       // 2. Check App User ID

//       // 3. Check if user can make payments
//       final canMakePayments = await Purchases.canMakePayments();
//       debugPrint("3️⃣ Can make payments: $canMakePayments");

//       // 4. Check Products directly from Google Play
//       debugPrint("\n4️⃣ FETCHING PRODUCTS FROM GOOGLE PLAY:");
//       final products = await Purchases.getProducts(['yearly', 'monthly']);
//       if (products.isEmpty) {
//         debugPrint("   ❌ NO PRODUCTS FOUND!");
//         debugPrint("   This means Google Play is not returning any products.");
//         debugPrint("   Check: Are you logged into the correct Google account?");
//         debugPrint("   Check: Is your test account added as a License Tester?");
//       } else {
//         for (var p in products) {
//           debugPrint("   ✅ Product: ${p.identifier}");
//           debugPrint("      - Title: ${p.title}");
//           debugPrint("      - Price: ${p.priceString}");
//         }
//       }

//       // 5. Check Offerings from RevenueCat
//       debugPrint("\n5️⃣ FETCHING OFFERINGS FROM REVENUECAT:");
//       final offerings = await Purchases.getOfferings();
//       debugPrint("   All offerings: ${offerings.all.keys}");

//       if (offerings.current == null) {
//         debugPrint("   ❌ No current offering!");
//       } else {
//         debugPrint("   ✅ Current offering: ${offerings.current!.identifier}");
//         debugPrint(
//             "   Available packages: ${offerings.current!.availablePackages.length}");

//         for (var pkg in offerings.current!.availablePackages) {
//           debugPrint("   📦 Package: ${pkg.identifier}");
//           debugPrint("      - Product ID: ${pkg.storeProduct.identifier}");
//           debugPrint("      - Price: ${pkg.storeProduct.priceString}");
//           debugPrint("      - Offering: ${pkg.offeringIdentifier}");
//         }
//       }

//       // 6. Check Customer Info
//       debugPrint("\n6️⃣ CHECKING CUSTOMER INFO:");
//       final customerInfo = await Purchases.getCustomerInfo();
//       debugPrint("   Original App User ID: ${customerInfo.originalAppUserId}");
//       debugPrint("   First Seen: ${customerInfo.firstSeen}");
//       debugPrint(
//           "   Active Subscriptions: ${customerInfo.activeSubscriptions}");
//       debugPrint(
//           "   All Purchased Product IDs: ${customerInfo.allPurchasedProductIdentifiers}");
//       debugPrint(
//           "   Latest Expiration Date: ${customerInfo.latestExpirationDate}");

//       // 7. Check Entitlements specifically
//       debugPrint("\n7️⃣ ENTITLEMENTS:");
//       debugPrint("   All entitlements: ${customerInfo.entitlements.all.keys}");
//       debugPrint(
//           "   Active entitlements: ${customerInfo.entitlements.active.keys}");

//       final entitlementId = "Appayi Bedtime Stories Pro";
//       final hasEntitlement =
//           customerInfo.entitlements.all.containsKey(entitlementId);
//       debugPrint("   Does '$entitlementId' exist: $hasEntitlement");

//       if (hasEntitlement) {
//         final entitlement = customerInfo.entitlements.all[entitlementId];
//         debugPrint("   Entitlement details:");
//         debugPrint("      - Identifier: ${entitlement?.identifier}");
//         debugPrint("      - Is Active: ${entitlement?.isActive}");
//         debugPrint("      - Will Renew: ${entitlement?.willRenew}");
//         debugPrint("      - Expiration Date: ${entitlement?.expirationDate}");
//         debugPrint("      - Product ID: ${entitlement?.productIdentifier}");
//       }

//       // 8. Check Google Play Account
//       debugPrint("\n8️⃣ CHECKING GOOGLE PLAY ACCOUNT:");
//       debugPrint("   Make sure you're testing with a License Tester account!");
//       debugPrint(
//           "   Current account should be added to: Google Play Console > Settings > License Testing");

//       // 9. Check App Installation Source
//       debugPrint("\n9️⃣ APP INSTALLATION SOURCE:");
//       debugPrint(
//           "   App should be installed from Internal Test link, NOT from IDE!");
//       debugPrint(
//           "   Internal test link should start with: https://play.google.com/apps/internaltest/...");

//       // 10. Summary
//       debugPrint("\n🔟 DIAGNOSTIC SUMMARY:");
//       if (products.isEmpty) {
//         debugPrint("   ❌ CRITICAL: No products found from Google Play");
//         debugPrint("      This is why you're getting ITEM_UNAVAILABLE");
//         debugPrint(
//             "      Solution: Verify License Tester setup and wait 2-4 hours");
//       } else if (offerings.current == null) {
//         debugPrint("   ❌ CRITICAL: No offerings found from RevenueCat");
//         debugPrint("      Check RevenueCat dashboard > Offerings");
//       } else {
//         debugPrint("   ✅ Products and offerings look good!");
//         debugPrint("   Next step: Try a purchase and share the logs");
//       }
//     } catch (e, stack) {
//       debugPrint("❌ DIAGNOSTIC ERROR: $e");
//       debugPrint("Stack: $stack");
//     }

//     debugPrint("\n🔍 ===== END DIAGNOSTIC =====\n");
//   }

//   Future<void> _initializeRevenueCat() async {
//     try {
//       await _configureRevenueCat();

//       final customerInfo = await Purchases.getCustomerInfo();

//       // Check specifically for your entitlement
//       final hasActivePro =
//           customerInfo.entitlements.active.containsKey(_entitlementId);

//       debugPrint("🎯 Has active pro entitlement: $hasActivePro");
//       debugPrint(
//           "🎯 Active entitlements: ${customerInfo.entitlements.active.keys}");
//       debugPrint("🎯 All entitlements: ${customerInfo.entitlements.all.keys}");

//       if (!mounted) return;

//       if (!hasActivePro) {
//         await _verifyAndShowPaywall();
//       } else {
//         debugPrint("✅ User has pro access, navigating to app");
//         _navigateToAuthGate();
//       }
//     } catch (e) {
//       debugPrint("❌ RevenueCat initialization error: $e");
//       setState(() {
//         _errorMessage = "Unable to check subscription status";
//       });

//       Future.delayed(const Duration(seconds: 2), () {
//         if (mounted) _navigateToAuthGate();
//       });
//     }
//   }

//   Future<void> _configureRevenueCat() async {
//     try {
//       // Check if already configured
//       try {
//         await Purchases.getOfferings();
//         debugPrint("✅ RevenueCat already configured");
//         return;
//       } catch (_) {
//         // Not configured, continue
//       }

//       final configuration = Platform.isAndroid
//           ? PurchasesConfiguration('goog_hDJJIjRdZpkNoEMOMsGsYukoQMW')
//           : Platform.isIOS
//               ? PurchasesConfiguration('your_ios_key_here')
//               : throw UnsupportedError("Unsupported platform");

//       await Purchases.setDebugLogsEnabled(!kReleaseMode);
//       await Purchases.configure(configuration);

//       debugPrint("✅ RevenueCat configured successfully");

//       // Log in if user exists
//       final user = FirebaseAuth.instance.currentUser;
//       if (user != null) {
//         final logInResult = await Purchases.logIn(user.uid);
//         debugPrint("✅ User logged in to RevenueCat");
//         debugPrint(
//             "   - Active entitlements: ${logInResult.customerInfo.entitlements.active.keys}");
//       }
//     } catch (e) {
//       debugPrint("❌ Config error: $e");
//       rethrow;
//     }
//   }

//   Future<void> _verifyAndShowPaywall() async {
//     if (_paywallShown) {
//       debugPrint("⚠️ Paywall already shown, skipping");
//       return;
//     }

//     try {
//       // First, directly fetch products to verify they're available
//       final storeProducts = await Purchases.getProducts(
//         <String>{'yearly', 'monthly'}.toList(),
//       );

//       debugPrint("📦 Products fetched from Play Store:");
//       for (var product in storeProducts) {
//         debugPrint("  - ${product.identifier}: ${product.priceString}");
//       }

//       if (storeProducts.isEmpty) {
//         debugPrint("⚠️ No products found!");
//         setState(() {
//           _errorMessage = "Products not available yet";
//         });
//         Future.delayed(const Duration(seconds: 2), () {
//           if (mounted) _navigateToAuthGate();
//         });
//         return;
//       }

//       // Get offerings
//       final offerings = await Purchases.getOfferings();

//       if (offerings.current == null) {
//         debugPrint("⚠️ No current offering available");
//         _navigateToAuthGate();
//         return;
//       }

//       debugPrint("📦 Current offering: ${offerings.current!.identifier}");
//       debugPrint(
//           "📦 Packages available: ${offerings.current!.availablePackages.length}");

//       for (var pkg in offerings.current!.availablePackages) {
//         debugPrint("  - Package: ${pkg.identifier}");
//         debugPrint("    Product ID: ${pkg.storeProduct.identifier}");
//         debugPrint("    Price: ${pkg.storeProduct.priceString}");
//       }

//       if (offerings.current!.availablePackages.isEmpty) {
//         debugPrint("⚠️ Current offering has no packages");
//         _navigateToAuthGate();
//         return;
//       }

//       _paywallShown = true;

//       if (!mounted) return;

//       // Add a small delay to ensure UI is ready
//       await Future.delayed(const Duration(milliseconds: 500));

//       try {
//         // Use the paywall with your entitlement ID
//         await RevenueCatUI.presentPaywallIfNeeded(
//           _entitlementId, // Now using your actual entitlement ID
//           offering: offerings.current!,
//           displayCloseButton: true,
//         );

//         debugPrint("✅ Paywall dismissed");

//         // Check if user purchased after paywall
//         await Future.delayed(const Duration(seconds: 1));
//         final updatedInfo = await Purchases.getCustomerInfo();
//         final nowHasPro =
//             updatedInfo.entitlements.active.containsKey(_entitlementId);
//         debugPrint("After paywall - has pro: $nowHasPro");
//       } catch (e) {
//         debugPrint("❌ Error showing paywall: $e");

//         if (e.toString().contains("ITEM_UNAVAILABLE")) {
//           debugPrint("⚠️ Products not properly configured or not synced");
//           setState(() {
//             _errorMessage =
//                 "Subscription setup in progress. Please try again later.";
//           });
//           await Future.delayed(const Duration(seconds: 2));
//         }
//       } finally {
//         if (mounted && !_navigationInProgress) {
//           _navigateToAuthGate();
//         }
//       }
//     } catch (e) {
//       debugPrint("❌ Error in paywall verification: $e");
//       if (mounted) {
//         _navigateToAuthGate();
//       }
//     }
//   }

//   // Debug function to verify setup
//   Future<void> _debugRevenueCatSetup() async {
//     try {
//       debugPrint("🔍 Starting RevenueCat debug...");

//       // 1. Check offerings
//       debugPrint("1️⃣ Checking offerings...");
//       final offerings = await Purchases.getOfferings();
//       debugPrint("   ✅ Offerings: ${offerings.all.keys}");

//       if (offerings.current != null) {
//         debugPrint("   ✅ Current offering: ${offerings.current!.identifier}");
//         for (var pkg in offerings.current!.availablePackages) {
//           debugPrint("      📦 Package: ${pkg.identifier}");
//           debugPrint("         Product: ${pkg.storeProduct.identifier}");
//           debugPrint("         Price: ${pkg.storeProduct.priceString}");
//         }
//       }

//       // 2. Check entitlements
//       debugPrint("2️⃣ Checking entitlements...");
//       final customerInfo = await Purchases.getCustomerInfo();
//       debugPrint(
//           "   ✅ All entitlements: ${customerInfo.entitlements.all.keys}");
//       debugPrint(
//           "   ✅ Active entitlements: ${customerInfo.entitlements.active.keys}");

//       // Check specifically for your entitlement
//       final hasPro = customerInfo.entitlements.all.containsKey(_entitlementId);
//       debugPrint("   ✅ Pro entitlement exists in system: $hasPro");
//     } catch (e) {
//       debugPrint("❌ Debug error: $e");
//     }
//   }

//   void _navigateToAuthGate() {
//     if (_navigationInProgress || !mounted) return;

//     _navigationInProgress = true;

//     Navigator.of(context).pushReplacement(
//       PageRouteBuilder(
//         pageBuilder: (_, __, ___) => const AuthGate(),
//         transitionDuration: const Duration(milliseconds: 220),
//         transitionsBuilder: (_, animation, __, child) {
//           final curved =
//               CurvedAnimation(parent: animation, curve: Curves.easeOut);
//           return FadeTransition(opacity: curved, child: child);
//         },
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       body: Stack(
//         children: [
//           Positioned.fill(
//             child: Image.asset(
//               'assets/splash/intro.png',
//               fit: BoxFit.cover,
//               errorBuilder: (_, __, ___) => Container(
//                 color: Colors.purple.shade900,
//                 child: const Center(
//                   child:
//                       Icon(Icons.auto_stories, color: Colors.white, size: 80),
//                 ),
//               ),
//             ),
//           ),
//           if (_isLoading)
//             const Positioned(
//               bottom: 100,
//               left: 0,
//               right: 0,
//               child: Center(
//                 child: CircularProgressIndicator(color: Colors.white),
//               ),
//             )
//           else if (_errorMessage != null)
//             Positioned(
//               bottom: 100,
//               left: 0,
//               right: 0,
//               child: Center(
//                 child: Container(
//                   padding: const EdgeInsets.all(16),
//                   margin: const EdgeInsets.symmetric(horizontal: 32),
//                   decoration: BoxDecoration(
//                     color: Colors.black54,
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Text(
//                     _errorMessage!,
//                     textAlign: TextAlign.center,
//                     style: const TextStyle(color: Colors.white70),
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }

// lib/splash_screen.dart
import 'dart:io';
import 'package:audio_story_app/main.dart';
import 'package:audio_story_app/services/app_audio_service.dart';
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
