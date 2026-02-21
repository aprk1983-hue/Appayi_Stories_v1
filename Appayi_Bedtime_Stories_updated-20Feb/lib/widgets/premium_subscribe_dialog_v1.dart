// lib/widgets/premium_subscribe_dialog.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audio_story_app/services/paywall_service.dart';

/// Use this helper anywhere:
/// await showPremiumSubscribeDialog(context);
Future<void> showPremiumSubscribeDialog(
  BuildContext context, {
  Future<void> Function()? onSubscribe,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    builder: (_) => PremiumSubscribeDialog(onSubscribe: onSubscribe),
  );
}

/// Also provides a Widget for code that expects:
/// `builder: (_) => const PremiumSubscribeDialog()`
class PremiumSubscribeDialog extends StatefulWidget {
  final Future<void> Function()? onSubscribe;
  const PremiumSubscribeDialog({super.key, this.onSubscribe});

  @override
  State<PremiumSubscribeDialog> createState() => _PremiumSubscribeDialogState();
}

class _PremiumSubscribeDialogState extends State<PremiumSubscribeDialog> {
  _Cfg cfg = _Cfg.defaults();
  bool loaded = false;

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

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final onBg =
        theme.brightness == Brightness.dark ? Colors.white : Colors.black;
    final card = theme.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : Colors.white;

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
              if (cfg.imageUrl != null && cfg.imageUrl!.trim().isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    cfg.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      alignment: Alignment.center,
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
                      child: Icon(Icons.workspace_premium,
                          size: 48, color: onBg.withOpacity(0.65)),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  alignment: Alignment.center,
                  child: Icon(Icons.workspace_premium,
                      size: 48, color: Colors.orange),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                child: Text(
                  cfg.title!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: onBg),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: Text(
                  cfg.message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: onBg.withOpacity(0.75), height: 1.35),
                ),
              ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Row(
                  children: [
                    if (cfg.showSecondaryButton == true) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
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
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          if (widget.onSubscribe != null) {
                            await widget.onSubscribe!();
                          } else {
                            await PaywallService.open(ctx);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(cfg.primaryButtonText!),
                      ),
                    ),
                  ],
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
