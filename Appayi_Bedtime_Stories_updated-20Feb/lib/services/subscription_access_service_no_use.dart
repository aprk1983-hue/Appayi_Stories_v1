import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Subscription + free-access gatekeeper.
///
/// Firestore:
/// - users/{uid} contains subscription status (bool fields)
/// - appConfig/freeAccess contains:
///   - perLanguageFreeCount (number)
///   - freeShareIdsByLanguage { en: [..], hi: [..], ta: [..] }
///
/// ✅ Fallback (if Firestore config can't be read due to rules/network):
/// Uses the baked-in lists below so non-subscribers still get free stories.
class SubscriptionAccessService {
  SubscriptionAccessService._();
  static final SubscriptionAccessService instance = SubscriptionAccessService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _freeAccessCache;
  DateTime? _freeAccessFetchedAt;

  // ---------- Fallback Free Lists ----------
  static const int _fallbackPerLanguageFreeCount = 20;

  static const Map<String, List<int>> _fallbackFreeShareIdsByLanguage = {
    'en': [3, 23, 24, 25, 28, 29, 31, 33, 43, 45, 48, 51, 61, 77, 80, 82, 86, 87, 88, 89],
    'hi': [2, 5, 9, 11],
    'ta': [1, 6, 8, 12],
  };

  // ---------- Public API ----------

  /// Subscription gating has been removed.
  ///
  /// This service is kept for backward compatibility with the UI code that
  /// previously showed locks/paywalls. All callers should now treat every user
  /// as having full access.

  Stream<bool> watchIsSubscribed() {
    // Always true: all users have access.
    return Stream<bool>.value(true);
  }

  Future<bool> isSubscribed() async {
    // Always true: all users have access.
    return true;
  }

  /// Returns the configured free shareIds for a language code (e.g., "en").
  /// Respects perLanguageFreeCount (caps the returned set).
  ///
  /// If Firestore config is unavailable, returns fallback list.
  Future<Set<int>> getFreeShareIdsForLanguage(String language) async {
    // With subscription gating removed, "free" lists are no longer needed.
    // Return an empty set; callers should rely on [canPlayStory] which is
    // always true.
    return <int>{};

    /*
    final lang = normalizeLanguage(language);

    // 1) Try Firestore config
    try {
      final data = await _getFreeAccessDocData();
      final ids = _extractFreeIdsFromConfig(data, lang);
      if (ids.isNotEmpty) return ids;
    } catch (_) {
      // ignore
    }

    // 2) Fallback list
    final raw = _fallbackFreeShareIdsByLanguage[lang] ?? const <int>[];
    final capped = raw.take(_fallbackPerLanguageFreeCount).toSet();
    return capped;
    */
  }

  /// Can a (non-subscriber) play this story?
  Future<bool> canPlayStory({required String language, required int? shareId}) async {
    // Always true: all stories are playable.
    return true;
  }

  /// Can a user download audio for offline?
  Future<bool> canDownload() async => await isSubscribed();


  /// Normalize language values (handles "English", "en-US", etc.)
  String normalizeLanguage(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return 'en';
    if (s.startsWith('english')) return 'en';
    if (s.startsWith('hindi')) return 'hi';
    if (s.startsWith('tamil')) return 'ta';
    if (s.startsWith('telugu')) return 'te';
    if (s.startsWith('malayalam')) return 'ml';
    if (s.startsWith('kannada')) return 'kn';
    if (s.contains('-')) return s.split('-').first;
    return s;
  }

  // ---------- Internals ----------

  bool _parseSubscribedFromUserDoc(Map<String, dynamic> d) {
    bool pickBool(String key) => (d[key] is bool) ? d[key] as bool : false;

    if (pickBool('isSubscribed')) return true;
    if (pickBool('subscribed')) return true;
    if (pickBool('premium')) return true;
    if (pickBool('isPremium')) return true;
    if (pickBool('planActive')) return true;

    final sub = d['subscription'];
    if (sub is Map) {
      final active = sub['active'];
      if (active is bool && active) return true;

      final status = sub['status'];
      if (status is String) {
        final s = status.toLowerCase();
        if (s == 'active' || s == 'paid' || s == 'premium') return true;
      }
    }

    final plan = d['plan'];
    if (plan is String) {
      final p = plan.toLowerCase();
      if (p.contains('premium') || p.contains('paid') || p.contains('pro')) return true;
    }

    return false;
  }

  Set<int> _extractFreeIdsFromConfig(Map<String, dynamic>? data, String lang) {
    if (data == null) return <int>{};

    final map = data['freeShareIdsByLanguage'];
    if (map is! Map) return <int>{};

    final rawList = map[lang];
    if (rawList is! List) return <int>{};

    final per = _coerceInt(data['perLanguageFreeCount']) ?? rawList.length;

    final out = <int>[];
    for (final v in rawList) {
      final i = _coerceInt(v);
      if (i != null) out.add(i);
    }
    return out.take(per).toSet();
  }

  Future<Map<String, dynamic>?> _getFreeAccessDocData() async {
    // cache for ~2 minutes
    if (_freeAccessCache != null &&
        _freeAccessFetchedAt != null &&
        DateTime.now().difference(_freeAccessFetchedAt!).inSeconds < 120) {
      return _freeAccessCache;
    }
    final doc = await _db.collection('appConfig').doc('freeAccess').get();
    _freeAccessCache = doc.data();
    _freeAccessFetchedAt = DateTime.now();
    return _freeAccessCache;
  }

  int? _coerceInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
