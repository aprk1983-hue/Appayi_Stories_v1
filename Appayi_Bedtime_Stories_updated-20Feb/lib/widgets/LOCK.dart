// // lib/widgets/subscription_lock.dart
// import 'package:audio_story_app/services/SubProvider.dart';
// import 'package:audio_story_app/widgets/premium_subscribe_dialog_v1.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// class SubscriptionLock extends StatelessWidget {
//   final Widget child;
//   final bool isFreeContent;
//   final VoidCallback? onLockPressed;

//   const SubscriptionLock({
//     Key? key,
//     required this.child,
//     this.isFreeContent = false,
//     this.onLockPressed,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     // If it's free content, always show the child
//     if (isFreeContent) {
//       return child;
//     }

//     return Consumer<SubscriptionProvider>(
//       builder: (context, provider, _) {
//         // If user has subscription, show the content
//         if (provider.hasSubscription) {
//           return child;
//         }

//         // Otherwise show locked content with tap to subscribe
//         return GestureDetector(
//           onTap: () {
//             if (onLockPressed != null) {
//               onLockPressed!();
//             } else {
//               showPremiumSubscribeDialog(context);
//             }
//           },
//           child: Stack(
//             children: [
//               // Blurred child content
//               Opacity(
//                 opacity: 0.3,
//                 child: child,
//               ),
//               // Lock overlay
//               Positioned.fill(
//                 child: Container(
//                   decoration: BoxDecoration(
//                     color: Colors.black.withOpacity(0.2),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Container(
//                         padding: const EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: Colors.black.withOpacity(0.6),
//                           shape: BoxShape.circle,
//                         ),
//                         child: const Icon(
//                           Icons.lock_outline,
//                           color: Colors.white,
//                           size: 28,
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       Container(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 12,
//                           vertical: 4,
//                         ),
//                         decoration: BoxDecoration(
//                           color: Colors.orange,
//                           borderRadius: BorderRadius.circular(20),
//                         ),
//                         child: const Text(
//                           'SUBSCRIBE',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold,
//                             fontSize: 12,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }
// lib/widgets/subscription_lock.dart
import 'dart:ui';

import 'package:audio_story_app/services/SubProvider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SubscriptionLock extends StatelessWidget {
  final Widget child;
  final bool isFreeContent;
  final VoidCallback? onLockPressed;
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;

  const SubscriptionLock({
    Key? key,
    required this.child,
    this.isFreeContent = false,
    this.onLockPressed,
    this.height,
    this.width,
    this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isFreeContent) {
      return child;
    }

    return Consumer<SubscriptionProvider>(
      builder: (context, provider, _) {
        if (provider.hasAccess) {
          return child;
        }

        return GestureDetector(
          onTap: () {
            if (onLockPressed != null) {
              onLockPressed!();
            } else {
              _showPremiumSheet(context);
            }
          },
          child: Stack(
            children: [
              // Smooth blurred content
              ClipRRect(
                borderRadius: borderRadius ?? BorderRadius.circular(16),
                child: Stack(
                  children: [
                    child,
                    // Premium blur effect instead of dull opacity
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                    // Subtle gradient overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.2),
                              Colors.black.withOpacity(0.6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Premium lock overlay with animation
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.9, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeInOut,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius ?? BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Premium lock icon with glow
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF3A3A3A),
                                Color(0xFF1A1A1A),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Colors.amber.withOpacity(0.2),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Premium gradient badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFFFF6B6B),
                                Color(0xFFFFA07A),
                                Color(0xFFFFD700),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.4),
                                blurRadius: 15,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Text(
                            'PREMIUM',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  offset: Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Subtle hint text with better typography
                        Text(
                          'Tap to unlock',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPremiumSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Premium header with gradient
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF6B6B),
                    Color(0xFFFFA07A),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Premium Content',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Subscribe to unlock this and thousands of other stories',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            // Benefits list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildBenefitItem(
                    icon: Icons.auto_stories_rounded,
                    title: 'Unlimited Stories',
                    subtitle: 'Access to our entire library',
                  ),
                  _buildBenefitItem(
                    icon: Icons.offline_bolt_rounded,
                    title: 'Download & Listen Offline',
                    subtitle: 'Save stories for later',
                  ),
                  _buildBenefitItem(
                    icon: Icons.volume_up_rounded,
                    title: 'High Quality Audio',
                    subtitle: 'Crystal clear narration',
                  ),
                  _buildBenefitItem(
                    icon: Icons.family_restroom_rounded,
                    title: 'Family Sharing',
                    subtitle: 'Share with up to 5 family members',
                  ),
                ],
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'NOT NOW',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/paywall');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'SUBSCRIBE',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.orange, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
