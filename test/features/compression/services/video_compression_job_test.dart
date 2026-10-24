import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';
import 'package:slimshotai/features/compression/services/video_compression_service.dart';

/// Which job the compressor runs — WhatsApp Status beside the presets.
void main() {
  final service = VideoCompressionService();
  final best = CompressionPresets.videoPresets.firstWhere((p) => p.id == 'best_quality');
  final smart = CompressionPresets.videoPresets.firstWhere((p) => p.id == 'smart');

  VideoMetadata meta({int width = 720, int height = 1280, int kbps = 1200}) => VideoMetadata(
        width: width,
        height: height,
        bitrateKbps: kbps,
        codec: 'h264',
        durationSecs: 30,
        frameRate: 30,
        avgFrameRate: 30,
        colorTransfer: 'bt709',
        audioCodec: 'aac',
        audioChannels: 2,
      );

  VideoJob job({
    CompressionPreset? preset,
    VideoMetadata? metadata,
    bool status = true,
    String format = 'mp4',
  }) =>
      service.jobFor(
        inputPath: '/in.mp4',
        outputPath: '/out.mp4',
        preset: preset ?? smart,
        metadata: metadata,
        whatsAppStatus: status,
        removeMetadata: true,
        targetFormat: format,
      );

  test('a 1080×1920 video is brought to 720×1280 and kept even if larger', () {
    final j = job(metadata: meta(width: 1080, height: 1920, kbps: 900)) as RunFfmpeg;
    expect(j.command, contains('force_original_aspect_ratio=decrease'));
    expect(j.keepIfLarger, isTrue);
  });

  test('a status-ready video is copied, never handed back as it was', () {
    final j = job(metadata: meta());
    expect(j, isA<RunFfmpeg>());
    expect((j as RunFfmpeg).command, contains('-c copy'));
    expect(j.command, contains('-map_metadata -1'));
  });

  test("Best quality's skip does not apply under WhatsApp Status", () {
    final small = meta(width: 1920, height: 1080, kbps: 1000);
    expect(small.isAlreadyOptimized, isTrue);
    expect(job(preset: best, metadata: small), isA<RunFfmpeg>());
  });

  test('a video the probe could not read is still made status-shaped', () {
    final j = job(metadata: null) as RunFfmpeg;
    expect(j.command, contains('force_original_aspect_ratio=decrease'));
    expect(j.command, isNot(contains('1920')));
  });

  test('WebM chosen before the switch still makes an MP4', () {
    final j = job(metadata: meta(width: 1080, height: 1920), format: 'webm') as RunFfmpeg;
    expect(j.command, isNot(contains('libvpx')));
    expect(service.outputExtension(whatsAppStatus: true, targetFormat: 'webm'), 'mp4');
    expect(service.outputExtension(whatsAppStatus: false, targetFormat: 'webm'), 'webm');
  });

  group('with the switch off, as before', () {
    test('Best quality keeps an already small video', () {
      expect(
        job(preset: best, metadata: meta(width: 1920, height: 1080, kbps: 1000), status: false),
        isA<KeepOriginal>(),
      );
    });
    test('Smart encodes, and a larger result gives the original back', () {
      final j = job(metadata: meta(width: 1920, height: 1080, kbps: 9000), status: false) as RunFfmpeg;
      expect(j.command, contains('-preset superfast -crf 26'));
      expect(j.keepIfLarger, isFalse);
    });
  });
}
