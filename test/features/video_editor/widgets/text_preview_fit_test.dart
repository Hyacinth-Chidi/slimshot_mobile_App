import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_glyph_layout.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_preview_tile.dart';

import '../../../support/test_fonts.dart';

/// A preview tile shows the **whole** look, and fills itself with it.
///
/// It used to fit the text *box* and scale only down, so a shadow or an
/// outline — which reach past the box — was cut off at the tile's edge,
/// exactly where a glow or a far drop shadow lives, and a short word sat
/// small in the middle of an empty tile.
void main() {
  TextOverlayModel look(
    String text, {
    Color shadow = Colors.transparent,
    double blur = kTextShadowDefaultBlur,
    double distance = kTextShadowDefaultDistance,
    Color outline = Colors.transparent,
    double outlineWidth = 0,
    Color box = Colors.transparent,
  }) =>
      TextOverlayModel(
        id: 't',
        text: text,
        fontFamily: kTestFontFamily,
        referenceCanvasSize: kTextPreviewCanvas,
        shadowColor: shadow,
        shadowBlurRadius: blur,
        shadowDistance: distance,
        strokeColor: outline,
        strokeWidth: outlineWidth,
        backgroundColor: box,
        endTime: const Duration(seconds: 1),
      );

  final cases = {
    'plain': look('Title'),
    'default shadow': look('Title', shadow: Colors.black),
    'glow': look('Neon', shadow: Colors.cyan, blur: kTextShadowMaxBlur, distance: 0),
    'far shadow': look(
      'Far',
      shadow: Colors.black,
      blur: kTextShadowMaxBlur,
      distance: kTextShadowMaxDistance,
    ),
    'thick outline': look('Pop', outline: Colors.black, outlineWidth: 10),
    'boxed': look('Boxed', box: Colors.white),
    'long': look('A much longer caption'),
  };

  Future<void> pumpTile(WidgetTester tester, TextOverlayModel overlay) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 110,
            height: 100,
            child: TextPreviewTile(
              overlay: overlay,
              spanSeconds: 1,
              label: 'x',
              isSelected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
  }

  /// Where the look lands on screen: the painted box, grown by the shadow's
  /// and the outline's reach at the tile's own scale.
  Rect paintedLook(WidgetTester tester, TextOverlayModel overlay) {
    final box = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TextOverlayPainter,
      ),
    );
    final layout = TextOverlayLayout.measure(overlay, kTextPreviewCanvas);
    final scale = box.width / layout.boxSize.width;
    return box.inflate(
      textGlyphBleedPadding(overlay, layout.renderScale) * scale,
    );
  }

  Rect previewArea(WidgetTester tester) => tester.getRect(
        find
            .descendant(
              of: find.byType(TextPreviewTile),
              matching: find.byType(ClipRect),
            )
            .first,
      );

  for (final MapEntry(key: name, value: overlay) in cases.entries) {
    testWidgets('$name: the whole look fits inside the tile', (tester) async {
      await pumpTile(tester, overlay);
      final area = previewArea(tester);
      final look = paintedLook(tester, overlay);
      expect(look.left, greaterThanOrEqualTo(area.left - 0.5), reason: name);
      expect(look.top, greaterThanOrEqualTo(area.top - 0.5), reason: name);
      expect(look.right, lessThanOrEqualTo(area.right + 0.5), reason: name);
      expect(look.bottom, lessThanOrEqualTo(area.bottom + 0.5), reason: name);
    });

    testWidgets('$name: and fills it', (tester) async {
      // Filling means reaching the tile's margin in whichever dimension runs
      // out first — not sitting small in the middle.
      await pumpTile(tester, overlay);
      final area = previewArea(tester);
      final look = paintedLook(tester, overlay);
      final fill = [look.width / area.width, look.height / area.height]
          .reduce((a, b) => a > b ? a : b);
      expect(fill, greaterThan(0.8), reason: name);
    });
  }

  testWidgets('a word of two letters is not blown up past a readable size',
      (tester) async {
    // Filling has a ceiling: magnified without limit, "Hi" would be a pair of
    // giant letters that no longer read as the style being offered.
    final overlay = look('Hi');
    await pumpTile(tester, overlay);
    final layout = TextOverlayLayout.measure(overlay, kTextPreviewCanvas);
    final box = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TextOverlayPainter,
      ),
    );
    expect(box.width / layout.boxSize.width,
        lessThanOrEqualTo(kTextPreviewMaxUpscale + 1e-9));
  });

  test("a tile's words sit on one line", () {
    // A tile measured its text on a 240px canvas, so anything wider than
    // ~208px wrapped: HEADLINE and BREAKING broke in two, and Press Start 2P —
    // a full em per letter — wrapped almost anything. Eight graphemes of the
    // user's own text is the most a tile shows, so eight of the test font's
    // full-em glyphs is the widest case there is.
    TextOverlayModel inTile(TextTemplate t, String words) => t
        .apply(
          id: 't',
          startTime: Duration.zero,
          endTime: const Duration(seconds: 1),
          canvasSize: kTextPreviewCanvas,
        )
        .copyWith(
          fontFamily: kTestFontFamily,
          text: words,
          position: Offset.zero,
          scale: 1,
        );
    double lines(TextOverlayModel o) =>
        TextOverlayLayout.measure(o, kTextPreviewCanvas).textHeight /
        TextOverlayLayout.measure(o.copyWith(text: 'H'), kTextPreviewCanvas)
            .textHeight;

    for (final t in kTextTemplates) {
      expect(lines(inTile(t, t.sampleText)), closeTo(1, 0.01), reason: t.id);
      expect(lines(inTile(t, 'WWWWWWWW')), closeTo(1, 0.01), reason: t.id);
    }
  });

  test('the preview stage lets both white and black styling read', () {
    // Black outlines and shadows — a subtitle's, a comic's — vanished into
    // the tile's near-black surface. Relative-luminance contrast, WCAG's
    // formula: enough against black for an outline to show, and plenty
    // against white for the fill.
    double luminance(Color c) {
      double channel(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * channel(c.r) +
          0.7152 * channel(c.g) +
          0.0722 * channel(c.b);
    }

    double contrast(Color a, Color b) {
      final la = luminance(a), lb = luminance(b);
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    const stage = AppColors.previewStage;
    expect(contrast(stage, const Color(0xFF000000)), greaterThan(2.5));
    expect(contrast(stage, const Color(0xFFFFFFFF)), greaterThan(4.5));
  });

  testWidgets('the preview sits on that stage', (tester) async {
    await pumpTile(tester, look('Title'));
    final stages = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(TextPreviewTile),
            matching: find.byType(Container),
          ),
        )
        .where(
          (c) =>
              (c.decoration as BoxDecoration?)?.color ==
              AppColors.previewStage,
        );
    expect(stages, hasLength(1));
  });
}
