import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:audio_story_app/widgets/background_container.dart';
import 'package:audio_story_app/utils/app_theme.dart';
import 'package:audio_story_app/screens/onboarding_screen.dart'; // Child details screen

class MasterProfileScreen extends StatefulWidget {
  const MasterProfileScreen({Key? key}) : super(key: key);

  @override
  State<MasterProfileScreen> createState() => _MasterProfileScreenState();
}

class _MasterProfileScreenState extends State<MasterProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _relationship;
  bool _confirm = false;

  // --- REMOVED AVATAR/PHOTO VARIABLES ---

  static const _relationships = <String>[
    'Mother',
    'Father',
    'Guardian',
    'Grandparent',
    'Relative',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    if (u?.email != null) {
      _emailCtrl.text = u!.email!;
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // --- REMOVED _pickAndUpload and _uploadToStorage METHODS ---

  InputDecoration _pillInput(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.black.withOpacity(0.65),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffixIcon != null
          ? Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: suffixIcon,
            )
          : null,
      suffixIconColor: Colors.white70,
      hintStyle: TextStyle(
        color: Colors.white70,
        fontFamily: AppTheme.bodyFont,
        fontSize: 18.0,
      ),
    );
  }

  Future<void> _saveAndNext() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please confirm you are the parent/guardian.')),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'guardian': {
          'firstName': _firstCtrl.text.trim(),
          'lastName': _lastCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'relationship': _relationship,
          // --- REMOVED photoUrl LINE ---
          'confirmedGuardian': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${e.message ?? e.code}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- REMOVED avatarChild WIDGET LOGIC ---

    const textInputStyle = TextStyle(
      color: Colors.white,
      fontFamily: AppTheme.bodyFont,
      fontSize: 20.0,
    );

    return BackgroundContainer(
      imagePath: 'assets/backgrounds/master_profile.jpg',
      dimOpacity: 0.12,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Card(
                  color: Colors.black.withOpacity(0.35),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Master Profile',
                            style: TextStyle(
                              fontFamily: AppTheme.headingFont,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          // --- REMOVED PROFILE PICTURE STACK AND SIZED BOXES ---
                          const SizedBox(height: 24), // Added padding to top
                          TextFormField(
                            controller: _firstCtrl,
                            style: textInputStyle,
                            textAlign: TextAlign.center,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _pillInput('First Name',
                                suffixIcon: const Icon(Icons.person_outline)),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter first name'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _lastCtrl,
                            style: textInputStyle,
                            textAlign: TextAlign.center,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _pillInput('Last Name',
                                suffixIcon: const Icon(Icons.person_outline)),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter last name'
                               : null,
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String?>(
                            value: _relationship,
                            style: textInputStyle,
                            iconEnabledColor: Colors.white70,
                            dropdownColor: Colors.grey[850],
                            alignment: Alignment.center,
                            items: _relationships
                                .map((r) => DropdownMenuItem(
                                    value: r,
                                    child: Center(
                                        child: Text(r,
                                            style: textInputStyle.copyWith(
                                                color: Colors.white)))))
                                .toList(),
                            onChanged: (v) => setState(() => _relationship = v),
                            decoration: _pillInput('Select Relationship',
                                suffixIcon:
                                    const Icon(Icons.keyboard_arrow_down)),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Select a relationship'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailCtrl,
                            style: textInputStyle,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _pillInput('Email',
                                suffixIcon:
                                    const Icon(Icons.alternate_email)),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Checkbox(
                                value: _confirm,
                                onChanged: (v) =>
                                    setState(() => _confirm = v ?? false),
                                activeColor: Colors.white,
                                checkColor: Colors.black,
                                side: const BorderSide(color: Colors.white),
                              ),
                              Expanded(
                                child: Text(
                                  'I confirm that I am the parent or legal guardian of the child',
                                  textAlign: TextAlign.left,
                                  style: textInputStyle.copyWith(
                                    color: Colors.white,
                                    fontSize: 15.0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _saveAndNext,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28)),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontFamily: AppTheme.bodyFont,
                                ),
                              ),
                              child: const Text('Create'),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}