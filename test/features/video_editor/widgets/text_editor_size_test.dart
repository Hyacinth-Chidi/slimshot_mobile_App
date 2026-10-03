import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_editor_dialog.dart';

import '../../../support/test_fonts.dart';

/// The text editor's Size tab: a ruler for the letters' size, for everyone
/// who would rather not pinch.
void main() {
  const canvas = Size(400, 700);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<VideoEditorNotifier> open(
    WidgetTester tester,
    List<TextOverlayModel> texts,
  ) async {
    final notifier = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: texts);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(videoEditorProvider);
                return ElevatedButton(
                  onPressed: () => showTextEditor(
                    context: context,
                    overlay: texts.first,
                    ref: ref,
                    initialTool: TextEditorTool.size,
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

  TextOverlayModel words({double? size, String id = 't', String? setId}) =>
      TextOverlayModel(
        id: id,
        text: 'Hello',
        fontFamily: kTestFontFamily,
        referenceCanvasSize: canvas,
        fontSize: size,
        captionSetId: setId,
      );

  String readout(WidgetTester tester) => tester
      .widget<Text>(find.descendant(
        of: find.byKey(const Key('value_ruler_readout')),
        matching: find.byType(Text),
      ))
      .data!;

  testWidgets("shows the text's Size on a ruler", (tester) async {
    await open(tester, [words(size: 150)]);
    expect(find.byType(ValueRuler), findsOneWidget);
    expect(readout(tester), '150');
  });

  testWidgets("a drag changes the letters' size, as one undo step", (tester) async {
    final n = await open(tester, [words(size: 150)]);
    await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
    await settle(tester);
    expect(n.state.textOverlays.single.fontSize, 170);
    expect(readout(tester), '170');
    n.undo();
    expect(n.state.textOverlays.single.fontSize, 150);
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('tapping the number puts the default back', (tester) async {
    final n = await open(tester, [words(size: 150)]);
    await tester.tap(find.byKey(const Key('value_ruler_readout')));
    await settle(tester);
    expect(n.state.textOverlays.single.fontSize, kDefaultTextSize);
  });

  testWidgets("a caption's default is a caption's", (tester) async {
    final n = await open(tester, [words(size: 150, setId: 's')]);
    await tester.tap(find.byKey(const Key('value_ruler_readout')));
    await settle(tester);
    expect(n.state.textOverlays.single.fontSize, kCaptionTextSize);
  });

  testWidgets('an old text shows the Size its letters have, and starts there',
      (tester) async {
    // 32 px letters on a frame whose short side is 400.
    final n = await open(tester, [words()]);
    expect(readout(tester), '80');
    await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
    await settle(tester);
    expect(n.state.textOverlays.single.fontSize, 100);
  });

  testWidgets('on a caption it reaches the set', (tester) async {
    final n = await open(tester, [
      words(size: 100, id: 'a', setId: 's'),
      words(size: 100, id: 'b', setId: 's'),
    ]);
    await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
    await settle(tester);
    expect(n.state.textOverlays.map((t) => t.fontSize), [120, 120]);
  });
}
