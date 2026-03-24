// lib/widgets/premium_subscribe_dialog.dart
import 'package:audio_story_app/paywall.dart';
import 'package:audio_story_app/services/subscription.dart';
import 'package:audio_story_app/services/trialService.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Use this helper anywhere:
/// await showPremiumSubscribeDialog(context);
Future<bool?> showPremiumSubscribeDialog(
  BuildContext context, {
  Future<void> Function()? onSubscribe,
  int? remainingTrialDays,
}) async {
  if (!context.mounted) return false;

  // If remainingTrialDays is not provided, fetch it
  int trialDays = remainingTrialDays ?? 0;
  if (remainingTrialDays == null) {
    try {
      trialDays = await TrialService().getRemainingTrialDays();
      debugPrint('📱 Fetched remaining trial days: $trialDays');
    } catch (e) {
      debugPrint('Error getting trial days: $e');
      trialDays = 0;
    }
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    builder: (_) => PremiumSubscribeDialog(
      onSubscribe: onSubscribe,
      remainingTrialDays: trialDays,
    ),
  );
}

class PremiumSubscribeDialog extends StatefulWidget {
  final Future<void> Function()? onSubscribe;
  final int remainingTrialDays;

  const PremiumSubscribeDialog({
    super.key,
    this.onSubscribe,
    this.remainingTrialDays = 0,
  });

  @override
  State<PremiumSubscribeDialog> createState() => _PremiumSubscribeDialogState();
}

class _PremiumSubscribeDialogState extends State<PremiumSubscribeDialog> {
  _Cfg cfg = _Cfg.defaults();
  bool loaded = false;
  bool _isSubscribing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('premiumDialog')
          .get();
      final d = doc.data();
      if (d != null) {
        cfg = _Cfg(
          title: d['title'] as String?,
          message: d['message'] as String?,
          imageUrl: d['imageUrl'] as String?,
          primaryButtonText: d['primaryButtonText'] as String?,
          secondaryButtonText: d['secondaryButtonText'] as String?,
          showSecondaryButton: d['showSecondaryButton'] as bool?,
        ).mergeDefaults();
      }
    } catch (_) {
      // keep defaults
    }
    if (mounted) setState(() => loaded = true);
  }

  String _getMessage() {
    debugPrint(
        '📱 Dialog - Remaining trial days: ${widget.remainingTrialDays}');

    if (widget.remainingTrialDays > 0) {
      return 'You have ${widget.remainingTrialDays} day${widget.remainingTrialDays > 1 ? 's' : ''} left in your free trial. Subscribe now to continue enjoying premium features!';
    } else if (widget.remainingTrialDays == 0) {
      return 'Your free trial has ended. Subscribe to unlock all stories, remove limits, and enable offline downloads.';
    }
    return cfg.message!;
  }

  String _getTitle() {
    if (widget.remainingTrialDays > 0) {
      return 'Trial Ending Soon';
    } else if (widget.remainingTrialDays == 0) {
      return 'Trial Expired';
    }
    return cfg.title!;
  }

  Future<void> _handleSubscribe() async {
    if (_isSubscribing) return;

    setState(() => _isSubscribing = true);

    try {
      // Close the dialog first
      Navigator.of(context).pop(false);

      // Navigate to RevenueCat paywall
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const RevenueCatSplashScreen(),
        ),
      );

      // After paywall is dismissed, check if subscription was successful
      final hasAccess = await SubscriptionService().hasAccess();
      final remainingDays = await TrialService().getRemainingTrialDays();

      debugPrint(
          '📱 After paywall - Has access: $hasAccess, Remaining days: $remainingDays');

      if (hasAccess && mounted) {
        // Subscription successful
        Navigator.of(context).pop(true);
      } else if (mounted) {
        // Subscription failed or was cancelled
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      debugPrint('Error during subscription: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop(false);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubscribing = false);
      }
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final onBg =
        theme.brightness == Brightness.dark ? Colors.white : Colors.black;
    final card = theme.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : Colors.white;

    // Determine the icon and color based on trial status
    IconData mainIcon;
    Color iconColor;

    if (widget.remainingTrialDays > 0) {
      mainIcon = Icons.timer;
      iconColor = Colors.green;
    } else if (widget.remainingTrialDays == 0) {
      mainIcon = Icons.lock;
      iconColor = Colors.red;
    } else {
      mainIcon = Icons.workspace_premium;
      iconColor = Colors.orange;
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              blurRadius: 24,
              offset: Offset(0, 12),
              color: Color(0x33000000),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image section
              if (cfg.imageUrl != null && cfg.imageUrl!.trim().isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      Image.network(
                        cfg.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          alignment: Alignment.center,
                          color: theme.colorScheme.surfaceVariant
                              .withOpacity(0.25),
                          child: Icon(mainIcon, size: 48, color: iconColor),
                        ),
                      ),
                      // Trial badge overlay
                      if (widget.remainingTrialDays > 0)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.remainingTrialDays} day${widget.remainingTrialDays > 1 ? 's' : ''} left',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Expired badge
                      if (widget.remainingTrialDays == 0)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Expired',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  alignment: Alignment.center,
                  child: Icon(
                    mainIcon,
                    size: 48,
                    color: iconColor,
                  ),
                ),

              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                child: Text(
                  _getTitle(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: onBg,
                  ),
                ),
              ),

              // Message
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: Text(
                  _getMessage(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onBg.withOpacity(0.75),
                    height: 1.35,
                  ),
                ),
              ),

              // Loading indicator
              if (!loaded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.orange),
                    ),
                  ),
                ),

              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Row(
                  children: [
                    if (cfg.showSecondaryButton == true) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubscribing
                              ? null
                              : () => Navigator.of(ctx).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(cfg.secondaryButtonText!),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubscribing ? null : _handleSubscribe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isSubscribing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(cfg.primaryButtonText!),
                      ),
                    ),
                  ],
                ),
              ),

              // Trial info footer (only show if trial is active)
              if (widget.remainingTrialDays > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Cancel anytime • No commitment',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onBg.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cfg {
  final String? title;
  final String? message;
  final String? imageUrl;
  final String? primaryButtonText;
  final String? secondaryButtonText;
  final bool? showSecondaryButton;

  const _Cfg({
    this.title,
    this.message,
    this.imageUrl,
    this.primaryButtonText,
    this.secondaryButtonText,
    this.showSecondaryButton,
  });

  factory _Cfg.defaults() => const _Cfg(
        title: 'Subscribe to unlock',
        message:
            'Unlock all stories, remove limits, and enable offline downloads.',
        primaryButtonText: 'Subscribe',
        secondaryButtonText: 'Not now',
        showSecondaryButton: true,
      );

  _Cfg mergeDefaults() {
    final d = _Cfg.defaults();
    return _Cfg(
      title: (title == null || title!.trim().isEmpty) ? d.title : title,
      message:
          (message == null || message!.trim().isEmpty) ? d.message : message,
      imageUrl: imageUrl,
      primaryButtonText:
          (primaryButtonText == null || primaryButtonText!.trim().isEmpty)
              ? d.primaryButtonText
              : primaryButtonText,
      secondaryButtonText:
          (secondaryButtonText == null || secondaryButtonText!.trim().isEmpty)
              ? d.secondaryButtonText
              : secondaryButtonText,
      showSecondaryButton: showSecondaryButton ?? d.showSecondaryButton,
    );
  }
}
