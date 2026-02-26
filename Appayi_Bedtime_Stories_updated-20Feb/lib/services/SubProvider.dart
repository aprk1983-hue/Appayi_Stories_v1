// lib/providers/subscription_provider.dart
import 'package:audio_story_app/services/subscription.dart';
import 'package:flutter/foundation.dart';

class SubscriptionProvider extends ChangeNotifier {
  final SubscriptionService _service = SubscriptionService();
  bool _hasSubscription = false;
  bool _isLoading = true;

  bool get hasSubscription => _hasSubscription;
  bool get isLoading => _isLoading;

  SubscriptionProvider() {
    _init();
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    // Listen to subscription status changes
    _service.subscriptionStatus.listen((hasActive) {
      _hasSubscription = hasActive;
      _isLoading = false;
      notifyListeners();
    });

    // Check current status
    await _service.checkSubscriptionStatus();
  }

  Future<void> refreshStatus() async {
    _isLoading = true;
    notifyListeners();
    await _service.checkSubscriptionStatus(forceRefresh: true);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> restorePurchases() async {
    await _service.restorePurchases();
    await refreshStatus();
  }
}
