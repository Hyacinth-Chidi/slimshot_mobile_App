import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

/// A clip's transform and volume became [AnimatableDouble]s so a diamond on the
/// timeline can pin them at an instant.
///
/// **The whole risk of that change is that it is supposed to be invisible.** A
/// clip nobody has keyframed must render, serialise and compose exactly as it
/// did when these were plain doubles — same numbers in the draft, same numbers
/// on the wire, same values resolved at every progress. Most of this file
/// exists to pin that, not the new behaviour.
void main() {
  group('a clip with no keyframes is exactly what it was', () {
    test('json is bare numbers, not maps', () {
      final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5);
      final json = s.toJson();

      expect(json['volume'], 1.0);
      expect(json['canvasScale'], 1.0);
      expect(json['canvasOffsetX'], 0.0);
      expect(json['canvasOffsetY'], 0.0);

      // The shape matters as much as the value: a map here would grow every
      // draft already saved and would not load in a build that predates this.
      expect(json['volume'], isA<num>());
      expect(json['canvasScale'], isA<num>());
      expect(json['canvasOffsetX'], isA<num>());
      expect(json['canvasOffsetY'], isA<num>());
    });

    test('a draft of plain numbers loads and resolves flat', () {
      final s = VideoSegment.fromJson(const {
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 5.0,
        'volume': 0.5,
        'canvasScale': 2.0,
        'canvasOffsetX': 0.1,
        'canvasOffsetY': -0.2,
      });

      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(s.volumeAt(t), 0.5, reason: 'volume @ $t');
        expect(s.canvasScaleAt(t), 2.0, reason: 'scale @ $t');
        expect(s.canvasOffsetXAt(t), closeTo(0.1, 1e-9), reason: 'x @ $t');
        expect(s.canvasOffsetYAt(t), closeTo(-0.2, 1e-9), reason: 'y @ $t');
      }
      expect(s.hasKeyframes, isFalse);
    });

    test('a draft with the fields absent falls back to the old defaults', () {
      final s = VideoSegment.fromJson(const {
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 5.0,
      });
      expect(s.volumeAt(0.5), 1.0);
      expect(s.canvasScaleAt(0.5), 1.0);
      expect(s.canvasOffsetXAt(0.5), 0.0);
      expect(s.canvasOffsetYAt(0.5), 0.0);
    });

    test('a malformed field falls back rather than throwing', () {
      // A draft can arrive hand-edited or truncated. A saved project turning
      // into a crash on open is the worst failure this read could have.
      final s = VideoSegment.fromJson(const {
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 5.0,
        'volume': 'loud',
        'canvasScale': null,
        'canvasOffsetX': <String, dynamic>{},
      });
      expect(s.volumeAt(0.5), 1.0);
      expect(s.canvasScaleAt(0.5), 1.0);
      expect(s.canvasOffsetXAt(0.5), 0.0);
    });

    test('an unkeyframed clip round-trips byte for byte', () {
      final s = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 5,
        volume: const AnimatableDouble(baseValue: 0.7),
        canvasScale: const AnimatableDouble(baseValue: 1.4),
      );
      final once = jsonEncode(s.toJson());
      final twice = jsonEncode(VideoSegment.fromJson(jsonDecode(once)).toJson());
      expect(twice, once);
    });
  });

  group('an animated clip', () {
    VideoSegment keyframedScale() => VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 5,
          canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
            Keyframe(progress: 0.0, value: 1.0),
            Keyframe(
              progress: 1.0,
              value: 2.0,
              interpolation: KeyframeInterpolation.bounceOut,
            ),
          ]),
        );

    test('round-trips through json as a map, easing intact', () {
      final restored =
          VideoSegment.fromJson(jsonDecode(jsonEncode(keyframedScale().toJson())));

      // Linear between 1 and 2 — the interpolation belongs to the keyframe the
      // segment *starts* at, which is the default-constructed first one.
      expect(restored.canvasScaleAt(0.5), closeTo(1.5, 1e-9));
      expect(restored.canvasScale.keyframes.last.interpolation,
          KeyframeInterpolation.bounceOut);
      expect(restored.hasKeyframes, isTrue);
    });

    test('an animated field serialises as a map, an untouched one does not', () {
      final json = keyframedScale().toJson();
      expect(json['canvasScale'], isA<Map>());
      // The other three never asked for animation, so they keep the cheap shape.
      expect(json['volume'], isA<num>());
      expect(json['canvasOffsetX'], isA<num>());
      expect(json['canvasOffsetY'], isA<num>());
    });

    test('hasKeyframes reports any property, not just one', () {
      final plain = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5);
      expect(plain.hasKeyframes, isFalse);

      for (final animated in [
        plain.copyWith(
          volume: const AnimatableDouble(
              baseValue: 1.0, keyframes: [Keyframe(progress: 0.5, value: 0.2)]),
        ),
        plain.copyWith(
          canvasOffsetY: const AnimatableDouble(
              baseValue: 0.0, keyframes: [Keyframe(progress: 0.5, value: 0.2)]),
        ),
        plain.copyWith(
          effectIntensity: const AnimatableDouble(
              baseValue: 1.0, keyframes: [Keyframe(progress: 0.5, value: 0.2)]),
        ),
      ]) {
        expect(animated.hasKeyframes, isTrue);
      }
    });

    test('an envelope alone is not a keyframe', () {
      // `hasKeyframes` gates the timeline's diamonds and the notifier's edit
      // rule. An envelope shapes a clip nobody has placed a diamond on, so it
      // must not make the plus button behave as though diamonds existed.
      final s = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 5,
        effectIntensity: const AnimatableDouble(baseValue: 0.8, envelope: 'throb'),
      );
      expect(s.hasKeyframes, isFalse);
      expect(s.effectIntensity.isAnimated, isTrue);
    });
  });

  group('clip progress', () {
    test('is whole-clip and clamped at both ends', () {
      final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4); // duration 4
      expect(s.clipProgressAt(10.0, 10.0), 0.0);
      expect(s.clipProgressAt(11.0, 10.0), 0.25);
      expect(s.clipProgressAt(12.0, 10.0), 0.5);
      expect(s.clipProgressAt(14.0, 10.0), 1.0);
      // Outside the clip in either direction holds at the ends rather than
      // running off — the same rule `resolveAt` follows for progress.
      expect(s.clipProgressAt(99.0, 10.0), 1.0);
      expect(s.clipProgressAt(0.0, 10.0), 0.0);
    });

    test('accounts for speed, because duration does', () {
      // A clip sped up 2× occupies half the timeline, so its midpoint is half
      // its timeline span in — not half its source span.
      final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4, speed: 2.0);
      expect(s.duration, 2.0);
      expect(s.clipProgressAt(11.0, 10.0), 0.5);
    });

    test('a zero-length clip resolves at 0, never NaN', () {
      // A photo clip mid-edit, or a degenerate range from a hand-edited draft.
      // NaN here would reach a shader uniform and paint a black frame.
      final s = VideoSegment(id: 'a', sourceStart: 2, sourceEnd: 2);
      final p = s.clipProgressAt(5.0, 5.0);
      expect(p, 0.0);
      expect(p.isNaN, isFalse);
    });
  });

  group('rotation', () {
    // **Rotation did not exist before this.** The `rotate` tool was a menu
    // entry with no handler, and the only `rotation` in the contract belonged
    // to overlays. This is a clip's own angle, the sixth keyframable property.
    test('defaults to zero and serialises as a bare number', () {
      final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5);
      expect(s.canvasRotationAt(0.5), 0.0);
      // Bare `0.0`, not a map: a clip nobody rotated writes what it always
      // would have, so no draft migration and no growth in saved projects.
      expect(s.toJson()['canvasRotation'], 0.0);
      expect(s.toJson()['canvasRotation'], isA<num>());
    });

    test('a draft without the field loads unrotated', () {
      final s = VideoSegment.fromJson(const {
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 5.0,
      });
      expect(s.canvasRotationAt(0.3), 0.0);
    });

    test('is stored in degrees and round-trips', () {
      // Degrees, not radians: it is what the ruler shows and what a draft
      // should be readable as. The shader converts once.
      final s = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 5,
        canvasRotation: const AnimatableDouble(baseValue: 90.0),
      );
      final restored =
          VideoSegment.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(restored.canvasRotationAt(0.5), 90.0);
    });

    test('keyframes like every other property', () {
      final s = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 5,
        canvasRotation: const AnimatableDouble(baseValue: 0.0, keyframes: [
          Keyframe(progress: 0.0, value: 0.0),
          Keyframe(progress: 1.0, value: 180.0),
        ]),
      );
      expect(s.canvasRotationAt(0.5), closeTo(90.0, 1e-9));
      expect(s.hasKeyframes, isTrue);
    });
  });
}
