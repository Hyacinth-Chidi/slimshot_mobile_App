import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

/// The minimum a draft needs to be readable, so each test can state only the
/// fields it is actually about.
Map<String, dynamic> _draft(Map<String, dynamic> extra) => {
      'id': 't1',
      'text': 'hello',
      ...extra,
    };

void main() {
  group('schema 0 — a draft written before speeds existed', () {
    // The stored field held a *duration* then and holds a *speed* now, and the
    // two ranges overlap (0.5–2.0), so no value can identify itself. The marker
    // decides, never the number.
    //
    // 1.0 is not merely a safe default, it is exactly faithful: the old preview
    // played flutter_animate's stock 0.5s and the composer hardcoded 0.5, so
    // the stored duration was already ignored by everything that drew anything.
    for (final stored in <double>[0.1, 0.3, 0.5, 1.0, 2.0]) {
      test('a stored duration of ${stored}s loads as speed 1.0', () {
        final overlay = TextOverlayModel.fromJson(_draft({
          'animationInDuration': stored,
          'animationOutDuration': stored,
        }));

        expect(overlay.animationInDuration, 1.0);
        expect(overlay.animationOutDuration, 1.0);
      });
    }

    test('an explicit animationSchema: 0 is treated the same as an absent one',
        () {
      final overlay = TextOverlayModel.fromJson(_draft({
        'animationSchema': 0,
        'animationInDuration': 0.2,
        'animationOutDuration': 1.8,
      }));

      expect(overlay.animationInDuration, 1.0);
      expect(overlay.animationOutDuration, 1.0);
    });

    test('a loop is absent from an old draft and defaults to none', () {
      final overlay = TextOverlayModel.fromJson(_draft({
        'animationInDuration': 0.4,
      }));

      expect(overlay.loopAnimation, 'none');
      expect(overlay.loopSpeed, 1.0);
    });
  });

  group('schema 1 — a draft that stores speeds', () {
    test('a speed round-trips exactly', () {
      final written = TextOverlayModel(
        id: 't1',
        text: 'hello',
        animationInDuration: 2.5,
        animationOutDuration: 0.75,
        loopAnimation: 'wave_loop',
        loopSpeed: 1.75,
      ).toJson();

      final read = TextOverlayModel.fromJson(written);

      expect(read.animationInDuration, 2.5);
      expect(read.animationOutDuration, 0.75);
      expect(read.loopAnimation, 'wave_loop');
      expect(read.loopSpeed, 1.75);
    });

    test('a stored speed above the range clamps to 3.0', () {
      final overlay = TextOverlayModel.fromJson(_draft({
        'animationSchema': 1,
        'animationInDuration': 9.0,
        'animationOutDuration': 4.0,
        'loopSpeed': 100.0,
      }));

      expect(overlay.animationInDuration, 3.0);
      expect(overlay.animationOutDuration, 3.0);
      expect(overlay.loopSpeed, 3.0);
    });

    test('a stored speed below the range clamps to 0.5', () {
      final overlay = TextOverlayModel.fromJson(_draft({
        'animationSchema': 1,
        'animationInDuration': 0.1,
        'animationOutDuration': 0.0,
        // A zero or negative speed divides a duration to infinity downstream;
        // the clamp is what stops that reaching the renderer.
        'loopSpeed': -2.0,
      }));

      expect(overlay.animationInDuration, 0.5);
      expect(overlay.animationOutDuration, 0.5);
      expect(overlay.loopSpeed, 0.5);
    });

    test('a missing speed defaults to 1.0 even at schema 1', () {
      final overlay = TextOverlayModel.fromJson(_draft({
        'animationSchema': 1,
      }));

      expect(overlay.animationInDuration, 1.0);
      expect(overlay.animationOutDuration, 1.0);
      expect(overlay.loopSpeed, 1.0);
    });

    test('a schema newer than this build still reads its speeds', () {
      // Forward compatibility: a draft from a later build carries speeds in the
      // same fields, so reading them is better than discarding them.
      final overlay = TextOverlayModel.fromJson(_draft({
        'animationSchema': 2,
        'animationInDuration': 1.5,
      }));

      expect(overlay.animationInDuration, 1.5);
    });
  });

  group('loop', () {
    test('round-trips, and defaults when absent', () {
      expect(TextOverlayModel.fromJson(_draft({})).loopAnimation, 'none');
      expect(TextOverlayModel.fromJson(_draft({})).loopSpeed, 1.0);

      final overlay = TextOverlayModel.fromJson(_draft({
        'loopAnimation': 'pulse_loop',
        'loopSpeed': 2.0,
        'animationSchema': 1,
      }));
      expect(overlay.loopAnimation, 'pulse_loop');
      expect(overlay.loopSpeed, 2.0);
    });

    test('copyWith carries the loop fields', () {
      final base = TextOverlayModel(id: 't1', text: 'hello');
      final copy = base.copyWith(loopAnimation: 'shake_loop', loopSpeed: 0.6);

      expect(copy.loopAnimation, 'shake_loop');
      expect(copy.loopSpeed, 0.6);
      // The original is untouched, and an omitted field keeps its value.
      expect(base.loopAnimation, 'none');
      expect(copy.animationInDuration, base.animationInDuration);
    });
  });

  group('the wire contract', () {
    // These key names are read by `NativeTimelineOverlay.fromMap` in Kotlin.
    // Nothing on either side type-checks them, so a rename here is an animation
    // that silently stops happening — the export would fall back to defaults
    // and look plausible. Pin the exact strings.
    EditorTimelineOverlay overlay({
      String? animationLoop,
      double speedIn = 1.0,
      double speedOut = 1.0,
      double speedLoop = 1.0,
    }) =>
        EditorTimelineOverlay(
          id: 'o1',
          kind: 'text',
          path: '/tmp/a.png',
          centerX: const AnimatableDouble(baseValue: 0.5),
          centerY: const AnimatableDouble(baseValue: 0.5),
          boxWidth: 0.25,
          boxHeight: 0.25,
          scale: const AnimatableDouble(baseValue: 1),
          rotation: const AnimatableDouble(baseValue: 0),
          opacity: const AnimatableDouble(baseValue: 1),
          startSeconds: 0,
          endSeconds: 3,
          laneIndex: 0,
          slideOffsetX: 0,
          slideOffsetY: 0,
          animationLoop: animationLoop,
          speedIn: speedIn,
          speedOut: speedOut,
          speedLoop: speedLoop,
        );

    test('serialises the loop and the three speeds under the parsed names', () {
      final json = overlay(
        animationLoop: 'wave_loop',
        speedIn: 2.0,
        speedOut: 2.0,
        speedLoop: 0.5,
      ).toJson();

      expect(json['animationLoop'], 'wave_loop');
      expect(json['speedIn'], 2.0);
      expect(json['speedOut'], 2.0);
      expect(json['speedLoop'], 0.5);
    });

    test('an overlay that sets none of them carries the no-op defaults', () {
      // An image or video overlay takes exactly this path — the composer never
      // passes the new arguments for one — so this is what pins "existing
      // overlays are unchanged apart from new keys carrying defaults".
      final json = overlay().toJson();

      expect(json['animationLoop'], isNull);
      // 1.0, never 0: a speed divides a duration, so a zero would make a
      // window infinitely long and freeze the animation on its first frame.
      expect(json['speedIn'], 1.0);
      expect(json['speedOut'], 1.0);
      expect(json['speedLoop'], 1.0);
    });

    test('the untouched overlay keys still serialise as before', () {
      final json = overlay().toJson();

      expect(json['animationIn'], isNull);
      expect(json['animationOut'], isNull);
      expect(json['animationInSeconds'], 0.5);
      expect(json['animationOutSeconds'], 0.5);
      expect(json['kind'], 'text');
      expect(json['opacity'], 1.0);
    });
  });

  group('writing', () {
    test('toJson stamps animationSchema 1', () {
      final json = TextOverlayModel(id: 't1', text: 'hello').toJson();
      expect(json['animationSchema'], 1);
    });

    test('a migrated draft re-saves at schema 1 with its migrated speed', () {
      // The migration is one-way and durable: once an old draft has been read
      // and saved, its speeds are speeds and the marker says so.
      final migrated = TextOverlayModel.fromJson(_draft({
        'animationInDuration': 0.2,
      }));
      final resaved = migrated.toJson();

      expect(resaved['animationSchema'], 1);
      expect(resaved['animationInDuration'], 1.0);

      expect(TextOverlayModel.fromJson(resaved).animationInDuration, 1.0);
    });
  });
}
