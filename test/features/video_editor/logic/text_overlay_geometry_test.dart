import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

void main() {
  group('textOverlayFitBox', () {
    // The native overlay pass contain-fits inside a pixel-square box. A wide
    // raster handed over in its own rectangle was squashed to a fraction of
    // its height (the fit applied the aspect a second time); in a square of
    // its longer side the fit lands on the raster's exact size.
    test('a wide raster gets a square of its width', () {
      expect(textOverlayFitBox(const Size(400, 60)), const Size(400, 400));
    });

    test('a tall raster gets a square of its height', () {
      expect(textOverlayFitBox(const Size(120, 300)), const Size(300, 300));
    });

    test('contain-fitting the raster into its square returns its own size', () {
      const raster = Size(400, 60);
      final box = textOverlayFitBox(raster);
      // OverlayRenderer.writeCorners, verbatim.
      final aspect = raster.width / raster.height;
      final fitW = aspect >= 1 ? 1.0 : aspect;
      final fitH = aspect >= 1 ? 1 / aspect : 1.0;
      expect(box.width * fitW, closeTo(raster.width, 1e-9));
      expect(box.height * fitH, closeTo(raster.height, 1e-9));
    });
  });

  group('textOverlayRenderScale', () {
    test('is the smaller of the two axis ratios', () {
      final overlay = TextOverlayModel(
        id: 't',
        text: 'hi',
        referenceCanvasSize: const Size(400, 700),
      );
      expect(textOverlayRenderScale(overlay, const Size(800, 1400)), 2.0);
      expect(textOverlayRenderScale(overlay, const Size(800, 700)), 1.0);
    });

    test('is 1 without a reference canvas', () {
      final overlay = TextOverlayModel(id: 't', text: 'hi');
      expect(textOverlayRenderScale(overlay, const Size(800, 1400)), 1.0);
    });
  });

  group('clampTextOverlayPosition', () {
    test('keeps the centre on the canvas, in reference pixels', () {
      const canvas = Size(400, 800);
      expect(
        clampTextOverlayPosition(const Offset(1000, -1000), canvas, 2.0),
        const Offset(100, -200),
      );
      expect(
        clampTextOverlayPosition(const Offset(10, 20), canvas, 2.0),
        const Offset(10, 20),
      );
    });
  });

  group('TextOverlayRasterizer.effectiveRasterScale', () {
    test('folds the pinch scale into the density', () {
      expect(
        TextOverlayRasterizer.effectiveRasterScale(
          rasterScale: 2.5,
          overlayScale: 3.0,
          canvasPxSize: const Size(100, 40),
        ),
        7.5,
      );
    });

    test('never drops below canvas density', () {
      expect(
        TextOverlayRasterizer.effectiveRasterScale(
          rasterScale: 1.0,
          overlayScale: 0.2,
          canvasPxSize: const Size(100, 40),
        ),
        1.0,
      );
    });

    test('caps the raster at the texture limit', () {
      final density = TextOverlayRasterizer.effectiveRasterScale(
        rasterScale: 4.0,
        overlayScale: 5.0,
        canvasPxSize: const Size(400, 100),
      );
      expect(density * 400, lessThanOrEqualTo(TextOverlayRasterizer.kMaxRasterSidePx));
      expect(density, closeTo(4096 / 400, 1e-9));
    });
  });
}
