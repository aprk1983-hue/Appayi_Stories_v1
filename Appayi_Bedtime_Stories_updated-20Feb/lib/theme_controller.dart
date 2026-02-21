import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Kept for API compatibility across the app.
enum AppThemeMode { light, dark, auto }

/// Dark-theme-only controller.
///
/// This controller intentionally ignores any persisted theme preference and
/// always returns [ThemeMode.dark]. It keeps the same public API shape as your
/// original controller so that existing UI (theme buttons, etc.) won't break.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  // Always dark.
  AppThemeMode _mode = AppThemeMode.dark;
  AppThemeMode get mode => _mode;

  ThemeMode get materialMode => ThemeMode.dark;

  // We keep these fields to avoid touching other logic that expects them.
  String? _uid;
  StreamSubscription<User?>? _authSub;

  /// Call once in main() after Firebase.initializeApp().
  ///
  /// We still listen to auth changes only to keep _uid in sync (some code may
  /// rely on it), but we do not read/write any theme preference.
  Future<void> init() async {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _uid = user?.uid;
      // Force dark and notify only if something changed (shouldn't).
      if (_mode != AppThemeMode.dark) {
        _mode = AppThemeMode.dark;
        notifyListeners();
      }
    });

    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid;

    // Ensure dark is set.
    if (_mode != AppThemeMode.dark) {
      _mode = AppThemeMode.dark;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Keep signature, but ignore the requested mode.
  Future<void> setMode(AppThemeMode m) async {
    if (_mode == AppThemeMode.dark) return;
    _mode = AppThemeMode.dark;
    notifyListeners();
  }

  /// Keep signature; no-op for dark-only.
  Future<void> cycle() async {
    // Do nothing; dark-only.
  }

  /// Expose uid if some code uses it.
  String? get uid => _uid;
}
