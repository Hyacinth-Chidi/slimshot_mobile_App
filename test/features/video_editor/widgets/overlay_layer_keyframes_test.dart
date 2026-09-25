import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/image_overlay/image_overlay_layer.dart';
import 'package:slimshotai/features/video_editor/widgets/overlay_content_box.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_layer.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/video_overlay/video_overlay_layer.dart';

import '../../../support/test_fonts.dart';

/// Keyframed overlays on the canvas: drawn where their keyframes put them at
/// the playhead, and edited from there.
///
/// Every overlay here spans 2s–6s and the playhead sits at 4s, progress 0.5.
/// No reference canvas is set, so a text's render scale is 1 and its canvas
/// pixels are the layer's.
void main() {
  const canvas = Size(360, 640);
  const start = Duration(seconds: 2);
  const end = Duration(seconds: 6);

  /// x 0 → 100, scale 1 → 3 and opacity 1 → 0 across the span: at 0.5 an
  /// overlay is drawn at x 50, scale 2, half faded.
  const glide = OverlayKeyframes({
    OverlayProperty.x: [
      Keyframe(progress: 0, value: 0),
      Keyframe(progress: 1, value: 100),
    ],
    OverlayProperty.scale: [
      Keyframe(progress: 0, value: 1),
      Keyframe(progress: 1, value: 3),
    ],
    OverlayProperty.opacity: [
      Keyframe(progress: 0, value: 1),
      Keyframe(progress: 1, value: 0),
    ],
  });

  List<double> diamonds(OverlayMotion m) => {
        for (final p in OverlayProperty.values)
          for (final k in m.keyframes.of(p)) k.progress,
      }.toList()
        ..sort();

  Future<VideoEditorNotifier> pumpLayer(
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

  group('text', () {
    TextOverlayModel text({
      OverlayKeyframes keyframes = glide,
      double opacity = 1.0,
    }) =>
        TextOverlayModel(
          id: 't',
          text: 'Hi',
          fontFamily: kTestFontFamily,
          startTime: start,
          endTime: end,
          opacity: opacity,
          keyframes: keyframes,
        );

    Widget layer() => TextOverlayLayer(
          videoCanvasSize: canvas,
          onShowTextEditor: (_, __) {},
        );

    final body = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is TextOverlayPainter,
    );
    Finder opacityIn(Type layerType) => find.descendant(
          of: find.byType(layerType),
          matching: find.byType(Opacity),
        );

    testWidgets('is drawn where its keyframes put it, half faded',
        (tester) async {
      await pumpLayer(
        tester,
        VideoEditorState(
          textOverlays: [text()],
          currentPlaybackPosition: 4,
        ),
        layer(),
      );
      expect(tester.getCenter(body).dx, closeTo(180 + 50, 0.5));
      expect(tester.widget<Opacity>(opacityIn(TextOverlayLayer)).opacity,
          closeTo(0.5, 1e-9));
      // The frame's width is the box at the resolved scale of 2.
      final box = tester.getSize(body);
      expect(box.width, greaterThan(0));
    });

    testWidgets('a text at full opacity pays for no Opacity layer, and one '
        'at 0.4 shows at 0.4', (tester) async {
      final n = await pumpLayer(
        tester,
        VideoEditorState(
          textOverlays: [text(keyframes: OverlayKeyframes.none)],
          currentPlaybackPosition: 4,
        ),
        layer(),
      );
      expect(opacityIn(TextOverlayLayer), findsNothing);
      n.state = n.state.copyWith(
        textOverlays: [text(keyframes: OverlayKeyframes.none, opacity: 0.4)],
      );
      await tester.pump();
      expect(tester.widget<Opacity>(opacityIn(TextOverlayLayer)).opacity, 0.4);
    });

    testWidgets('a drag starts from where it is drawn and writes a keyframe',
        (tester) async {
      // Review Focus 2: anchoring on the stored base would jump a keyframed
      // text back towards x 0 the moment it was touched.
      final n = await pumpLayer(
        tester,
        VideoEditorState(
          textOverlays: [text()],
          selectedTextId: 't',
          currentPlaybackPosition: 4,
          isPlaying: true,
        ),
        layer(),
      );
      final gesture = await tester.startGesture(tester.getCenter(body));
      await gesture.moveBy(const Offset(40, 0)); // past the slop
      await tester.pump();
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();

      final t = n.state.textOverlays.single;
      final shownX = t.shownAt(4).position.dx;
      expect(shownX, greaterThan(50), reason: 'no jump towards the base');
      expect(shownX, lessThanOrEqualTo(100));
      expect(t.position.dx, 0, reason: 'the base is untouched');
      expect(diamonds(t.motion), [0, 0.5, 1]);
      expect(n.state.isPlaying, isFalse, reason: 'a drag pauses first');
      expect(tester.getCenter(body).dx, closeTo(180 + shownX, 0.5));

      await gesture.up();
      // Past the double-tap window, whose recogniser the body also carries.
      await tester.pump(const Duration(milliseconds: 500));
      n.undo();
      expect(diamonds(n.state.textOverlays.single.motion), [0, 1],
          reason: 'the whole drag is one undo step');
    });

    testWidgets('widening a keyframed text moves it through a keyframe',
        (tester) async {
      // The pill keeps the far edge where it is by shifting the centre — a
      // position write, so on a keyframed text it has to go through the edit
      // rule, from where the text is drawn.
      final n = await pumpLayer(
        tester,
        VideoEditorState(
          textOverlays: [text()],
          selectedTextId: 't',
          currentPlaybackPosition: 4,
        ),
        layer(),
      );
      final pills = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_HandlePill',
      );
      expect(pills, findsNWidgets(2));
      final widthBefore = n.state.textOverlays.single.boxWidth;
      // The right-hand pill.
      final right = tester.getCenter(pills.last).dx > tester.getCenter(pills.first).dx
          ? pills.last
          : pills.first;
      final gesture = await tester.startGesture(tester.getCenter(right));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final t = n.state.textOverlays.single;
      expect(t.boxWidth, isNot(widthBefore));
      expect(t.position.dx, 0, reason: 'the base is untouched');
      expect(t.shownAt(4).position.dx, greaterThan(50),
          reason: 'the right edge grew, so the centre moved right of 50');
      expect(diamonds(t.motion), [0, 0.5, 1]);
    });
  });

  /// Scale 0.5 → 1 across the span, drawn at 0.75 at the playhead: small
  /// enough that every corner handle is on the canvas, and away from the base
  /// of 1, so a resize anchored on the base is caught.
  const shrunk = OverlayKeyframes({
    OverlayProperty.scale: [
      Keyframe(progress: 0, value: 0.5),
      Keyframe(progress: 1, value: 1),
    ],
  });

  for (final kind in ['photo', 'video']) {
    group(kind, () {
      VideoEditorState stateWith({
        required bool selected,
        OverlayKeyframes keyframes = glide,
      }) =>
          kind == 'photo'
              ? VideoEditorState(
                  imageOverlays: [
                    ImageOverlayModel(
                      id: 'o',
                      imagePath: '/missing.png',
                      startTime: start,
                      endTime: end,
                      keyframes: keyframes,
                    ),
                  ],
                  selectedImageId: selected ? 'o' : null,
                  currentPlaybackPosition: 4,
                )
              : VideoEditorState(
                  videoOverlays: [
                    VideoOverlayModel(
                      id: 'o',
                      videoPath: '/missing.mp4',
                      timelineStart: start,
                      timelineEnd: end,
                      keyframes: keyframes,
                    ),
                  ],
                  selectedVideoOverlayId: selected ? 'o' : null,
                  currentPlaybackPosition: 4,
                );
      Widget layer() => kind == 'photo'
          ? const ImageOverlayLayer(videoCanvasSize: canvas)
          : const VideoOverlayLayer(videoCanvasSize: canvas);
      OverlayMotion motionOf(VideoEditorNotifier n) => kind == 'photo'
          ? n.state.imageOverlays.single.motion
          : n.state.videoOverlays.single.motion;

      final content = find.byType(OverlayContentBox);

      testWidgets('its frame sits where its keyframes put it', (tester) async {
        await pumpLayer(tester, stateWith(selected: true), layer());
        expect(tester.getCenter(content).dx, closeTo(180 + 50, 0.5));
      });

      testWidgets('a drag starts from where it is drawn and writes a keyframe',
          (tester) async {
        final n = await pumpLayer(tester, stateWith(selected: true), layer());
        final gesture = await tester.startGesture(tester.getCenter(content));
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final m = motionOf(n);
        expect(m.at(0.5).position.dx, greaterThan(50),
            reason: 'no jump towards the base');
        expect(m.position.dx, 0, reason: 'the base is untouched');
        expect(m.at(0.5).scale, closeTo(2, 1e-9),
            reason: 'a move writes the scale it was drawn at, not the base');
        expect(diamonds(m), [0, 0.5, 1]);
      });

      testWidgets('a corner handle resizes from the drawn size',
          (tester) async {
        final n = await pumpLayer(
          tester,
          stateWith(selected: true, keyframes: shrunk),
          layer(),
        );
        final corners = find.descendant(
          of: find.byType(kind == 'photo' ? ImageOverlayLayer : VideoOverlayLayer),
          matching: find.byWidgetPredicate(
            (w) => w is GestureDetector && w.onPanStart != null,
          ),
        );
        expect(corners, findsNWidgets(4));
        // The bottom-right one: the furthest right and down.
        final bottomRight = List.generate(4, (i) => corners.at(i)).reduce(
          (a, b) {
            final ca = tester.getCenter(a), cb = tester.getCenter(b);
            return ca.dx + ca.dy >= cb.dx + cb.dy ? a : b;
          },
        );
        final gesture = await tester.startGesture(tester.getCenter(bottomRight));
        await gesture.moveBy(const Offset(30, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(10, 10));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final scale = motionOf(n).at(0.5).scale;
        expect(scale, greaterThan(0.75), reason: 'grown from the drawn 0.75');
        expect(scale, lessThan(1), reason: 'not from the base of 1');
        expect(motionOf(n).scale, 1, reason: 'the base is untouched');
        expect(diamonds(motionOf(n)), [0, 0.5, 1]);
      });
    });
  }
}
