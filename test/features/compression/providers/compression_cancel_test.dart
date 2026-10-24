import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';
import 'package:slimshotai/features/compression/providers/compression_provider.dart';
import 'package:slimshotai/features/compression/services/image_compression_service.dart';
import 'package:slimshotai/features/compression/services/video_compression_service.dart';

/// A compressor whose runs finish when the test says so.
class _FakeVideoService extends VideoCompressionService {
  final runs = <Completer<String?>>[];
  final progress = <void Function(double)>[];
  int cancels = 0;

  @override
  Future<VideoMetadata?> getVideoMetadata(String inputPath) async => null;

  @override
  Future<String?> compressVideo({
    required String inputPath,
    required CompressionPreset preset,
    VideoMetadata? metadata,
    bool whatsAppOptimize = false,
    bool removeMetadata = true,
    String targetFormat = 'mp4',
    Function(double progress)? onProgress,
  }) {
    final run = Completer<String?>();
    runs.add(run);
    progress.add((p) => onProgress?.call(p));
    return run.future;
  }

  @override
  Future<void> cancelCompression() async => cancels++;
}

/// Cancel, then compress again: the cancelled run must not touch the new one.
///
/// Every run asked "is a compression running?" rather than "is mine?", so a
/// cancelled run finishing late — FFmpeg reports a cancel as a failure — saw
/// the restarted run's "running", marked it failed and stopped, and its
/// result was thrown away. Its progress landed on the new run's ring too.
void main() {
  late Directory dir;
  late _FakeVideoService video;
  late CompressionNotifier notifier;
  late CompressionState current;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('compress_cancel');
    final input = File('${dir.path}/in.mp4')..writeAsBytesSync(List.filled(1000, 1));
    video = _FakeVideoService();
    notifier = CompressionNotifier(video, ImageCompressionService());
    notifier.addListener((s) => current = s);
    notifier.setInputFiles([XFile(input.path)],
        defaultPreset: CompressionPresets.videoPresets[1]);
    await pumpEventQueue();
  });

  tearDown(() async {
    notifier.dispose();
    await dir.delete(recursive: true);
  });

  /// Real file reads finish on their own time, which `pumpEventQueue` does
  /// not wait for; under a busy test run it checked too early.
  Future<void> settle(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<String> output(String name) async {
    final f = File('${dir.path}/$name')..writeAsBytesSync(List.filled(400, 2));
    return f.path;
  }

  test('a cancelled run finishing late leaves the restarted run alone', () async {
    unawaited(notifier.compressVideo()); // run A
    await pumpEventQueue();
    await notifier.cancelCompression();
    expect(current.isProcessing, isFalse);

    unawaited(notifier.compressVideo()); // run B
    await pumpEventQueue();
    expect(current.isProcessing, isTrue);

    // A's progress, then A's FFmpeg call ending as cancelled (null).
    final progressBefore = current.progress;
    video.progress[0](80);
    expect(current.progress, progressBefore);
    video.runs[0].complete(null);
    await pumpEventQueue();
    expect(current.isProcessing, isTrue, reason: 'B is still running');
    expect(current.error, isNull);

    // B finishes: its result is kept.
    final b = await output('b.mp4');
    video.runs[1].complete(b);
    await settle(() => !current.isProcessing);
    expect(current.isProcessing, isFalse);
    expect(current.outputPaths, [b]);
    expect(current.error, isNull);
  });

  test('a cancelled run that had already finished does not deliver a result', () async {
    unawaited(notifier.compressVideo());
    await pumpEventQueue();
    await notifier.cancelCompression();
    video.runs[0].complete(await output('a.mp4'));
    await pumpEventQueue();
    expect(current.outputPaths, isEmpty);
    expect(current.isProcessing, isFalse);
  });
}
