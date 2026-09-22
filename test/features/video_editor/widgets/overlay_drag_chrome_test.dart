import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/image_overlay/image_overlay_layer.dart';

/// The selection frame steps aside while the overlay is being moved.
///
/// The frame is a Flutter widget and the picture is drawn by GL, a frame or two
/// later by construction — so on a fast drag the dashed box visibly ran ahead
/// of the photo it was meant to surround (device-reported). Two drawings that
/// cannot agree should not both be on screen: while the body is dragged only
/// the picture shows, and the frame returns where the picture rests.
void main() {
  testWidgets('moving a photo overlay hides its frame until release, as one undo step',
      (tester) async {
    final notifier = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10)],
        imageOverlays: [ImageOverlayModel(id: 'i', imagePath: '/missing.png')],
        selectedImageId: 'i',
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 640,
                child: ImageOverlayLayer(videoCanvasSize: Size(360, 640)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final actionBar = find.byIcon(LucideIcons.trash2);
    expect(actionBar, findsOneWidget, reason: 'selected: the frame is up');

    final centre = tester.getCenter(find.byType(ImageOverlayLayer));
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 20));
    await tester.pump();

    expect(actionBar, findsNothing, reason: 'mid-drag: only the picture shows');
    expect(notifier.state.imageOverlays.single.position, isNot(Offset.zero));

    await gesture.up();
    await tester.pump();
    expect(actionBar, findsOneWidget, reason: 'released: the frame is back');

    notifier.undo();
    expect(notifier.state.imageOverlays.single.position, Offset.zero);
    expect(notifier.state.canUndo, isFalse, reason: 'the drag was one step');
  });
}
