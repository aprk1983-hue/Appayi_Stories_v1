import 'package:flutter/material.dart';

/// A simple background image wrapper with a dim overlay.
/// Usage:
///   BackgroundContainer(
///     imagePath: 'assets/backgrounds/login_bg_purple.png',
///     dimOpacity: 0.15,
///     child: YourScreen(),
///   )
class BackgroundContainer extends StatelessWidget {
  final Widget child;
  final String imagePath;
  final double dimOpacity;

  const BackgroundContainer({
    Key? key,
    required this.child,
    required this.imagePath,
    this.dimOpacity = 0.4,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image
        Image.asset(
          imagePath,
          fit: BoxFit.cover,
        ),

        // Dim overlay
        Container(
          color: Colors.black.withOpacity(dimOpacity.clamp(0.0, 1.0)),
        ),

        // Foreground content
        child,
      ],
    );
  }
}
