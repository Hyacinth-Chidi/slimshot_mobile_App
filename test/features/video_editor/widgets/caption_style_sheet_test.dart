import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_look.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/caption_sheet_parts.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/caption_style_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/caption_preset_tile.dart';

import '../../../support/test_fonts.dart';

/// Caption style: a caption's menu opens it, and every tap restyles the set.
///
/// The real catalog's faces are downloaded, which a test cannot load, so the
/// sheet is handed styles of its own in the bundled test face.
const testPresets = [
  CaptionPreset(id: 'a', name: 'Alpha', look: TextLook(fontFamily: kTestFontFamily)),
  CaptionPreset(
    id: 'b',
    name: 'Beta',
    look: TextLook(fontFamily: kTestFontFamily, color: Color(0xFFFFC107)),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.karaoke),
  ),
  CaptionPreset(
    id: 'c',
    name: 'Gamma',
    look: TextLook(fontFamily: kTestFontFamily, strokeWidth: 3),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.focus),
  ),
];

void _noPreset(CaptionPreset _) {}
void _noHighlight(CaptionHighlight _) {}

void main() {
  final chosen = <String>[];
  final applied = <CaptionHighlight>[];

  setUp(() {
    chosen.clear();
    applied.clear();
  });

  /// Opens the sheet on a caption wearing [preset]'s look and highlight, or
  /// [look]/[highlight] when given.
  Future<void> open(
    WidgetTester tester, {
    CaptionPreset? preset,
    TextLook? look,
    CaptionHighlight? highlight,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEditorSheet<void>(
                context,
                builder: (_) => CaptionStyleSheet(
                  presets: testPresets,
                  look: look ?? preset!.look,
                  highlight: highlight ?? preset!.highlight,
                  onPresetChosen: (p) => chosen.add(p.id),
                  onHighlightChanged: applied.add,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key), skipOffstage: false));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  bool marked(WidgetTester tester, String id) => tester
      .widget<CaptionPresetTile>(find.byKey(Key('caption_preset_$id'), skipOffstage: false))
      .isSelected;

  const swatch = Key('caption_highlight_color_0');

  /// Whether the colours can be chosen: they stay on the sheet either way,
  /// dimmed where the highlight lights in no colour.
  bool coloursOffered(WidgetTester tester) => tester
      .widget<CaptionColorRow>(find.byType(CaptionColorRow, skipOffstage: false))
      .enabled;

  test('offers the real catalog unless told otherwise', () {
    const sheet = CaptionStyleSheet(
      look: kDefaultCaptionLook,
      highlight: kDefaultCaptionHighlight,
      onPresetChosen: _noPreset,
      onHighlightChanged: _noHighlight,
    );
    expect(sheet.presets, same(kCaptionPresets));
  });

  testWidgets('every style, the one the caption wears marked', (tester) async {
    await open(tester, preset: testPresets[1]);
    expect(find.byType(CaptionPresetTile, skipOffstage: false),
        findsNWidgets(testPresets.length));
    expect(marked(tester, 'b'), isTrue);
    expect(marked(tester, 'a'), isFalse);
  });

  // The owner's call (2026-10-29): under the styles, the highlight's colours
  // sat below the fold of a sheet capped at 45% of the screen, where most
  // users would never find them. They come first now, the highlights under
  // them, and the styles after.
  testWidgets('no title; the highlight colours first, then the highlights, '
      'then the styles', (tester) async {
    await open(tester, preset: testPresets[0]);
    expect(find.text('Caption style'), findsNothing);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(find.text('Highlight')), lessThan(top(find.byKey(swatch))));
    expect(top(find.byKey(swatch)),
        lessThan(top(find.byKey(const Key('caption_highlight_pop')))));
    expect(top(find.byKey(const Key('caption_highlight_pop'))),
        lessThan(top(find.text('Styles'))));
    expect(top(find.text('Styles')),
        lessThan(top(find.byKey(const Key('caption_preset_a')))));
  });

  testWidgets('a style reaches the set, and the Highlight row follows it',
      (tester) async {
    await open(tester, preset: testPresets[0]);
    expect(coloursOffered(tester), isFalse);

    await tapKey(tester, 'caption_preset_b');
    expect(chosen, ['b']);
    expect(marked(tester, 'b'), isTrue);
    // Karaoke lights in a colour, so its colours are offered to tune it.
    expect(coloursOffered(tester), isTrue);

    await tapKey(tester, 'caption_preset_c');
    expect(chosen, ['b', 'c']);
    expect(coloursOffered(tester), isFalse);
  });

  testWidgets('a highlight reaches the set, the look kept', (tester) async {
    await open(tester, preset: testPresets[1]);
    await tapKey(tester, 'caption_highlight_pop');
    await tapKey(tester, 'caption_highlight_color_4');
    expect(applied, [
      const CaptionHighlight(style: CaptionHighlightStyle.pop),
      CaptionHighlight(
        style: CaptionHighlightStyle.pop,
        color: kCaptionHighlightColors[4],
      ),
    ]);
    expect(chosen, isEmpty);
    // Beta's look with another highlight is no longer Beta.
    expect(marked(tester, 'b'), isFalse);
  });

  testWidgets('offers every highlight, colours only where one lights',
      (tester) async {
    await open(tester, preset: testPresets[0]);
    for (final style in CaptionHighlightStyle.values) {
      expect(
        find.byKey(Key('caption_highlight_${style.name}'), skipOffstage: false),
        findsOneWidget,
        reason: style.name,
      );
    }
    await tapKey(tester, 'caption_highlight_pill');
    expect(coloursOffered(tester), isTrue);
    await tapKey(tester, 'caption_highlight_focus');
    expect(coloursOffered(tester), isFalse);
    // A dimmed colour does nothing when tapped.
    applied.clear();
    await tester.tap(find.byKey(const Key('caption_highlight_color_3')),
        warnIfMissed: false);
    await tester.pump();
    expect(applied, isEmpty);
  });

  // At the top of the sheet, a row that came and went would move every row
  // under it the moment a style was picked — under the finger.
  testWidgets('the colours stay where they are whatever the highlight',
      (tester) async {
    await open(tester, preset: testPresets[1]);
    // From the top of the highlight rows to the styles: what a row coming
    // and going would change, whatever the sheet is scrolled to.
    double span() =>
        tester.getTopLeft(find.text('Styles', skipOffstage: false)).dy -
        tester.getTopLeft(find.text('Highlight', skipOffstage: false)).dy;
    final before = span();
    await tapKey(tester, 'caption_highlight_focus');
    expect(coloursOffered(tester), isFalse);
    expect(span(), before);
  });

  testWidgets('a hand-tuned caption marks no style', (tester) async {
    await open(
      tester,
      look: const TextLook(fontFamily: kTestFontFamily, color: Color(0xFF7C3AED)),
      highlight: CaptionHighlight.none,
    );
    for (final p in testPresets) {
      expect(marked(tester, p.id), isFalse, reason: p.id);
    }
  });

  testWidgets('choosing what the set already wears says nothing new',
      (tester) async {
    await open(tester, preset: testPresets[1]);
    await tapKey(tester, 'caption_highlight_karaoke');
    // The notifier would take no undo step either; the sheet does not even
    // ask it to.
    expect(applied, isEmpty);
  });
}
