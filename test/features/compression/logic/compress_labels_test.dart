import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';
import 'package:slimshotai/features/compression/logic/compress_labels.dart';

const _mb = 1024 * 1024;

void main() {
  group('sizes read the way a person says them', () {
    test('compactSize', () {
      expect(compactSize((48.2 * _mb).round()), '48.2 MB');
      expect(compactSize(312 * _mb), '312 MB');
      expect(compactSize(10 * _mb), '10 MB');
      expect(compactSize(950 * 1024), '950 KB');
      expect(compactSize((1.5 * 1024 * _mb).round()), '1.5 GB');
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

  group('result labels', () {
    test('a format reads as people write it', () {
      expect(formatName('mp4'), 'MP4');
      expect(formatName('webm'), 'WebM');
      expect(formatName('jpg'), 'JPG');
      expect(formatName('webp'), 'WebP');
      expect(formatName('png'), 'PNG');
      expect(formatName('heic'), 'HEIC');
    });
  });

  test('a photo reads as its format and megapixels', () {
    expect(photoInfoLabel('IMG_1.HEIC', 4032, 3024), 'HEIC · 12 MP');
    expect(photoInfoLabel('a.jpeg', 3264, 2448), 'JPG · 8 MP');
    expect(photoInfoLabel('b.png', 1920, 1080), 'PNG · 2.1 MP');
    expect(photoInfoLabel('c.webp', 800, 600), 'WebP · 0.5 MP');
    // Without dimensions, the format alone; without an extension, the size.
    expect(photoInfoLabel('d.jpg', null, null), 'JPG');
    expect(photoInfoLabel('noext', 4000, 3000), '12 MP');
  });
}
