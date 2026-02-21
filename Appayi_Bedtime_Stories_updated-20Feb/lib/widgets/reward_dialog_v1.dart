// lib/widgets/reward_dialog.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';

/// A helper function to show the dialog
Future<void> showRewardDialog(BuildContext context, String title, String message) {
  return showDialog(
    context: context,
    builder: (ctx) => _RewardDialog(title: title, message: message),
  );
}

class _RewardDialog extends StatefulWidget {
  final String title;
  final String message;
  const _RewardDialog({required this.title, required this.message});

  @override
  State<_RewardDialog> createState() => _RewardDialogState();
}

class _RewardDialogState extends State<_RewardDialog> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 1));
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 24),
          ),
          content: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: TextStyle(color: textColor, fontSize: 18),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Awesome!', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        ConfettiWidget(
          confettiController: _confettiController,
          blastDirection: pi / 2, // down
          particleDrag: 0.05,
          emissionFrequency: 0.05,
          numberOfParticles: 20,
          gravity: 0.1,
          shouldLoop: false,
          colors: const [
            Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple
          ],
        ),
      ],
    );
  }
}