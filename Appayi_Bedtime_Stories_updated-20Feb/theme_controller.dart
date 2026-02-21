import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AppThemeMode { light, dark, auto }

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  AppThemeMode _mode = AppThemeMode.auto;
  AppThemeMode get mode => _mode;

  ThemeMode get materialMode {
    switch (_mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.auto:
      default:
        return ThemeMode.system; // auto = follow device
    }
  }

  String? _uid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Call once at startup (after Firebase init).
  Future<void> init() async {
    _uid = FirebaseAuth.instance.currentUser?.uid;

    // If user logged in, read + live-sync from Firestore; else default to auto.
    if (_uid != null) {
      final ref = FirebaseFirestore.instance.collection('users').doc(_uid);
      final snap = await ref.get();
      _mode = _parse((snap.data()?['settings']?['homeThemeMode']) as String?);

      // Live updates (optional, keeps theme synced across devices)
      _sub = ref.snapshots().listen((s) {
        final next = _parse((s.data()?['settings']?['homeThemeMode']) as String?);
        if (next != _mode) {
          _mode = next;
          notifyListeners();
        }
      });
    } else {
      _mode = AppThemeMode.auto;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  AppThemeMode _parse(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      case 'auto':
      default:
        return AppThemeMode.auto;
    }
  }

  Future<void> setMode(AppThemeMode m) async {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();

    if (_uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
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
