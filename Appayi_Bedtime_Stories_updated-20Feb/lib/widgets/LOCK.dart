// lib/widgets/subscription_lock.dart
import 'package:audio_story_app/services/SubProvider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SubscriptionLock extends StatelessWidget {
  final Widget child;
  final bool isFreeContent;
  final VoidCallback? onLockPressed;

  const SubscriptionLock({
    Key? key,
    required this.child,
    this.isFreeContent = false,
    this.onLockPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If it's free content, always show the child
    if (isFreeContent) {
      return child;
    }

    return Consumer<SubscriptionProvider>(
      builder: (context, provider, _) {
        // If user has subscription, show the content
        if (provider.hasSubscription) {
          return child;
        }

        // Otherwise show locked content with tap to subscribe
        return GestureDetector(
          onTap: () {
            if (onLockPressed != null) {
              onLockPressed!();
            } else {
              _showSubscribeDialog(context);
            }
          },
          child: Stack(
            children: [
              // Blurred child content
              Opacity(
                opacity: 0.3,
                child: child,
              ),
              // Lock overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'SUBSCRIBE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubscribeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Premium Content'),
        content: const Text(
            'This content requires a subscription. Would you like to subscribe now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('NOT NOW'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigate to paywall screen
              Navigator.pushNamed(context, '/paywall');
            },
            child: const Text('SUBSCRIBE'),
          ),
        ],
      ),
    );
  }
}
