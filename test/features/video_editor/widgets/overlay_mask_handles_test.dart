import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/image_overlay/image_overlay_layer.dart';
import 'package:slimshotai/features/video_editor/widgets/mask_outline_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/overlay_content_box.dart';
import 'package:slimshotai/features/video_editor/widgets/video_overlay/video_overlay_layer.dart';

/// An overlay's mask is placed on the canvas, like a clip's.
///
/// Overlays have carried a mask since the mask tool was built, but nothing on
/// the canvas could move or size it — only a clip's window answered a drag —
/// so an overlay's window sat at its default in the middle of the picture,
/// while the panel's hint said "drag on the canvas to move the window". The
/// car-crash edit masks an overlay with a tilted line, so the overlay needs
/// the same handles: drag to move, pinch to resize, twist to tilt.
///
/// The editor lives in each overlay layer, which already lays the box out
/// exactly where the engine draws the picture — animation and rotation
/// included — so a drag is read in the box's own axes for free. The outline
/// and the gesture maths are the clip's own (`MaskOutlinePainter`,
/// `maskAfterGesture`): one mask editor, not two.
void main() {
  const canvas = Size(360, 640);
  const window = ClipMask(
    shape: ClipMaskShape.rectangle,
    centerX: 0.5,
    centerY: 0.5,
    width: 0.4,
    height: 0.4,
  );

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

  // A file that does not exist has no measured shape, so the box is its
  // square: 200 px for a photo, 240 for a video, at scale 1.
  for (final (kind, box) in [('photo', 200.0), ('video', 240.0)]) {
    VideoEditorState stateWith({
      ClipMask mask = window,
      double rotation = 0,
      String? tool = 'mask',
    }) =>
        kind == 'photo'
            ? VideoEditorState(
                imageOverlays: [
                  ImageOverlayModel(
                    id: 'o',
                    imagePath: '/missing.png',
                    rotation: rotation,
                    endTime: const Duration(seconds: 5),
                    mask: mask,
                  ),
                ],
                selectedImageId: 'o',
                currentPlaybackPosition: 1,
                activeToolId: tool,
              )
            : VideoEditorState(
                videoOverlays: [
                  VideoOverlayModel(
                    id: 'o',
                    videoPath: '/missing.mp4',
                    rotation: rotation,
                    timelineEnd: const Duration(seconds: 5),
                    mask: mask,
                  ),
                ],
                selectedVideoOverlayId: 'o',
                currentPlaybackPosition: 1,
                activeToolId: tool,
              );
    Widget layer() => kind == 'photo'
        ? const ImageOverlayLayer(videoCanvasSize: canvas)
        : const VideoOverlayLayer(videoCanvasSize: canvas);
    ClipMask maskOf(VideoEditorNotifier n) => kind == 'photo'
        ? n.state.imageOverlays.single.mask
        : n.state.videoOverlays.single.mask;
    Offset positionOf(VideoEditorNotifier n) => kind == 'photo'
        ? n.state.imageOverlays.single.position
        : n.state.videoOverlays.single.position;

    /// Drags from the picture's centre, and returns the window after a first
    /// move and after a second — the second step is measured on its own, so
    /// the recogniser's touch slop cannot blur the arithmetic.
    Future<(ClipMask, ClipMask)> drag(
      WidgetTester tester,
      VideoEditorNotifier n,
      Offset second,
    ) async {
      final at = tester.getCenter(find.byType(OverlayContentBox));
      final gesture = await tester.startGesture(at);
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      final first = maskOf(n);
      await gesture.moveBy(second);
      await tester.pump();
      final then = maskOf(n);
      await gesture.up();
      await tester.pump();
      return (first, then);
    }

    testWidgets('$kind: in the mask tool a drag moves the window, not the overlay',
        (tester) async {
      final n = await pump(tester, stateWith(), layer());
      final (first, then) = await drag(tester, n, const Offset(40, 20));
      expect(then.centerX - first.centerX, closeTo(40 / box, 1e-6));
      expect(then.centerY - first.centerY, closeTo(20 / box, 1e-6));
      expect(positionOf(n), Offset.zero, reason: 'the overlay stays put');
    });

    testWidgets('$kind: on a turned overlay the window moves along its own axes',
        (tester) async {
      // Turned a quarter clockwise, the overlay's own x runs down the screen
      // and its y runs leftward — so a drag to the right moves the window up
      // its own y, and not along its x at all.
      final n = await pump(tester, stateWith(rotation: math.pi / 2), layer());
      final (first, then) = await drag(tester, n, const Offset(40, 0));
      expect(then.centerX - first.centerX, closeTo(0, 1e-6));
      expect(then.centerY - first.centerY, closeTo(-40 / box, 1e-6));
    });

    testWidgets('$kind: in the mask tool the outline replaces the handles',
        (tester) async {
      await pump(tester, stateWith(), layer());
      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MaskOutlinePainter),
        findsOneWidget,
      );
      // The corner dots are the overlay's resize handles: a mask edit must
      // not be able to grab the overlay instead.
      expect(
        find.byWidgetPredicate((w) => w is GestureDetector && w.onPanStart != null),
        findsNothing,
      );
    });

    testWidgets('$kind: outside the mask tool the overlay has its handles back',
        (tester) async {
      await pump(tester, stateWith(tool: null), layer());
      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MaskOutlinePainter),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is GestureDetector && w.onPanStart != null),
        findsNWidgets(4),
      );
    });

    testWidgets('$kind: with no window yet, a drag still moves the overlay',
        (tester) async {
      // Nothing to place until a shape is picked — the clip's rule too.
      final n = await pump(tester, stateWith(mask: ClipMask.none), layer());
      await drag(tester, n, const Offset(40, 20));
      expect(positionOf(n), isNot(Offset.zero));
      expect(maskOf(n), ClipMask.none);
    });

    testWidgets('$kind: one gesture is one undo step', (tester) async {
      final n = await pump(tester, stateWith(), layer());
      await drag(tester, n, const Offset(40, 20));
      expect(maskOf(n), isNot(window));
      n.undo();
      expect(maskOf(n), window);
    });
  }
}
