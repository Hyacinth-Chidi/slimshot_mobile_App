import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_layer.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';

import '../../../support/test_fonts.dart';

/// A text the engine draws is painted by the engine alone — in the frame of
/// the picture, at its time — and the layer keeps only what a finger needs:
/// the box to touch, the frame and its handles.
void main() {
  const canvas = Size(360, 640);
  final text = TextOverlayModel(
    id: 't',
    text: 'Hi',
    fontFamily: kTestFontFamily,
    startTime: Duration.zero,
    endTime: const Duration(seconds: 3),
  );

  final body = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is TextOverlayPainter,
  );

  Future<VideoEditorNotifier> pumpLayer(
    WidgetTester tester,
    ValueNotifier<Set<String>> engineDrawn, {
    String? selected,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        textOverlays: [text],
        currentPlaybackPosition: 1,
        selectedTextId: selected,
      );
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
                engineDrawn: engineDrawn,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return n;
  }

  testWidgets('an engine-drawn text paints nothing but still takes a tap', (tester) async {
    final drawn = ValueNotifier<Set<String>>({'t'});
    addTearDown(drawn.dispose);
    final n = await pumpLayer(tester, drawn);
    expect(body, findsNothing);

    // The text sits at the canvas centre.
    await tester.tapAt(const Offset(180, 320));
    await tester.pump(const Duration(milliseconds: 400));
    expect(n.state.selectedTextId, 't');
  });

  testWidgets('the selection frame stays', (tester) async {
    final drawn = ValueNotifier<Set<String>>({'t'});
    addTearDown(drawn.dispose);
    await pumpLayer(tester, drawn, selected: 't');
    expect(body, findsNothing);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(find.byIcon(LucideIcons.rotateCw), findsOneWidget);
  });

  testWidgets('handing back repaints', (tester) async {
    final drawn = ValueNotifier<Set<String>>({'t'});
    addTearDown(drawn.dispose);
    await pumpLayer(tester, drawn);
    expect(body, findsNothing);

    drawn.value = const {};
    await tester.pump();
    expect(body, findsOneWidget);
  });
}
