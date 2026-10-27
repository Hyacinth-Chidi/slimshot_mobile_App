import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/screens/onboarding_showreel.dart';

void main() {
  group('the loop', () {
    // The owner's call: Zoom Blur first, then the glitch, then the cube.
    test('Zoom Blur plays first, then Glitch, then Cube', () {
      expect([for (final s in kShowreelSteps) s.move],
          [ShowreelMove.zoomBlur, ShowreelMove.glitch, ShowreelMove.cube]);
      expect([for (final s in kShowreelSteps) s.label],
          ['Zoom Blur', 'Glitch', 'Cube']);
    });

    test('each photo rests, then its move takes it to the next', () {
      var start = Duration.zero;
      for (var i = 0; i < kShowreelSteps.length; i++) {
        final step = kShowreelSteps[i];
        final resting = showreelFrameAt(start + step.rest ~/ 2);
        expect(resting.step, i);
        expect(resting.progress, 0);
        expect(resting.from, i);
        final playing = showreelFrameAt(start + step.rest + step.play ~/ 2);
        expect(playing.step, i);
        expect(playing.progress, closeTo(0.5, 0.07));
        expect(playing.from, i);
        expect(playing.to, (i + 1) % kShowreelPhotos.length);
        start += step.rest + step.play;
      }
      expect(start, kShowreelLoop);
      expect(showreelFrameAt(kShowreelLoop), showreelFrameAt(Duration.zero),
          reason: 'round and round');
    });

    test('it opens resting on the first photo, Zoom Blur next', () {
      final first = showreelFrameAt(Duration.zero);
      expect(first.step, 0);
      expect(first.progress, 0);
      expect(first.move, ShowreelMove.zoomBlur);
    });

    // A corrupt frame is wrong, then wrong differently — never sliding.
    test('the glitch is stepped: one picture per tick', () {
      final glitch = kShowreelSteps[1];
      final start = kShowreelSteps[0].rest + kShowreelSteps[0].play + glitch.rest;
      final seen = <double>{};
      for (var ms = 1; ms < glitch.play.inMilliseconds; ms++) {
        final frame = showreelFrameAt(start + Duration(milliseconds: ms));
        expect(frame.move, ShowreelMove.glitch);
        seen.add(frame.progress);
      }
      expect(seen, hasLength(kGlitchTicks));
    });
  });

  group('the glitch', () {
    test('starts on the old photo and lands on the new one, flickering '
        'between', () {
      expect(glitchTickAt(0).showsTo, isFalse);
      expect(glitchTickAt(kGlitchTicks - 2).showsTo, isTrue);
      expect(glitchTickAt(kGlitchTicks - 1).showsTo, isTrue);
      final middle = [
        for (var k = 1; k < kGlitchTicks - 2; k++) glitchTickAt(k).showsTo,
      ];
      expect(middle, containsAll([true, false]));
    });

    test('every tick tears the picture and pulls its colours apart, hardest '
        'in the middle', () {
      for (var k = 0; k < kGlitchTicks; k++) {
        final tick = glitchTickAt(k);
        expect(tick.split, greaterThan(0), reason: 'tick $k');
        expect(tick.tears, isNotEmpty, reason: 'tick $k');
        for (final tear in tick.tears) {
          expect(tear.top, inInclusiveRange(0, 1));
          expect(tear.bottom, inInclusiveRange(tear.top, 1));
          expect(tear.shift.abs(), inInclusiveRange(0.001, 0.2));
        }
      }
      expect(glitchTickAt(kGlitchTicks ~/ 2).split,
          greaterThan(glitchTickAt(0).split));
    });

    test('is the same every time it plays', () {
      for (var k = 0; k < kGlitchTicks; k++) {
        expect(glitchTickAt(k).tears.map((t) => t.shift),
            glitchTickAt(k).tears.map((t) => t.shift));
      }
    });
  });

  group('the cube', () {
    const size = Size(180, 324);
    Offset at(Matrix4 m, double x, double y) =>
        MatrixUtils.transformPoint(m, Offset(x, y));

    test('a face at rest covers the frame exactly', () {
      final face = showreelCubeFace(size, 0, 1);
      expect(at(face, 0, 0), offsetMoreOrLessEquals(Offset.zero));
      expect(at(face, size.width, size.height),
          offsetMoreOrLessEquals(size.bottomRight(Offset.zero)));
      expect(showreelCubeZoom(0), 1);
      expect(showreelCubeZoom(1), 1);
    });

    test('mid-turn the faces meet on one edge, the nearest of the cube', () {
      final zoom = showreelCubeZoom(0.5);
      expect(zoom, lessThan(0.9), reason: 'it backs off as it turns');
      final out = showreelCubeFace(size, math.pi / 4, zoom);
      final into = showreelCubeFace(size, -math.pi / 4, zoom);
      final (w, h) = (size.width, size.height);
      expect(at(out, w, 0), offsetMoreOrLessEquals(at(into, 0, 0)));
      expect(at(out, w, h), offsetMoreOrLessEquals(at(into, 0, h)));
      final shared = at(out, w, h).dy - at(out, w, 0).dy;
      expect(shared, greaterThan(at(out, 0, h).dy - at(out, 0, 0).dy));
      expect(shared, greaterThan(at(into, w, h).dy - at(into, w, 0).dy));
      // The old photo turns away to the left, the new comes from the right.
      expect(at(out, 0, h / 2).dx, lessThan(w / 2));
      expect(at(into, w, h / 2).dx, greaterThan(w / 2));
    });

    test('the new photo comes in from the right', () {
      final into = showreelCubeFace(size, -math.pi / 2 * 0.9, 1);
      for (final (x, y) in [(0.0, 0.0), (0.0, size.height)]) {
        expect(at(into, x, y).dx, greaterThan(size.width / 2));
      }
    });

    test('the turning cube stays inside the frame', () {
      final (w, h) = (size.width, size.height);
      for (var i = 0; i <= 20; i++) {
        final q = i / 20;
        final zoom = showreelCubeZoom(q);
        for (final angle in [q * math.pi / 2, -(1 - q) * math.pi / 2]) {
          final face = showreelCubeFace(size, angle, zoom);
          for (final (x, y) in [(0.0, 0.0), (w, 0.0), (0.0, h), (w, h)]) {
            final p = at(face, x, y);
            expect(p.dx, inInclusiveRange(-0.5, w + 0.5), reason: 'q $q');
            expect(p.dy, inInclusiveRange(-0.5, h + 0.5), reason: 'q $q');
          }
        }
      }
    });
  });

  group('the painter', () {
    const size = Size(180, 324);
    late List<ui.Image> photos;

    Future<void> makePhotos(WidgetTester tester) async {
      photos = (await tester.runAsync(() async => [
                // One at a time: the helper refuses to run alongside itself.
                for (var i = 0; i < 3; i++)
                  await createTestImage(width: 9 + i, height: 16, cache: false),
              ]))!;
      addTearDown(() {
        for (final photo in photos) {
          photo.dispose();
        }
      });
    }

    ShowreelPainter painterAt(ShowreelFrame frame) => ShowreelPainter(
          frame: ValueNotifier(frame),
          photos: photos,
        );

    void paintWith(ShowreelPainter painter, Canvas canvas) =>
        painter.paint(canvas, size);

    // Every image drawn, in order.
    List<ui.Image> imagesDrawn(ShowreelPainter painter) {
      final drawn = <ui.Image>[];
      expect(
        (Canvas canvas) => paintWith(painter, canvas),
        paints
          ..everything((method, args) {
            if (method == #drawImageRect) drawn.add(args[0] as ui.Image);
            return true;
          }),
      );
      return drawn;
    }

    testWidgets('a resting frame draws its photo once', (tester) async {
      await makePhotos(tester);
      final painter = painterAt(const ShowreelFrame(1, 0));
      expect((Canvas c) => paintWith(painter, c),
          paintsExactlyCountTimes(#drawImageRect, 1));
      expect(imagesDrawn(painter), [photos[1]]);
    });

    testWidgets('mid zoom blur smears many copies of both photos',
        (tester) async {
      await makePhotos(tester);
      final drawn = imagesDrawn(painterAt(const ShowreelFrame(0, 0.5)));
      expect(drawn.where((i) => i == photos[0]).length, greaterThan(6));
      expect(drawn.where((i) => i == photos[1]).length, greaterThan(6));
      expect(drawn.toSet(), {photos[0], photos[1]});
    });

    testWidgets('a glitch tick pulls the colour channels apart',
        (tester) async {
      await makePhotos(tester);
      final lefts = <double>{};
      expect(
        (Canvas c) => paintWith(painterAt(showreelFrameAt(
              kShowreelSteps[0].rest +
                  kShowreelSteps[0].play +
                  kShowreelSteps[1].rest +
                  kShowreelSteps[1].play ~/ 2,
            )), c),
        paints
          ..everything((method, args) {
            if (method == #drawImageRect &&
                (args[3] as Paint).blendMode == BlendMode.plus) {
              lefts.add((args[2] as Rect).left);
            }
            return true;
          }),
      );
      expect(lefts.length, greaterThanOrEqualTo(3));
    });

    testWidgets('mid-turn the cube draws both photos over the dark floor',
        (tester) async {
      await makePhotos(tester);
      final painter = painterAt(const ShowreelFrame(2, 0.5));
      expect(
        (Canvas c) => paintWith(painter, c),
        paints..rect(color: AppColors.background),
      );
      expect(imagesDrawn(painter).toSet(), {photos[2], photos[0]});
    });

    testWidgets('a photo still loading draws the dark floor, not a hole',
        (tester) async {
      final painter = ShowreelPainter(
        frame: ValueNotifier(const ShowreelFrame(0, 0)),
        photos: const [null, null, null],
      );
      expect((Canvas c) => painter.paint(c, size),
          paints..rect(color: AppColors.background));
      expect((Canvas c) => painter.paint(c, size),
          paintsExactlyCountTimes(#drawImageRect, 0));
    });
  });
}
