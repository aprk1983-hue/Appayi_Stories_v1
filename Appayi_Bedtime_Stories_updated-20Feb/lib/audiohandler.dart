// // lib/audio_handler.dart
// import 'package:audio_service/audio_service.dart';
// import 'package:just_audio/just_audio.dart';
// import 'package:flutter/foundation.dart';

// // This is the entry point for the background audio isolate
// Future<void> audioHandlerTask() async {
//   AudioServiceBackground.run(() => AudioPlayerTaskHandler());
// }

// class AudioPlayerTaskHandler extends BaseAudioHandler {
//   final AudioPlayer _player = AudioPlayer();

//   AudioPlayerTaskHandler() {
//     // Background task setup
//     _player.playbackEventStream.listen((event) {
//       AudioServiceBackground.setState(
//         controls: [
//           MediaControl.skipToPrevious,
//           MediaControl.pause,
//           MediaControl.play,
//           MediaControl.stop,
//           MediaControl.skipToNext,
//         ],
//         systemActions: [MediaAction.seekTo],
//         androidCompactActions: [0, 1, 3],
//         processingState: AudioProcessingState.ready,
//         playing: _player.playing,
//         position: _player.position,
//         bufferedPosition: _player.bufferedPosition,
//         speed: _player.speed,
//       );
//     });
//   }

//   @override
//   Future<void> play() => _player.play();

//   @override
//   Future<void> pause() => _player.pause();

//   @override
//   Future<void> stop() => _player.stop();

//   @override
//   Future<void> seek(Duration position) => _player.seek(position);
// }
