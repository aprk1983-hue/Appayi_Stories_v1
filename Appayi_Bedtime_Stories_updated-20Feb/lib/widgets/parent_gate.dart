// lib/widgets/parent_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_story_app/services/parental_service.dart';

bool _pinVerifiedThisRun = false;

/// Ask for parent PIN once per app run.
/// If no PIN exists and [forceSetupIfMissing] is true, prompt to create one.
Future<bool> requireParentPinOnce(
  BuildContext context, {
  String reason = 'Parent PIN required',
  bool forceSetupIfMissing = false,
}) async {
  if (_pinVerifiedThisRun) return true;
  final ok = await _showPinGate(
    context,
    reason: reason,
    forceSetupIfMissing: forceSetupIfMissing,
  );
  if (ok) _pinVerifiedThisRun = true;
  return ok;
}

/// Always ask (ignores in-session cache).
Future<bool> requireParentPin(
  BuildContext context, {
  String reason = 'Parent PIN required',
  bool forceSetupIfMissing = false,
}) {
  return _showPinGate(
    context,
    reason: reason,
    forceSetupIfMissing: forceSetupIfMissing,
  );
}

Future<bool> _showPinGate(
  BuildContext context, {
  required String reason,
  required bool forceSetupIfMissing,
}) async {
  final hasPin = await ParentalService.instance.hasPin();
  return await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _PinDialog(
          reason: reason,
          hasPin: hasPin,
          forceSetupIfMissing: forceSetupIfMissing,
        ),
      ) ??
      false;
}

class _PinDialog extends StatefulWidget {
  final String reason;
  final bool hasPin;
  final bool forceSetupIfMissing;
  const _PinDialog({
    required this.reason,
    required this.hasPin,
    required this.forceSetupIfMissing,
  });

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _pin1 = TextEditingController();
  final TextEditingController _pin2 = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _creating = !widget.hasPin && widget.forceSetupIfMissing;
  }

  @override
  void dispose() {
    _pin1.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_creating) {
        final p1 = _pin1.text.trim();
        final p2 = _pin2.text.trim();
        if (p1.length != 4 || p2.length != 4) {
          _error = 'Enter 4 digits in both fields.';
        } else if (p1 != p2) {
          _error = 'PINs do not match.';
        } else {
          // Create brand new PIN
          await ParentalService.instance.setNewPin(p1);
          Navigator.of(context).pop(true);
          return;
        }
      } else {
        final pin = _pin1.text.trim();
        if (pin.length != 4) {
          _error = 'Enter your 4-digit PIN.';
        } else {
          final ok = await ParentalService.instance.verifyOrSetPin(
            pin,
            allowSetIfEmpty: false,
          );
          if (ok) {
            Navigator.of(context).pop(true);
            return;
          } else {
            _error = 'Incorrect PIN.';
          }
        }
      }
    } catch (_) {
      _error = 'Something went wrong. Please try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ParentalService.instance.clearPin();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN reset. Please create a new one.')),
        );
      }
      setState(() {
        _creating = true;
        _pin1.clear();
        _pin2.clear();
      });
    } catch (_) {
      setState(() => _error = 'Could not reset PIN.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1E1E1E);
    const cyan = Color(0xFF00FFFF);
    const orange = Color(0xFFFFA726);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: cyan.withOpacity(0.18),
              blurRadius: 30,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _creating ? 'Create Parent PIN' : 'Parent PIN',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _PinField(
                    controller: _pin1,
                    hint: _creating ? 'Enter new 4-digit PIN' : 'Enter 4-digit PIN',
                  ),
                ),
              ],
            ),
            if (_creating) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _PinField(
                      controller: _pin2,
                      hint: 'Re-enter PIN',
                    ),
                  ),
                ],
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),

            if (!_creating) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _resetPin,
                child: const Text('Reset PIN', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _PinField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00FFFF);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      style: const TextStyle(color: Colors.white, letterSpacing: 6, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF121212),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cyan),
        ),
      ),
    );
  }
}
