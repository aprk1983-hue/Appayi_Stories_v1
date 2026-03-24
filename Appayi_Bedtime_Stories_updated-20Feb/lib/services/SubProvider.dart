// lib/services/sub_provider.dart
import 'package:audio_story_app/services/subscription.dart';
import 'package:audio_story_app/services/trialService.dart';
import 'package:flutter/material.dart';

class SubscriptionProvider extends ChangeNotifier {
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TrialService _trialService = TrialService();

  bool _hasAccess = false;
  bool _shouldShowPaywall = false;
  bool _isLoading = true;

  bool get hasAccess => _hasAccess;
  bool get shouldShowPaywall => _shouldShowPaywall;
  bool get isLoading => _isLoading;

  SubscriptionProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _subscriptionService.initialize();

    // Listen to subscription changes
    _subscriptionService.subscriptionStatus.listen((hasSubscription) async {
      await _updateAccessStatus();
    });

    // Listen to trial changes
    _trialService.trialStatus.listen((_) async {
      await _updateAccessStatus();
    });

    await _updateAccessStatus();
  }

  Future<void> _updateAccessStatus() async {
    _isLoading = true;
    notifyListeners();

    _hasAccess = await _subscriptionService.hasAccess();
    _shouldShowPaywall = await _subscriptionService.shouldShowPaywall();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> checkSubscription() async {
    await _subscriptionService.checkSubscriptionStatus(forceRefresh: true);
    await _updateAccessStatus();
  }

  Future<int> getRemainingTrialDays() async {
    return await _trialService.getRemainingTrialDays();
  }

  @override
  void dispose() {
    _subscriptionService.dispose();
    super.dispose();
  }
}
