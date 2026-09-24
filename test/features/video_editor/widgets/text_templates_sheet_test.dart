import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/text_templates_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_preview_tile.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_template_tile.dart';

import '../../../support/test_fonts.dart';

/// The templates sheet: pick a starting look for a new text.
///
/// The real catalog's families are Google Fonts, which a test cannot load
/// (see `flutter_test_config.dart`), so these tests hand the sheet templates
/// of their own in the bundled test family. That the sheet *defaults* to the
/// real catalog is pinned separately, without building a tile.
void main() {
  const templates = [
    TextTemplate(
      id: 'a',
      name: 'Alpha',
      sampleText: 'Alpha',
      fontFamily: kTestFontFamily,
      color: Colors.amber,
      inAnimation: 'fade_in',
    ),
    TextTemplate(
      id: 'b',
      name: 'Beta',
      sampleText: 'Beta',
      fontFamily: kTestFontFamily,
      inAnimation: 'pop_in',
      loopAnimation: 'wave_loop',
    ),
    TextTemplate(
      id: 'c',
      name: 'Gamma',
      sampleText: 'Gamma',
      fontFamily: kTestFontFamily,
      backgroundColor: Colors.black,
    ),
  ];

  /// Past a sheet's arrival or departure — never `pumpAndSettle`.
  ///
  /// The tiles play forever off one repeating clock, by design, so the tree
  /// never settles: `pumpAndSettle` would pump ten simulated minutes and then
  /// fail. The sheet route's own motion is `AppMotion`'s, well inside this.
  Future<void> settleSheet(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<List<TextTemplate>> pumpSheet(WidgetTester tester) async {
    final chosen = <TextTemplate>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEditorSheet<void>(
                context,
                builder: (_) => TextTemplatesSheet(
                  templates: templates,
                  onTemplateSelected: chosen.add,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleSheet(tester);
    return chosen;
  }

  test('defaults to the real catalog', () {
    // No hardcoded second list: a template added to the catalog reaches the
    // sheet with no edit here.
    final sheet = TextTemplatesSheet(onTemplateSelected: (_) {});
    expect(identical(sheet.templates, kTextTemplates), isTrue);
  });

  testWidgets('lays its tiles out on the shared preview grid', (tester) async {
    await pumpSheet(tester);
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.gridDelegate, same(kTextPreviewGrid));
  });

  testWidgets('offers one tile per template', (tester) async {
    await pumpSheet(tester);
    // Counted from the grid's own itemCount rather than from built tiles:
    // the grid is lazy, so tiles below the fold do not exist yet.
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.childrenDelegate as SliverChildBuilderDelegate).childCount,
      templates.length,
    );
  });

  testWidgets('a tile shows the template by name, drawn by the canvas painter',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text('Alpha'), findsOneWidget);
    // A tile that drew its own approximation would promise a look the canvas
    // does not deliver. It paints through `TextOverlayPainter`, the one the
    // canvas and the export's rasteriser read.
    final painters = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(TextTemplateTile).first,
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<TextOverlayPainter>()
        .toList();
    expect(painters, hasLength(1));
    // The tile previews the sample words in the template's own look.
    expect(painters.single.overlay.text, 'Alpha');
    expect(painters.single.overlay.color, Colors.amber);
    expect(painters.single.overlay.fontFamily, kTestFontFamily);
  });

  testWidgets('tapping a tile reports it and closes the sheet', (tester) async {
    final chosen = await pumpSheet(tester);

    await tester.tap(find.byType(TextTemplateTile).at(1));
    await settleSheet(tester);

    expect(chosen.map((t) => t.id), ['b']);
    expect(find.byType(TextTemplatesSheet), findsNothing);
  });

  testWidgets('stops at the sheet preview fraction, over the frame it styles',
      (tester) async {
    await pumpSheet(tester);
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final height = tester.getSize(find.byType(TextTemplatesSheet)).height;
    expect(height, closeTo(screenHeight * kEditorSheetPreviewFraction, 1.0));
  });

  testWidgets('has no title — the tool that opened it already said Templates',
      (tester) async {
    await pumpSheet(tester);
    expect(find.text('Templates'), findsNothing);
  });
}
