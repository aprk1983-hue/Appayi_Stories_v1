import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart'; // Corrected import
import 'package:firebase_auth/firebase_auth.dart'; // Corrected import
import 'package:cloud_firestore/cloud_firestore.dart'; // Corrected import
import 'package:image_picker/image_picker.dart'; // Corrected import
import 'package:firebase_storage/firebase_storage.dart'; // Corrected import

// --- FIXED THESE IMPORTS ---
import 'package:audio_story_app/widgets/background_container.dart';
import 'package:audio_story_app/utils/app_theme.dart';
import 'package:audio_story_app/main.dart' show AuthGate;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _childNameCtrl = TextEditingController();
  final _nickNameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  String _gender = 'Boy';

  // Photo state
  final _picker = ImagePicker();
  Uint8List? _previewBytes;
  String? _photoUrl;
  bool _uploadingPhoto = false;

  static const _avatarAssets = <String>[
    'assets/avatars/cute_baby_1.png',
    'assets/avatars/cute_baby_2.png',
    'assets/avatars/cute_baby_3.png',
    'assets/avatars/cute_baby_4.png',
  ];
  late final String _placeholderAvatar =
      _avatarAssets[Random().nextInt(_avatarAssets.length)];

  bool _saving = false;
  // --- REMOVED AUTH LISTENER ---

  // @override
  // void initState() {
  //   super.initState();
  //   // --- REMOVED AUTH LISTENER LOGIC ---
  // }

  @override
  void dispose() {
    // --- REMOVED AUTH LISTENER CANCEL ---
    _childNameCtrl.dispose();
    _nickNameCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _showImagePickerSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            runSpacing: 8,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text('Take Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndUpload(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndUpload(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (x == null) return;

    final bytes = await x.readAsBytes();
    setState(() => _previewBytes = bytes);

    await _uploadToStorage(bytes,
        x.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
  }

  Future<void> _uploadToStorage(Uint8List data, String contentType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return;
    }

    setState(() => _uploadingPhoto = true);
    try {
      final path =
          'users/${user.uid}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putData(data, SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'child': {'photoUrl': url, 'updatedAt': FieldValue.serverTimestamp()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() => _photoUrl = url);
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _saveAndNext() async {
    if (!_formKey.currentState!.validate()) return;

    final age = int.tryParse(_ageCtrl.text.trim());
    if (age == null || age <= 0 || age > 18) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid age (1-18).')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      final uid = user.uid;
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);

      await ref.set({
        'child': {
          'name': _childNameCtrl.text.trim(),
          'nickName': _nickNameCtrl.text.trim().isEmpty
              ? null
              : _nickNameCtrl.text.trim(),
          'age': age,
          'gender': _gender,
          if (_photoUrl != null) 'photoUrl': _photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'isProfileComplete': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      // --- Navigation fix to prevent "white flash" ---
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const AuthGate(),
          // Make the transition instant
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
        (r) => false,
      );
      // --- End of navigation fix ---
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _pillInput(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.black.withOpacity(0.65),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      hintStyle: TextStyle(
        color: Colors.white70,
        fontFamily: AppTheme.bodyFont,
        fontSize: 18.0,
      ),
    );
  }

  // --- ✨ FULLY UPDATED DARK GENDER SHEET ---
  Future<void> _showGenderSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: const Color(0xFF1A1A1A), // ✨ CHANGED: Dark background
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        Widget option({
          required String label,
          required String asset,
          required bool selected,
          required VoidCallback onTap,
          Color activeColor = const Color(0xFFFFA726),
        }) {
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(60),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? activeColor.withOpacity(0.2)
                        : Colors.grey.shade800, // ✨ CHANGED
                    border: Border.all(
                      color: selected
                          ? activeColor
                          : Colors.grey.shade600, // ✨ CHANGED
                      width: selected ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: ClipOval(
                    child: Image.asset(
                      asset,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                          label == 'Boy' ? Icons.boy : Icons.girl,
                          size: 40,
                          color: Colors.grey.shade400), // ✨ CHANGED
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    color: Colors.white, // ✨ CHANGED
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white30, // ✨ CHANGED
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              Text(
                'Select Gender',
                style: TextStyle(
                  fontFamily: AppTheme.headingFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white, // ✨ CHANGED
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  option(
                    label: 'Boy',
                    asset: 'assets/avatars/baby_boy.png',
                    selected: _gender == 'Boy',
                    onTap: () {
                      setState(() => _gender = 'Boy');
                      Navigator.pop(context);
                    },
                  ),
                  option(
                    label: 'Girl',
                    asset: 'assets/avatars/baby_girl.png',
                    selected: _gender == 'Girl',
                    onTap: () {
                      setState(() => _gender = 'Girl');
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
  // --- END OF UPDATED GENDER SHEET ---

  @override
  Widget build(BuildContext context) {
    Widget avatarChild;
    if (_previewBytes != null) {
      avatarChild = ClipOval(
          child: Image.memory(_previewBytes!,
              width: 112, height: 112, fit: BoxFit.cover));
    } else if (_photoUrl != null) {
      avatarChild = ClipOval(
        child: Image.network(_photoUrl!,
            width: 112,
            height: 112,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.emoji_emotions,
                size: 56, color: Colors.white)),
      );
    } else {
      avatarChild = ClipOval(
        child: Image.asset(
          _placeholderAvatar,
          width: 112,
          height: 112,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.emoji_emotions, size: 56, color: Colors.white),
        ),
      );
    }

    const textInputStyle = TextStyle(
      color: Colors.white,
      fontFamily: AppTheme.bodyFont,
      fontSize: 20.0,
    );

    return BackgroundContainer(
      imagePath: 'assets/backgrounds/child_details.jpg',
      dimOpacity: 0.15,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'Child Details',
            style: TextStyle(
              fontFamily: AppTheme.headingFont,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
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
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.15),
                              ),
                              child: avatarChild,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: _uploadingPhoto
                                    ? null
                                    : _showImagePickerSheet,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: _uploadingPhoto
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(Icons.camera_alt,
                                          size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Upload Profile Photo',
                          style: Theme.of(context)
                              .primaryTextTheme
                              .labelLarge
                              ?.copyWith(
                                fontFamily: AppTheme.bodyFont,
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _childNameCtrl,
                          style: textInputStyle,
                          textAlign: TextAlign.center,
                          textCapitalization: TextCapitalization.characters,
                          decoration: _pillInput('Child\'s Name'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter a name'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _nickNameCtrl,
                          style: textInputStyle,
                          textAlign: TextAlign.center,
                          textCapitalization: TextCapitalization.characters,
                          decoration: _pillInput('Child\'s Nick Name'),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _ageCtrl,
                          keyboardType: TextInputType.number,
                          style: textInputStyle,
                          textAlign: TextAlign.center,
                          decoration: _pillInput('Age (years)'),
                          validator: (v) {
                            final age = int.tryParse(v?.trim() ?? '');
                            if (age == null || age <= 0 || age > 18)
                              return 'Enter a valid age (1-18)';
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        InkWell(
                          onTap: _showGenderSheet,
                          borderRadius: BorderRadius.circular(28),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 24),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Row(
                              children: [
                                ClipOval(
                                  child: Image.asset(
                                    _gender == 'Boy'
                                        ? 'assets/avatars/baby_boy.png'
                                        : 'assets/avatars/baby_girl.png',
                                    width: 28,
                                    height: 28,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                        _gender == 'Boy'
                                            ? Icons.boy
                                            : Icons.girl,
                                        color: Colors.white70),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _gender,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 20.0,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down,
                                    color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveAndNext,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28)),
                              textStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFamily: AppTheme.bodyFont,
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Next'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
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
