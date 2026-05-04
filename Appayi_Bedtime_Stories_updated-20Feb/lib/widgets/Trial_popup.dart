// lib/widgets/trial_popup.dart
import 'package:flutter/material.dart';
import '../paywall.dart';
import 'parent_gate.dart' as gate;

class TrialPopup extends StatelessWidget {
  final int remainingDays;
  final bool isExpired;
  final VoidCallback onClose;

  const TrialPopup({
    super.key,
    required this.remainingDays,
    required this.isExpired,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isExpired
                ? [
                    const Color(0xFF2C3E50),
                    const Color(0xFF1A2632),
                  ]
                : [
                    const Color(0xFF1A2980),
                    const Color(0xFF26D0CE),
                  ],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isExpired ? Icons.lock_outline : Icons.celebration,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(
                  isExpired
                      ? '✨ Free Trial Expired ✨'
                      : remainingDays > 0
                          ? '🎉 $remainingDays-Day Free Trial! 🎉'
                          : '🎉 Welcome to Your Free Trial! 🎉',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 10,
                        color: Colors.black26,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                ),
              ),

              // Message
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  isExpired
                      ? 'Your 7-day free trial has ended. Subscribe now to continue enjoying unlimited stories, downloads, and premium features! 🌟'
                      : remainingDays > 0
                          ? 'You have $remainingDays day${remainingDays > 1 ? 's' : ''} left in your free trial! Enjoy unlimited access to all stories, offline downloads, and premium features. 🌟'
                          : 'Welcome to your 7-day free trial! Enjoy unlimited access to all stories, offline downloads, and premium features. 🌟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.95),
                    height: 1.4,
                  ),
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    // Subscribe Button - FIXED: Don't pop first!
                    ElevatedButton(
                      onPressed: () async {
                        debugPrint('🔵 1. Subscribe button pressed');

                        // IMPORTANT: Don't close the trial popup yet!
                        // Show parent gate on top of the trial popup
                        final bool isVerified = await gate.requireParentPin(
                          context, // Use the trial popup's context (still valid)
                          reason:
                              'Parental permission required for subscription',
                          forceSetupIfMissing: true,
                        );

                        debugPrint('🔵 2. Verification result: $isVerified');

                        if (!isVerified) {
                          debugPrint('🔵 3. Verification failed or cancelled');
                          return;
                        }

                        debugPrint(
                            '🔵 4. Verification successful, closing trial popup');

                        // Now close the trial popup
                        if (context.mounted) {
                          Navigator.pop(context);
                        }

                        debugPrint('🔵 5. Showing paywall');

                        // Show paywall
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const RevenueCatSplashScreen(isShow: true),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 5,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: Text(
                        isExpired ? 'Subscribe Now' : 'Subscribe & Support',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Continue/Maybe Later Button
                    TextButton(
                      onPressed: onClose,
                      child: Text(
                        isExpired ? 'Maybe Later' : 'Continue Free Trial',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ),

                    // Small footer text for trial period
                    if (!isExpired && remainingDays > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Cancel anytime • No commitment',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
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
