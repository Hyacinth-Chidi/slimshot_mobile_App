import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';
import 'package:slimshotai/features/compression/logic/size_estimate.dart';

const _mb = 1024 * 1024;

void main() {
  group('estimateOutputRange', () {
    test("a preset's expected reduction becomes the output's range", () {
      final range = estimateOutputRange(100 * _mb, '50-80%')!;
      expect(range.low, 20 * _mb); // 80% smaller
      expect(range.high, 50 * _mb); // 50% smaller
    });

    test('the order of the two numbers does not matter', () {
      final range = estimateOutputRange(100 * _mb, '80-50%')!;
      expect((range.low, range.high), (20 * _mb, 50 * _mb));
    });

    test('nothing to estimate without a size or a readable reduction', () {
      expect(estimateOutputRange(0, '50-80%'), isNull);
      expect(estimateOutputRange(100 * _mb, 'smaller'), isNull);
    });

    test('every video preset can be estimated', () {
      for (final preset in CompressionPresets.videoPresets) {
        expect(estimateOutputRange(10 * _mb, preset.expectedCompression),
            isNotNull,
            reason: preset.id);
      }
    });
  });

  group('sizes read the way a person says them', () {
    test('compactSize', () {
      expect(compactSize((48.2 * _mb).round()), '48.2 MB');
      expect(compactSize(312 * _mb), '312 MB');
      expect(compactSize(10 * _mb), '10 MB');
      expect(compactSize(950 * 1024), '950 KB');
      expect(compactSize((1.5 * 1024 * _mb).round()), '1.5 GB');
    });

    test('approxRange takes one unit, from the larger end', () {
      expect(approxRange(SizeRange((9.64 * _mb).round(), (24.1 * _mb).round())),
          '≈ 9.6–24 MB');
      expect(approxRange(const SizeRange(400 * 1024, 2 * _mb)), '≈ 0.4–2 MB');
    });
  });

  group('videoInfoLabel', () {
    VideoMetadata meta(int w, int h, double secs) => VideoMetadata(
        width: w, height: h, bitrateKbps: 0, codec: 'h264', durationSecs: secs);

    test('resolution and length', () {
      expect(videoInfoLabel(meta(1920, 1080, 42)), '1080p · 0:42');
      expect(videoInfoLabel(meta(1080, 1920, 605)), '1080p · 10:05');
      expect(videoInfoLabel(meta(3840, 2160, 3723)), '4K · 1:02:03');
    });

    test('an unknown length is left out', () {
      expect(videoInfoLabel(meta(1280, 720, 0)), '720p');
    });
  });
}
