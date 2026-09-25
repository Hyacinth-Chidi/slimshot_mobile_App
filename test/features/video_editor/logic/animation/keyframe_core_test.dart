import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/keyframe_core.dart';

/// What a diamond does, for any set of named parameters.
///
/// Clips and overlays are both thin adapters over these functions, so every
/// rule a diamond obeys is pinned here once, against a toy two-parameter set
/// that knows nothing about either.
enum _P { a, b }

void main() {
  const tol = 0.01;

  KeyframeParams<_P> flat({double a = 1, double b = 10}) => {
        _P.a: AnimatableDouble(baseValue: a),
        _P.b: AnimatableDouble(baseValue: b),
      };

  /// a: 0 → 1 across the whole span; b: 10 held, keyframed at the same two
  /// instants so the set has one pair of diamonds.
  KeyframeParams<_P> ramped() => {
        _P.a: AnimatableDouble.sorted(baseValue: 0, keyframes: const [
          Keyframe(progress: 0.2, value: 0),
          Keyframe(progress: 0.8, value: 1),
        ]),
        _P.b: AnimatableDouble.sorted(baseValue: 10, keyframes: const [
          Keyframe(progress: 0.2, value: 10),
          Keyframe(progress: 0.8, value: 20),
        ]),
      };

  double at(KeyframeParams<_P> p, _P key, double progress) =>
      p[key]!.resolveAt(progress);

  group('capture', () {
    test('pins every parameter at its resolved value — nothing moves', () {
      final before = ramped();
      final after = captureKeyframeIn(before, 0.5);
      for (final progress in [0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0]) {
        for (final key in _P.values) {
          expect(at(after, key, progress), closeTo(at(before, key, progress), 1e-9),
              reason: '$key at $progress');
        }
      }
      expect(keyframeProgressesIn(after), [0.2, 0.5, 0.8]);
    });

    test('on an existing diamond keeps it: no duplicate, curve and all', () {
      final twice = captureKeyframeIn(captureKeyframeIn(ramped(), 0.5), 0.5);
      expect(keyframeProgressesIn(twice), [0.2, 0.5, 0.8]);
      expect(twice[_P.a]!.keyframes, hasLength(3));
      // A split that lands exactly on a diamond pins the cut there; replacing
      // it with a fresh linear keyframe straightened the curve leaving it.
      final eased = setKeyframeCurveIn(
          ramped(), 0.5, tol, KeyframeInterpolation.cubicInOut);
      final again = captureKeyframeIn(eased, 0.2);
      for (final key in _P.values) {
        expect(again[key]!.keyframes.first.interpolation,
            KeyframeInterpolation.cubicInOut);
      }
    });
  });

  group('remove', () {
    test('the last diamond hands its value back as the base', () {
      final one = captureKeyframeIn(flat(a: 3), 0.4);
      final edited = writeKeyframedValueIn(one, _P.a, 7,
          playheadProgress: 0.4, tolerance: tol);
      final removed = removeKeyframeIn(edited, 0.4, tol);
      expect(hasKeyframesIn(removed), isFalse);
      expect(removed[_P.a]!.baseValue, 7);
    });

    test('with nothing near returns the very same map', () {
      final p = ramped();
      expect(identical(removeKeyframeIn(p, 0.5, tol), p), isTrue);
    });
  });

  group('move', () {
    test('moves every parameter\'s keyframe together, value and curve kept',
        () {
      final moved = moveKeyframeIn(ramped(), 0.8, 0.6, tol)!;
      expect(keyframeProgressesIn(moved), [0.2, 0.6]);
      expect(at(moved, _P.a, 0.6), 1);
      expect(at(moved, _P.b, 0.6), 20);
    });

    test('refuses to land on another diamond', () {
      expect(moveKeyframeIn(ramped(), 0.8, 0.2, tol), isNull);
    });

    test('refuses when there is no diamond to pick up', () {
      expect(moveKeyframeIn(ramped(), 0.5, 0.6, tol), isNull);
    });
  });

  group('the edit rule', () {
    test('with no keyframes, writes the base', () {
      final out = writeKeyframedValueIn(flat(), _P.a, 5,
          playheadProgress: 0.5, tolerance: tol);
      expect(out[_P.a]!.baseValue, 5);
      expect(hasKeyframesIn(out), isFalse);
    });

    test('with no playhead on the item, writes the base', () {
      final out = writeKeyframedValueIn(ramped(), _P.a, 5,
          playheadProgress: null, tolerance: tol);
      expect(out[_P.a]!.baseValue, 5);
      expect(keyframeProgressesIn(out), [0.2, 0.8]);
    });

    test('on a diamond, writes that keyframe and leaves the base alone', () {
      final out = writeKeyframedValueIn(ramped(), _P.a, 0.3,
          playheadProgress: 0.8, tolerance: tol);
      expect(at(out, _P.a, 0.8), 0.3);
      expect(out[_P.a]!.baseValue, 0);
      expect(keyframeProgressesIn(out), [0.2, 0.8]);
    });

    test('between diamonds, places exactly one and captures the others', () {
      final before = ramped();
      final out = writeKeyframedValueIn(before, _P.a, 0.9,
          playheadProgress: 0.5, tolerance: tol);
      expect(keyframeProgressesIn(out), [0.2, 0.5, 0.8]);
      expect(at(out, _P.a, 0.5), 0.9);
      // b was not edited, so it holds exactly what it showed there.
      expect(at(out, _P.b, 0.5), closeTo(at(before, _P.b, 0.5), 1e-9));
    });

    test('successive writes at one instant never add a second diamond', () {
      // A gesture writes every frame; the first frame places the diamond and
      // the rest must find it.
      var p = ramped();
      for (var i = 0; i < 30; i++) {
        p = writeKeyframedValueIn(p, _P.a, i / 30,
            playheadProgress: 0.5, tolerance: tol);
      }
      expect(keyframeProgressesIn(p), [0.2, 0.5, 0.8]);
    });
  });

  group('curves', () {
    test('the target is the segment the playhead is inside', () {
      expect(keyframeCurveTargetIn(ramped(), 0.5, tol), 0.2);
      expect(keyframeCurveTargetIn(ramped(), 0.1, tol), isNull);
      // On the last diamond, the segment arriving at it.
      expect(keyframeCurveTargetIn(ramped(), 0.8, tol), 0.2);
    });

    test('setting a curve re-eases every parameter, placing nothing', () {
      final out = setKeyframeCurveIn(
          ramped(), 0.5, tol, KeyframeInterpolation.cubicInOut);
      expect(keyframeProgressesIn(out), [0.2, 0.8]);
      expect(keyframeCurveAtIn(out, 0.2), KeyframeInterpolation.cubicInOut);
      for (final key in _P.values) {
        expect(out[key]!.keyframes.first.interpolation,
            KeyframeInterpolation.cubicInOut);
      }
    });

    test('no target leaves the very same map', () {
      final p = ramped();
      expect(
        identical(
          setKeyframeCurveIn(p, 0.1, tol, KeyframeInterpolation.cubicInOut),
          p,
        ),
        isTrue,
      );
    });
  });

  group('split', () {
    test('pins the cut and rescales each half into its own 0..1', () {
      final left = splitKeyframesIn(ramped(), 0.5, isLeft: true);
      final right = splitKeyframesIn(ramped(), 0.5, isLeft: false);
      // The seam reads the same value from both sides.
      expect(at(left, _P.a, 1.0), closeTo(at(ramped(), _P.a, 0.5), 1e-9));
      expect(at(right, _P.a, 0.0), closeTo(at(ramped(), _P.a, 0.5), 1e-9));
      void near(List<double> actual, List<double> expected) {
        expect(actual, hasLength(expected.length));
        for (var i = 0; i < expected.length; i++) {
          expect(actual[i], closeTo(expected[i], 1e-9));
        }
      }

      near(keyframeProgressesIn(left), [0.4, 1.0]);
      near(keyframeProgressesIn(right), [0.0, 0.6]);
    });

    test('a cut exactly on an eased diamond keeps the curve leaving it', () {
      // Tap a diamond — the playhead lands on it — then split. The travel
      // from that diamond to the next is not cut at all, so the right half
      // must play it exactly as the original did.
      final eased = setKeyframeCurveIn(
          ramped(), 0.5, tol, KeyframeInterpolation.cubicInOut);
      final right = splitKeyframesIn(eased, 0.2, isLeft: false);
      for (final p in [0.1, 0.3, 0.5, 0.7]) {
        expect(at(right, _P.a, p), closeTo(at(eased, _P.a, 0.2 + p * 0.8), 1e-9),
            reason: 'at $p');
      }
    });

    test('a degenerate cut or no keyframes returns the very same map', () {
      final p = ramped();
      expect(identical(splitKeyframesIn(p, 0, isLeft: true), p), isTrue);
      expect(identical(splitKeyframesIn(p, 1, isLeft: false), p), isTrue);
      final f = flat();
      expect(identical(splitKeyframesIn(f, 0.5, isLeft: true), f), isTrue);
    });
  });
}
