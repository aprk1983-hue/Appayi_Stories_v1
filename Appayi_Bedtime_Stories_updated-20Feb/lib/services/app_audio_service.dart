// // lib/services/app_audio_service.dart
// //
// // Background/notification audio controls for the app.
// // Uses audio_service + just_audio so playback continues when the app is
// // minimized and exposes play/pause/stop/next/previous from the notification.

// import 'dart:async';

// import 'package:audio_service/audio_service.dart';
// import 'package:just_audio/just_audio.dart';

// /// Global singleton service so the app only ever has ONE audio player.
// class AppAudioService {
//   static StoryAudioHandler? _handler;

//   static Future<void> init() async {
//     if (_handler != null) return;
//     final handler = await AudioService.init(
//       builder: () => StoryAudioHandler(),
//       config: const AudioServiceConfig(
//         androidNotificationChannelId: 'com.audio_story_app.channel.audio',
//         androidNotificationChannelName: 'Story playback',
//         androidNotificationOngoing: true,
//         androidStopForegroundOnPause: true,
//       ),
//     );
//     _handler = handler as StoryAudioHandler;
//   }

//   static StoryAudioHandler get handler {
//     final h = _handler;
//     if (h == null) {
//       throw StateError(
//           'AppAudioService not initialized. Call AppAudioService.init() in main().');
//     }
//     return h;
//   }

//   static AudioPlayer get player => handler.player;
// }

// /// Audio handler that maps notification actions to the app's AudioPlayer.
// ///
// /// IMPORTANT: skipNext/skipPrevious are implemented to jump between AUDIO
// /// segments only (skipping prompt/silence parts), matching your in-app logic.
// class StoryAudioHandler extends BaseAudioHandler
//     with QueueHandler, SeekHandler {
//   final AudioPlayer _player = AudioPlayer();
//   StreamSubscription<PlaybackEvent>? _eventSub;
//   StreamSubscription<int?>? _indexSub;

//   List<int> _audioSegmentIndices = const <int>[];

//   AudioPlayer get player => _player;

//   void updateAudioSegmentIndices(List<int> indices) {
//     _audioSegmentIndices = List<int>.from(indices);
//   }

//   /// Update notification metadata (title/art) and queue.
//   void setQueueItems(List<MediaItem> items) {
//     queue.add(items);
//     final idx = _player.currentIndex ?? 0;
//     if (idx >= 0 && idx < items.length) {
//       mediaItem.add(items[idx]);
//     } else if (items.isNotEmpty) {
//       mediaItem.add(items.first);
//     }
//   }

//   StoryAudioHandler() {
//     _eventSub = _player.playbackEventStream.listen(_broadcastState);
//     _indexSub = _player.currentIndexStream.listen((index) {
//       final items = queue.value;
//       if (index == null) return;
//       if (index >= 0 && index < items.length) {
//         mediaItem.add(items[index]);
//       }
//     });
//   }

//   @override
//   Future<void> play() => _player.play();

//   @override
//   Future<void> pause() => _player.pause();

//   @override
//   Future<void> stop() async {
//     await _player.stop();
//     await super.stop();
//   }

//   @override
//   Future<void> seek(Duration position) => _player.seek(position);

//   int? _nextAudioIndex() {
//     final cur = _player.currentIndex;
//     if (cur == null) return null;
//     for (final i in _audioSegmentIndices) {
//       if (i > cur) return i;
//     }
//     return null;
//   }

//   int? _prevAudioIndex() {
//     final cur = _player.currentIndex;
//     if (cur == null) return null;
//     int? prev;
//     for (final i in _audioSegmentIndices) {
//       if (i < cur) prev = i;
//     }
//     return prev;
//   }

//   @override
//   Future<void> skipToNext() async {
//     final next = _nextAudioIndex();
//     if (next == null) return;
//     await _player.seek(Duration.zero, index: next);
//   }

//   @override
//   Future<void> skipToPrevious() async {
//     final prev = _prevAudioIndex();
//     if (prev == null) {
//       // If there is no previous audio segment, just restart.
//       await _player.seek(Duration.zero);
//       return;
//     }
//     await _player.seek(Duration.zero, index: prev);
//   }

//   void _broadcastState(PlaybackEvent event) {
//     final playing = _player.playing;
//     final processingState = switch (_player.processingState) {
//       ProcessingState.idle => AudioProcessingState.idle,
//       ProcessingState.loading => AudioProcessingState.loading,
//       ProcessingState.buffering => AudioProcessingState.buffering,
//       ProcessingState.ready => AudioProcessingState.ready,
//       ProcessingState.completed => AudioProcessingState.completed,
//     };

//     playbackState.add(
//       playbackState.value.copyWith(
//         controls: [
//           MediaControl.skipToPrevious,
//           if (playing) MediaControl.pause else MediaControl.play,
//           MediaControl.stop,
//           MediaControl.skipToNext,
//         ],
//         androidCompactActionIndices: const [0, 1, 3],
//         processingState: processingState,
//         playing: playing,
//         updatePosition: _player.position,
//         bufferedPosition: _player.bufferedPosition,
//         speed: _player.speed,
//         queueIndex: event.currentIndex,
//       ),
//     );
//   }

//   /// Clean up resources.
//   ///
//   /// `BaseAudioHandler` does not define `dispose()`, so we expose this as a
//   /// helper you can call manually if you ever need to fully tear down the
//   /// handler.
//   Future<void> disposeHandler() async {
//     await _eventSub?.cancel();
//     await _indexSub?.cancel();
//     await _player.dispose();
//   }
// }

// lib/services/app_audio_service.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

class AppAudioService {
  static StoryAudioHandler? _handler;
  static bool _isInitializing = false;
  static final List<Completer<void>> _initWaiters = [];

  static Future<void> init() async {
    // If already initialized, return
    if (_handler != null) {
      debugPrint('✅ AudioService already initialized');
      return;
    }

    // If initializing, wait
    if (_isInitializing) {
      debugPrint('⏳ AudioService already initializing, waiting...');
      final completer = Completer<void>();
      _initWaiters.add(completer);
      return completer.future;
    }

    _isInitializing = true;
    debugPrint('🎵 Initializing AudioService...');

    try {
      // Initialize AudioService with background task
      _handler = await AudioService.init(
        builder: () => StoryAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.ryanheise.audioservice.channel.audio',
          androidNotificationChannelName: 'Audio Service',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );

      debugPrint('✅ AudioService initialized successfully');

      // Complete all waiters
      for (final completer in _initWaiters) {
        completer.complete();
      }
      _initWaiters.clear();
    } catch (e, stack) {
      debugPrint('❌ AudioService init error: $e');
      debugPrint('Stack: $stack');

      for (final completer in _initWaiters) {
        completer.completeError(e);
      }
      _initWaiters.clear();
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  static StoryAudioHandler get handler {
    if (_handler == null) {
      throw StateError(
          'AppAudioService not initialized. Call AppAudioService.init() in main().');
    }
    return _handler!;
  }

  static AudioPlayer get player => handler.player;

  static bool get isInitialized => _handler != null;
}

class StoryAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<int?>? _indexSub;
  List<int> _audioSegmentIndices = const <int>[];

  AudioPlayer get player => _player;

  StoryAudioHandler() {
    // Initialize audio session for background playback
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen((index) {
      final items = queue.value;
      if (index != null && index >= 0 && index < items.length) {
        mediaItem.add(items[index]);
      }
    });
  }

  void updateAudioSegmentIndices(List<int> indices) {
    _audioSegmentIndices = List<int>.from(indices);
  }

  void setQueueItems(List<MediaItem> items) {
    queue.add(items);
    if (items.isNotEmpty) {
      mediaItem.add(items.first);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  int? _nextAudioIndex() {
    final cur = _player.currentIndex;
    if (cur == null) return null;
    for (final i in _audioSegmentIndices) {
      if (i > cur) return i;
    }
    return null;
  }

  int? _prevAudioIndex() {
    final cur = _player.currentIndex;
    if (cur == null) return null;
    int? prev;
    for (final i in _audioSegmentIndices) {
      if (i < cur) prev = i;
    }
    return prev;
  }

  @override
  Future<void> skipToNext() async {
    final next = _nextAudioIndex();
    if (next != null) {
      await _player.seek(Duration.zero, index: next);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final prev = _prevAudioIndex();
    if (prev != null) {
      await _player.seek(Duration.zero, index: prev);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _getProcessingState();

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  AudioProcessingState _getProcessingState() {
    switch (_player.processingState) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _indexSub?.cancel();
    await _player.dispose();
  }
}
