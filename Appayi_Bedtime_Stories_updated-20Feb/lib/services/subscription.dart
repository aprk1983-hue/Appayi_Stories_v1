// import 'dart:async';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/foundation.dart';
// import 'package:purchases_flutter/purchases_flutter.dart';

// class SubscriptionService {
//   static final SubscriptionService _instance = SubscriptionService._internal();
//   factory SubscriptionService() => _instance;
//   SubscriptionService._internal();

//   static const String _entitlementId = "premium";
//   static const String _collection = 'subscriptions';

//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   final FirebaseAuth _auth = FirebaseAuth.instance;

//   StreamSubscription<User?>? _authSubscription;
//   bool _isInitialized = false;

//   // Stream for subscription status changes
//   final _subscriptionStatusController = StreamController<bool>.broadcast();
//   Stream<bool> get subscriptionStatus => _subscriptionStatusController.stream;

//   // Current subscription status cache
//   bool _hasActiveSubscription = false;
//   bool get hasActiveSubscription => _hasActiveSubscription;

//   Future<void> initialize() async {
//     if (_isInitialized) return;

//     try {
//       // Listen to auth changes
//       _authSubscription = _auth.authStateChanges().listen((User? user) async {
//         if (user != null) {
//           await _syncUserWithRevenueCat(user);
//         } else {
//           _updateSubscriptionStatus(false);
//         }
//       });

//       // Set up customer info update listener
//       Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);

//       _isInitialized = true;
//       debugPrint('✅ SubscriptionService initialized');
//     } catch (e) {
//       debugPrint('❌ SubscriptionService initialization error: $e');
//     }
//   }

//   void _updateSubscriptionStatus(bool hasActive) {
//     if (_hasActiveSubscription != hasActive) {
//       _hasActiveSubscription = hasActive;
//       _subscriptionStatusController.add(hasActive);
//     }
//   }

//   Future<void> _onCustomerInfoUpdate(CustomerInfo customerInfo) async {
//     final user = _auth.currentUser;
//     if (user != null) {
//       await updateSubscriptionInFirestore(
//         userId: user.uid,
//         customerInfo: customerInfo,
//       );
//     }
//   }

//   Future<void> _syncUserWithRevenueCat(User user) async {
//     try {
//       final logInResult = await Purchases.logIn(user.uid);

//       await updateSubscriptionInFirestore(
//         userId: user.uid,
//         customerInfo: logInResult.customerInfo,
//       );

//       debugPrint('✅ User synced with RevenueCat: ${user.uid}');
//     } catch (e) {
//       debugPrint('❌ Error syncing user with RevenueCat: $e');
//     }
//   }

//   Future<void> updateSubscriptionInFirestore({
//     required String userId,
//     required CustomerInfo customerInfo,
//   }) async {
//     try {
//       final entitlement = customerInfo.entitlements.all[_entitlementId];
//       final hasActivePro = entitlement?.isActive ?? false;

//       // Check if the user is in trial
//       final isTrial = entitlement != null &&
//           entitlement.latestPurchaseDate != null &&
//           entitlement.originalPurchaseDate != null &&
//           entitlement.latestPurchaseDate == entitlement.originalPurchaseDate &&
//           hasActivePro;

//       final subscriptionData = {
//         'userId': userId,
//         'hasActiveSubscription': hasActivePro,
//         'isTrial': isTrial,
//         'entitlementId': _entitlementId,
//         'isActive': hasActivePro,
//         'expirationDate': entitlement?.expirationDate,
//         'willRenew': entitlement?.willRenew ?? false,
//         'productIdentifier': entitlement?.productIdentifier,
//         'lastChecked': FieldValue.serverTimestamp(),
//         'originalPurchaseDate': entitlement?.latestPurchaseDate,
//       };

//       await _firestore
//           .collection(_collection)
//           .doc(userId)
//           .set(subscriptionData, SetOptions(merge: true));

//       // Update user doc
//       await _firestore.collection('users').doc(userId).update({
//         'subscription': {
//           'hasActive': hasActivePro,
//           'isTrial': isTrial,
//           'lastUpdated': FieldValue.serverTimestamp(),
//         }
//       });

//       _updateSubscriptionStatus(hasActivePro);

//       debugPrint(
//           '📱 Subscription status updated in Firestore: $hasActivePro, isTrial: $isTrial');
//     } catch (e) {
//       debugPrint('❌ Error updating Firestore subscription: $e');
//     }
//   }

//   Future<bool> checkSubscriptionStatus({bool forceRefresh = false}) async {
//     try {
//       final user = _auth.currentUser;
//       if (user == null) return false;

//       // Get from Firestore first (cached)
//       if (!forceRefresh) {
//         final doc =
//             await _firestore.collection(_collection).doc(user.uid).get();
//         if (doc.exists) {
//           final hasActive = doc.data()?['hasActiveSubscription'] ?? false;
//           _updateSubscriptionStatus(hasActive);
//           return hasActive;
//         }
//       }

//       // Force refresh from RevenueCat
//       final customerInfo = await Purchases.getCustomerInfo();
//       await updateSubscriptionInFirestore(
//         userId: user.uid,
//         customerInfo: customerInfo,
//       );

//       final hasActive =
//           customerInfo.entitlements.active.containsKey(_entitlementId);
//       _updateSubscriptionStatus(hasActive);
//       return hasActive;
//     } catch (e) {
//       debugPrint('❌ Error checking subscription: $e');
//       return false;
//     }
//   }

//   Future<void> restorePurchases() async {
//     try {
//       final customerInfo = await Purchases.restorePurchases();
//       final user = _auth.currentUser;

//       if (user != null) {
//         await updateSubscriptionInFirestore(
//           userId: user.uid,
//           customerInfo: customerInfo,
//         );
//       }

//       debugPrint('✅ Purchases restored successfully');
//     } catch (e) {
//       debugPrint('❌ Error restoring purchases: $e');
//       rethrow;
//     }
//   }

//   void dispose() {
//     _authSubscription?.cancel();
//     _subscriptionStatusController.close();
//   }
// }

// lib/services/subscription_service.dart (updated)
import 'dart:async';
import 'package:audio_story_app/services/trialService.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  static const String _entitlementId = "premium";
  static const String _collection = 'subscriptions';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TrialService _trialService = TrialService();

  StreamSubscription<User?>? _authSubscription;
  bool _isInitialized = false;

  // Stream for subscription status changes
  final _subscriptionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get subscriptionStatus => _subscriptionStatusController.stream;

  // Current subscription status cache
  bool _hasActiveSubscription = false;
  bool get hasActiveSubscription => _hasActiveSubscription;

  // Check if user has access (either paid OR in trial)
  Future<bool> hasAccess() async {
    final hasPaid = _hasActiveSubscription;
    final isInTrial = await _trialService.isTrialEligible;

    return hasPaid || isInTrial;
  }

  // Check if user should see paywall (trial expired AND no subscription)
  Future<bool> shouldShowPaywall() async {
    final hasPaid = _hasActiveSubscription;
    final isTrialExpired = await _trialService.isTrialExpired;

    return !hasPaid && isTrialExpired;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize trial service
      await _trialService.initialize();

      // Listen to auth changes
      _authSubscription = _auth.authStateChanges().listen((User? user) async {
        if (user != null) {
          await _syncUserWithRevenueCat(user);
        } else {
          _updateSubscriptionStatus(false);
        }
      });

      // Set up customer info update listener
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);

      _isInitialized = true;
      debugPrint('✅ SubscriptionService initialized');
      debugPrint(
          '🎯 Trial status: eligible=${_trialService.isTrialEligible}, expired=${_trialService.isTrialExpired}');
    } catch (e) {
      debugPrint('❌ SubscriptionService initialization error: $e');
    }
  }

  void _updateSubscriptionStatus(bool hasActive) {
    if (_hasActiveSubscription != hasActive) {
      _hasActiveSubscription = hasActive;
      _subscriptionStatusController.add(hasActive);
    }
  }

  Future<void> _onCustomerInfoUpdate(CustomerInfo customerInfo) async {
    final user = _auth.currentUser;
    if (user != null) {
      await updateSubscriptionInFirestore(
        userId: user.uid,
        customerInfo: customerInfo,
      );
    }
  }

  Future<void> _syncUserWithRevenueCat(User user) async {
    try {
      final logInResult = await Purchases.logIn(user.uid);

      await updateSubscriptionInFirestore(
        userId: user.uid,
        customerInfo: logInResult.customerInfo,
      );

      debugPrint('✅ User synced with RevenueCat: ${user.uid}');
    } catch (e) {
      debugPrint('❌ Error syncing user with RevenueCat: $e');
    }
  }
// lib/services/subscription_service.dart (updated)
// Add this method to sync trial with subscription status

  Future<void> updateSubscriptionInFirestore({
    required String userId,
    required CustomerInfo customerInfo,
  }) async {
    try {
      final entitlement = customerInfo.entitlements.all[_entitlementId];
      final hasActivePro = entitlement?.isActive ?? false;

      // Get trial status from Firestore (not local)
      final trialDoc =
          await _firestore.collection('user_trials').doc(userId).get();
      final isInTrial =
          trialDoc.exists && (trialDoc.data()?['isActive'] ?? false);
      final remainingTrialDays =
          isInTrial ? await _trialService.getRemainingTrialDays() : 0;

      // If user just subscribed, mark trial as inactive
      if (hasActivePro && isInTrial) {
        await _firestore.collection('user_trials').doc(userId).update({
          'isActive': false,
          'convertedToPaid': true,
          'convertedAt': FieldValue.serverTimestamp(),
        });
      }

      // ... rest of your existing code
    } catch (e) {
      debugPrint('❌ Error updating Firestore subscription: $e');
    }
  }
  // Future<void> updateSubscriptionInFirestore({
  //   required String userId,
  //   required CustomerInfo customerInfo,
  // }) async {
  //   try {
  //     final entitlement = customerInfo.entitlements.all[_entitlementId];
  //     final hasActivePro = entitlement?.isActive ?? false;

  //     // Get trial status
  //     final isInTrial = await _trialService.isTrialEligible;
  //     final remainingTrialDays = await _trialService.getRemainingTrialDays();

  //     // Check if the user is in RevenueCat trial
  //     final isRevenueCatTrial = entitlement != null &&
  //         entitlement.latestPurchaseDate != null &&
  //         entitlement.originalPurchaseDate != null &&
  //         entitlement.latestPurchaseDate == entitlement.originalPurchaseDate &&
  //         hasActivePro;

  //     final subscriptionData = {
  //       'userId': userId,
  //       'hasActiveSubscription': hasActivePro,
  //       'isInTrial': isInTrial,
  //       'remainingTrialDays': remainingTrialDays,
  //       'isRevenueCatTrial': isRevenueCatTrial,
  //       'entitlementId': _entitlementId,
  //       'isActive': hasActivePro,
  //       'expirationDate': entitlement?.expirationDate,
  //       'willRenew': entitlement?.willRenew ?? false,
  //       'productIdentifier': entitlement?.productIdentifier,
  //       'lastChecked': FieldValue.serverTimestamp(),
  //       'originalPurchaseDate': entitlement?.latestPurchaseDate,
  //     };

  //     await _firestore
  //         .collection(_collection)
  //         .doc(userId)
  //         .set(subscriptionData, SetOptions(merge: true));

  //     // Update user doc
  //     await _firestore.collection('users').doc(userId).update({
  //       'subscription': {
  //         'hasActive': hasActivePro,
  //         'isInTrial': isInTrial,
  //         'remainingTrialDays': remainingTrialDays,
  //         'lastUpdated': FieldValue.serverTimestamp(),
  //       }
  //     });

  //     _updateSubscriptionStatus(hasActivePro);

  //     debugPrint(
  //         '📱 Subscription status updated: hasActive=$hasActivePro, isInTrial=$isInTrial, remainingDays=$remainingTrialDays');
  //   } catch (e) {
  //     debugPrint('❌ Error updating Firestore subscription: $e');
  //   }
  // }

  Future<bool> checkSubscriptionStatus({bool forceRefresh = false}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Get from Firestore first (cached)
      if (!forceRefresh) {
        final doc =
            await _firestore.collection(_collection).doc(user.uid).get();
        if (doc.exists) {
          final hasActive = doc.data()?['hasActiveSubscription'] ?? false;
          _updateSubscriptionStatus(hasActive);
          return hasActive;
        }
      }

      // Force refresh from RevenueCat
      final customerInfo = await Purchases.getCustomerInfo();
      await updateSubscriptionInFirestore(
        userId: user.uid,
        customerInfo: customerInfo,
      );

      final hasActive =
          customerInfo.entitlements.active.containsKey(_entitlementId);
      _updateSubscriptionStatus(hasActive);
      return hasActive;
    } catch (e) {
      debugPrint('❌ Error checking subscription: $e');
      return false;
    }
  }

  Future<void> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      final user = _auth.currentUser;

      if (user != null) {
        await updateSubscriptionInFirestore(
          userId: user.uid,
          customerInfo: customerInfo,
        );
      }

      debugPrint('✅ Purchases restored successfully');
    } catch (e) {
      debugPrint('❌ Error restoring purchases: $e');
      rethrow;
    }
  }

  void dispose() {
    _authSubscription?.cancel();
    _subscriptionStatusController.close();
    _trialService.dispose();
  }
}
