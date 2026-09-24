import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';

/// Overlay keyframes ride **beside** the plain fields.
///
/// `position`, `scale`, `rotation` and `opacity` stay exactly what they were —
/// the base values every existing reader already uses — and a track per
/// property sits next to them. An overlay with no tracks is every overlay that
/// exists today, and it must read, write and draw exactly as it did.
void main() {
  /// x from 0 at the start to 100 at the end; opacity 1 → 0 over the same span.
  const glide = OverlayKeyframes({
    OverlayProperty.x: [
      Keyframe(progress: 0, value: 0),
      Keyframe(progress: 1, value: 100),
    ],
    OverlayProperty.opacity: [
      Keyframe(progress: 0, value: 1),
      Keyframe(progress: 1, value: 0),
    ],
  });

  group('OverlayKeyframes', () {
    test('writes nothing when empty — the draft format of today', () {
      expect(OverlayKeyframes.none.isEmpty, isTrue);
      expect(OverlayKeyframes.none.toJson(), isNull);
    });

    test('round-trips through a draft', () {
      final back = OverlayKeyframes.fromJson(glide.toJson());
      expect(back.of(OverlayProperty.x), glide.of(OverlayProperty.x));
      expect(back.of(OverlayProperty.opacity),
          glide.of(OverlayProperty.opacity));
      expect(back.of(OverlayProperty.scale), isEmpty);
    });

    test('reads a hand-edited or future draft without throwing', () {
      // Review Focus: an unknown property is ignored, a malformed entry
      // skipped, and anything that is not a map is no keyframes at all.
      final back = OverlayKeyframes.fromJson({
        'x': [
          {'progress': 0.5, 'value': 20},
          'not a keyframe',
          42,
        ],
        'hue': [
          {'progress': 0.5, 'value': 1},
        ],
        'scale': 'nope',
      });
      expect(back.of(OverlayProperty.x), hasLength(1));
      expect(back.of(OverlayProperty.scale), isEmpty);
      expect(OverlayKeyframes.fromJson(null).isEmpty, isTrue);
      expect(OverlayKeyframes.fromJson('x').isEmpty, isTrue);
      expect(OverlayKeyframes.fromJson([1, 2]).isEmpty, isTrue);
    });
  });

  group('OverlayMotion', () {
    const still = OverlayMotion(
      position: Offset(10, 20),
      scale: 1.5,
      rotation: 0.3,
      opacity: 0.8,
    );

    test('its params are the base values plus the tracks', () {
      final moving = still.copyWithKeyframes(glide);
      final params = moving.params;
      expect(params.keys, OverlayProperty.values);
      expect(params[OverlayProperty.y]!.baseValue, 20);
      expect(params[OverlayProperty.x]!.keyframes, hasLength(2));
      final back = OverlayMotion.fromParams(params);
      expect(back.position, still.position);
      expect(back.scale, still.scale);
      expect(back.rotation, still.rotation);
      expect(back.opacity, still.opacity);
      expect(back.keyframes.of(OverlayProperty.x), glide.of(OverlayProperty.x));
    });

    test('at() resolves between keyframes', () {
      final m = still.copyWithKeyframes(glide).at(0.25);
      expect(m.position.dx, closeTo(25, 1e-9));
      expect(m.position.dy, 20); // no y track: the base holds
      expect(m.opacity, closeTo(0.75, 1e-9));
      expect(m.hasKeyframes, isFalse);
    });

    test('a motion with no keyframes resolves to itself', () {
      expect(identical(still.at(0.5), still), isTrue);
    });
  });

  group('overlayProgressAt', () {
    test('is the fraction of the span, clamped', () {
      const s = Duration(seconds: 2), e = Duration(seconds: 6);
      expect(overlayProgressAt(s, e, 3), closeTo(0.25, 1e-9));
      expect(overlayProgressAt(s, e, 1), 0);
      expect(overlayProgressAt(s, e, 9), 1);
    });

    test('a zero or negative span is progress 0, never NaN', () {
      // Review Focus: an overlay trimmed to nothing, or a hand-edited draft.
      const t = Duration(seconds: 2);
      expect(overlayProgressAt(t, t, 2), 0);
      expect(overlayProgressAt(t, Duration.zero, 2), 0);
    });
  });

  group('the models', () {
    TextOverlayModel text() => TextOverlayModel(
          id: 't',
          text: 'Hi',
          position: const Offset(10, 20),
          startTime: const Duration(seconds: 2),
          endTime: const Duration(seconds: 6),
        );

    test('an old draft opens with no keyframes and a fully present text', () {
      final t = TextOverlayModel.fromJson(const {'id': 't', 'text': 'Hi'});
      expect(t.keyframes.isEmpty, isTrue);
      expect(t.opacity, 1.0);
      final i = ImageOverlayModel.fromJson(const {'id': 'i', 'imagePath': '/p'});
      expect(i.keyframes.isEmpty, isTrue);
      final v = VideoOverlayModel.fromJson(const {'id': 'v', 'videoPath': '/v'});
      expect(v.keyframes.isEmpty, isTrue);
    });

    test('an overlay without keyframes writes no keyframes key', () {
      expect(text().toJson().containsKey('keyframes'), isFalse);
      expect(ImageOverlayModel(id: 'i', imagePath: '/p').toJson()
          .containsKey('keyframes'), isFalse);
      expect(VideoOverlayModel(id: 'v', videoPath: '/v').toJson()
          .containsKey('keyframes'), isFalse);
    });

    test('keyframes and text opacity survive a draft', () {
      final t = TextOverlayModel.fromJson(
        text().copyWith(keyframes: glide, opacity: 0.4).toJson(),
      );
      expect(t.keyframes.of(OverlayProperty.x), glide.of(OverlayProperty.x));
      expect(t.opacity, 0.4);
      final i = ImageOverlayModel.fromJson(
        ImageOverlayModel(id: 'i', imagePath: '/p', keyframes: glide).toJson(),
      );
      expect(i.keyframes.of(OverlayProperty.x), hasLength(2));
      final v = VideoOverlayModel.fromJson(
        VideoOverlayModel(id: 'v', videoPath: '/v', keyframes: glide).toJson(),
      );
      expect(v.keyframes.of(OverlayProperty.opacity), hasLength(2));
    });

    test('a text opacity out of range reads back clamped', () {
      expect(
        TextOverlayModel.fromJson(const {'id': 't', 'text': 'x', 'opacity': 3})
            .opacity,
        1.0,
      );
    });

    test('copyWith carries the keyframes — a duplicate keeps its motion', () {
      final t = text().copyWith(keyframes: glide).copyWith(id: 'u');
      expect(t.keyframes.of(OverlayProperty.x), hasLength(2));
    });

    test('motion and withMotion round-trip the four values and the tracks', () {
      final moved = text().withMotion(
        text().motion.copyWithKeyframes(glide),
      );
      expect(moved.motion.keyframes.of(OverlayProperty.x), hasLength(2));
      expect(moved.position, const Offset(10, 20));
    });

    test('shownAt resolves at the playhead, and is the overlay itself when '
        'nothing is keyframed', () {
      final t = text().copyWith(keyframes: glide);
      // 3s of a 2s–6s span is progress 0.25.
      final shown = t.shownAt(3);
      expect(shown.position.dx, closeTo(25, 1e-9));
      expect(shown.opacity, closeTo(0.75, 1e-9));
      final plain = text();
      expect(identical(plain.shownAt(3), plain), isTrue);

      final i = ImageOverlayModel(
        id: 'i',
        imagePath: '/p',
        startTime: const Duration(seconds: 2),
        endTime: const Duration(seconds: 6),
        keyframes: glide,
      );
      expect(i.shownAt(3).position.dx, closeTo(25, 1e-9));
      final v = VideoOverlayModel(
        id: 'v',
        videoPath: '/v',
        timelineStart: const Duration(seconds: 2),
        timelineEnd: const Duration(seconds: 6),
        keyframes: glide,
      );
      expect(v.shownAt(3).opacity, closeTo(0.75, 1e-9));
    });

    test('a template restyle leaves the motion alone', () {
      // A template is the look; keyframes are placement.
      final t = kTextTemplates.first.restyle(text().copyWith(keyframes: glide));
      expect(t.keyframes.of(OverlayProperty.x), glide.of(OverlayProperty.x));
    });
  });
}
