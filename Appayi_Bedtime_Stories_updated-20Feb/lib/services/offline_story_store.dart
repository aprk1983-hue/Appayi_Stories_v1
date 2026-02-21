// lib/services/offline_story_store.dart
// Offline downloads stored INSIDE the app only (app-private storage).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Stores offline story assets (audio + cover) in app-private storage.
///
/// Design goals:
/// - No export to device Downloads / Files app.
/// - Stable filenames derived from URL (no extra DB required).
/// - Simple existence checks to decide local vs network playback.
/// - Lightweight downloaded-story indicator support via [downloadedStoryIds].
class OfflineStoryStore {
  OfflineStoryStore._();
  static final OfflineStoryStore instance = OfflineStoryStore._();

  static const String _rootFolderName = 'offline_stories';

  /// Notifies listeners when the set of downloaded storyIds changes.
  /// This is handy for showing a "downloaded" badge in Home / Category lists.
  final ValueNotifier<Set<String>> downloadedStoryIds = ValueNotifier<Set<String>>(<String>{});

  bool _cacheLoaded = false;

  Future<Directory> _rootDir() async {
    // Support dir is app-private and persists across launches.
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/$_rootFolderName');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  String _shortKey(String input, {int len = 16}) {
    // url-safe base64, trimmed for filename use.
    final raw = base64UrlEncode(utf8.encode(input)).replaceAll('=', '');
    return raw.length <= len ? raw : raw.substring(0, len);
  }

  String _extFromUrl(String url, {String fallback = 'bin'}) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      final dot = last.lastIndexOf('.');
      if (dot > 0 && dot < last.length - 1) {
        final ext = last.substring(dot + 1).toLowerCase();
        if (ext.length <= 5) return ext;
      }
    } catch (_) {}
    return fallback;
  }

  Future<Directory> _storyDir(String storyId) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/$storyId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> localAudioFile({
    required String storyId,
    required String remoteUrl,
    required int segmentIndex,
  }) async {
    final dir = await _storyDir(storyId);
    final ext = _extFromUrl(remoteUrl, fallback: 'mp3');
    final key = _shortKey(remoteUrl);
    return File('${dir.path}/audio_${segmentIndex}_$key.$ext');
  }

  Future<File> localCoverFile({required String storyId, required String remoteUrl}) async {
    final dir = await _storyDir(storyId);
    final ext = _extFromUrl(remoteUrl, fallback: 'jpg');
    final key = _shortKey(remoteUrl);
    return File('${dir.path}/cover_$key.$ext');
  }

  Future<bool> hasAudio({required String storyId, required String remoteUrl, required int segmentIndex}) async {
    final f = await localAudioFile(storyId: storyId, remoteUrl: remoteUrl, segmentIndex: segmentIndex);
    return f.exists();
  }

  Future<bool> hasCover({required String storyId, required String remoteUrl}) async {
    final f = await localCoverFile(storyId: storyId, remoteUrl: remoteUrl);
    return f.exists();
  }

  /// Returns a URI to play: local file if downloaded, else the network URL.
  Future<Uri> resolvePlayableAudioUri({
    required String storyId,
    required String remoteUrl,
    required int segmentIndex,
  }) async {
    final local = await localAudioFile(storyId: storyId, remoteUrl: remoteUrl, segmentIndex: segmentIndex);
    if (await local.exists()) {
      return Uri.file(local.path);
    }
    return Uri.parse(remoteUrl);
  }

  /// Returns local cover path if downloaded, else null.
  Future<String?> resolveLocalCoverPath({
    required String storyId,
    required String remoteUrl,
  }) async {
    final local = await localCoverFile(storyId: storyId, remoteUrl: remoteUrl);
    if (await local.exists()) return local.path;
    return null;
  }

  /// Loads downloaded IDs once (lazy). Call this early in app if you want.
  Future<void> ensureCacheLoaded() async {
    if (_cacheLoaded) return;
    await refreshDownloadedStoryIds();
    _cacheLoaded = true;
  }

  /// Returns true if *any* offline file exists for this storyId.
  /// (We treat the story as "downloaded" if at least one audio segment exists.)
  Future<bool> isStoryDownloaded(String storyId) async {
    await ensureCacheLoaded();
    return downloadedStoryIds.value.contains(storyId);
  }

  /// Returns the current downloaded storyIds (after ensuring cache is loaded).
  Future<Set<String>> getDownloadedStoryIds() async {
    await ensureCacheLoaded();
    return downloadedStoryIds.value;
  }

  /// Scans the offline folder and refreshes [downloadedStoryIds].
  Future<void> refreshDownloadedStoryIds() async {
    final root = await _rootDir();
    final Set<String> ids = <String>{};
    if (await root.exists()) {
      final entities = root.listSync(followLinks: false);
      for (final e in entities) {
        if (e is Directory) {
          try {
            final files = e
                .listSync(recursive: false, followLinks: false)
                .whereType<File>()
                .map((f) => f.path.split(Platform.pathSeparator).last)
                .toList();
            final hasAnyAudio = files.any((n) => n.startsWith('audio_'));
            if (hasAnyAudio) {
              ids.add(e.path.split(Platform.pathSeparator).last);
            }
          } catch (_) {
            // ignore a broken folder
          }
        }
      }
    }
    downloadedStoryIds.value = ids;
  }

  /// Download a URL into the provided file (app-private), with optional progress.
  Future<void> _downloadToFile(
    String url,
    File outFile, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('HTTP ${res.statusCode} when downloading $url');
      }
      final total = res.contentLength; // may be -1
      await outFile.parent.create(recursive: true);

      // Write to temp first then rename (prevents half-written files being treated as valid).
      final tmp = File('${outFile.path}.part');
      if (await tmp.exists()) {
        try { await tmp.delete(); } catch (_) {}
      }
      final sink = tmp.openWrite();
      int received = 0;
      await for (final chunk in res) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) onProgress(received, total);
      }
      await sink.close();
      if (await outFile.exists()) {
        try { await outFile.delete(); } catch (_) {}
      }
      await tmp.rename(outFile.path);
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadAudio({
    required String storyId,
    required String remoteUrl,
    required int segmentIndex,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final out = await localAudioFile(storyId: storyId, remoteUrl: remoteUrl, segmentIndex: segmentIndex);
    if (await out.exists()) {
      // ensure indicator is correct
      await _markDownloaded(storyId);
      return out;
    }
    await _downloadToFile(remoteUrl, out, onProgress: onProgress);
    await _markDownloaded(storyId);
    return out;
  }

  Future<File> downloadCover({
    required String storyId,
    required String remoteUrl,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final out = await localCoverFile(storyId: storyId, remoteUrl: remoteUrl);
    if (await out.exists()) return out;
    await _downloadToFile(remoteUrl, out, onProgress: onProgress);
    // cover alone shouldn't mark as downloaded; but refreshing is cheap and safe.
    await refreshDownloadedStoryIds();
    return out;
  }

  Future<void> _markDownloaded(String storyId) async {
    await ensureCacheLoaded();
    if (downloadedStoryIds.value.contains(storyId)) return;
    final next = <String>{...downloadedStoryIds.value, storyId};
    downloadedStoryIds.value = next;
  }

  /// Deletes all offline files for a story.
  Future<void> deleteStoryDownloads(String storyId) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/$storyId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await refreshDownloadedStoryIds();
  }
}
