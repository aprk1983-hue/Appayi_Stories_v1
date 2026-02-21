// lib/screens/language_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:audio_story_app/widgets/background_container.dart';
import 'package:audio_story_app/main.dart' show AuthGate;
import 'package:audio_story_app/utils/app_theme.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({Key? key}) : super(key: key);

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  // Store a list of selected language codes
  final List<String> _selected = ['en']; 
  bool _saving = false;

  // Master list of languages
  final _langs = const [
    _LangCard(title: 'English', code: 'en'),
    _LangCard(title: 'हिन्दी (Hindi)', code: 'hi'),
    _LangCard(title: 'தமிழ் (Tamil)', code: 'ta'),
   // _LangCard(title: 'മലയാളം (Malayalam)', code: 'ml'),
   // _LangCard(title: 'తెలుగు (Telugu)', code: 'te'),
   // _LangCard(title: 'ಕನ್ನಡ (Kannada)', code: 'kn'),
  ];

  Future<void> _saveLanguage() async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not signed in');

      // Save the list to 'selectedLanguages'
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'selectedLanguages': _selected,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const AuthGate(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (r) => false,
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${e.message ?? e.code}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundContainer(
      imagePath: 'assets/backgrounds/login_bg_purple.png',
      dimOpacity: 0.15,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Select Languages'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  'Choose your languages',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.headingFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _langs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final l = _langs[index];
                          final selected = _selected.contains(l.code);
                          return _LanguageTile(
                            title: l.title,
                            selected: selected,
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  // Don't allow unselecting the last item
                                  if (_selected.length == 1) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'At least one language must be selected.')),
                                    );
                                    return;
                                  }
                                  _selected.remove(l.code);
                                } else {
                                  _selected.add(l.code);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveLanguage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          foregroundColor: Colors.orangeAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Next'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LangCard {
  final String title;
  final String code;
  const _LangCard({required this.title, required this.code});
}

class _LanguageTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    Key? key,
    required this.title,
    required this.selected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? Colors.orangeAccent : Colors.white.withOpacity(0.12),
            width: selected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(context).primaryTextTheme.titleLarge,
              ),
              const Spacer(),
              Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: selected ? Colors.orangeAccent : Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}