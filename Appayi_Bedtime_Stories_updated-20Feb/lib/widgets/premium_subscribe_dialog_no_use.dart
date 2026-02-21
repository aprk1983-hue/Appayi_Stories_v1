// lib/widgets/premium_subscribe_dialog.dart
//
// NOTE:
// Subscription gating has been removed from the app.
// This file is intentionally kept for backward compatibility with any existing
// imports/usages of `showPremiumSubscribeDialog` / `PremiumSubscribeDialog`.
// Any calls will now be a no-op (no popup).

import 'package:flutter/material.dart';

/// Backward compatible helper (no-op).
///
/// Old usage:
///   await showPremiumSubscribeDialog(context);
Future<void> showPremiumSubscribeDialog(
  BuildContext context, {
  Future<void> Function()? onSubscribe,
}) async {
  // Do nothing: all stories are available without subscription.
  return;
}

/// Backward compatible widget (renders nothing).
class PremiumSubscribeDialog extends StatelessWidget {
  final Future<void> Function()? onSubscribe;
  const PremiumSubscribeDialog({super.key, this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    // Render nothing.
    return const SizedBox.shrink();
  }
}
