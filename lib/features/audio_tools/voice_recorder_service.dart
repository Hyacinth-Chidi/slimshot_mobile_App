import 'package:flutter/services.dart';

/// A recorded voiceover file.
class RecordedTake {
  const RecordedTake({required this.path, required this.durationSeconds});

  final String path;
  final double durationSeconds;
}

/// The recorder would not start or could not save, with the line to show.
class VoiceRecorderException implements Exception {
  const VoiceRecorderException(this.message);

  final String message;

  @override
  String toString() => 'VoiceRecorderException($message)';
}

/// The microphone, one take at a time. The take is what is heard while
/// capturing; everything else the microphone hears is dropped.
abstract class VoiceRecorder {
  /// Starts the microphone, writing to [outputPath]. Nothing is kept yet.
  Future<void> open(String outputPath);

  /// Keeps what the microphone hears from now ([on]) or stops keeping it.
  Future<void> setCapturing(bool on);

  /// Stops the microphone. Kept with anything captured, the take; else null
  /// and the file is gone.
  Future<RecordedTake?> close({required bool keep});
}

/// [VoiceRecorder] over `slimshot_ai/voice_recorder` (`VoiceRecorderChannel.kt`).
class ChannelVoiceRecorder implements VoiceRecorder {
  ChannelVoiceRecorder({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('slimshot_ai/voice_recorder');

  final MethodChannel _channel;

  @override
  Future<void> open(String outputPath) async {
    try {
      await _channel.invokeMethod<Object?>('open', {'outputPath': outputPath});
    } on PlatformException catch (e) {
      throw VoiceRecorderException(
        e.message ?? 'The microphone is in use or unavailable.',
      );
    }
  }

  @override
  Future<void> setCapturing(bool on) =>
      _channel.invokeMethod<Object?>('setCapturing', {'capturing': on});

  @override
  Future<RecordedTake?> close({required bool keep}) async {
    final Map<Object?, Object?>? answer;
    try {
      answer = await _channel.invokeMapMethod<Object?, Object?>('close', {'keep': keep});
    } on PlatformException catch (e) {
      throw VoiceRecorderException(e.message ?? 'The recording could not be saved.');
    }
    final path = answer?['path'];
    final ms = answer?['durationMs'];
    if (path is! String || ms is! num) return null;
    return RecordedTake(path: path, durationSeconds: ms / 1000.0);
  }
}
