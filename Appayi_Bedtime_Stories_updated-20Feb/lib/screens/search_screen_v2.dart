// lib/screens/search_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:audio_story_app/screens/story_player_screen.dart';
import 'package:audio_story_app/models/story_model.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _q = '';

  Stream<QuerySnapshot<Map<String, dynamic>>> _allStories() {
    // We’ll only subscribe to this stream AFTER user types something.
    return FirebaseFirestore.instance.collection('stories').limit(50).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    // Global animated background is applied via MaterialApp.builder.
    // Keep this screen transparent so the shared background is visible.
    final Color bg = Colors.transparent;
    final Color onBg = dark ? Colors.white : Colors.black;
    final Color card = dark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Search Stories', style: TextStyle(color: onBg)),
        iconTheme: IconThemeData(color: onBg),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(28)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                style: TextStyle(color: onBg),
                decoration: InputDecoration(
                  hintText: 'Search your stories here',
                  hintStyle: TextStyle(color: onBg.withOpacity(0.7)),
                  border: InputBorder.none,
                  suffixIcon: Icon(Icons.search, color: onBg.withOpacity(0.7)),
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 12),

            // Only show results AFTER there's a query
            Expanded(
              child: _q.isEmpty
                  ? Center(
                      child: Text(
                        'Type something to search…',
                        style: TextStyle(color: onBg.withOpacity(0.7)),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _allStories(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snap.hasData) return const SizedBox.shrink();

                        final stories = snap.data!.docs
                            .map((d) => Story.fromFirestore(d))
                            .where((s) => s.title.toLowerCase().contains(_q))
                            .toList();

                        if (stories.isEmpty) {
                          return Center(
                            child: Text('No stories match your search', style: TextStyle(color: onBg)),
                          );
                        }

                        return ListView.separated(
                          itemCount: stories.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _SearchItem(story: stories[i], dark: dark),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchItem extends StatelessWidget {
  final Story story;
  final bool dark;
  const _SearchItem({required this.story, required this.dark});

  Future<String?> _toHttp(String p) async {
    if (p.isEmpty) return null;
    p = p.trim();
    if (p.startsWith('https://')) return p;
    if (p.startsWith('http://')) return 'https://${p.substring('http://'.length)}';
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

  @override
  Widget build(BuildContext context) {
    final textColor = dark ? Colors.white : Colors.black;
    final card = dark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.06);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        storyPlayerRoute(story.id),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: card,
          child: Row(
            children: [
              SizedBox(
                height: 84,
                width: 84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FutureBuilder<String?>(
                    future: _toHttp(story.coverImageUrl),
                    builder: (context, s) {
                      final url = s.data;
                      if (s.connectionState == ConnectionState.waiting || url == null || url.isEmpty) {
                        return Container(color: Colors.grey[700]);
                      }
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Container(color: Colors.grey[700]),
                          ),
],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  story.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------
//  Thumbnail Badges
// -------------------------


class _LangNoBadge extends StatelessWidget {
  final String? lang;
  final String? number;

  const _LangNoBadge({this.lang, this.number});

  @override
  Widget build(BuildContext context) {
    final l = (lang ?? '').trim();
    final n = (number ?? '').trim();
    if (l.isEmpty && n.isEmpty) return const SizedBox.shrink();

    const double size = 44;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
      ),
      child: Center(
        child: (l.isNotEmpty && n.isNotEmpty)
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      n,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                l.isNotEmpty ? l : n,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  height: 1.0,
                ),
              ),
      ),
    );
  }
}

class _StoryNumberBadge extends StatelessWidget {
  final String label;
  const _StoryNumberBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.80),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LangBadge extends StatelessWidget {
  final String label;
  const _LangBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
