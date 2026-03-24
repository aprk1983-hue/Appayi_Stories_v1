// lib/services/trial_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrialService {
  static final TrialService _instance = TrialService._internal();
  factory TrialService() => _instance;
  TrialService._internal();

  static const String _trialInstallDateKey = 'trial_install_date';
  static const int _trialDays = 7;

  bool _trialEligible = false;
  bool _trialExpired = false;

  // Stream for trial status changes
  final _trialStatusController = StreamController<bool>.broadcast();
  Stream<bool> get trialStatus => _trialStatusController.stream;

  bool get isTrialEligible => _trialEligible;
  bool get isTrialExpired => _trialExpired;

  Future<void> initialize() async {
    await _checkTrialStatus();
  }

  Future<void> _checkTrialStatus() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if install date exists
    if (!prefs.containsKey(_trialInstallDateKey)) {
      // First launch - set install date
      final now = DateTime.now();
      await prefs.setString(_trialInstallDateKey, now.toIso8601String());
      _trialEligible = true;
      _trialExpired = false;
      debugPrint('🎯 Trial started: $now');
    } else {
      // Existing user - check if trial is still active
      final installDateStr = prefs.getString(_trialInstallDateKey);
      if (installDateStr != null) {
        final installDate = DateTime.parse(installDateStr);
        final daysSinceInstall = DateTime.now().difference(installDate).inDays;

        _trialEligible = daysSinceInstall < _trialDays;
        _trialExpired = !_trialEligible;

        debugPrint(
            '📅 Days since install: $daysSinceInstall, Trial eligible: $_trialEligible');
      }
    }

    _trialStatusController.add(_trialEligible);
  }

  Future<int> getRemainingTrialDays() async {
    final prefs = await SharedPreferences.getInstance();
    final installDateStr = prefs.getString(_trialInstallDateKey);

    if (installDateStr == null) return _trialDays;

    final installDate = DateTime.parse(installDateStr);
    final daysSinceInstall = DateTime.now().difference(installDate).inDays;
    final remainingDays = (_trialDays - daysSinceInstall).clamp(0, _trialDays);

    return remainingDays;
  }

  void dispose() {
    _trialStatusController.close();
  }
}
