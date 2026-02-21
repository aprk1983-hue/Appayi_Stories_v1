import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AppThemeMode { light, dark, auto }

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  // --- CHANGED DEFAULT ---
  AppThemeMode _mode = AppThemeMode.light;
  AppThemeMode get mode => _mode;

  /// Map our enum to MaterialApp's ThemeMode
  ThemeMode get materialMode {
    switch (_mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.auto:
      default:
        return ThemeMode.system;
    }
  }

  String? _uid;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  /// Call once in main() after Firebase.initializeApp()
  Future<void> init() async {
    // Start listening to auth changes so the theme stays in sync when user logs in/out
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      // Cancel any previous user doc subscription
      _userDocSub?.cancel();

      _uid = user?.uid;

      if (_uid == null) {
        // No user -> default to light
        // --- CHANGED DEFAULT ---
        _setModeInternal(AppThemeMode.light);
        return;
      }

      // Read once
      try {
        final ref = FirebaseFirestore.instance.collection('users').doc(_uid);
        final snap = await ref.get();
        _setModeInternal(_parse((snap.data()?['settings']?['homeThemeMode']) as String?));

        // Live updates
        _userDocSub = ref.snapshots().listen((s) {
          final next = _parse((s.data()?['settings']?['homeThemeMode']) as String?);
          if (next != _mode) _setModeInternal(next);
        });
      } catch (_) {
        // On error just keep current mode
      }
    });

    // Also seed with current user immediately
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _uid = user.uid;
      try {
        final ref = FirebaseFirestore.instance.collection('users').doc(_uid);
        final snap = await ref.get();
        _setModeInternal(_parse((snap.data()?['settings']?['homeThemeMode']) as String?));

        _userDocSub?.cancel();
        _userDocSub = ref.snapshots().listen((s) {
          final next = _parse((s.data()?['settings']?['homeThemeMode']) as String?);
          if (next != _mode) _setModeInternal(next);
        });
      } catch (_) {
        // --- CHANGED DEFAULT ---
        _setModeInternal(AppThemeMode.light);
      }
    } else {
      // --- CHANGED DEFAULT ---
      _setModeInternal(AppThemeMode.light);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }

  Future<void> setMode(AppThemeMode m) async {
    if (_mode == m) return;
    _setModeInternal(m);

    // Persist for signed-in users
    final uid = _uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'settings': {'homeThemeMode': _string(m)},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> cycle() async {
    final next = _mode == AppThemeMode.light
        ? AppThemeMode.dark
        : _mode == AppThemeMode.dark
            ? AppThemeMode.auto
            : AppThemeMode.light;
    await setMode(next);
  }

  // ---- helpers ----
  void _setModeInternal(AppThemeMode m) {
    _mode = m;
    notifyListeners();
  }

  AppThemeMode _parse(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      case 'auto':
        return AppThemeMode.auto;
      // --- CHANGED DEFAULT ---
      default:
        return AppThemeMode.light; // Default to light if value is invalid/missing
    }
  }

  String _string(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.dark:
        return 'dark';
      case AppThemeMode.auto:
      default:
        return 'auto';
    }
  }
}