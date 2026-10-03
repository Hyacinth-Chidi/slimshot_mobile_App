import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';

import '../../../support/test_fonts.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async =>
      (await Directory.systemTemp.createTemp('text_size_test_')).path;
}

/// A text's Size: its letters, as a fraction of the frame — separate from its
/// scale, which is the whole text as an object.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  const canvas = Size(400, 700);

  TextOverlayModel text({
    double? size,
    Size? ref = canvas,
    String words = 'Hello',
    double? boxWidth,
  }) =>
      TextOverlayModel(
        id: 't',
        text: words,
        fontFamily: kTestFontFamily,
        referenceCanvasSize: ref,
        fontSize: size,
        boxWidth: boxWidth,
      );

  group('the model', () {
    test('a size survives a draft, and a text without one stays without', () {
      expect(TextOverlayModel.fromJson(text(size: 150).toJson()).fontSize, 150);
      // Every text saved before sizes existed reads exactly as it was saved.
      expect(text().toJson().containsKey('fontSize'), isFalse);
      expect(TextOverlayModel.fromJson(text().toJson()).fontSize, isNull);
    });

    test('a damaged size is held inside the ruler, and junk reads as none', () {
      Map<String, dynamic> withSize(Object value) =>
          text().toJson()..['fontSize'] = value;
      expect(TextOverlayModel.fromJson(withSize(5000)).fontSize, kMaxTextSize);
      expect(TextOverlayModel.fromJson(withSize(-3)).fontSize, kMinTextSize);
      expect(TextOverlayModel.fromJson(withSize('big')).fontSize, isNull);
    });

    test('copies keep it', () {
      final sized = text(size: 150);
      expect(sized.copyWith(text: 'Other').fontSize, 150);
      expect(sized.copyWith(fontSize: 90).fontSize, 90);
    });
  });

  group('the Size a text shows', () {
    test('its own, when it has one', () {
      expect(textSizeOf(text(size: 150), canvas), 150);
    });

    test('for a text made before sizes, the one its letters have', () {
      // 32 px letters on a frame whose short side is 400: 80 thousandths.
      expect(textSizeOf(text(), canvas), closeTo(80, 1e-9));
      // With no reference canvas, the one it is drawn on.
      expect(textSizeOf(text(ref: null), const Size(320, 569)), closeTo(100, 1e-9));
    });

    test('moving the ruler on an old text starts where its letters are', () {
      final old = text(words: 'Hello there friends', boxWidth: 200);
      final explicit = old.copyWith(fontSize: textSizeOf(old, canvas));
      final a = TextOverlayLayout.measure(old, canvas);
      final b = TextOverlayLayout.measure(explicit, canvas);
      expect(b.inkScale, closeTo(a.inkScale, 1e-9));
      expect(b.boxSize.width, closeTo(a.boxSize.width, 1e-6));
      expect(b.boxSize.height, closeTo(a.boxSize.height, 1e-6));
    });
  });

  group('the layout', () {
    test('an old text measures exactly as it always did', () {
      // Drawn at twice its reference canvas: everything doubles, as before.
      final layout =
          TextOverlayLayout.measure(text(ref: const Size(200, 350)), canvas);
      expect(layout.canvasScale, 2);
      expect(layout.inkScale, 2);
    });

    test('Size is a fraction of the frame, so it looks the same on any phone', () {
      for (final frame in const [Size(200, 356), Size(400, 711), Size(270, 480)]) {
        final layout = TextOverlayLayout.measure(text(size: 100, ref: frame), frame);
        // Size 100: the letters' em is a tenth of the frame's short side.
        expect(
          layout.inkScale * kTextOverlayFontSize,
          closeTo(frame.shortestSide / 10, 1e-9),
          reason: '$frame',
        );
      }
    });

    test('a landscape frame sizes by its short side, not its width', () {
      const landscape = Size(711, 400);
      final layout =
          TextOverlayLayout.measure(text(size: 100, ref: landscape), landscape);
      expect(layout.inkScale * kTextOverlayFontSize, closeTo(40, 1e-9));
    });

    test("a bigger Size re-wraps inside the text's width", () {
      final base = text(size: 100, words: 'one two three four five six', boxWidth: 300);
      final a = TextOverlayLayout.measure(base, canvas);
      final b = TextOverlayLayout.measure(base.copyWith(fontSize: 200), canvas);
      // The width is the text's own, so it stays...
      expect(b.boxSize.width, closeTo(a.boxSize.width, 1e-6));
      // ...and the letters, twice as big, need more lines: more than twice
      // the height.
      expect(b.textHeight, greaterThan(a.textHeight * 2));
    });

    test('the style grows with the letters, so a look keeps its proportions', () {
      final styled = text(size: 100).copyWith(
        backgroundColor: Colors.black,
        backgroundPadding: 12,
        strokeColor: Colors.black,
        strokeWidth: 4,
        shadowColor: Colors.black,
        shadowBlurRadius: 6,
        shadowDistance: 3,
      );
      final a = TextOverlayLayout.measure(styled, canvas);
      final b = TextOverlayLayout.measure(styled.copyWith(fontSize: 200), canvas);
      expect(b.inkScale, closeTo(a.inkScale * 2, 1e-9));
      expect(b.canvasScale, a.canvasScale);
      expect(b.outerPadding, closeTo(a.outerPadding * 2, 1e-9));
      expect(b.backgroundPaddingH, closeTo(a.backgroundPaddingH * 2, 1e-9));
      // The shadow's offset doubles, and its blur is the doubled radius's —
      // Flutter's sigma for a radius is not proportional to it (it adds half a
      // pixel), so the radius, not the sigma, is what keeps proportion.
      expect(
        TextOverlayLayout.shadowOffsetFor(styled, b.inkScale).distance,
        closeTo(TextOverlayLayout.shadowOffsetFor(styled, a.inkScale).distance * 2, 1e-9),
      );
      expect(
        TextOverlayLayout.shadowSigmaFor(styled, b.inkScale),
        closeTo(Shadow.convertRadiusToSigma(6 * a.inkScale * 2), 1e-9),
      );
    });
  });

  group('drawn at a size', () {
    test('the letters grow with it and stay inside their box', () {
      final small = TextOverlayPainter.glyphBoxesFor(text(size: 100, words: 'Hi'), canvas);
      final bigText = text(size: 200, words: 'Hi');
      final big = TextOverlayPainter.glyphBoxesFor(bigText, canvas);
      expect(big.first.inkRect.height, closeTo(small.first.inkRect.height * 2, 1.0));
      final box = Offset.zero & TextOverlayLayout.measure(bigText, canvas).boxSize;
      for (final g in big) {
        expect(box.inflate(0.5).contains(g.inkRect.topLeft), isTrue);
        expect(box.inflate(0.5).contains(g.inkRect.bottomRight), isTrue);
      }
    });

    test("the export's letters grow with the size", () async {
      // The box alone comes from the layout, so it would agree even if the
      // raster drew its letters at the canvas's scale. The ink cannot.
      Future<double> inkHeight(double size) async {
        final raster = await TextOverlayRasterizer.rasterize(
          overlay: text(size: size, words: 'Hi'),
          canvasSize: canvas,
          rasterScale: 1,
        );
        final codec =
            await ui.instantiateImageCodec(await File(raster!.pngPath).readAsBytes());
        final image = (await codec.getNextFrame()).image;
        final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        var top = image.height;
        var bottom = -1;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            if (data.getUint8((y * image.width + x) * 4 + 3) > 128) {
              if (y < top) top = y;
              if (y > bottom) bottom = y;
            }
          }
        }
        image.dispose();
        return (bottom - top + 1).toDouble();
      }

      final small = await inkHeight(100);
      final big = await inkHeight(200);
      expect(small, greaterThan(10));
      expect(big / small, closeTo(2, 0.15));
    });

    test('the export draws the same box', () async {
      final sized = text(size: 200, words: 'Big words wrap');
      final layout = TextOverlayLayout.measure(sized, canvas);
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: sized,
        canvasSize: canvas,
        rasterScale: 1,
      );
      expect(atlas!.canvasPxSize, layout.boxSize);
      final flat = await TextOverlayRasterizer.rasterize(
        overlay: sized,
        canvasSize: canvas,
        rasterScale: 1,
      );
      expect(flat!.canvasPxSize, layout.boxSize);
    });
  });
}
