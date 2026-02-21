// lib/screens/playlists_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:audio_story_app/screens/story_player_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _auth = FirebaseAuth.instance;
  final String _defaultPlaylistId = 'default';

  // TODO: Put your image in assets and update this path if needed.
  static const bool _useAssetBackground = false;

  static const String _bgAsset = 'assets/backgrounds/playlist_bg.jpg';

  Future<String?> _toHttp(String p) async {
    if (p.isEmpty) return null;
    if (p.startsWith('http')) return p;
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

  // Primary: users/{uid}/playlists/default/items
  Stream<QuerySnapshot<Map<String, dynamic>>> _playlistStreamPrimary() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('playlists')
        .doc(_defaultPlaylistId)
        .collection('items')
        .orderBy('addedAt', descending: true)
        .snapshots();
  }

  // Fallback: users/{uid}/playlist/items  (singular "playlist")
  Stream<QuerySnapshot<Map<String, dynamic>>> _playlistStreamFallback() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('playlist')
        .doc(_defaultPlaylistId)
        .collection('items')
        .orderBy('addedAt', descending: true)
        .snapshots();
  }

  // Fetch stories by IDs (chunked whereIn)
  Future<Map<String, Map<String, dynamic>>> _fetchStoriesByIds(
      List<String> ids) async {
    final Map<String, Map<String, dynamic>> out = {};
    const int chunk = 10; // Firestore whereIn limit
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, i + (i + chunk > ids.length ? ids.length - i : chunk));
      final snap = await FirebaseFirestore.instance
          .collection('stories')
          .where(FieldPath.documentId, whereIn: part)
          .get();
      for (final d in snap.docs) {
        out[d.id] = d.data();
      }
    }
    return out;
  }

  Future<void> _removeStory(String storyId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    Future<void> _try(String pathPluralOrSingular) async {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(pathPluralOrSingular) // 'playlists' OR 'playlist'
          .doc(_defaultPlaylistId)
          .collection('items')
          .doc(storyId)
          .delete();
    }

    try {
      // Try both structures; ignore errors for the one that doesn't exist
      await _try('playlists');
    } catch (_) {}
    try {
      await _try('playlist');
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Story removed from playlist')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color onBg = dark ? Colors.white : Colors.black;

    return _OptionalAssetBackground(
      enabled: _useAssetBackground,
      assetPath: _bgAsset,
      overlayOpacity: 0.25,
      child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('My Playlist',
            style: TextStyle(color: onBg, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: onBg),
          ),
          body: StreamBuilder<User?>(
            stream: _auth.authStateChanges(),
            builder: (context, userSnap) {
              if (!userSnap.hasData || userSnap.data == null) {
                return Center(
                  child: Text(
                    'Please log in to view your playlist.',
                    style: TextStyle(color: onBg.withOpacity(0.7)),
                  ),
                );
              }

              // Primary stream
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _playlistStreamPrimary(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // If primary is empty, try fallback structure
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _playlistStreamFallback(),
                      builder: (context, fb) {
                        if (fb.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!fb.hasData || fb.data!.docs.isEmpty) {
                          return Center(
                            child: Text(
                              'Your playlist is empty. Add some stories!',
                              style: TextStyle(color: onBg.withOpacity(0.7)),
                            ),
                          );
                        }
                        return _PlaylistList(
                          itemDocs: fb.data!.docs,
                          toHttp: _toHttp,
                          onRemove: _removeStory,
                        );
                      },
                    );
                  }

                  // Use primary
                  return _PlaylistList(
                    itemDocs: snap.data!.docs,
                    toHttp: _toHttp,
                    onRemove: _removeStory,
                  );
                },
              );
            },
          ),
        ),
    );
  }
}

class _OptionalAssetBackground extends StatelessWidget {
  final bool enabled;
  final String assetPath;
  final Widget child;
  final double overlayOpacity;

  const _OptionalAssetBackground({
    required this.enabled,
    required this.assetPath,
    required this.child,
    this.overlayOpacity = 0.25,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(assetPath, fit: BoxFit.cover),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withOpacity(overlayOpacity)),
        ),
        child,
      ],
    );
  }
}


class _PlaylistList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> itemDocs;
  final Future<String?> Function(String) toHttp;
  final Future<void> Function(String) onRemove;

  const _PlaylistList({
    required this.itemDocs,
    required this.toHttp,
    required this.onRemove,
  });

  List<String> _collectStoryIds() {
    return itemDocs.map((d) {
      final data = d.data();
      final sidField = data['storyId'];
      final sid = (sidField is String && sidField.isNotEmpty) ? sidField : d.id;
      return sid;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color onBg = dark ? Colors.white : Colors.black;

    final ids = _collectStoryIds();

    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: _fetchStories(ids),
      builder: (context, storySnap) {
        final byId = storySnap.data ?? const {};

        if (storySnap.connectionState == ConnectionState.waiting &&
            byId.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: itemDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final item = itemDocs[i];
            final data = item.data();
            final storyId = (data['storyId'] is String && (data['storyId'] as String).isNotEmpty)
                ? data['storyId'] as String
                : item.id;

            // Prefer canonical story doc fields if available
            final storyData = byId[storyId] ?? {};
            final title = (storyData['title'] ??
                    data['title'] ??
                    'Untitled Story')
                .toString();
            final cover = (storyData['coverImageUrl'] ??
                    data['coverImageUrl'] ??
                    '')
                .toString();

            final rawNo = storyData['storyNo'] ?? data['storyNo'];
            final int? storyNo = (rawNo is num)
                ? rawNo.toInt()
                : int.tryParse(rawNo?.toString() ?? '');
            final String? language = (storyData['language'] ?? data['language'])?.toString();

            return _PlaylistItemTile(
              storyId: storyId,
              title: title,
              coverImageUrl: cover,
              storyNo: storyNo,
              language: language,
              onRemove: () => onRemove(storyId),
              toHttp: toHttp,
            );
          },
        );
      },
    );
  }

  Future<Map<String, Map<String, dynamic>>> _fetchStories(
      List<String> ids) async {
    // Chunked whereIn queries
    final Map<String, Map<String, dynamic>> out = {};
    const int chunk = 10;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, i + (i + chunk > ids.length ? ids.length - i : chunk));
      final snap = await FirebaseFirestore.instance
          .collection('stories')
          .where(FieldPath.documentId, whereIn: part)
          .get();
      for (final d in snap.docs) {
        out[d.id] = d.data();
      }
    }
    return out;
  }
}

class _PlaylistItemTile extends StatelessWidget {
  final String storyId;
  final String title;
  final String coverImageUrl;
  final int? storyNo;
  final String? language;
  final VoidCallback onRemove;
  final Future<String?> Function(String) toHttp;

  const _PlaylistItemTile({
    required this.storyId,
    required this.title,
    required this.coverImageUrl,
    this.storyNo,
    this.language,
    required this.onRemove,
    required this.toHttp,
  });

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color onBg = dark ? Colors.white : Colors.black;
    final Color inactive = dark ? Colors.white70 : Colors.black54;

    final String lang = (language ?? '').trim();
    final String no = (storyNo == null) ? '' : '#${storyNo!}';
    final String subtitle = [no, if (lang.isNotEmpty) lang.toUpperCase()]
        .where((s) => s.isNotEmpty)
        .join(' • ');

    return InkWell(
      onTap: () => Navigator.push(
        context,
        storyPlayerRoute(storyId),
      ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: dark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            FutureBuilder<String?>(
              future: toHttp(coverImageUrl),
              builder: (context, s) {
                final url = s.data;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: (url == null || url.isEmpty)
                        ? Container(color: Colors.grey.shade800)
                        : CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (context, _) =>
                                Container(color: Colors.grey.shade800),
                            errorWidget: (context, _, __) =>
                                Container(color: Colors.grey.shade800),
                          ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onBg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: inactive,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: Icon(Icons.delete_outline_rounded, color: inactive),
              onPressed: onRemove,
            ),
          ],
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
