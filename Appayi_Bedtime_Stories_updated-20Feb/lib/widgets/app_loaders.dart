import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Centralized Lottie-based loader.
///
/// Defaults
/// - Renders the Lottie in its ORIGINAL colors (no tint).
/// - Uses a slightly larger default [size] for centered/full-screen loaders.
///
/// Customization
/// - Swap animation by passing [asset].
/// - Force a single-color loader by setting [tint] = true.
/// - Override the tint color with [color] (when [tint] is true).
class AppLoader extends StatelessWidget {
  final double size;
  final Color? color;
  final String asset;

  /// When true, applies a color filter to the whole Lottie (single-color loader).
  /// When false (default), the Lottie renders with its original colors.
  final bool tint;

  const AppLoader({
    super.key,
    // Bigger default so it looks good for full-screen / centered loaders.
    // For inline/pagination loaders, pass a smaller size explicitly (e.g. 32–48).
    this.size = 180,
    this.color,
    this.asset = 'assets/bouncing_loader.json',
    this.tint = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    final LottieDelegates? delegates = tint
        ? LottieDelegates(values: [
            ValueDelegate.colorFilter(
              const ['**'],
              value: ColorFilter.mode(effectiveColor, BlendMode.srcIn),
            ),
          ])
        : null;

    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        asset,
        fit: BoxFit.contain,
        delegates: delegates,
        errorBuilder: (context, error, stack) {
          return Center(
            child: SizedBox(
              width: size * 0.35,
              height: size * 0.35,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: effectiveColor,
              ),
            ),
          );
        },
      ),
    );
  }
}
