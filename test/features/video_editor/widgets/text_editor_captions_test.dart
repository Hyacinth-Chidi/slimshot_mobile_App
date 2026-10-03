import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_editor_dialog.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_template_tile.dart';

import '../../../support/test_fonts.dart';

/// The text editor on a caption: a look edit is the set's unless the user
/// says otherwise, and a template restyles a caption without resizing it.
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

  TextOverlayModel caption(String id, String words) => TextOverlayModel(
        id: id,
        text: words,
        fontFamily: kTestFontFamily,
        scale: 2.4,
        startTime: id == 'c0' ? Duration.zero : const Duration(seconds: 1),
        endTime: id == 'c0' ? const Duration(seconds: 1) : const Duration(seconds: 2),
        captionSetId: 's',
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<VideoEditorNotifier> open(
    WidgetTester tester,
    List<TextOverlayModel> texts, {
    TextEditorTool tool = TextEditorTool.templates,
  }) async {
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
                    initialTool: tool,
                    templates: const [alpha],
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

  testWidgets("a caption's editor offers Apply to all captions, on",
      (tester) async {
    final n = await open(tester, [caption('c0', 'Hello'), caption('c1', 'there')]);
    expect(find.text('Apply to all captions'), findsOneWidget);
    expect(n.state.captionLookToAll, isTrue);

    await tester.tap(find.text('Apply to all captions'));
    await settle(tester);
    expect(n.state.captionLookToAll, isFalse);
  });

  testWidgets('plain text has no such switch', (tester) async {
    await open(tester, [
      TextOverlayModel(id: 't', text: 'Title', fontFamily: kTestFontFamily),
    ]);
    expect(find.text('Apply to all captions'), findsNothing);
  });

  testWidgets('nor does the keyboard: words are each caption\'s own',
      (tester) async {
    await open(
      tester,
      [caption('c0', 'Hello'), caption('c1', 'there')],
      tool: TextEditorTool.keyboard,
    );
    expect(find.text('Apply to all captions'), findsNothing);
  });

  testWidgets('a template on a caption keeps its size and reaches the set',
      (tester) async {
    final n = await open(tester, [caption('c0', 'Hello'), caption('c1', 'there')]);
    await tester.tap(find.byType(TextTemplateTile));
    await settle(tester);

    final captions = n.state.textOverlays;
    expect(captions.map((c) => c.scale), everyElement(2.4));
    expect(captions.every(alpha.isAppliedTo), isTrue);
    expect(captions.map((c) => c.text), ['Hello', 'there']);
  });
}
