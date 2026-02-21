import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single item in a story's script timeline.
///
/// Supported types are typically: "audio", "text", "pause" (your app can decide).
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
  final String? language;

  /// Cover image URL (thumbnail).
  final String coverImageUrl;

  /// A single audio URL for the story (legacy / quick play).
  final String audioUrl;

  /// A list that may contain script items (audio/text/pause). Kept as dynamic
  /// for backward compatibility with your current Firestore structure.
  final List<dynamic> audioScript;

  /// NEW: Global sequential number based on upload order (1..N).
  /// Used for showing 01, 02, ... 100 on thumbnails.
  final int? storyNo;

  /// Optional created time (recommended to store in Firestore).
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
    final data = doc.data();
    if (data == null) {
      // Defensive fallback (should be rare)
      return Story(
        id: doc.id,
        title: 'Untitled',
        coverImageUrl: '',
        audioUrl: '',
        audioScript: const [],
      );
    }

    // Resolve audioScript regardless of whether Firestore stored it as List or Map
    final audioScriptField = data['audioScript'];
    final List<dynamic> resolvedAudioScript = audioScriptField is List
        ? audioScriptField
        : (audioScriptField is Map ? audioScriptField.values.toList() : []);

    // Resolve audioUrl (prefer explicit audioUrl, else infer from first script item)
    String? resolvedAudioUrl = data['audioUrl']?.toString();
    if ((resolvedAudioUrl == null || resolvedAudioUrl.trim().isEmpty) &&
        resolvedAudioScript.isNotEmpty) {
      final firstItem = resolvedAudioScript.first;
      if (firstItem is Map) {
        resolvedAudioUrl = (firstItem['audioUrl'] ?? firstItem['url'])?.toString();
      }
    }

    // NEW: storyNo can be int/num/string
    final rawNo = data['storyNo'];
    final int? parsedStoryNo = (rawNo is num)
        ? rawNo.toInt()
        : int.tryParse(rawNo?.toString() ?? '');

    // NEW: createdAt supports Timestamp/int(ms)/String(ISO)
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

  /// Optional helper if you ever want to write back to Firestore.
  Map<String, dynamic> toFirestore() {
    return {
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
