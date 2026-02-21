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

    // storyNo can be int/num/string
    final rawNo = data['storyNo'];
    final int? parsedStoryNo =
        (rawNo is num) ? rawNo.toInt() : int.tryParse(rawNo?.toString() ?? '');

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
