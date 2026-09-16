import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/canvas_geometry.dart';

void main() {
  const fullFrame = Rect.fromLTWH(0, 0, 1, 1);
  const canvas = Size(400, 300);

  group('resolveContentRect', () {
    test('no crop and no zoom shows the whole frame', () {
      final rect = resolveContentRect(
        cropRect: fullFrame,
        videoScale: 1.0,
        videoPan: Offset.zero,
        previewCanvasSize: canvas,
      );

      expect(isFullFrame(rect), isTrue);
    });

    test('zoom narrows the sampled rect about the centre', () {
      final rect = resolveContentRect(
        cropRect: fullFrame,
        videoScale: 2.0,
        videoPan: Offset.zero,
        previewCanvasSize: canvas,
      );

      // 2x zoom shows half the frame in each axis, centred.
      expect(rect.width, closeTo(0.5, 1e-9));
      expect(rect.height, closeTo(0.5, 1e-9));
      expect(rect.center.dx, closeTo(0.5, 1e-9));
      expect(rect.center.dy, closeTo(0.5, 1e-9));
    });

    test('pan moves the sampled rect and stays inside the frame', () {
      final rect = resolveContentRect(
        cropRect: fullFrame,
        videoScale: 2.0,
        // Dragging the picture right shows more of its left side.
        videoPan: const Offset(100, 0),
        previewCanvasSize: canvas,
      );

      expect(rect.center.dx, lessThan(0.5));
      expect(rect.left, greaterThanOrEqualTo(0.0));
      expect(rect.right, lessThanOrEqualTo(1.0));
    });

    test('pan can never push the rect outside the source', () {
      final rect = resolveContentRect(
        cropRect: fullFrame,
        videoScale: 2.0,
        videoPan: const Offset(100000, -100000),
        previewCanvasSize: canvas,
      );

      expect(rect.left, greaterThanOrEqualTo(0.0));
      expect(rect.top, greaterThanOrEqualTo(0.0));
      expect(rect.right, lessThanOrEqualTo(1.0));
      expect(rect.bottom, lessThanOrEqualTo(1.0));
    });

    test('zoom compounds with an existing crop', () {
      final rect = resolveContentRect(
        cropRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
        videoScale: 2.0,
        videoPan: Offset.zero,
        previewCanvasSize: canvas,
      );

      // Half of the already-cropped half.
      expect(rect.width, closeTo(0.25, 1e-9));
      expect(rect.center.dx, closeTo(0.5, 1e-9));
    });

    test('pan is ignored without a canvas size rather than misapplied', () {
      // Pan is stored in preview pixels; with no canvas to convert against,
      // applying it would scale it wrongly.
      final rect = resolveContentRect(
        cropRect: fullFrame,
        videoScale: 2.0,
        videoPan: const Offset(100, 0),
        previewCanvasSize: null,
      );

      expect(isFullFrame(rect), isTrue);
    });

    test('a crop alone survives with no zoom', () {
      final rect = resolveContentRect(
        cropRect: const Rect.fromLTWH(0.1, 0.2, 0.5, 0.6),
        videoScale: 1.0,
        videoPan: Offset.zero,
        previewCanvasSize: canvas,
      );

      expect(rect.left, closeTo(0.1, 1e-9));
      expect(rect.top, closeTo(0.2, 1e-9));
      expect(rect.width, closeTo(0.5, 1e-9));
      expect(rect.height, closeTo(0.6, 1e-9));
    });
  });

  group('contentAspectRatio', () {
    test('a full frame keeps the source aspect', () {
      expect(
        contentAspectRatio(fullFrame, const Size(1920, 1080)),
        closeTo(16 / 9, 1e-9),
      );
    });

    test('a square crop of a landscape source is square', () {
      // 0.5 of width, 0.888 of height on a 16:9 source ≈ 1:1.
      final aspect = contentAspectRatio(
        const Rect.fromLTWH(0.25, 0.0, 0.5, 0.888888),
        const Size(1920, 1080),
      );
      expect(aspect, closeTo(1.0, 0.01));
    });

    test('is null when the source size is unknown', () {
      expect(contentAspectRatio(fullFrame, Size.zero), isNull);
    });
  });

  group('composeCropRects', () {
    test('inner is a fraction of outer, not of the frame', () {
      const outer = Rect.fromLTWH(0.25, 0.0, 0.5, 1.0);
      const inner = Rect.fromLTWH(0.5, 0.0, 0.5, 1.0);
      final r = composeCropRects(outer, inner);
      expect(r.left, closeTo(0.5, 1e-9));
      expect(r.width, closeTo(0.25, 1e-9));
    });

    test('the identity crop changes nothing', () {
      const outer = Rect.fromLTWH(0.1, 0.2, 0.5, 0.6);
      final r = composeCropRects(outer, const Rect.fromLTWH(0, 0, 1, 1));
      expect(r, outer);
    });

    test('never leaves the frame, even from junk', () {
      final r = composeCropRects(
        const Rect.fromLTWH(-1, -1, 5, 5),
        const Rect.fromLTWH(2, 2, 2, 2),
      );
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(1));
      expect(r.bottom, lessThanOrEqualTo(1));
    });
  });


  group('fittedFrameRect', () {
    // The Dart half of Kotlin's `LaneFit.of`: where a clip's picture lands
    // inside the canvas box once contain-fitted. The clip-crop editor draws
    // its handles over *this* rect, not the whole box — a rectangle drawn over
    // a letterboxed clip's bars would crop a region the user never pointed at.
    const box = Size(360, 640);

    test('a wide picture in a tall box keeps full width, bars above and below',
        () {
      final r = fittedFrameRect(contentAspect: 16 / 9, canvasSize: box);
      expect(r.left, closeTo(0, 1e-9));
      expect(r.width, closeTo(360, 1e-9));
      expect(r.height, closeTo(202.5, 1e-9));
      expect(r.top, closeTo(218.75, 1e-9));
    });

    test('a tall picture in a wide box keeps full height, bars either side',
        () {
      final r = fittedFrameRect(
          contentAspect: 9 / 16, canvasSize: const Size(640, 360));
      expect(r.top, closeTo(0, 1e-9));
      expect(r.height, closeTo(360, 1e-9));
      expect(r.width, closeTo(202.5, 1e-9));
      expect(r.left, closeTo(218.75, 1e-9));
    });

    test('a matching shape fills the box', () {
      final r = fittedFrameRect(contentAspect: 9 / 16, canvasSize: box);
      expect(r, const Rect.fromLTWH(0, 0, 360, 640));
    });

    test('an unknown shape fills the box rather than guessing one', () {
      // The same rule `LaneFit.of` follows for an unprobed clip.
      expect(fittedFrameRect(contentAspect: null, canvasSize: box),
          const Rect.fromLTWH(0, 0, 360, 640));
      expect(fittedFrameRect(contentAspect: 0, canvasSize: box),
          const Rect.fromLTWH(0, 0, 360, 640));
    });
  });
}
