// lib/screens/categories_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:audio_story_app/models/story_model.dart';
import 'package:audio_story_app/screens/story_player_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_story_app/utils/language_data.dart';
import 'package:audio_story_app/widgets/app_loaders.dart';

/* --------------------------------------------------------------------------
 * Story badge helpers
 * --------------------------------------------------------------------------
 * Some newer stories may store story number in Firestore as a String ("01"),
 * a num (1.0), or under a different key (storyNumber, story_no, etc).
 * We normalize it here so the LANG+NO badge always shows correctly.
 */

int? _coerceInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    final m = RegExp(r'\d+').firstMatch(s);
    if (m != null) return int.tryParse(m.group(0)!);
  }
  return null;
}

int? _storyNoFromData(Map<String, dynamic>? data) {
  if (data == null) return null;
  final v = data['storyNo'] ??
      data['story_no'] ??
      data['storyNumber'] ??
      data['story_number'] ??
      data['number'] ??
      data['no'];
  return _coerceInt(v);
}

String? _langFromData(Map<String, dynamic>? data, {String? fallback}) {
  final v = (data?['language'] ?? data?['lang'] ?? fallback)?.toString();
  if (v == null) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<String> _selectedLanguages = ['en'];
  StreamSubscription? _userSub;

  // Cache category cover lookups to avoid many realtime listeners (reduces scroll lag)
  final Map<String, Future<String?>> _categoryCoverCache = {};

  Future<String?> _getCategoryCover(String langCode, String categoryKey) {
    final lc = langCode.trim().toLowerCase();
    final cacheKey = '$lc|$categoryKey';
    return _categoryCoverCache.putIfAbsent(cacheKey, () async {
      try {
        final qs = await FirebaseFirestore.instance
            .collection('stories')
            .where('language', isEqualTo: lc)
            .where('category', isEqualTo: categoryKey)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();

        if (qs.docs.isEmpty) return null;
        final data = qs.docs.first.data();
        final src = (data['coverImageUrl'] ?? '').toString();
        if (src.isEmpty) return null;
        if (src.startsWith('http')) return src;
        return await _toHttp(src);
      } catch (_) {
        return null;
      }
    });
  }


  @override
  void initState() {
    super.initState();
    _userSub = _userStream().listen((data) {
      if (!mounted) return;
      final List<String> langs = (data['selectedLanguages'] is List)
          ? List<String>.from(data['selectedLanguages'] as List)
          : ['en'];
      if (langs.isEmpty) langs.add('en');
      setState(() {
        _selectedLanguages = langs;
      });
    });
  }

  Stream<Map<String, dynamic>> _userStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((s) => (s.data() ?? {}));
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  // ✨ UPDATED: Requires language
  Query<Map<String, dynamic>> _qCategory({
    required String category,
    required String language,
  }) {
    return FirebaseFirestore.instance
        .collection('stories')
        .where('language', isEqualTo: language)
        .where('category', isEqualTo: category)
        .orderBy('createdAt', descending: true);
  }

  // No-animation route to avoid flicker when opening/closing list pages.

  PageRoute<T> _noAnimRoute<T>(Widget page) {

    return PageRouteBuilder<T>(

      pageBuilder: (context, animation, secondaryAnimation) => page,

      transitionDuration: Duration.zero,

      reverseTransitionDuration: Duration.zero,

      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,

    );

  }

  void _openViewAll({

    required String title,

    required Query<Map<String, dynamic>> base,

    required String orderByField,

  }) {

    Navigator.of(context).push(

      _noAnimRoute<void>(

        _ViewAllPage(

          title: title,

          baseQuery: base,

          orderByField: orderByField,

        ),

      ),

    );

  }
  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    // Global animated background is applied via MaterialApp.builder.
    // Keep this screen transparent so the shared background is visible.
    final Color bg = Colors.transparent;
    final Color onBg = dark ? Colors.white : Colors.black;
    final Color card = dark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Categories', style: TextStyle(color: onBg)),
        iconTheme: IconThemeData(color: onBg),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ✨ NEW: Loop through languages
          ..._selectedLanguages.expand((langCode) {
            final langName = LanguageData.getLanguageName(langCode);
            final langCategories = LanguageData.categoriesByLang[langCode] ?? [];

            if (langCategories.isEmpty) return [const SizedBox.shrink()];

            return [
              const SizedBox(height: 4),
              Center(
                child: Text(
                  langName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: onBg),
                ),
              ),
              const SizedBox(height: 12),
              ...langCategories.map((c) {
                final label = c['label']!;
                final key = c['key']!;
                return _CategoryCard(
                  title: label,
                  categoryKey: key,
                  langCode: langCode, // ✨ NEW
                  coverFuture: _getCategoryCover(langCode, key),
                  onTap: () {
                    _openViewAll(
                      title: label,
                      base: _qCategory(category: key, language: langCode),
                      orderByField: 'createdAt',
                    );
                  },
                  dark: dark,
                  card: card,
                  onBg: onBg,
                );
              }),
            ];
          }).toList(),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final String categoryKey;
  final String langCode; // ✨ NEW
  final Future<String?> coverFuture; // cached cover lookup
  final VoidCallback onTap;
  final bool dark;
  final Color card;
  final Color onBg;

  const _CategoryCard({
    super.key,
    required this.title,
    required this.categoryKey,
    required this.langCode, // ✨ NEW
    required this.coverFuture, // cached cover lookup
    required this.onTap,
    required this.dark,
    required this.card,
    required this.onBg,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> _coverStream() {
    return FirebaseFirestore.instance
        .collection('stories')
        .where('language', isEqualTo: langCode) // ✨ NEW
        .where('category', isEqualTo: categoryKey)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<String?>(
                  future: coverFuture,
                  builder: (context, snap) {
                    final url = snap.data;
                    if (url == null || url.isEmpty) {
                      return Container(color: card);
                    }
                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: card),
                      errorWidget: (_, __, ___) => Container(color: card),
                    );
                  },
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.45),
                        Colors.black.withOpacity(0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: Colors.white,
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

/* ----------------- Common Utility Functions ----------------- */


class _LangNoBadge extends StatelessWidget {
  final String? language;
  final int? storyNo;
  final double scale;

  const _LangNoBadge({
    required this.language,
    required this.storyNo,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final lc = (language ?? '').trim();
    final no = storyNo;
    if (lc.isEmpty && no == null) return const SizedBox.shrink();

    final langLabel = lc.isEmpty ? '' : lc.toUpperCase();
    final noLabel = (no == null) ? '' : no.toString().padLeft(2, '0');

    // Round badge like the reference: language on top, number on bottom.
    // Reduced size slightly per request.
    final langStyle = TextStyle(
      fontSize: 10 * scale,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1.0,
    );

    final noStyle = TextStyle(
      fontSize: 11 * scale,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      height: 1.0,
    );

    final size = 40 * scale; // was larger; now slightly smaller

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (langLabel.isNotEmpty) Text(langLabel, style: langStyle),
          if (langLabel.isNotEmpty && noLabel.isNotEmpty)
            SizedBox(height: 1 * scale),
          if (noLabel.isNotEmpty) Text(noLabel, style: noStyle),
        ],
      ),
    );
  }
}


Future<String?> _toHttp(String p) async {
  if (p.isEmpty) return null;
  p = p.trim(); // ✨ Trim!
  if (p.startsWith('https://')) return p;
  if (p.startsWith('http://')) {
    return 'https://${p.substring('http://'.length)}';
  }
  if (p.startsWith('gs://')) {
    try {
      final ref = FirebaseStorage.instance.refFromURL(p);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }
  return null;
}

// ... (The rest of the file _ViewAllPage etc. logic remains largely the same, just rely on the new _toHttp logic above) ...
// To be brief, I assume you can keep the _ViewAllPage logic from the previous file but update the _getAudioDuration to use the TRIMMED _toHttp.

Future<String> _getAudioDuration(String? gsUrl) async {
  if (gsUrl == null || gsUrl.isEmpty) return '00:00';
  try {
    final downloadUrl = await _toHttp(gsUrl);
    if (downloadUrl == null) return '00:00';
    final player = AudioPlayer();
    final duration = await player.setUrl(downloadUrl);
    await player.dispose();
    if (duration == null) return '00:00';
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  } catch (_) {
    return '--:--';
  }
}

class _ViewAllPage extends StatelessWidget {
  final String title;
  final Query<Map<String, dynamic>> baseQuery;
  final String orderByField;

  const _ViewAllPage({
    required this.title,
    required this.baseQuery,
    required this.orderByField,
  });

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color onBg = dark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title, style: TextStyle(color: onBg)),
        iconTheme: IconThemeData(color: onBg),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: baseQuery.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: AppLoader());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No stories yet'));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc = docs[i];
              final story = Story.fromFirestore(doc);
              final storyNo = _storyNoFromData(doc.data());
              final lang = _langFromData(doc.data(), fallback: story.language);
              return _SquareStoryTile(
                story: story,
                storyNoOverride: storyNo,
                langOverride: lang,
              );
            },
          );
},
      ),
    );
  }
}

class _SquareStoryTile extends StatelessWidget {
  final Story story;
  final int? storyNoOverride;
  final String? langOverride;

  const _SquareStoryTile({
    required this.story,
    this.storyNoOverride,
    this.langOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          storyPlayerRoute(story.id),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: FutureBuilder<String?>(
                  future: _toHttp(story.coverImageUrl),
                  builder: (context, s) {
                    final url = s.data;
                    if (s.connectionState == ConnectionState.waiting) {
                      return Container(color: Colors.black12);
                    }
                    if (url == null) {
                      return Container(color: Colors.black12);
                    }
                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: Colors.black12),
                      errorWidget: (context, url, error) => Container(color: Colors.black12),
                    );
                  },
                ),
              ),

              // Subtle glossy sheen (no title text)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.10),
                        Colors.transparent,
                        Colors.black.withOpacity(0.10),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),

              // Language + story number badge (bottom-left)
              Positioned(
                left: 10,
                bottom: 10,
                child: _LangNoBadge(
                  language: (story.language != null && story.language!.trim().isNotEmpty)
                      ? story.language
                      : langOverride,
                  storyNo: story.storyNo ?? storyNoOverride,
                  scale: 0.7,
                ),
              ),

              // Thin card border for a clean grid look
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.14), width: 1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

