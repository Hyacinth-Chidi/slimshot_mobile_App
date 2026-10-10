import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/tool_dismissal.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/canvas/video_preview_canvas.dart';

/// A tap in the empty space beside the 9:16 picture — not on it — is the
/// editor's "I'm done here": the screen closes the panel and clears the
/// selection on it, as the empty timeline does. The picture keeps its own tap
/// (play/pause), and a tap just past its edge, where handles hang over, is
/// neither.
void main() {
  late int outside;
  late int toggles;

  Future<Rect> pump(WidgetTester tester) async {
    outside = 0;
    toggles = 0;
    final n = VideoEditorNotifier(VideoEditorService())..state = const VideoEditorState();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: MaterialApp(
          home: Scaffold(
            body: VideoPreviewCanvas(
              videoSurface: const SizedBox.expand(),
              onTogglePreview: () => toggles++,
              onOutsidePictureTapped: () => outside++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getRect(find.byType(AspectRatio).first);
  }

  testWidgets('a tap beside the picture is an outside tap', (tester) async {
    final picture = await pump(tester);
    expect(picture.left, greaterThan(kPictureTapMarginPx * 2),
        reason: 'the test needs side space');
    await tester.tapAt(Offset(picture.left / 2, picture.center.dy));
    expect(outside, 1);
    expect(toggles, 0);
  });

  testWidgets('a tap on the picture keeps its own meaning', (tester) async {
    final picture = await pump(tester);
    await tester.tapAt(picture.center);
    expect(outside, 0);
    expect(toggles, 1);
  });

  testWidgets('a tap just past the edge, where a handle hangs, is neither',
      (tester) async {
    final picture = await pump(tester);
    await tester.tapAt(Offset(picture.left - kPictureTapMarginPx / 2, picture.center.dy));
    expect(outside, 0);
    expect(toggles, 0);
  });
}
