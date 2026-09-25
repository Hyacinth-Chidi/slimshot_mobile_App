import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/image_overlay/image_overlay_layer.dart';
import 'package:slimshotai/features/video_editor/widgets/overlay_content_box.dart';
import 'package:slimshotai/features/video_editor/widgets/video_overlay/video_overlay_layer.dart';

/// A scaled-up photo or video overlay can be touched everywhere it is drawn.
///
/// Every `RenderBox` gates hit-testing on its own size, and a `Transform` does
/// not change its child's. The gesture detector used to wrap the transforms,
/// so it kept the *unscaled* box: scaled past about 1.4×, the corner handles
/// and the outer band of the picture lay outside it, and a corner could not be
/// grabbed at all. The text layer had the same fault and the same fix.
void main() {
  const canvas = Size(360, 640);

  Future<VideoEditorNotifier> pump(
    WidgetTester tester,
    VideoEditorState state,
    Widget layer,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notifier = VideoEditorNotifier(VideoEditorService())..state = state;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: canvas.width,
                height: canvas.height,
                child: layer,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return notifier;
  }

  // Scales at which the whole picture is still on the canvas but its corners
  // are well outside the unscaled box.
  for (final (kind, scale) in [('photo', 1.6), ('video', 1.45)]) {
    VideoEditorState stateWith() => kind == 'photo'
        ? VideoEditorState(
            imageOverlays: [
              ImageOverlayModel(
                id: 'o',
                imagePath: '/missing.png',
                scale: scale,
                endTime: const Duration(seconds: 5),
              ),
            ],
            selectedImageId: 'o',
            currentPlaybackPosition: 1,
          )
        : VideoEditorState(
            videoOverlays: [
              VideoOverlayModel(
                id: 'o',
                videoPath: '/missing.mp4',
                scale: scale,
                timelineEnd: const Duration(seconds: 5),
              ),
            ],
            selectedVideoOverlayId: 'o',
            currentPlaybackPosition: 1,
          );
    Widget layer() => kind == 'photo'
        ? const ImageOverlayLayer(videoCanvasSize: canvas)
        : const VideoOverlayLayer(videoCanvasSize: canvas);
    double scaleOf(VideoEditorNotifier n) => kind == 'photo'
        ? n.state.imageOverlays.single.scale
        : n.state.videoOverlays.single.scale;
    Offset positionOf(VideoEditorNotifier n) => kind == 'photo'
        ? n.state.imageOverlays.single.position
        : n.state.videoOverlays.single.position;

    testWidgets('$kind at ${scale}x: a corner handle can be grabbed',
        (tester) async {
      final n = await pump(tester, stateWith(), layer());
      final corners = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onPanStart != null,
      );
      expect(corners, findsNWidgets(4));
      final bottomRight = List.generate(4, (i) => corners.at(i)).reduce((a, b) {
        final ca = tester.getCenter(a), cb = tester.getCenter(b);
        return ca.dx + ca.dy >= cb.dx + cb.dy ? a : b;
      });
      final at = tester.getCenter(bottomRight);
      expect(at.dx, lessThan(canvas.width), reason: 'the corner is on screen');

      final gesture = await tester.startGesture(at);
      await gesture.moveBy(const Offset(30, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(scaleOf(n), greaterThan(scale));
    });

    testWidgets('$kind at ${scale}x: the outer band of the picture can be '
        'dragged', (tester) async {
      final n = await pump(tester, stateWith(), layer());
      final content = tester.getRect(find.byType(OverlayContentBox));
      // Inside the drawn picture, a few pixels in from its right edge — past
      // where the unscaled box used to end.
      final at = Offset(content.right - 8, content.center.dy);
      final gesture = await tester.startGesture(at);
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(positionOf(n).dy, greaterThan(0));
    });
  }
}
