// lib/screens/downloaded_stories_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:audio_story_app/models/story_model.dart';
import 'package:audio_story_app/screens/story_player_screen.dart';
import 'package:audio_story_app/services/offline_story_store.dart';

class DownloadedStoriesScreen extends StatefulWidget {
  const DownloadedStoriesScreen({super.key});

  @override
  State<DownloadedStoriesScreen> createState() => _DownloadedStoriesScreenState();
}

class _DownloadedStoriesScreenState extends State<DownloadedStoriesScreen> {
  late Future<List<Story>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadDownloadedStories();
  }

  Future<List<Story>> _loadDownloadedStories() async {
    final ids = await OfflineStoryStore.instance.getDownloadedStoryIds();
    if (ids.isEmpty) return <Story>[];

    final idList = ids.toList();
    final List<Story> out = [];

    // Firestore whereIn supports up to 10 values per query.
    for (int i = 0; i < idList.length; i += 10) {
      final chunk = idList.sublist(i, (i + 10) > idList.length ? idList.length : (i + 10));
      final snap = await FirebaseFirestore.instance
          .collection('stories')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snap.docs) {
        try {
          out.add(Story.fromFirestore(doc));
        } catch (_) {
          // If Story model changes, skip broken docs rather than crashing.
        }
      }
    }

    // Keep a stable order (optional): sort by title
    out.sort((a, b) => (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()));
    return out;
  }

  Route _smoothRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        final offset = Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: offset, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    );
  }

  Future<void> _refresh() async {
    await OfflineStoryStore.instance.refreshDownloadedStoryIds();
    if (!mounted) return;
    setState(() {
      _future = _loadDownloadedStories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloaded Stories'),
        backgroundColor: bg,
        elevation: 0,
      ),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: OfflineStoryStore.instance.downloadedStoryIds,
        builder: (context, ids, _) {
          return FutureBuilder<List<Story>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final stories = snapshot.data ?? <Story>[];
              if (stories.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_done_rounded, size: 56, color: isDark ? Colors.white70 : Colors.black45),
                        const SizedBox(height: 12),
                        Text(
                          'No downloaded stories yet',
                          style: TextStyle(fontSize: 18, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Download a story from the player to listen offline.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        )
                      ],
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: stories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final s = stories[i];
                    final storyId = s.id;
                    final downloaded = ids.contains(storyId);

                    return _DownloadedStoryRow(
                      story: s,
                      downloaded: downloaded,
                      onPlay: () {
                        Navigator.of(context).push(_smoothRoute(StoryPlayerScreen(storyId: storyId)));
                      },
                      onRemove: () async {
                        await OfflineStoryStore.instance.deleteStoryDownloads(storyId);
                        await _refresh();
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DownloadedStoryRow extends StatelessWidget {
  final Story story;
  final bool downloaded;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  const _DownloadedStoryRow({
    required this.story,
    required this.downloaded,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF141A22) : const Color(0xFFF3F5F8);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPlay,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _CoverThumb(story: story),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title ?? 'Story',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (downloaded)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white12 : Colors.black12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_done_rounded, size: 16, color: isDark ? Colors.white70 : Colors.black54),
                              const SizedBox(width: 6),
                              Text(
                                'Downloaded',
                                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      if ((story.category ?? '').trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          story.category!,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove download',
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline_rounded, color: isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 4),
            Icon(Icons.play_circle_fill_rounded, size: 34, color: isDark ? Colors.white : Colors.black87),
          ],
        ),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final Story story;
  const _CoverThumb({required this.story});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black12,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.auto_stories_rounded, color: isDark ? Colors.white60 : Colors.black45),
    );

    final url = (story.coverImageUrl ?? '').trim();
    if (url.isEmpty) return placeholder;

    return FutureBuilder<String?>(
      future: OfflineStoryStore.instance.resolveLocalCoverPath(storyId: story.id, remoteUrl: url),
      builder: (context, snap) {
        final localPath = snap.data;
        if (localPath != null && localPath.isNotEmpty && File(localPath).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(localPath), width: 68, height: 68, fit: BoxFit.cover),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: url,
            width: 68,
            height: 68,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          ),
        );
      },
    );
  }
}
