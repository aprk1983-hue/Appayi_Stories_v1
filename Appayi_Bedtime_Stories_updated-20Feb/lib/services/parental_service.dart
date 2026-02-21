// lib/services/parental_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ParentalSettings {
  final bool childMode;
  final bool commentsEnabled;
  final List<String> allowedCategories;
  final int dailyMinutes;
  final String quietStart; // "21:00"
  final String quietEnd;   // "06:00"
  final bool analyticsOptIn;

  final String? _pinHash;
  final String? _pinSalt;

  ParentalSettings({
    required this.childMode,
    required this.commentsEnabled,
    required this.allowedCategories,
    required this.dailyMinutes,
    required this.quietStart,
    required this.quietEnd,
    required this.analyticsOptIn,
    String? pinHash,
    String? pinSalt,
  })  : _pinHash = pinHash,
        _pinSalt = pinSalt;

  bool get hasPin => (_pinHash?.isNotEmpty ?? false) && (_pinSalt?.isNotEmpty ?? false);

  Map<String, dynamic> toMap() => {
        'childMode': childMode,
        'commentsEnabled': commentsEnabled,
        'allowedCategories': allowedCategories,
        'dailyMinutes': dailyMinutes,
        'quietHours': {'start': quietStart, 'end': quietEnd},
        'analyticsOptIn': analyticsOptIn,
        if (_pinHash != null) 'parentPinHash': _pinHash,
        if (_pinSalt != null) 'parentPinSalt': _pinSalt,
      };

  factory ParentalSettings.fromMap(Map<String, dynamic> m) {
    // --- UPDATED DEFAULTS FOR QUIET HOURS ---
    const defaultStart = '00:00'; // 12 AM (Midnight)
    const defaultEnd = '06:00';   // 6 AM
    
    final qh = (m['quietHours'] as Map?) ?? const {};
    return ParentalSettings(
      childMode: (m['childMode'] as bool? ?? true), 
      commentsEnabled: (m['commentsEnabled'] as bool? ?? false),
      allowedCategories: (m['allowedCategories'] is List)
          ? List<String>.from(m['allowedCategories'])
          : const <String>[],
      dailyMinutes: (m['dailyMinutes'] is int) ? m['dailyMinutes'] : 0,
      quietStart: (qh['start']?.toString() ?? defaultStart), 
      quietEnd: (qh['end']?.toString() ?? defaultEnd),     
      analyticsOptIn: (m['analyticsOptIn'] as bool? ?? false),
      pinHash: m['parentPinHash']?.toString(),
      pinSalt: m['parentPinSalt']?.toString(),
    );
  }
}

class ParentalService {
  ParentalService._();
  static final instance = ParentalService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // --- UPDATED DEFAULTS FOR LOGGED-OUT USER / NEW USER ---
  static const defaultQuietStart = '00:00'; // 12 AM
  static const defaultQuietEnd = '06:00';   // 6 AM
  
  Stream<ParentalSettings> watch() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // --- RETURN DEFAULT SETTINGS FOR LOGGED-OUT USER ---
      return Stream.value(ParentalSettings(
        childMode: true,
        commentsEnabled: false,
        allowedCategories: const [],
        dailyMinutes: 0,
        quietStart: defaultQuietStart, 
        quietEnd: defaultQuietEnd,     
        analyticsOptIn: false,
      ));
    }
    return _db.collection('users').doc(uid).snapshots().map((d) {
      final m = (d.data()?['settings'] as Map?) ?? const {};
      return ParentalSettings.fromMap(Map<String, dynamic>.from(m));
    });
  }

  Future<ParentalSettings> get() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return ParentalSettings(
        childMode: true,
        commentsEnabled: false,
        allowedCategories: const [],
        dailyMinutes: 0,
        quietStart: defaultQuietStart, 
        quietEnd: defaultQuietEnd,     
        analyticsOptIn: false,
      );
    }
    final d = await _db.collection('users').doc(uid).get();
    final m = (d.data()?['settings'] as Map?) ?? const {};
    return ParentalSettings.fromMap(Map<String, dynamic>.from(m));
  }

  Future<void> save(ParentalSettings s) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'settings': s.toMap(),
      // --- FIX: Use FieldValue directly ---
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------- Helpers used by the gate ----------
  Future<bool> hasPin() async {
    final s = await get();
    return s.hasPin;
  }

  Future<void> setNewPin(String pin) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final salt = _newSalt();
    final hash = _hash(pin, salt);
    await _db.collection('users').doc(uid).set({
      'settings': {
        'parentPinHash': hash,
        'parentPinSalt': salt,
      },
      // --- FIX: Use FieldValue directly ---
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearPin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'settings': {
        // --- FIX: Use FieldValue directly ---
        'parentPinHash': FieldValue.delete(),
        'parentPinSalt': FieldValue.delete(),
      },
      // --- FIX: Use FieldValue directly ---
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setCommentsEnabled(bool enabled) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'settings': {'commentsEnabled': enabled},
      // --- FIX: Use FieldValue directly ---
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Verify against existing PIN. If none exists and [allowSetIfEmpty] is true, set it.
  Future<bool> verifyOrSetPin(String pin, {bool allowSetIfEmpty = false}) async {
    final current = await get();
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    if (current.hasPin) {
      final calc = _hash(pin, current._pinSalt!);
      return calc == current._pinHash!;
    }

    if (!allowSetIfEmpty) return false;

    final salt = _newSalt();
    final hash = _hash(pin, salt);
    await _db.collection('users').doc(uid).set({
      'settings': {
        'parentPinHash': hash,
        'parentPinSalt': salt,
      },
      // --- FIX: Use FieldValue directly ---
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  String _hash(String pin, String salt) {
    final h = sha256.convert(utf8.encode('$salt:$pin'));
    return h.toString();
  }

  String _newSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }
}