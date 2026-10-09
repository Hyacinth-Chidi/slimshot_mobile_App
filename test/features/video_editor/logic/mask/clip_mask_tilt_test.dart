import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';

/// A mask can be tilted: CapCut turns its mask with a two-finger twist on the
/// picture, and the car-crash edit tilts a line mask so the car passes behind
/// it. The angle is degrees, **clockwise** — the way the fingers turn and the
/// way every other rotation in the editor reads.
void main() {
  group('the model', () {
    test('an untilted mask writes exactly the keys it always wrote', () {
      // Drafts and the engine payload stay byte-identical for every mask that
      // was never twisted.
      const m = ClipMask(shape: ClipMaskShape.rectangle, centerX: 0.3);
      expect(m.angle, 0.0);
      expect(m.toJson().keys, [
        'shape',
        'centerX',
        'centerY',
        'width',
        'height',
        'feather',
        'inverted',
        'cornerRadius',
      ]);
    });

    test('a tilt round-trips through a draft', () {
      const m = ClipMask(shape: ClipMaskShape.linear, centerX: 0.4, angle: -59);
      final back = ClipMask.fromJson(jsonDecode(jsonEncode(m.toJson())));
      expect(back, m);
      expect(back.angle, -59);
    });

    test('a stored angle reads folded into (-180, 180], junk as untilted', () {
      double read(Object? angle) =>
          ClipMask.fromJson({'shape': 'circle', 'angle': angle}).angle;
      expect(read(270), -90);
      expect(read(-190), 170);
      expect(read(540), 180);
      expect(read('left'), 0);
      expect(ClipMask.fromJson({'shape': 'circle'}).angle, 0);
    });

    test('the tilt is part of what makes two masks the same', () {
      expect(
        const ClipMask(shape: ClipMaskShape.rectangle, angle: 10) ==
            const ClipMask(shape: ClipMaskShape.rectangle),
        isFalse,
      );
      expect(const ClipMask(shape: ClipMaskShape.rectangle).copyWith(angle: 10).angle, 10);
    });
  });

  group('the twist snaps to straight', () {
    test('within 3 degrees of a right angle it lands on it', () {
      expect(snapMaskAngle(88), 90);
      expect(snapMaskAngle(-2.5), 0);
      expect(snapMaskAngle(178.5), 180);
      expect(snapMaskAngle(-179), 180);
      expect(snapMaskAngle(-91), -90);
    });

    test('further away it is left alone, folded into (-180, 180]', () {
      expect(snapMaskAngle(45), 45);
      expect(snapMaskAngle(93.5), 93.5);
      expect(snapMaskAngle(400), 40);
      expect(snapMaskAngle(double.nan), 0);
    });
  });

  group('coverage', () {
    test('a tall window turned a quarter is a wide one', () {
      const tall = ClipMask(
        shape: ClipMaskShape.rectangle,
        width: 0.2,
        height: 0.6,
        feather: 0.0,
        angle: 90,
      );
      expect(maskCoverage(tall, 0.75, 0.5), 1.0);
      expect(maskCoverage(tall, 0.5, 0.75), 0.0);
    });

    test('it turns clockwise, as the fingers do', () {
      // A line keeps the left of itself. Turned a quarter clockwise, the left
      // swings up: it keeps the top.
      const line = ClipMask(shape: ClipMaskShape.linear, angle: 90);
      expect(maskCoverage(line, 0.5, 0.1), 1.0);
      expect(maskCoverage(line, 0.5, 0.9), 0.0);
    });

    test('a half turn keeps the other side of a line', () {
      const line = ClipMask(shape: ClipMaskShape.linear, angle: 180);
      expect(maskCoverage(line, 0.9, 0.5), 1.0);
      expect(maskCoverage(line, 0.1, 0.5), 0.0);
    });

    test('it turns on the picture\'s real proportions, so a round window stays round',
        () {
      // A 9:16 picture. A window 0.3 of the height tall and 0.3 / (9/16) of
      // the width wide is a circle in pixels — and a circle looks the same at
      // any angle. Turning raw fractions instead would squash it into a
      // tilted ellipse on any frame that is not square.
      const aspect = 9 / 16;
      const round = ClipMask(
        shape: ClipMaskShape.circle,
        width: 0.3 / aspect,
        height: 0.3,
        feather: 0.04,
      );
      for (final angle in [17.0, 45.0, 90.0, -120.0]) {
        final turned = round.copyWith(angle: angle);
        for (var i = 0; i <= 20; i++) {
          for (var j = 0; j <= 20; j++) {
            final x = i / 20, y = j / 20;
            expect(
              maskCoverage(turned, x, y, aspect: aspect),
              closeTo(maskCoverage(round, x, y, aspect: aspect), 1e-9),
              reason: '$angle° at ($x, $y)',
            );
          }
        }
      }
    });

    test('an untilted window ignores the proportions entirely', () {
      // Every existing project: the frame's shape cannot change what an
      // untilted mask keeps.
      for (final shape in [
        ClipMaskShape.rectangle,
        ClipMaskShape.circle,
        ClipMaskShape.linear,
        ClipMaskShape.roundedRectangle,
      ]) {
        final m = ClipMask(shape: shape, centerX: 0.4, centerY: 0.6, width: 0.5, height: 0.3);
        for (var i = 0; i <= 10; i++) {
          for (var j = 0; j <= 10; j++) {
            expect(
              maskCoverage(m, i / 10, j / 10, aspect: 0.5625),
              maskCoverage(m, i / 10, j / 10),
              reason: '$shape at (${i / 10}, ${j / 10})',
            );
          }
        }
      }
    });
  });

  group('the uniforms', () {
    test('a third vec4 carries the tilt as its cosine and sine', () {
      expect(
        maskUniforms(const ClipMask(shape: ClipMaskShape.rectangle)).sublist(8),
        [1.0, 0.0, 0.0, 0.0],
      );
      final turned =
          maskUniforms(const ClipMask(shape: ClipMaskShape.rectangle, angle: -59))
              .sublist(8);
      expect(turned[0], closeTo(math.cos(-59 * math.pi / 180), 1e-12));
      expect(turned[1], closeTo(math.sin(-59 * math.pi / 180), 1e-12));
      expect(turned.sublist(2), [0.0, 0.0]);
    });

    test('no mask is still no mask, and the same length', () {
      final none = maskUniforms(ClipMask.none);
      expect(none, hasLength(12));
      expect(none.first, 0.0);
    });
  });

  group('the canvas gesture', () {
    const start = ClipMask(
      shape: ClipMaskShape.rectangle,
      centerX: 0.5,
      centerY: 0.5,
      width: 0.4,
      height: 0.4,
      angle: 10,
    );

    test('a twist adds its turn, clockwise, to the angle the gesture began on', () {
      final next = maskAfterGesture(start, rotationRadians: 30 * math.pi / 180);
      expect(next.angle, closeTo(40, 1e-9));
    });

    test('a twist that ends near straight lands on it', () {
      final next = maskAfterGesture(start, rotationRadians: 81 * math.pi / 180);
      expect(next.angle, 90);
    });

    test('moving and pinching are what they always were', () {
      final next = maskAfterGesture(start, pan: const Offset(0.1, -0.2), scale: 1.5);
      expect(next.centerX, closeTo(0.6, 1e-9));
      expect(next.centerY, closeTo(0.3, 1e-9));
      expect(next.width, closeTo(0.6, 1e-9));
      expect(next.height, closeTo(0.6, 1e-9));
      expect(next.angle, 10, reason: 'no twist, no turn');
    });

    test('the window stays on the picture and inside the sizes the tool makes', () {
      final next = maskAfterGesture(start, pan: const Offset(2, -2), scale: 100);
      expect(next.centerX, 1.0);
      expect(next.centerY, 0.0);
      expect(next.width, 2.0);
      expect(next.height, 2.0);
    });

    test('the readout is the angle, whole degrees', () {
      expect(maskAngleLabel(-59.4), '-59°');
      expect(maskAngleLabel(90), '90°');
      expect(maskAngleLabel(0.2), '0°');
    });
  });
}
