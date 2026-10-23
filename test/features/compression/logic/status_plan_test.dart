import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/compression/logic/compression_presets.dart';
import 'package:slimshotai/features/compression/logic/status_plan.dart';

/// What a WhatsApp Status compression makes of each input.
void main() {
  VideoMetadata meta({
    int width = 720,
    int height = 1280,
    int bitrateKbps = 1800,
    String codec = 'h264',
    double frameRate = 30,
    double avgFrameRate = 30,
    int bitDepth = 8,
    String? colorTransfer = 'bt709',
    int rotation = 0,
    String? audioCodec = 'aac',
    int audioChannels = 2,
  }) =>
      VideoMetadata(
        width: width,
        height: height,
        bitrateKbps: bitrateKbps,
        codec: codec,
        durationSecs: 30,
        frameRate: frameRate,
        avgFrameRate: avgFrameRate,
        bitDepth: bitDepth,
        colorTransfer: colorTransfer,
        rotation: rotation,
        audioCodec: audioCodec,
        audioChannels: audioChannels,
      );

  group('size: inside 720×1280, never larger than the source', () {
    void sizes(int w, int h, int ew, int eh, {int rotation = 0}) {
      final plan = statusPlan(meta(width: w, height: h, rotation: rotation));
      expect((plan.width, plan.height), (ew, eh), reason: '$w×$h r$rotation');
    }

    test('portrait and landscape phone video', () {
      sizes(1080, 1920, 720, 1280);
      sizes(1920, 1080, 1280, 720);
      sizes(3840, 2160, 1280, 720);
    });
    test('a screen recording taller than 9:16 is held by its long side', () {
      sizes(720, 1612, 572, 1280);
    });
    test('a square, and odd sizes, come out even', () {
      sizes(1080, 1080, 720, 720);
      sizes(1079, 1919, 720, 1280);
      sizes(641, 361, 640, 360);
    });
    test('small sources are never enlarged', () {
      sizes(640, 360, 640, 360);
      sizes(320, 240, 320, 240);
    });
    test('a video stored sideways comes out the way it is shown', () {
      sizes(1920, 1080, 720, 1280, rotation: 90);
    });
  });

  group('frame rate', () {
    test('halves, thirds or caps a fast source', () {
      expect(statusFrameRate(60), 30);
      expect(statusFrameRate(59.94), closeTo(29.97, 0.01));
      expect(statusFrameRate(50), 25);
      expect(statusFrameRate(48), 24);
      expect(statusFrameRate(120), 30);
      expect(statusFrameRate(90), 30);
      expect(statusFrameRate(33), 30);
    });
    test('leaves a normal one alone', () {
      expect(statusFrameRate(30), 30);
      expect(statusFrameRate(25), 25);
      expect(statusFrameRate(24), 24);
    });
    test('an unknown rate is 30', () => expect(statusFrameRate(0), 30));
    test('the plan reads the average rate when it is known', () {
      expect(statusPlan(meta(frameRate: 60, avgFrameRate: 33)).frameRate, 30);
      expect(statusPlan(meta(frameRate: 50, avgFrameRate: 0)).frameRate, 25);
    });
  });

  test('HDR is tone-mapped; 10-bit SDR is not', () {
    expect(statusPlan(meta(colorTransfer: 'smpte2084')).toneMap, isTrue);
    expect(statusPlan(meta(colorTransfer: 'arib-std-b67')).toneMap, isTrue);
    expect(statusPlan(meta(colorTransfer: 'bt709', bitDepth: 10)).toneMap, isFalse);
  });

  test('sound: more than two channels become stereo, none stays none', () {
    expect(statusPlan(meta(audioChannels: 6)).audioChannels, 2);
    expect(statusPlan(meta(audioChannels: 1)).audioChannels, 1);
    expect(statusPlan(meta(audioCodec: null, audioChannels: 0)).audioChannels, 0);
    // A track whose channel count the probe could not read is still sound.
    expect(statusPlan(meta(audioCodec: 'aac', audioChannels: 0)).audioChannels, 2);
  });

  group('already status-ready: copied, not encoded', () {
    test('a ready file', () {
      expect(statusPlan(meta()).copyOnly, isTrue);
      expect(statusPlan(meta(audioCodec: null, audioChannels: 0)).copyOnly, isTrue);
    });
    test('anything out of shape is encoded', () {
      final notReady = {
        'hevc': meta(codec: 'hevc'),
        'opus sound': meta(audioCodec: 'opus'),
        '1080×1920': meta(width: 1080, height: 1920),
        '60 fps': meta(frameRate: 60, avgFrameRate: 60),
        'variable rate': meta(frameRate: 30, avgFrameRate: 27),
        '10-bit': meta(bitDepth: 10),
        'HLG': meta(colorTransfer: 'arib-std-b67'),
        'rotated': meta(width: 1280, height: 720, rotation: 90),
        'over the ceiling': meta(bitrateKbps: 2500),
        'unknown bitrate': meta(bitrateKbps: 0),
        'six channels': meta(audioChannels: 6),
      };
      notReady.forEach((name, m) => expect(statusPlan(m).copyOnly, isFalse, reason: name));
    });
  });

  test('an unknown source still gets a status-shaped plan', () {
    final plan = statusPlan(null);
    expect(plan.copyOnly, isFalse);
    expect(plan.width, isNull);
    expect(plan.height, isNull);
    expect(plan.frameRate, 30);
    expect(plan.toneMap, isFalse);
    expect(plan.audioChannels, 2);
  });

  test('the ceiling is provisional 2000 kbps', () {
    expect(kStatusMaxVideoKbps, 2000);
    expect(kStatusCrf, 21);
    expect(kStatusX264Preset, 'medium');
  });
}
