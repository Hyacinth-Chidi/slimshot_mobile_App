import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_look.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/caption_preset_tile.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_preview_tile.dart';

import '../../../support/test_fonts.dart';

/// The caption styles grid: each tile is a caption wearing its preset, drawn
/// by the canvas's own painter with its words timed, so the highlight plays.
void main() {
  const presets = [
    CaptionPreset(
      id: 'a',
      name: 'Alpha',
      look: TextLook(fontFamily: kTestFontFamily),
    ),
    CaptionPreset(
      id: 'b',
      name: 'Beta',
      sampleText: 'one two three',
      look: TextLook(fontFamily: kTestFontFamily, color: Colors.amber),
      highlight: CaptionHighlight(style: CaptionHighlightStyle.karaoke),
    ),
    CaptionPreset(
      id: 'c',
      name: 'Gamma',
      look: TextLook(fontFamily: kTestFontFamily, strokeWidth: 3, strokeColor: Colors.black),
      highlight: CaptionHighlight(style: CaptionHighlightStyle.focus),
    ),
  ];

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: child)),
      );

  List<TextOverlayPainter> paintersIn(WidgetTester tester, Finder within) => tester
      .widgetList<CustomPaint>(find.descendant(of: within, matching: find.byType(CustomPaint)))
      .map((p) => p.painter)
      .whereType<TextOverlayPainter>()
      .toList();

  testWidgets('a tile is a caption wearing the preset, its words timed',
      (tester) async {
    await tester.pumpWidget(host(
      SizedBox(
        width: 120,
        height: 110,
        child: CaptionPresetTile(preset: presets[1], onTap: () {}),
      ),
    ));
    final overlay = paintersIn(tester, find.byType(CaptionPresetTile)).single.overlay;
    expect(overlay.text, 'one two three');
    expect(overlay.isCaption, isTrue);
    expect(overlay.highlight, presets[1].highlight);
    expect(presets[1].look.sameLookAs(TextLook.of(overlay)), isTrue);

    // One timed word per word of the sample, in order, without overlap.
    final words = overlay.captionWords!;
    expect(words, hasLength(3));
    expect(overlay.text.substring(words[1].textStart, words[1].textEnd), 'two');
    for (var i = 1; i < words.length; i++) {
      expect(words[i].start, greaterThanOrEqualTo(words[i - 1].end));
    }
    expect(words.last.end, lessThanOrEqualTo(overlay.endTime - overlay.startTime));
  });

  testWidgets('the grid shows every preset and marks the current one',
      (tester) async {
    await tester.pumpWidget(host(
      CaptionPresetGrid(presets: presets, selectedId: 'b', onSelected: (_) {}),
    ));
    final tiles = tester.widgetList<TextPreviewTile>(find.byType(TextPreviewTile)).toList();
    expect(tiles, hasLength(presets.length));
    expect(tiles.where((t) => t.isSelected).map((t) => t.label), ['Beta']);
  });

  testWidgets('a tap chooses its preset, once', (tester) async {
    final chosen = <String>[];
    await tester.pumpWidget(host(
      CaptionPresetGrid(
        presets: presets,
        onSelected: (p) => chosen.add(p.id),
      ),
    ));
    await tester.tap(find.text('Gamma'));
    await tester.pump();
    expect(chosen, ['c']);
  });
}
