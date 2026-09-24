import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_editor_dialog.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_template_tile.dart';

import '../../../support/test_fonts.dart';

/// Type, then choose: the text editor's Templates tab.
///
/// A template used to be chosen before there were any words — the Text
/// submenu's Templates makes an empty text wearing it. The tab puts a
/// template on a text that already has words, previews every template in
/// those words, and swaps one for another as often as the user likes.
///
/// The real catalog's families are Google Fonts, which a test cannot load, so
/// the sheet is handed templates of its own in the bundled test family.
void main() {
  const alpha = TextTemplate(
    id: 'a',
    name: 'Alpha',
    sampleText: 'Alpha',
    fontFamily: kTestFontFamily,
    color: Color(0xFFFFC107),
    strokeColor: Color(0xFF000000),
    strokeWidth: 4,
    scale: 1.5,
  );
  const beta = TextTemplate(
    id: 'b',
    name: 'Beta',
    sampleText: 'Beta',
    fontFamily: kTestFontFamily,
    color: Color(0xFF00E5FF),
    backgroundColor: Color(0xFF000000),
    scale: 0.8,
  );
  const gamma = TextTemplate(
    id: 'c',
    name: 'Gamma',
    sampleText: 'Gamma',
    fontFamily: kTestFontFamily,
    shadowColor: Color(0xFFFF2BD6),
    shadowBlur: 14,
    shadowDistance: 0,
  );
  const templates = [alpha, beta, gamma];

  TextOverlayModel text(String words) => TextOverlayModel(
        id: 't',
        text: words,
        fontFamily: kTestFontFamily,
        position: const Offset(30, 40),
        rotation: 0.2,
      );

  /// Past the sheet's arrival — never `pumpAndSettle`: the tiles play on a
  /// repeating clock, so the tree never settles.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<VideoEditorNotifier> open(
    WidgetTester tester,
    TextOverlayModel overlay,
  ) async {
    final notifier = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: [overlay]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                // The provider is autoDispose; the editor screen keeps it
                // alive by watching it, and so does this host.
                ref.watch(videoEditorProvider);
                return ElevatedButton(
                  onPressed: () => showTextEditor(
                    context: context,
                    overlay: overlay,
                    ref: ref,
                    initialTool: TextEditorTool.templates,
                    templates: templates,
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    return notifier;
  }

  Finder tileFor(TextTemplate t) => find.byWidgetPredicate(
        (w) => w is TextTemplateTile && w.template.id == t.id,
      );

  bool selected(WidgetTester tester, TextTemplate t) =>
      tester.widget<TextTemplateTile>(tileFor(t)).isSelected;

  String wordsIn(WidgetTester tester, TextTemplate t) {
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(of: tileFor(t), matching: find.byType(CustomPaint)),
        )
        .map((p) => p.painter)
        .whereType<TextOverlayPainter>()
        .single;
    return painter.overlay.text;
  }

  TextOverlayModel current(VideoEditorNotifier n) =>
      n.state.textOverlays.single;

  Future<void> choose(WidgetTester tester, TextTemplate t) async {
    await tester.ensureVisible(tileFor(t));
    await tester.tap(tileFor(t));
    await settle(tester);
  }

  testWidgets("every template is previewed in the text's own words",
      (tester) async {
    await open(tester, text('Hello'));
    for (final t in templates) {
      expect(wordsIn(tester, t), 'Hello', reason: t.id);
    }
  });

  testWidgets('with no words yet, each shows its own sample', (tester) async {
    await open(tester, text(''));
    for (final t in templates) {
      expect(wordsIn(tester, t), t.sampleText, reason: t.id);
    }
  });

  testWidgets('choosing one restyles the text, keeping its words and place — '
      'one undo step', (tester) async {
    final n = await open(tester, text('Hello'));
    await choose(tester, beta);

    final o = current(n);
    expect(beta.isAppliedTo(o), isTrue);
    expect(o.text, 'Hello');
    expect(o.position, const Offset(30, 40));
    expect(o.rotation, 0.2);

    n.undo();
    expect(beta.isAppliedTo(current(n)), isFalse);
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('the chosen one is highlighted; choosing another moves it — '
      'and the look with it', (tester) async {
    final n = await open(tester, text('Hello'));
    await choose(tester, alpha);
    expect(selected(tester, alpha), isTrue);
    expect(selected(tester, beta), isFalse);

    await choose(tester, beta);
    expect(selected(tester, alpha), isFalse);
    expect(selected(tester, beta), isTrue);
    // Alpha's outline does not survive into Beta.
    expect(current(n).strokeColor, Colors.transparent);
    expect(current(n).strokeWidth, 0);
  });

  testWidgets('typing afterwards keeps the look', (tester) async {
    // The sheet rewrites the whole text from its own copies of every field on
    // each keystroke; if choosing a template did not update those copies,
    // the next letter typed would put the old look back.
    final n = await open(tester, text('Hello'));
    await choose(tester, alpha);

    await tester.tap(find.text('Keyboard'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Hello there');
    await settle(tester);

    expect(current(n).text, 'Hello there');
    expect(alpha.isAppliedTo(current(n)), isTrue);
  });

  testWidgets('a text already wearing a template opens with it highlighted',
      (tester) async {
    await open(tester, gamma.restyle(text('Hello')));
    expect(selected(tester, gamma), isTrue);
    expect(selected(tester, alpha), isFalse);
  });
}
