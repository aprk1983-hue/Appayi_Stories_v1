// lib/screens/parental_controls_screen.dart
import 'package:flutter/material.dart';
import 'package:audio_story_app/services/parental_service.dart';
// --- ADDED IMPORT FOR THE PIN DIALOG ---
import 'package:audio_story_app/widgets/parent_gate.dart' as gate;


class ParentalControlsScreen extends StatefulWidget {
  const ParentalControlsScreen({super.key});

  @override
  State<ParentalControlsScreen> createState() => _ParentalControlsScreenState();
}

class _ParentalControlsScreenState extends State<ParentalControlsScreen> {
  late Stream<ParentalSettings> _settingsStream;
  ParentalSettings? _currentSettings; // Store the latest settings

  @override
  void initState() {
    super.initState();
    _settingsStream = ParentalService.instance.watch();
  }

  /// Parses a 'HH:mm' string into a TimeOfDay object
  TimeOfDay _parseTime(String time) {
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      // Default fallback if parsing fails
      return const TimeOfDay(hour: 22, minute: 30); 
    }
  }

  Future<void> _onSave(ParentalSettings newSettings) async {
    await ParentalService.instance.save(newSettings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Parental settings saved'),
        backgroundColor: Colors.grey, // Theme-neutral snackbar
      ),
    );
  }

  // --- NEW: FUNCTION TO RESET PIN ---
  Future<void> _showResetPinDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    // 1. Confirm the reset
    final bool didConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        title: Text('Reset PIN?', style: TextStyle(color: textColor)),
        content: Text(
          'Are you sure you want to reset your Parent PIN? You will be asked to create a new one immediately.',
          style: TextStyle(color: textColor.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: textColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (!didConfirm || !mounted) return;

    // 2. Clear the old PIN
    try {
      await ParentalService.instance.clearPin();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN Cleared. Please create a new one.')),
      );

      // 3. Force creation of a new PIN
      await gate.requireParentPin(
        context,
        reason: 'Create your new 4-digit Parent PIN',
        forceSetupIfMissing: true,
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resetting PIN: $e')),
      );
    }
  }
  // --- END OF NEW FUNCTION ---

  @override
  Widget build(BuildContext context) {
    // --- Read the global theme ---
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final textColor = theme.textTheme.bodyLarge?.color;
    final secondaryTextColor = theme.textTheme.bodyMedium?.color;
    final cardColor = isDark ? (Colors.grey[900] ?? Colors.black) : Colors.white;
    const accentColor = Colors.orange;

    return StreamBuilder<ParentalSettings>(
      stream: _settingsStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            backgroundColor: scaffoldBg,
            body: const Center(child: CircularProgressIndicator(color: accentColor))
          );
        }
        
        _currentSettings = snap.data!;
        final s = _currentSettings!; // Use 's' for brevity

        // --- Apply consistent styling ---
        return Scaffold(
          backgroundColor: scaffoldBg,
          appBar: AppBar(
            title: const Text('Parental Controls'),
            backgroundColor: scaffoldBg,
            elevation: 0,
            titleTextStyle: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            iconTheme: theme.iconTheme,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- Styled SwitchListTile ---
              SwitchListTile(
                title: Text('Child Mode (recommended)', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600)),
                subtitle: Text('Hides sharing, blocks external links, and uses kid-safe defaults', style: TextStyle(color: secondaryTextColor)),
                value: s.childMode,
                onChanged: (v) => _onSave(ParentalSettings(
                  childMode: v,
                  commentsEnabled: s.commentsEnabled,
                  allowedCategories: s.allowedCategories,
                  dailyMinutes: s.dailyMinutes,
                  quietStart: s.quietStart,
                  quietEnd: s.quietEnd,
                  analyticsOptIn: s.analyticsOptIn, // This will just pass the existing value
                )),
                activeColor: accentColor, // Orange switch
                tileColor: cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              const SizedBox(height: 12),
              // --- Styled SwitchListTile ---
              SwitchListTile(
                title: Text('Allow child to post comments', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600)),
                value: s.commentsEnabled,
                onChanged: (v) => _onSave(ParentalSettings(
                  childMode: s.childMode,
                  commentsEnabled: v,
                  allowedCategories: s.allowedCategories,
                  dailyMinutes: s.dailyMinutes,
                  quietStart: s.quietStart,
                  quietEnd: s.quietEnd,
                  analyticsOptIn: s.analyticsOptIn, // This will just pass the existing value
                )),
                activeColor: accentColor, // Orange switch
                tileColor: cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              
              const SizedBox(height: 12),
              // --- Styled ListTile ---
              ListTile(
                title: Text('Quiet hours', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600)),
                subtitle: Text('${s.quietStart} → ${s.quietEnd}', style: TextStyle(color: secondaryTextColor, fontSize: 16)),
                trailing: const Icon(Icons.schedule, color: accentColor), // Orange icon
                tileColor: cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                onTap: () async {
                  final TimeOfDay currentStartTime = _parseTime(s.quietStart);
                  final TimeOfDay currentEndTime = _parseTime(s.quietEnd);

                  final TimeOfDay? newStartTime = await showTimePicker(
                    context: context,
                    initialTime: currentStartTime,
                    helpText: 'Select Quiet Hours Start Time',
                  );

                  if (newStartTime == null) return;

                  if (!mounted) return;
                  final TimeOfDay? newEndTime = await showTimePicker(
                    context: context,
                    initialTime: currentEndTime,
                    helpText: 'Select Quiet Hours End Time',
                  );

                  if (newEndTime == null) return;

                  final String startString = '${newStartTime.hour.toString().padLeft(2, '0')}:${newStartTime.minute.toString().padLeft(2, '0')}';
                  final String endString = '${newEndTime.hour.toString().padLeft(2, '0')}:${newEndTime.minute.toString().padLeft(2, '0')}';

                  await _onSave(ParentalSettings(
                    childMode: s.childMode,
                    commentsEnabled: s.commentsEnabled,
                    allowedCategories: s.allowedCategories,
                    dailyMinutes: s.dailyMinutes,
                    quietStart: startString,
                    quietEnd: endString,
                    analyticsOptIn: s.analyticsOptIn, // This will just pass the existing value
                  ));
                },
              ),
              
              // --- "ALLOW ANALYTICS" TILE REMOVED ---

              // --- "RESET PIN" TILE ADDED ---
              const SizedBox(height: 12),
              ListTile(
                title: Text('Reset Parent PIN', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.key_rounded, color: accentColor),
                tileColor: cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                onTap: _showResetPinDialog,
              ),

              const SizedBox(height: 24),
              Text(
                'Tip: Set or change your PIN by tapping any parent-gated action.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondaryTextColor, fontSize: 14),
              ),
            ],
          ),
        );
      },
    );
  }
}