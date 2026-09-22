import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

import '../../../support/test_fonts.dart';

/// Emoji through the text pipeline.
///
/// The user reports emoji typed from the system keyboard already export
/// correctly, which settles the end-to-end question on a device. These tests
/// pin the parts that can regress *silently* from Dart — glyph counting and
/// atlas packing — so an emoji caption cannot quietly start exporting as
/// boxes or as one glyph per codepoint.
///
/// **What these tests deliberately do NOT claim.** A test environment's font
/// fallback is not the device's: `flutter_test` runs against a bundled test
/// font with no colour emoji face behind it, so asserting "the pixels are
/// coloured" here would pin the harness rather than the product. Colour is a
/// device fact, already confirmed on one. What is portable — and what breaks
/// under a careless edit — is that a multi-codepoint emoji stays **one**
/// glyph and that its cell is well formed.
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    final dir = await Directory.systemTemp.createTemp('emoji_atlas_test_');
    return dir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  TextOverlayModel overlayWith(String text) => TextOverlayModel(
        id: 't',
        text: text,
        fontFamily: kTestFontFamily,
        referenceCanvasSize: const Size(400, 700),
      );

  group('emoji reach the atlas as whole glyphs', () {
    test('a single-codepoint emoji is one glyph', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('\u{1F600}'), // grinning face
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas, isNotNull, reason: 'an emoji is inked text, not whitespace');
      expect(atlas!.glyphs.length, 1);
    });

    test('a multi-codepoint emoji is ONE glyph, not one per codepoint', () async {
      // A flag is two regional indicators and a skin tone is a base plus a
      // modifier; both are single *grapheme clusters*. Splitting by code unit
      // would draw two half-flags and an uncoloured hand, and would also cut
      // a surrogate pair in half — the reason the atlas counts clusters.
      for (final emoji in <String>[
        '\u{1F1EC}\u{1F1E7}', // flag: GB, two regional indicators
        '\u{1F44D}\u{1F3FD}', // thumbs up, medium skin tone
      ]) {
        final atlas = await TextOverlayRasterizer.rasterizeAtlas(
          overlay: overlayWith(emoji),
          canvasSize: const Size(400, 700),
          rasterScale: 1,
        );
        expect(
          atlas!.glyphs.length,
          1,
          reason: '"$emoji" is one grapheme cluster and must be one cell',
        );
      }
    });

    test('emoji mixed with letters keep one cell each', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('a\u{1F600}b'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas!.glyphs.length, 3);
    });

    test('an emoji cell is well formed and inside the atlas', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('\u{1F389}\u{1F525}'),
        canvasSize: const Size(400, 700),
        rasterScale: 2,
      );
      final bounds = Offset.zero & atlas!.atlasPxSize;
      for (final g in atlas.glyphs) {
        expect(g.atlasRect.width, greaterThan(0));
        expect(g.atlasRect.height, greaterThan(0));
        expect(bounds.contains(g.atlasRect.topLeft), isTrue);
        expect(
          bounds.contains(g.atlasRect.bottomRight - const Offset(0.01, 0.01)),
          isTrue,
        );
      }
      // Two glyphs, so their placement rects must not sit on top of each
      // other — the property that keeps ink from compositing twice.
      expect(atlas.glyphs.length, 2);
      expect(atlas.glyphs[0].boxRect.overlaps(atlas.glyphs[1].boxRect), isFalse);
    });
  });

  group('emoji rasterise with ink', () {
    test('painting an emoji puts pixels down', () async {
      // Not a colour assertion — see the file header. This catches the case
      // where an emoji lays out with a size but paints nothing at all, which
      // would export as an invisible caption rather than as a visible box.
      final overlay = overlayWith('\u{1F600}');
      const canvas = Size(400, 700);
      final layout = TextOverlayLayout.measure(overlay, canvas);
      expect(layout.boxSize.width, greaterThan(0));
      expect(layout.boxSize.height, greaterThan(0));

      final recorder = ui.PictureRecorder();
      final painter = TextOverlayLayout.textPainterFor(overlay, layout.renderScale)
        ..layout();
      painter.paint(Canvas(recorder), Offset.zero);
      final picture = recorder.endRecording();
      final width = painter.width.ceil().clamp(1, 4096);
      final height = painter.height.ceil().clamp(1, 4096);
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        var inked = 0;
        final bytes = data!.buffer.asUint8List();
        for (var i = 3; i < bytes.length; i += 4) {
          if (bytes[i] > 8) inked++;
        }
        expect(inked, greaterThan(0), reason: 'an emoji must paint something');
      } finally {
        image.dispose();
        picture.dispose();
        painter.dispose();
      }
    });
  });
}
