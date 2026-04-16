// // lib/services/trial_service.dart
// import 'dart:async';
// import 'package:flutter/foundation.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class TrialService {
//   static final TrialService _instance = TrialService._internal();
//   factory TrialService() => _instance;
//   TrialService._internal();

//   static const String _trialInstallDateKey = 'trial_install_date';
//   static const int _trialDays = 7;

//   bool _trialEligible = false;
//   bool _trialExpired = false;

//   // Stream for trial status changes
//   final _trialStatusController = StreamController<bool>.broadcast();
//   Stream<bool> get trialStatus => _trialStatusController.stream;

//   bool get isTrialEligible => _trialEligible;
//   bool get isTrialExpired => _trialExpired;

//   Future<void> initialize() async {
//     await _checkTrialStatus();
//   }

//   Future<void> _checkTrialStatus() async {
//     final prefs = await SharedPreferences.getInstance();

//     // Check if install date exists
//     if (!prefs.containsKey(_trialInstallDateKey)) {
//       // First launch - set install date
//       final now = DateTime.now();
//       await prefs.setString(_trialInstallDateKey, now.toIso8601String());
//       _trialEligible = true;
//       _trialExpired = false;
//       debugPrint('🎯 Trial started: $now');
//     } else {
//       // Existing user - check if trial is still active
//       final installDateStr = prefs.getString(_trialInstallDateKey);
//       if (installDateStr != null) {
//         final installDate = DateTime.parse(installDateStr);
//         final daysSinceInstall = DateTime.now().difference(installDate).inDays;

//         _trialEligible = daysSinceInstall < _trialDays;
//         _trialExpired = !_trialEligible;

//         debugPrint(
//             '📅 Days since install: $daysSinceInstall, Trial eligible: $_trialEligible');
//       }
//     }

//     _trialStatusController.add(_trialEligible);
//   }

//   Future<int> getRemainingTrialDays() async {
//     final prefs = await SharedPreferences.getInstance();
//     final installDateStr = prefs.getString(_trialInstallDateKey);

//     if (installDateStr == null) return _trialDays;

//     final installDate = DateTime.parse(installDateStr);
//     final daysSinceInstall = DateTime.now().difference(installDate).inDays;
//     final remainingDays = (_trialDays - daysSinceInstall).clamp(0, _trialDays);

//     return remainingDays;
//   }

//   void dispose() {
//     _trialStatusController.close();
//   }

//   Future<bool> isFirstLaunch() async {
//     final prefs = await SharedPreferences.getInstance();
//     return !prefs.containsKey(_trialInstallDateKey);
//   }
// }

// lib/services/trial_service.dart (UPDATED)
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class TrialService {
  static final TrialService _instance = TrialService._internal();
  factory TrialService() => _instance;
  TrialService._internal();

  static const int _trialDays = 7;
  static const String _trialCollection = 'user_trials';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _trialEligible = false;
  bool _trialExpired = false;
  DateTime? _trialStartDate;

  // Stream for trial status changes
  final _trialStatusController = StreamController<bool>.broadcast();
  Stream<bool> get trialStatus => _trialStatusController.stream;

  // Listen to auth changes to sync trial
  StreamSubscription<User?>? _authSubscription;

  bool get isTrialEligible => _trialEligible;
  bool get isTrialExpired => _trialExpired;
  DateTime? get trialStartDate => _trialStartDate;

  Future<void> initialize() async {
    // Listen to auth changes
    _authSubscription = _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        await _loadTrialFromFirestore(user.uid);
      } else {
        _resetTrialState();
      }
    });

    // If already logged in, load immediately
    final user = _auth.currentUser;
    if (user != null) {
      await _loadTrialFromFirestore(user.uid);
    }
  }

  Future<void> _loadTrialFromFirestore(String userId) async {
    try {
      final docRef = _firestore.collection(_trialCollection).doc(userId);
      final doc = await docRef.get();

      if (!doc.exists) {
        // First time user - create new trial
        await _createNewTrial(userId);
      } else {
        // Existing user - load trial data
        final data = doc.data()!;
        _trialStartDate = (data['trialStartDate'] as Timestamp).toDate();

        final daysSinceInstall =
            DateTime.now().difference(_trialStartDate!).inDays;
        _trialEligible = daysSinceInstall < _trialDays;
        _trialExpired = !_trialEligible;

        debugPrint('📅 Loaded trial from Firestore:');
        debugPrint('   User: $userId');
        debugPrint('   Start Date: $_trialStartDate');
        debugPrint('   Days since: $daysSinceInstall');
        debugPrint('   Trial eligible: $_trialEligible');
        debugPrint('   Days left: ${await getRemainingTrialDays()}');
      }

      _trialStatusController.add(_trialEligible);
    } catch (e) {
      debugPrint('❌ Error loading trial from Firestore: $e');
      // Fallback to local storage if Firestore fails
      await _fallbackToLocalStorage(userId);
    }
  }

  Future<void> _createNewTrial(String userId) async {
    _trialStartDate = DateTime.now();
    _trialEligible = true;
    _trialExpired = false;

    final trialData = {
      'userId': userId,
      'trialStartDate': Timestamp.fromDate(_trialStartDate!),
      'trialEndDate':
          Timestamp.fromDate(_trialStartDate!.add(Duration(days: _trialDays))),
      'trialDays': _trialDays,
      'isActive': true,
      'isExpired': false,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    await _firestore.collection(_trialCollection).doc(userId).set(trialData);

    debugPrint('🎯 Created new trial for user: $userId');
    debugPrint('   Start date: $_trialStartDate');
    debugPrint(
        '   End date: ${_trialStartDate!.add(Duration(days: _trialDays))}');
  }

  Future<int> getRemainingTrialDays() async {
    if (_trialStartDate == null) {
      // Try to load from Firestore first
      final user = _auth.currentUser;
      if (user != null) {
        await _loadTrialFromFirestore(user.uid);
      }

      if (_trialStartDate == null) return _trialDays;
    }

    final daysSinceInstall = DateTime.now().difference(_trialStartDate!).inDays;
    final remainingDays = (_trialDays - daysSinceInstall).clamp(0, _trialDays);

    return remainingDays;
  }

  Future<DateTime?> getTrialEndDate() async {
    if (_trialStartDate == null) return null;
    return _trialStartDate!.add(Duration(days: _trialDays));
  }

  Future<bool> isTrialExpiredCheck() async {
    final remainingDays = await getRemainingTrialDays();
    return remainingDays <= 0;
  }

  void _resetTrialState() {
    _trialEligible = false;
    _trialExpired = false;
    _trialStartDate = null;
  }

  Future<void> _fallbackToLocalStorage(String userId) async {
    debugPrint('⚠️ Using fallback local storage for trial');
    // Keep your original SharedPreferences logic as fallback
    // But log this so you know Firestore failed
    // ... existing SharedPreferences code ...
  }

  // Manual refresh method (call after subscription purchase)
  Future<void> refreshTrialStatus() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _loadTrialFromFirestore(user.uid);
    }
  }

  // Admin method to reset trial (for testing)
  Future<void> resetTrialForUser(String userId) async {
    await _firestore.collection(_trialCollection).doc(userId).delete();
    await _createNewTrial(userId);
  }

  void dispose() {
    _authSubscription?.cancel();
    _trialStatusController.close();
  }
}
