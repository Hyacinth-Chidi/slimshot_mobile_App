import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/color/color_adjustments.dart';
import 'package:slimshotai/features/video_editor/models/filter_preset.dart';

/// Adjust: brightness, contrast, saturation and temperature as one 4×5 colour
/// matrix in Flutter's `ColorFilter.matrix` layout — row-major, offsets on the
/// 0–255 scale — the same shape a filter preset already is, so it rides the
/// existing grade pipeline at both levels and needs no shader.
void main() {
  const grey = [128.0, 128.0, 128.0, 255.0];

  List<double> apply(List<double> m, List<double> rgba) => applyColorMatrix(m, rgba);

  void expectRgba(List<double> actual, List<double> expected) {
    for (var i = 0; i < 4; i++) {
      expect(actual[i], closeTo(expected[i], 1e-6), reason: 'channel $i');
    }
  }

  group('identity', () {
    test('no adjustment is the identity matrix, and says so', () {
      const none = ColorAdjustments.none;
      expect(none.isIdentity, isTrue);
      for (var i = 0; i < 20; i++) {
        expect(none.matrix[i], closeTo(FilterPreset.identityMatrix[i], 1e-9));
      }
    });

    test('any non-zero parameter is not identity', () {
      expect(const ColorAdjustments(brightness: 0.1).isIdentity, isFalse);
      expect(const ColorAdjustments(temperature: -0.1).isIdentity, isFalse);
    });
  });

  group('each parameter does one thing', () {
    test('brightness lifts every colour channel equally, alpha untouched', () {
      final m = const ColorAdjustments(brightness: 0.5).matrix;
      final out = apply(m, grey);
      expect(out[0], closeTo(128 + 0.5 * kBrightnessRange, 1e-6));
      expect(out[1], closeTo(out[0], 1e-6));
      expect(out[2], closeTo(out[0], 1e-6));
      expect(out[3], 255.0);
    });

    test('contrast pivots about mid grey', () {
      // Mid grey is the pivot, so it does not move; a lighter grey moves away
      // from it by the contrast factor.
      final up = const ColorAdjustments(contrast: 1.0).matrix;
      expectRgba(apply(up, [127.5, 127.5, 127.5, 255]), [127.5, 127.5, 127.5, 255]);
      final lighter = apply(up, [192.0, 192.0, 192.0, 255]);
      expect(lighter[0], closeTo(127.5 + (192 - 127.5) * 2, 1e-6));

      // Full negative contrast is flat mid grey whatever went in.
      final flat = const ColorAdjustments(contrast: -1.0).matrix;
      expectRgba(apply(flat, [10.0, 200.0, 90.0, 255]), [127.5, 127.5, 127.5, 255]);
    });

    test('full desaturation is luma grey; a grey is unmoved by saturation', () {
      final grayscale = const ColorAdjustments(saturation: -1.0).matrix;
      final red = apply(grayscale, [255.0, 0.0, 0.0, 255]);
      expect(red[0], closeTo(255 * 0.2126, 1e-6));
      expect(red[1], closeTo(red[0], 1e-6));
      expect(red[2], closeTo(red[0], 1e-6));

      final vivid = const ColorAdjustments(saturation: 1.0).matrix;
      expectRgba(apply(vivid, [100.0, 100.0, 100.0, 255]), [100.0, 100.0, 100.0, 255]);
    });

    test('temperature warms by lifting red and lowering blue', () {
      final warm = const ColorAdjustments(temperature: 1.0).matrix;
      final out = apply(warm, [100.0, 100.0, 100.0, 255]);
      expect(out[0], closeTo(100 * (1 + kTemperatureRange), 1e-6));
      expect(out[1], closeTo(100, 1e-6));
      expect(out[2], closeTo(100 * (1 - kTemperatureRange), 1e-6));

      final cool = const ColorAdjustments(temperature: -1.0).matrix;
      final cold = apply(cool, [100.0, 100.0, 100.0, 255]);
      expect(cold[0], lessThan(100));
      expect(cold[2], greaterThan(100));
    });
  });

  group('composition', () {
    const a = ColorAdjustments(brightness: 0.3);
    const b = ColorAdjustments(contrast: 0.5, saturation: -0.4);

    test('the identity is neutral on either side', () {
      final m = b.matrix;
      final left = composeColorMatrices(FilterPreset.identityMatrix, m);
      final right = composeColorMatrices(m, FilterPreset.identityMatrix);
      for (var i = 0; i < 20; i++) {
        expect(left[i], closeTo(m[i], 1e-9));
        expect(right[i], closeTo(m[i], 1e-9));
      }
    });

    test('compose(outer, inner) applies inner first', () {
      const sample = [40.0, 150.0, 220.0, 255.0];
      final composed = composeColorMatrices(a.matrix, b.matrix);
      final stepwise = apply(a.matrix, apply(b.matrix, sample));
      expectRgba(apply(composed, sample), stepwise);
    });
  });

  group('serialisation', () {
    test('round-trips, and reads junk or absence as none', () {
      const some = ColorAdjustments(
        brightness: 0.25,
        contrast: -0.5,
        saturation: 0.1,
        temperature: -0.75,
      );
      expect(ColorAdjustments.fromJson(some.toJson()), some);
      expect(ColorAdjustments.fromJson(null), ColorAdjustments.none);
      expect(ColorAdjustments.fromJson('warm'), ColorAdjustments.none);
      expect(ColorAdjustments.fromJson({'brightness': 'lots'}).brightness, 0.0);
    });

    test('values are clamped to the slider\'s range on read', () {
      final read = ColorAdjustments.fromJson({'brightness': 7.0, 'contrast': -3.0});
      expect(read.brightness, 1.0);
      expect(read.contrast, -1.0);
    });
  });

  group('parameters by name', () {
    test('read and write each parameter through the enum', () {
      var adj = ColorAdjustments.none;
      for (final p in AdjustParameter.values) {
        adj = adj.withValue(p, 0.5);
        expect(adj.valueOf(p), 0.5, reason: '$p');
      }
      expect(adj, const ColorAdjustments(
        brightness: 0.5,
        contrast: 0.5,
        saturation: 0.5,
        temperature: 0.5,
      ));
    });
  });
}
