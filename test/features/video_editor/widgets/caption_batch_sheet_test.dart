import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/caption_batch_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';

/// The caption list: read down it, fix what was misheard.
void main() {
  TextOverlayModel caption(String id, String text, int startMs, int endMs) {
    final words = <CaptionWord>[];
    var at = 0;
    var t = 60;
    for (final word in text.split(' ')) {
      words.add(
        CaptionWord(
          textStart: at,
          textEnd: at + word.length,
          start: Duration(milliseconds: t),
          end: Duration(milliseconds: t + 200),
        ),
      );
      at += word.length + 1;
      t += 300;
    }
    return TextOverlayModel(
      id: id,
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      captionSetId: 'set',
      captionWords: words,
    );
  }

  VideoEditorNotifier editor([List<TextOverlayModel>? captions]) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          textOverlays: [
            TextOverlayModel(id: 'title', text: 'Title'),
            ...captions ??
                [
                  caption('b', 'fox jumps', 64200, 65000),
                  caption('a', 'the quick brown', 1000, 2000),
                  caption('c', 'over it', 125000, 126000),
                ],
          ],
          captionSettings: const CaptionSettings(setId: 'set'),
        );

  Future<List<double>> open(
    WidgetTester tester,
    VideoEditorNotifier notifier, {
    String? initial,
  }) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showEditorSheet<void>(
                  context,
                  builder: (_) => CaptionBatchSheet(
                    initialCaptionId: initial,
                    onSeek: seeks.add,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return seeks;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  List<String> captionTexts(VideoEditorNotifier n) => (n.state.textOverlays
          .where((t) => t.isCaption)
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime)))
      .map((t) => t.text)
      .toList();

  testWidgets('lists every caption in the order spoken, with its time',
      (tester) async {
    await open(tester, editor());
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(fields, ['the quick brown', 'fox jumps', 'over it']);
    expect(find.text('0:01.0'), findsOneWidget);
    expect(find.text('1:04.2'), findsOneWidget);
    expect(find.text('2:05.0'), findsOneWidget);
    expect(find.text('Title'), findsNothing);
  });

  testWidgets('opens on the caption it was opened from', (tester) async {
    final many = [
      for (var i = 0; i < 40; i++)
        caption('c$i', 'caption number $i', i * 1000, i * 1000 + 900),
    ];
    await open(tester, editor(many), initial: 'c30');
    expect(find.byKey(const Key('caption_field_c30')), findsOneWidget);
    expect(find.byKey(const Key('caption_field_c0')), findsNothing);
  });

  testWidgets('a tap on the time goes there and selects the caption',
      (tester) async {
    final n = editor();
    final seeks = await open(tester, n);
    await tapKey(tester, 'caption_time_b');
    expect(seeks, [64.2]);
    expect(n.state.selectedTextId, 'b');
  });

  testWidgets('typing fixes the caption as it is typed, as one undo step',
      (tester) async {
    final n = editor();
    await open(tester, n);
    await tester.enterText(
      find.byKey(const Key('caption_field_a')),
      'the quack brown',
    );
    await tester.enterText(
      find.byKey(const Key('caption_field_a')),
      'the quack brown cow',
    );
    await tester.pump();
    expect(captionTexts(n).first, 'the quack brown cow');
    final a = n.state.textOverlays.firstWhere((t) => t.id == 'a');
    expect(a.captionWords, hasLength(4));

    n.undo();
    expect(captionTexts(n).first, 'the quick brown');
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('a field only looked at leaves nothing to undo', (tester) async {
    final n = editor();
    await open(tester, n);
    await tester.tap(find.byKey(const Key('caption_field_a')));
    await tester.pump();
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('an undo elsewhere shows in the list', (tester) async {
    final n = editor();
    await open(tester, n);
    await tester.enterText(
      find.byKey(const Key('caption_field_a')),
      'changed',
    );
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    n.undo();
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('caption_field_a')),
    );
    expect(field.controller!.text, 'the quick brown');
  });

  testWidgets('split cuts at the cursor', (tester) async {
    final n = editor();
    await open(tester, n);
    await tester.tap(find.byKey(const Key('caption_field_a')));
    await tester.pump();
    tester
        .widget<TextField>(find.byKey(const Key('caption_field_a')))
        .controller!
        .selection = const TextSelection.collapsed(offset: 10);
    await tapKey(tester, 'caption_split_a');
    expect(
      captionTexts(n),
      ['the quick', 'brown', 'fox jumps', 'over it'],
    );
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('merge takes the next caption in', (tester) async {
    final n = editor();
    await open(tester, n);
    await tapKey(tester, 'caption_merge_a');
    expect(captionTexts(n), ['the quick brown fox jumps', 'over it']);
  });

  testWidgets('the last caption has nothing to merge with', (tester) async {
    await open(tester, editor());
    expect(find.byKey(const Key('caption_merge_a')), findsOneWidget);
    expect(find.byKey(const Key('caption_merge_c')), findsNothing);
  });

  testWidgets('delete removes one caption', (tester) async {
    final n = editor();
    await open(tester, n);
    await tapKey(tester, 'caption_delete_b');
    expect(captionTexts(n), ['the quick brown', 'over it']);
  });

  testWidgets('a length re-cuts the set and shows as chosen', (tester) async {
    final n = editor();
    await open(tester, n);
    await tapKey(tester, 'caption_length_word');
    expect(
      captionTexts(n),
      ['the', 'quick', 'brown', 'fox', 'jumps', 'over', 'it'],
    );
    expect(n.state.captionSettings?.length, CaptionLength.word);
    // The list shows the new set (as many rows as fit), not the old one.
    final shown = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(shown.take(3), ['the', 'quick', 'brown']);
  });

  testWidgets('delete all removes the set and closes the list',
      (tester) async {
    final n = editor();
    await open(tester, n);
    await tapKey(tester, 'caption_delete_all');
    expect(captionTexts(n), isEmpty);
    expect(n.state.textOverlays.single.id, 'title');
    expect(find.byType(CaptionBatchSheet), findsNothing);
  });
}
