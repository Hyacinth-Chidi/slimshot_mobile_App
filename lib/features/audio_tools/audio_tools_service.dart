import 'package:flutter/services.dart';

/// A video's sound, taken out into a file of its own.
class ExtractedSound {
  const ExtractedSound({required this.path, required this.durationSeconds});

  final String path;
  final double durationSeconds;
}

/// A native call that failed, with the one line to show the user.
class AudioToolsException implements Exception {
  const AudioToolsException(this.message);

  final String message;

  @override
  String toString() => 'AudioToolsException($message)';
}

/// Extract's native calls (`slimshot_ai/audio_tools`, `AudioToolsChannel.kt`):
/// the sound out of a video, and a sound's waveform as peaks.
class AudioToolsService {
  AudioToolsService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('slimshot_ai/audio_tools');

  final MethodChannel _channel;

  /// The video's sound written to [outputPath], or null when it has none.
  Future<ExtractedSound?> extract({
    required String videoPath,
    required String outputPath,
  }) async {
    final Map<Object?, Object?>? answer;
    try {
      answer = await _channel.invokeMapMethod<Object?, Object?>('extract', {
        'videoPath': videoPath,
        'outputPath': outputPath,
      });
    } on PlatformException catch (e) {
      throw AudioToolsException(
        e.message ?? 'The sound could not be taken out of this video.',
      );
    }
    if (answer == null || answer['hasSound'] != true) return null;
    final path = answer['path'];
    final ms = answer['durationMs'];
    if (path is! String || ms is! num) {
      throw const AudioToolsException(
        'The sound could not be taken out of this video.',
      );
    }
    return ExtractedSound(path: path, durationSeconds: ms / 1000.0);
  }

  /// [count] peaks of [path]'s sound, each 0..1, for the sheet's waveform.
  Future<List<double>> peaks(String path, {int count = 200}) async {
    final answer = await _channel.invokeListMethod<Object?>('peaks', {
      'path': path,
      'count': count,
    });
    return [for (final v in answer ?? const []) (v as num?)?.toDouble() ?? 0.0];
  }
}
