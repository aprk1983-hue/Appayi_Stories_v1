import 'package:flutter/material.dart';

/// Central place to trigger your paywall / subscription purchase flow.
/// Keeps UI widgets (dialogs, tiles) simple and editable.
///
/// RevenueCat integration:
/// - Add purchases_flutter to pubspec
/// - Initialize Purchases in app startup
/// - Call Purchases.presentPaywall() / getOfferings() etc. from here.
class PaywallService {
  PaywallService._();

  static Future<void> open(BuildContext context) async {
    // Try navigating to a named route if you have one.
    // Example: MaterialApp(routes: {'/subscribe': (_) => const SubscribeScreen()})
    try {
      Navigator.of(context).pushNamed('/subscribe');
      return;
    } catch (_) {
      // If no route exists yet, just show a helpful message.
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Subscription screen not wired yet. Integrate RevenueCat paywall in PaywallService.open().'),
      ),
    );
  }
}
