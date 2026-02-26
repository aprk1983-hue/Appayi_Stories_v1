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

//   Future<void> initialize() async {
//     if (_isInitialized) return;

//     try {
//       // Listen to auth changes
//       _authSubscription = _auth.authStateChanges().listen((User? user) async {
//         if (user != null) {
//           await _syncUserWithRevenueCat(user);
//         } else {
//           _subscriptionStatusController.add(false);
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

//   Future<void> updateSubscriptionInFirestore({
//     required String userId,
//     required CustomerInfo customerInfo,
//   }) async {
//     await _updateSubscriptionInFirestore(
//       userId: userId,
//       customerInfo: customerInfo,
//     );
//   }

//   // This will be called whenever customer info updates
//   Future<void> _onCustomerInfoUpdate(CustomerInfo customerInfo) async {
//     final user = _auth.currentUser;
//     if (user != null) {
//       await _updateSubscriptionInFirestore(
//         userId: user.uid,
//         customerInfo: customerInfo,
//       );
//     }
//   }

//   Future<void> _syncUserWithRevenueCat(User user) async {
//     try {
//       final logInResult = await Purchases.logIn(user.uid);

//       // Update Firestore with subscription status
//       await _updateSubscriptionInFirestore(
//         userId: user.uid,
//         customerInfo: logInResult.customerInfo,
//       );

//       debugPrint('✅ User synced with RevenueCat: ${user.uid}');
//     } catch (e) {
//       debugPrint('❌ Error syncing user with RevenueCat: $e');
//     }
//   }

//   Future<void> _updateSubscriptionInFirestore({
//     required String userId,
//     required CustomerInfo customerInfo,
//   }) async {
//     try {
//       final hasActivePro =
//           customerInfo.entitlements.active.containsKey(_entitlementId);
//       final entitlement = customerInfo.entitlements.all[_entitlementId];

//       final subscriptionData = {
//         'userId': userId,
//         'hasActiveSubscription': hasActivePro,
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

//       // Add to user document as well for easy access
//       await _firestore.collection('users').doc(userId).update({
//         'subscription': {
//           'hasActive': hasActivePro,
//           'lastUpdated': FieldValue.serverTimestamp(),
//         }
//       });

//       _subscriptionStatusController.add(hasActivePro);

//       debugPrint('📱 Subscription status updated in Firestore: $hasActivePro');
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
//           return hasActive;
//         }
//       }

//       // Force refresh from RevenueCat
//       final customerInfo = await Purchases.getCustomerInfo();
//       await _updateSubscriptionInFirestore(
//         userId: user.uid,
//         customerInfo: customerInfo,
//       );

//       final hasActive =
//           customerInfo.entitlements.active.containsKey(_entitlementId);
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
//         await _updateSubscriptionInFirestore(
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
//     // Note: We don't remove the customer info listener as it's a static function
//   }
// }
// lib/services/subscription_service.dart
import 'dart:async';
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

  StreamSubscription<User?>? _authSubscription;
  bool _isInitialized = false;

  // Stream for subscription status changes
  final _subscriptionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get subscriptionStatus => _subscriptionStatusController.stream;

  // Current subscription status cache
  bool _hasActiveSubscription = false;
  bool get hasActiveSubscription => _hasActiveSubscription;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
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

  Future<void> updateSubscriptionInFirestore({
    required String userId,
    required CustomerInfo customerInfo,
  }) async {
    try {
      final hasActivePro =
          customerInfo.entitlements.active.containsKey(_entitlementId);
      final entitlement = customerInfo.entitlements.all[_entitlementId];

      final subscriptionData = {
        'userId': userId,
        'hasActiveSubscription': hasActivePro,
        'entitlementId': _entitlementId,
        'isActive': hasActivePro,
        'expirationDate': entitlement?.expirationDate,
        'willRenew': entitlement?.willRenew ?? false,
        'productIdentifier': entitlement?.productIdentifier,
        'lastChecked': FieldValue.serverTimestamp(),
        'originalPurchaseDate': entitlement?.latestPurchaseDate,
      };

      await _firestore
          .collection(_collection)
          .doc(userId)
          .set(subscriptionData, SetOptions(merge: true));

      // Add to user document as well for easy access
      await _firestore.collection('users').doc(userId).update({
        'subscription': {
          'hasActive': hasActivePro,
          'lastUpdated': FieldValue.serverTimestamp(),
        }
      });

      _updateSubscriptionStatus(hasActivePro);

      debugPrint('📱 Subscription status updated in Firestore: $hasActivePro');
    } catch (e) {
      debugPrint('❌ Error updating Firestore subscription: $e');
    }
  }

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
  }
}
