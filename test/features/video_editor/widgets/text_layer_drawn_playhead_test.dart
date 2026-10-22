import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_layer.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';

import '../../../support/test_fonts.dart';

/// Text is drawn at the playhead as drawn, every frame.
///
/// It was drawn at the last position report: it appeared, disappeared and
/// animated only when one landed — late against the picture, and an
/// animation stepped at half the frame rate.
void main() {
  const canvas = Size(360, 640);
  final text = TextOverlayModel(
    id: 't',
    text: 'Hi',
    fontFamily: kTestFontFamily,
    startTime: const Duration(seconds: 1),
    endTime: const Duration(seconds: 3),
  );

  final body = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is TextOverlayPainter,
  );

  Future<void> pumpLayer(WidgetTester tester, ValueNotifier<double> playhead) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The reports have the playhead at 0, before the text.
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: [text], currentPlaybackPosition: 0);
    await tester.pumpWidget(ProviderScope(
      overrides: [videoEditorProvider.overrideWith((ref) => n)],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: canvas.width,
              height: canvas.height,
              child: TextOverlayLayer(
                videoCanvasSize: canvas,
                onShowTextEditor: (_, __) {},
                playhead: playhead,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a text shows, and is painted, at the drawn playhead', (tester) async {
    final playhead = ValueNotifier<double>(2.0);
    addTearDown(playhead.dispose);
    await pumpLayer(tester, playhead);

    expect(body, findsOneWidget);
    expect((tester.widget<CustomPaint>(body).painter! as TextOverlayPainter).positionSeconds, 2.0);

    playhead.value = 2.016;
    await tester.pump();
    expect((tester.widget<CustomPaint>(body).painter! as TextOverlayPainter).positionSeconds, 2.016);
  });

  testWidgets('a text leaves when the drawn playhead passes its end', (tester) async {
    final playhead = ValueNotifier<double>(2.0);
    addTearDown(playhead.dispose);
    await pumpLayer(tester, playhead);
    expect(body, findsOneWidget);

    playhead.value = 3.0;
    await tester.pump();
    expect(body, findsNothing);
  });
}
