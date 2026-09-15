import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';

void main() {
  group('resolveAt', () {
    test('a plain value is flat across the clip', () {
      const p = AnimatableDouble(baseValue: 0.6);
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(p.resolveAt(t), 0.6);
      }
      expect(p.isAnimated, isFalse);
    });

    test('keyframes override an envelope entirely', () {
      // The whole rule of the feature: one keyframe means the user has taken
      // control, and the envelope must not blend into the result.
      const p = AnimatableDouble(
        baseValue: 0.5,
        envelope: 'pulse',
        keyframes: [
          Keyframe(progress: 0, value: 0.1),
          Keyframe(progress: 1, value: 0.9),
        ],
      );
      expect(p.resolveAt(0), closeTo(0.1, 1e-9));
      expect(p.resolveAt(1), closeTo(0.9, 1e-9));
      // Mid-clip must sit between the two keyframes, never wander off on the
      // envelope's curve.
      expect(p.resolveAt(0.5), inInclusiveRange(0.1, 0.9));
    });

    test('a single keyframe holds its value everywhere', () {
      const p = AnimatableDouble(
        baseValue: 0.5,
        keyframes: [Keyframe(progress: 0.5, value: 0.2)],
      );
      expect(p.resolveAt(0), closeTo(0.2, 1e-9));
      expect(p.resolveAt(0.5), closeTo(0.2, 1e-9));
      expect(p.resolveAt(1), closeTo(0.2, 1e-9));
    });

    test('a single keyframe with an envelope still silences the envelope', () {
      // The stricter half of the override rule: it is the *presence* of
      // keyframes that decides, not whether there are enough of them to
      // interpolate between. A one-keyframe parameter that fell back to the
      // envelope would be the one state where both are half-applied.
      const p = AnimatableDouble(
        baseValue: 0.5,
        envelope: 'ramp_in',
        keyframes: [Keyframe(progress: 0.5, value: 0.2)],
      );
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(p.resolveAt(t), closeTo(0.2, 1e-9));
      }
    });

    test('before the first and after the last keyframe, the value holds', () {
      const p = AnimatableDouble(baseValue: 0, keyframes: [
        Keyframe(progress: 0.3, value: 0.2),
        Keyframe(progress: 0.7, value: 0.8),
      ]);
      expect(p.resolveAt(0.0), closeTo(0.2, 1e-9));
      expect(p.resolveAt(0.1), closeTo(0.2, 1e-9));
      expect(p.resolveAt(1.0), closeTo(0.8, 1e-9));
      expect(p.resolveAt(0.9), closeTo(0.8, 1e-9));
    });

    test('linear interpolation is the straight line between two keyframes', () {
      const p = AnimatableDouble(baseValue: 0, keyframes: [
        Keyframe(progress: 0, value: 0, interpolation: KeyframeInterpolation.linear),
        Keyframe(
          progress: 1,
          value: 1,
          interpolation: KeyframeInterpolation.linear,
        ),
      ]);
      expect(p.resolveAt(0.25), closeTo(0.25, 1e-9));
      expect(p.resolveAt(0.5), closeTo(0.5, 1e-9));
      expect(p.resolveAt(0.75), closeTo(0.75, 1e-9));
    });

    test('ease is symmetric about the midpoint and slower at the ends', () {
      const p = AnimatableDouble(baseValue: 0, keyframes: [
        Keyframe(progress: 0, value: 0),
        Keyframe(progress: 1, value: 1),
      ]);
      // Halfway is halfway for any symmetric ease.
      expect(p.resolveAt(0.5), closeTo(0.5, 1e-9));
      // Ease-in-out lags a straight line early and leads it late.
      expect(p.resolveAt(0.25), lessThan(0.25));
      expect(p.resolveAt(0.75), greaterThan(0.75));
      // Symmetry: whatever it gives up early it makes up late.
      expect(p.resolveAt(0.25) + p.resolveAt(0.75), closeTo(1.0, 1e-9));
    });

    test('hold interpolation steps rather than ramps', () {
      // The segment's interpolation comes from the keyframe it *starts* at, so
      // a held keyframe keeps its value right up to the next one and then
      // jumps.
      const p = AnimatableDouble(baseValue: 0, keyframes: [
        Keyframe(
          progress: 0.0,
          value: 0.2,
          interpolation: KeyframeInterpolation.hold,
        ),
        Keyframe(progress: 1.0, value: 0.8),
      ]);
      expect(p.resolveAt(0.0), closeTo(0.2, 1e-9));
      expect(p.resolveAt(0.5), closeTo(0.2, 1e-9));
      expect(p.resolveAt(0.999), closeTo(0.2, 1e-9));
      expect(p.resolveAt(1.0), closeTo(0.8, 1e-9));
    });

    test('unordered keyframes are evaluated in order, not trusted', () {
      // Built through the plain `const` constructor, which cannot sort. The
      // evaluator must still be right: a caller reaching for the obvious
      // constructor is not a caller who opted out of correct values.
      const p = AnimatableDouble(baseValue: 0, keyframes: [
        Keyframe(progress: 0.9, value: 0.9, interpolation: KeyframeInterpolation.linear),
        Keyframe(progress: 0.1, value: 0.1, interpolation: KeyframeInterpolation.linear),
        Keyframe(progress: 0.5, value: 0.5, interpolation: KeyframeInterpolation.linear),
      ]);
      expect(p.resolveAt(0.0), closeTo(0.1, 1e-9));
      expect(p.resolveAt(0.1), closeTo(0.1, 1e-9));
      expect(p.resolveAt(0.3), closeTo(0.3, 1e-9));
      expect(p.resolveAt(0.5), closeTo(0.5, 1e-9));
      expect(p.resolveAt(0.7), closeTo(0.7, 1e-9));
      expect(p.resolveAt(1.0), closeTo(0.9, 1e-9));
    });

    test('the sorting constructor stores them in order', () {
      // A timeline row lets a user drag one keyframe past another, and the
      // stored list is what such a row draws. Sorting here is what keeps the
      // model legible; `resolveAt` above proves the *value* never depended on
      // it.
      final p = AnimatableDouble.sorted(
        baseValue: 0,
        keyframes: const [
          Keyframe(progress: 0.9, value: 0.9),
          Keyframe(progress: 0.1, value: 0.1),
          Keyframe(progress: 0.5, value: 0.5),
        ],
      );
      expect(p.keyframes.map((k) => k.progress).toList(), [0.1, 0.5, 0.9]);
      // …and it hands back a list a caller cannot mutate behind the model's
      // back, since an edit there would desynchronise the row from the value.
      expect(
        () => p.keyframes.add(const Keyframe(progress: 0.2, value: 0.2)),
        throwsUnsupportedError,
      );
    });

    test('fromJson stores keyframes in order whatever the draft says', () {
      final p = AnimatableDouble.fromJson(const {
        'baseValue': 0.0,
        'keyframes': [
          {'progress': 0.9, 'value': 0.9},
          {'progress': 0.1, 'value': 0.1},
        ],
      });
      expect(p.keyframes.map((k) => k.progress).toList(), [0.1, 0.9]);
    });

    test('two keyframes at the same progress do not divide by zero', () {
      // A user can drag one keyframe exactly onto another, and a UI that
      // rejects it is a later concern; the evaluator must not produce NaN in
      // the meantime.
      const p = AnimatableDouble(baseValue: 0, keyframes: [
        Keyframe(progress: 0.5, value: 0.2),
        Keyframe(progress: 0.5, value: 0.8),
      ]);
      for (final t in [0.0, 0.5, 1.0]) {
        expect(p.resolveAt(t).isFinite, isTrue);
      }
    });

    test('an unknown envelope name resolves to the base value', () {
      // Same rule unknown effect and transition ids follow: degrade, never
      // throw.
      const p = AnimatableDouble(baseValue: 0.42, envelope: 'no_such_curve');
      for (final t in [0.0, 0.3, 0.6, 1.0]) {
        expect(p.resolveAt(t), closeTo(0.42, 1e-9));
      }
      // And the raw evaluator says the same thing in multiplier terms.
      expect(resolveEnvelope('no_such_curve', 0.5), closeTo(1.0, 1e-9));
    });

    test('an empty envelope name is treated as no envelope', () {
      const p = AnimatableDouble(baseValue: 0.42, envelope: '');
      expect(p.isAnimated, isFalse);
      expect(p.resolveAt(0.5), closeTo(0.42, 1e-9));
    });

    test('progress outside 0..1 is clamped', () {
      const keyed = AnimatableDouble(baseValue: 0, keyframes: [
        Keyframe(progress: 0.0, value: 0.2),
        Keyframe(progress: 1.0, value: 0.8),
      ]);
      expect(keyed.resolveAt(-5), closeTo(0.2, 1e-9));
      expect(keyed.resolveAt(7), closeTo(0.8, 1e-9));
      // NaN is a real arrival: a clip of zero length divides to it when a
      // caller turns seconds into progress.
      expect(keyed.resolveAt(double.nan), closeTo(0.2, 1e-9));

      const enveloped = AnimatableDouble(baseValue: 0.5, envelope: 'ramp_in');
      expect(enveloped.resolveAt(-1), closeTo(enveloped.resolveAt(0), 1e-9));
      expect(enveloped.resolveAt(2), closeTo(enveloped.resolveAt(1), 1e-9));
    });

    test('an envelope scales the base value', () {
      const p = AnimatableDouble(baseValue: 0.5, envelope: 'ramp_in');
      expect(p.isAnimated, isTrue);
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(p.resolveAt(t), closeTo(0.5 * resolveEnvelope('ramp_in', t), 1e-9));
      }
    });
  });

  group('resolveEnvelope', () {
    test('every seeded envelope is a 0..1 multiplier throughout', () {
      for (final name in kEnvelopeNames) {
        for (var i = 0; i <= 100; i++) {
          final v = resolveEnvelope(name, i / 100);
          expect(v.isFinite, isTrue, reason: '$name at ${i / 100}');
          expect(v, inInclusiveRange(0.0, 1.0), reason: '$name at ${i / 100}');
        }
      }
    });

    test('every envelope rests at full strength on the clip\'s last frame', () {
      // The endpoint rule. An effect caught mid-transition on the final frame
      // pops the instant the next clip starts, so every envelope lands on 1 —
      // the clip's own unmodulated intensity — at p == 1.
      for (final name in kEnvelopeNames) {
        expect(resolveEnvelope(name, 1.0), closeTo(1.0, 1e-9),
            reason: name);
      }
    });

    test('ramp_in opens from nothing and arrives at full strength', () {
      expect(resolveEnvelope('ramp_in', 0.0), closeTo(0.0, 1e-9));
      expect(resolveEnvelope('ramp_in', 1.0), closeTo(1.0, 1e-9));
      // Monotonic: it only ever grows.
      var previous = -1.0;
      for (var i = 0; i <= 100; i++) {
        final v = resolveEnvelope('ramp_in', i / 100);
        expect(v, greaterThanOrEqualTo(previous - 1e-12));
        previous = v;
      }
    });

    test('ramp_out clears away and is gone by the last frame', () {
      expect(resolveEnvelope('ramp_out', 0.0), closeTo(1.0, 1e-9));
      // It reaches nothing *before* the end and stays there, so the effect is
      // already absent when the clip hands over.
      expect(resolveEnvelope('ramp_out', 1.0), closeTo(1.0, 1e-9));
      expect(resolveEnvelope('ramp_out', 0.5), lessThan(0.5));
    });

    test('ramp_in_out opens and closes, full in the middle', () {
      expect(resolveEnvelope('ramp_in_out', 0.0), closeTo(0.0, 1e-9));
      expect(resolveEnvelope('ramp_in_out', 0.5), closeTo(1.0, 1e-9));
      expect(resolveEnvelope('ramp_in_out', 1.0), closeTo(1.0, 1e-9));
    });

    test('pulse beats a whole number of times and ends at rest', () {
      expect(resolveEnvelope('pulse', 0.0), closeTo(1.0, 1e-9));
      expect(resolveEnvelope('pulse', 1.0), closeTo(1.0, 1e-9));
      // It actually moves: a flat "envelope" would pass every other assertion.
      var lowest = 1.0;
      for (var i = 0; i <= 200; i++) {
        lowest = lowest < resolveEnvelope('pulse', i / 200)
            ? lowest
            : resolveEnvelope('pulse', i / 200);
      }
      expect(lowest, lessThan(0.5));
    });

    test('throb breathes without ever dropping the effect entirely', () {
      expect(resolveEnvelope('throb', 0.0), closeTo(1.0, 1e-9));
      expect(resolveEnvelope('throb', 1.0), closeTo(1.0, 1e-9));
      var lowest = 1.0;
      for (var i = 0; i <= 200; i++) {
        final v = resolveEnvelope('throb', i / 200);
        if (v < lowest) lowest = v;
      }
      // Unlike pulse, throb never reaches zero — the effect stays present.
      expect(lowest, greaterThan(0.0));
      expect(lowest, lessThan(1.0));
    });

    test('the names list and the lookup agree', () {
      // A name in the list with no curve behind it would degrade silently to
      // the base value and look like a broken preset.
      for (final name in kEnvelopeNames) {
        expect(resolveEnvelope(name, 0.37), isNot(closeTo(1.0, 1e-12)),
            reason: '$name looks like the unknown-name fallback');
      }
    });
  });

  group('serialisation', () {
    test('a plain value round-trips', () {
      const p = AnimatableDouble(baseValue: 0.65);
      final restored = AnimatableDouble.fromJson(p.toJson());
      expect(restored.baseValue, 0.65);
      expect(restored.envelope, isNull);
      expect(restored.keyframes, isEmpty);
      expect(restored.isAnimated, isFalse);
    });

    test('a plain value serialises as a bare number', () {
      // Nothing is animated, so nothing but the number is worth writing — and
      // a build that has not learned about this model yet still reads it as
      // the double it used to be.
      const p = AnimatableDouble(baseValue: 0.65);
      expect(p.toJson(), 0.65);
    });

    test('an envelope and keyframes round-trip in order', () {
      const p = AnimatableDouble(
        baseValue: 0.4,
        envelope: 'pulse',
        keyframes: [
          Keyframe(progress: 0.8, value: 0.9, interpolation: KeyframeInterpolation.hold),
          Keyframe(progress: 0.2, value: 0.1, interpolation: KeyframeInterpolation.linear),
        ],
      );
      final restored = AnimatableDouble.fromJson(p.toJson());
      expect(restored.baseValue, 0.4);
      expect(restored.envelope, 'pulse');
      expect(restored.keyframes.length, 2);
      expect(restored.keyframes[0].progress, 0.2);
      expect(restored.keyframes[0].value, 0.1);
      expect(restored.keyframes[0].interpolation, KeyframeInterpolation.linear);
      expect(restored.keyframes[1].progress, 0.8);
      expect(restored.keyframes[1].interpolation, KeyframeInterpolation.hold);
      // And it evaluates identically, which is what a round-trip is actually
      // for.
      for (var i = 0; i <= 20; i++) {
        expect(restored.resolveAt(i / 20), closeTo(p.resolveAt(i / 20), 1e-12));
      }
    });

    test('a pre-stage draft (a bare number) loads as a plain value', () {
      // The field was a double before this stage. Reading one must not throw.
      final restored = AnimatableDouble.fromJson(0.75);
      expect(restored.baseValue, 0.75);
      expect(restored.envelope, isNull);
      expect(restored.keyframes, isEmpty);
      expect(restored.resolveAt(0.5), 0.75);
    });

    test('an int from a hand-edited or re-encoded draft loads', () {
      // JSON has one number type; a value that happens to be whole comes back
      // as an int through `jsonDecode`.
      expect(AnimatableDouble.fromJson(1).baseValue, 1.0);
    });

    test('a null or absent field falls back rather than throwing', () {
      expect(AnimatableDouble.fromJson(null).baseValue, 0.0);
      expect(AnimatableDouble.fromJson(null, fallback: 1.0).baseValue, 1.0);
    });

    test('junk in a draft never throws', () {
      // Defensive reads are the house style: a saved project must open in a
      // build that changed the shape under it, and a hand-edited file must not
      // be a crash on open.
      final cases = <dynamic>[
        'not a number',
        <dynamic>[1, 2, 3],
        <String, dynamic>{},
        <String, dynamic>{'baseValue': 'nope'},
        <String, dynamic>{'baseValue': 0.5, 'envelope': 42},
        <String, dynamic>{'baseValue': 0.5, 'keyframes': 'nope'},
        <String, dynamic>{
          'baseValue': 0.5,
          'keyframes': [null, 7, 'x'],
        },
        <String, dynamic>{
          'baseValue': 0.5,
          'keyframes': [
            {'progress': 'x', 'value': null, 'interpolation': 'wobble'},
          ],
        },
      ];
      for (final json in cases) {
        final restored = AnimatableDouble.fromJson(json, fallback: 0.3);
        expect(restored.resolveAt(0.5).isFinite, isTrue, reason: '$json');
      }
    });

    test('an unknown interpolation name degrades to the default', () {
      final k = Keyframe.fromJson(const {
        'progress': 0.5,
        'value': 0.5,
        'interpolation': 'bezier_from_a_future_build',
      });
      expect(k.interpolation, KeyframeInterpolation.ease);
    });

    test('a keyframe round-trips', () {
      const k = Keyframe(
        progress: 0.25,
        value: 0.75,
        interpolation: KeyframeInterpolation.hold,
      );
      final restored = Keyframe.fromJson(k.toJson());
      expect(restored.progress, 0.25);
      expect(restored.value, 0.75);
      expect(restored.interpolation, KeyframeInterpolation.hold);
    });

    test('a keyframe progress out of range is clamped on read', () {
      // Progress is clip-relative 0..1 by definition; a value outside it would
      // sit off the end of every timeline row that draws it.
      final k = Keyframe.fromJson(const {'progress': 4.0, 'value': 0.5});
      expect(k.progress, 1.0);
    });
  });

  group('isAnimated', () {
    test('is true for an envelope, true for keyframes, false for neither', () {
      expect(const AnimatableDouble(baseValue: 1).isAnimated, isFalse);
      expect(
        const AnimatableDouble(baseValue: 1, envelope: 'pulse').isAnimated,
        isTrue,
      );
      expect(
        const AnimatableDouble(
          baseValue: 1,
          keyframes: [Keyframe(progress: 0, value: 0)],
        ).isAnimated,
        isTrue,
      );
      // An unknown envelope is still "animated" as far as the model is
      // concerned — the name is set. It simply resolves flat.
      expect(
        const AnimatableDouble(baseValue: 1, envelope: 'nope').isAnimated,
        isTrue,
      );
    });
  });

  group('equality', () {
    test('two parameters with the same content are equal', () {
      // Timeline pushes are gated on whether anything actually changed; a
      // parameter that compared by identity would rebuild the lanes on every
      // recompose.
      const a = AnimatableDouble(
        baseValue: 0.5,
        envelope: 'pulse',
        keyframes: [Keyframe(progress: 0.5, value: 0.2)],
      );
      const b = AnimatableDouble(
        baseValue: 0.5,
        envelope: 'pulse',
        keyframes: [Keyframe(progress: 0.5, value: 0.2)],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const AnimatableDouble(baseValue: 0.5)));
    });
  });
}
