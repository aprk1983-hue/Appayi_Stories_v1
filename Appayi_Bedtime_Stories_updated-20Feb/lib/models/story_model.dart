import 'package:cloud_firestore/cloud_firestore.dart';

class StoryScriptItem {
  final String type;
  final String? audioUrl;
  final String? text;
  final int? pauseDurationMs;

  StoryScriptItem({
    required this.type,
    this.audioUrl,
    this.text,
    this.pauseDurationMs,
  });

  factory StoryScriptItem.fromJson(Map<String, dynamic> json) {
    final t = (json['type'] ?? '').toString().trim().toLowerCase();
    return StoryScriptItem(
      type: t.isEmpty ? 'audio' : t,
      // .trim() to remove invisible spaces that can break players
      audioUrl: (json['audioUrl'] ?? json['url'] ?? '').toString().trim(),
      text: (json['text'] ?? '').toString(),
      pauseDurationMs: (json['pauseDurationMs'] is int)
          ? json['pauseDurationMs'] as int
          : (json['pause'] is int ? json['pause'] as int : null),
    );
  }
}

class Story {
  final String id;
  final String title;
  final String? category;

  /// Language code like: EN, TA, HI, etc.
  final String? language;

  /// Cover image URL for the thumbnail / hero image.
  final String coverImageUrl;

  /// Legacy single audio URL (if your story has just one audio file).
  final String audioUrl;

  /// Timeline script (audio/text/pause). Kept dynamic for backwards compatibility.
  final List<dynamic> audioScript;

  /// OPTIONAL: Permanent upload sequence number (1..N).
  /// Use this to show: 01 / 02 / ... / 100 on thumbnails.
  final int? storyNo;

  /// OPTIONAL: Story creation/upload time.
  final DateTime? createdAt;

  const Story({
    required this.id,
    required this.title,
    required this.coverImageUrl,
    required this.audioUrl,
    required this.audioScript,
    this.category,
    this.language,
    this.storyNo,
    this.createdAt,
  });

  factory Story.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    // Support audioScript stored as List OR Map
    final audioScriptField = data['audioScript'];
    final List<dynamic> resolvedAudioScript = audioScriptField is List
        ? audioScriptField
        : (audioScriptField is Map ? audioScriptField.values.toList() : <dynamic>[]);

    // Prefer explicit audioUrl, else infer from first script item (if present)
    String? resolvedAudioUrl = data['audioUrl']?.toString();
    if ((resolvedAudioUrl == null || resolvedAudioUrl.trim().isEmpty) &&
        resolvedAudioScript.isNotEmpty) {
      final first = resolvedAudioScript.first;
      if (first is Map) {
        resolvedAudioUrl = (first['audioUrl'] ?? first['url'])?.toString();
      }
    }

    // storyNo can be stored with different keys/types, OR it can be inferred from URL paths like:
    // https://.../stories/en/Adventure/045/main.mp3  => 45
    int? parsedStoryNo;

    dynamic pickFirst(List<String> keys) {
      for (final k in keys) {
        if (data.containsKey(k) && data[k] != null) return data[k];
      }
      return null;
    }

    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) return null;
        final direct = int.tryParse(s);
        if (direct != null) return direct;
        final m = RegExp(r'(\d{1,4})').firstMatch(s);
        return m == null ? null : int.tryParse(m.group(1)!);
      }
      return null;
    }

    // 1) Direct fields (best)
    final rawNo = pickFirst(<String>[
      'storyNo',
      'story_no',
      'storyNumber',
      'storyNum',
      'number',
      'seq',
      'sequence',
      'storyIndex',
      'index',
    ]);
    parsedStoryNo = toInt(rawNo);

    // 2) Infer from URLs (your new docs have .../045/... in audio/cover URLs)
    if (parsedStoryNo == null) {
      final urlCandidates = <String?>[
        data['mainAudioUrl']?.toString(),
        data['audioUrl']?.toString(),
        resolvedAudioUrl,
        data['coverImageUrl']?.toString(),
      ];

      for (final u in urlCandidates) {
        final url = (u ?? '').trim();
        if (url.isEmpty) continue;

        // Grab the LAST numeric path segment (handles leading zeros like 045)
        final matches = RegExp(r'/(\d{1,4})(?=/|$)').allMatches(url).toList();
        if (matches.isEmpty) continue;

        parsedStoryNo = int.tryParse(matches.last.group(1)!);
        if (parsedStoryNo != null) break;
      }
    }

    // 3) Last fallback: doc id / slug / title contains digits
    if (parsedStoryNo == null) {
      final idCandidates = <String?>[
        doc.id,
        data['slug']?.toString(),
        data['title']?.toString(),
      ];
      for (final s in idCandidates) {
        final str = (s ?? '').trim();
        if (str.isEmpty) continue;
        final matches = RegExp(r'(\d{1,4})').allMatches(str).toList();
        if (matches.isEmpty) continue;

        parsedStoryNo = int.tryParse(matches.last.group(1)!);
        if (parsedStoryNo != null) break;
      }
    }


    // createdAt can be Firestore Timestamp / int milliseconds / ISO string
    final rawCreatedAt = data['createdAt'];
    DateTime? parsedCreatedAt;
    if (rawCreatedAt is Timestamp) {
      parsedCreatedAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is num) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt.toInt());
    } else if (rawCreatedAt is String) {
      parsedCreatedAt = DateTime.tryParse(rawCreatedAt);
    }

    return Story(
      id: doc.id,
      title: data['title']?.toString() ?? 'Untitled',
      category: data['category']?.toString(),
      language: data['language']?.toString(),
      coverImageUrl: (data['coverImageUrl']?.toString() ?? '').trim(),
      audioUrl: (resolvedAudioUrl ?? '').trim(),
      audioScript: resolvedAudioScript,
      storyNo: parsedStoryNo,
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'title': title,
      'category': category,
      'language': language,
      'coverImageUrl': coverImageUrl,
      'audioUrl': audioUrl,
      'audioScript': audioScript,
      if (storyNo != null) 'storyNo': storyNo,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    };
  }
}
