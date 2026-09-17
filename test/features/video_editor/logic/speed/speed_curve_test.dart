import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/speed/speed_curve.dart';

/// A speed curve: speed as a function of *where in the source* the clip is,
/// and the arithmetic that turns it into where the clip is *when*.
///
/// The curve is speed-over-source, so source time is not `timeline × speed`
/// any more: reaching source fraction `x` takes `∫₀ˣ dx'/v(x')` of timeline,
/// and the inverse — which source frame is due at a timeline instant — is what
/// playback, the filmstrip and export all ask. Both directions are closed-form
/// over linear segments, and these tests hold them to a numeric integral so a
/// sign slip in the logarithm cannot pass as "roughly right".
void main() {
  /// Trapezoid integral of 1/v from 0 to [x], the slow honest way.
  double numericTime(SpeedCurve c, double x, {int steps = 20000}) {
    var sum = 0.0;
    final h = x / steps;
    for (var i = 0; i < steps; i++) {
      final a = c.speedAtSource(i * h);
      final b = c.speedAtSource((i + 1) * h);
      sum += h * 0.5 * (1 / a + 1 / b);
    }
    return sum;
  }

  const xs = [0.0, 0.1, 0.33, 0.5, 0.77, 1.0];

  group('a constant curve', () {
    test('is exactly the scalar speed it replaces', () {
      final c = SpeedCurve.constant(2.0);
      expect(c.durationFactor, closeTo(0.5, 1e-9));
      expect(c.timeToSource(0.5), closeTo(0.25, 1e-9));
      expect(c.sourceAtTime(0.25), closeTo(0.5, 1e-9));
      expect(c.speedAtSource(0.3), closeTo(2.0, 1e-9));
    });
  });

  group('timeToSource', () {
    test('matches a numeric integral of 1/speed on every preset', () {
      for (final p in kSpeedCurvePresets) {
        for (final x in xs) {
          expect(
            p.curve.timeToSource(x),
            closeTo(numericTime(p.curve, x), 1e-4),
            reason: '${p.id} @ $x',
          );
        }
      }
    });

    test('starts at zero and only ever grows', () {
      for (final p in kSpeedCurvePresets) {
        expect(p.curve.timeToSource(0), 0);
        var last = 0.0;
        for (var i = 1; i <= 100; i++) {
          final t = p.curve.timeToSource(i / 100);
          expect(t, greaterThan(last), reason: '${p.id} @ ${i / 100}');
          last = t;
        }
      }
    });

    test('a segment whose speed ramps is a logarithm, not a chord', () {
      // 1.0 → 3.0 over the whole clip: ∫ dx / (1 + 2x) = ln(3) / 2.
      final c = SpeedCurve(const [SpeedPoint(0, 1), SpeedPoint(1, 3)]);
      expect(c.durationFactor, closeTo(0.5493061443, 1e-9));
    });
  });

  group('sourceAtTime', () {
    test('inverts timeToSource on every preset', () {
      for (final p in kSpeedCurvePresets) {
        for (final x in xs) {
          final u = p.curve.timeToSource(x);
          expect(p.curve.sourceAtTime(u), closeTo(x, 1e-9),
              reason: '${p.id} @ $x');
        }
      }
    });

    test('clamps to the clip at both ends', () {
      final c = kSpeedCurvePresets.first.curve;
      expect(c.sourceAtTime(-1), 0);
      expect(c.sourceAtTime(c.durationFactor + 1), 1);
    });
  });

  group('presets', () {
    test('every preset spans 0..1 in order with speeds in range', () {
      for (final p in kSpeedCurvePresets) {
        final pts = p.curve.points;
        expect(pts.length, greaterThanOrEqualTo(2), reason: p.id);
        expect(pts.first.x, 0, reason: p.id);
        expect(pts.last.x, 1, reason: p.id);
        for (var i = 1; i < pts.length; i++) {
          expect(pts[i].x, greaterThanOrEqualTo(pts[i - 1].x), reason: p.id);
        }
        for (final pt in pts) {
          expect(pt.speed, inInclusiveRange(SpeedCurve.kMinSpeed, SpeedCurve.kMaxSpeed),
              reason: p.id);
        }
        expect(p.curve.presetId, p.id);
      }
    });

    test('ids are unique, and custom is flat 1× so it changes nothing when chosen',
        () {
      final ids = kSpeedCurvePresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      final custom = speedCurvePresetById('custom')!.curve;
      expect(custom.durationFactor, closeTo(1.0, 1e-9));
      expect(speedCurvePresetById('nope'), isNull);
    });
  });

  group('editing', () {
    test('changing a point clamps to the range and makes the curve custom', () {
      final c = speedCurvePresetById('montage')!.curve;
      final edited = c.withPointSpeed(1, 100.0);
      expect(edited.points[1].speed, SpeedCurve.kMaxSpeed);
      expect(edited.presetId, isNull);
      expect(edited.points.length, c.points.length);
    });

    test('a new point lands on the curve where it is added, in order', () {
      final c = SpeedCurve(const [SpeedPoint(0, 1), SpeedPoint(1, 3)]);
      final added = c.addPoint(0.5);
      expect(added.points.length, 3);
      expect(added.points[1].x, 0.5);
      expect(added.points[1].speed, closeTo(2.0, 1e-9));
      // Adding a point changes nothing about the picture.
      expect(added.durationFactor, closeTo(c.durationFactor, 1e-9));
    });

    test('the endpoints cannot be removed; an inner point can', () {
      final c = speedCurvePresetById('montage')!.curve;
      expect(c.removePoint(0).points.length, c.points.length);
      expect(c.removePoint(c.points.length - 1).points.length, c.points.length);
      expect(c.removePoint(1).points.length, c.points.length - 1);
    });
  });

  group('splitAt', () {
    test('the halves keep the whole duration and agree at the seam', () {
      for (final p in kSpeedCurvePresets) {
        for (final x in [0.2, 0.5, 0.8]) {
          final halves = p.curve.splitAt(x);
          expect(
            halves.left.durationFactor * x + halves.right.durationFactor * (1 - x),
            closeTo(p.curve.durationFactor, 1e-9),
            reason: '${p.id} @ $x',
          );
          expect(halves.left.speedAtSource(1), closeTo(p.curve.speedAtSource(x), 1e-9));
          expect(halves.right.speedAtSource(0), closeTo(p.curve.speedAtSource(x), 1e-9));
          expect(halves.left.speedAtSource(0.5),
              closeTo(p.curve.speedAtSource(x * 0.5), 1e-9));
          expect(halves.right.speedAtSource(0.5),
              closeTo(p.curve.speedAtSource(x + (1 - x) * 0.5), 1e-9));
        }
      }
    });
  });

  group('json', () {
    test('round-trips with its preset id', () {
      final c = speedCurvePresetById('hero')!.curve;
      final back = SpeedCurve.fromJson(c.toJson());
      expect(back, c);
      expect(back!.presetId, 'hero');
    });

    test('junk reads as no curve, and a thin list is padded to span the clip',
        () {
      expect(SpeedCurve.fromJson(null), isNull);
      expect(SpeedCurve.fromJson('x'), isNull);
      expect(SpeedCurve.fromJson({'points': []}), isNull);
      expect(SpeedCurve.fromJson({'points': [{'x': 0, 'speed': 1}]}), isNull);
      // Unsorted and not reaching the ends: sorted, then held flat to 0 and 1.
      final c = SpeedCurve.fromJson({
        'points': [
          {'x': 0.8, 'speed': 2},
          {'x': 0.2, 'speed': 1},
        ],
      })!;
      expect(c.points.map((p) => p.x), [0, 0.2, 0.8, 1]);
      expect(c.points.first.speed, 1);
      expect(c.points.last.speed, 2);
    });

    test('equality is structural', () {
      final a = SpeedCurve(const [SpeedPoint(0, 1), SpeedPoint(1, 2)]);
      final b = SpeedCurve(const [SpeedPoint(0, 1), SpeedPoint(1, 2)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(SpeedCurve(const [SpeedPoint(0, 1), SpeedPoint(1, 3)])));
    });
  });
}
