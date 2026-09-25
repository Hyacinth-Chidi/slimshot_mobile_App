import 'dart:io';

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
import 'package:slimshotai/features/video_editor/widgets/timeline/clip_keyframe_diamonds.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// An overlay's diamonds sit on **its own bar** in the timeline, the way a
/// clip's sit on its filmstrip — and only while it is the one selected, so
/// the diamonds on screen are always the ones the playback bar acts on.
void main() {
  const start = Duration(seconds: 2);
  const end = Duration(seconds: 6);

  /// Diamonds at 0.25 and 0.75 of the span: 3s and 5s on the timeline.
  const twoDiamonds = OverlayKeyframes({
    OverlayProperty.x: [
      Keyframe(progress: 0.25, value: 0),
      Keyframe(progress: 0.75, value: 100),
    ],
  });

  TextOverlayModel text({String id = 't', int lane = 0}) => TextOverlayModel(
        id: id,
        text: 'Hi $id',
        startTime: start,
        endTime: end,
        laneIndex: lane,
        keyframes: twoDiamonds,
      );

  group('the diamonds widget', () {
    const widthPx = 200.0;

    testWidgets('draws the selected overlay\'s diamonds, and a tap seeks '
        'onto one', (tester) async {
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          textOverlays: [text()],
          selectedTextId: 't',
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [videoEditorProvider.overrideWith((ref) => n)],
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: widthPx,
                    height: 24,
                    child: ClipKeyframeDiamonds(widthPx: widthPx, height: 24),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final diamonds = find.byType(KeyframeDiamond);
      expect(diamonds, findsNWidgets(2));
      final xs = [
        for (var i = 0; i < 2; i++) tester.getCenter(diamonds.at(i)).dx,
      ]..sort();
      expect(xs[0], closeTo(0.25 * widthPx, 0.5));
      expect(xs[1], closeTo(0.75 * widthPx, 0.5));

      await tester.tap(diamonds.at(1));
      await tester.pump();
      final seeked = n.state.currentPlaybackPosition;
      expect([3.0, 5.0].any((t) => (t - seeked).abs() < 1e-9), isTrue,
          reason: 'the playhead lands on the diamond: start + progress × span');
      expect(n.state.playheadIsOnKeyframe, isTrue);
    });
  });

  group('the timeline', () {
    Future<VideoEditorNotifier> pumpTimeline(
      WidgetTester tester,
      VideoEditorState state,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final n = VideoEditorNotifier(VideoEditorService())..state = state;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [videoEditorProvider.overrideWith((ref) => n)],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 400,
                child: ScrollableTimeline(
                  onPausePlayback: () {},
                  inputPath: '',
                  durationSeconds: 10,
                  trimRange: const RangeValues(0, 10),
                  textOverlays: state.textOverlays,
                  selectedTextId: state.selectedTextId,
                  imageOverlays: state.imageOverlays,
                  selectedImageId: state.selectedImageId,
                  videoOverlays: state.videoOverlays,
                  selectedVideoId: state.selectedVideoOverlayId,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return n;
    }

    /// The bar a lane item is drawn as: the box its label sits in.
    Rect barOf(WidgetTester tester, String label) => tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );

    testWidgets('the selected text\'s bar carries its diamonds; another\'s '
        'does not', (tester) async {
      await pumpTimeline(
        tester,
        VideoEditorState(
          textOverlays: [text(), text(id: 'u', lane: 1)],
          selectedTextId: 't',
        ),
      );
      final diamonds = find.byType(KeyframeDiamond);
      expect(diamonds, findsNWidgets(2), reason: 'only the selected text');

      final bar = barOf(tester, 'Hi t');
      for (var i = 0; i < 2; i++) {
        final c = tester.getCenter(diamonds.at(i));
        final p = (c.dx - bar.left) / bar.width;
        expect([0.25, 0.75].any((q) => (q - p).abs() < 0.01), isTrue,
            reason: 'diamond $i at progress $p across its own bar');
        expect(c.dy, closeTo(bar.center.dy, 1), reason: 'on the bar');
      }
    });

    testWidgets('a photo and a video carry theirs when selected',
        (tester) async {
      await pumpTimeline(
        tester,
        VideoEditorState(
          imageOverlays: [
            ImageOverlayModel(
              id: 'i',
              imagePath: '/p.png',
              startTime: start,
              endTime: end,
              keyframes: twoDiamonds,
            ),
          ],
          selectedImageId: 'i',
        ),
      );
      expect(find.byType(KeyframeDiamond), findsNWidgets(2));

      await pumpTimeline(
        tester,
        VideoEditorState(
          videoOverlays: [
            VideoOverlayModel(
              id: 'v',
              videoPath: '/v.mp4',
              timelineStart: start,
              timelineEnd: end,
              keyframes: twoDiamonds,
            ),
          ],
          selectedVideoOverlayId: 'v',
        ),
      );
      expect(find.byType(KeyframeDiamond), findsNWidgets(2));
    });

    testWidgets('nothing selected, no diamonds anywhere', (tester) async {
      await pumpTimeline(tester, VideoEditorState(textOverlays: [text()]));
      expect(find.byType(KeyframeDiamond), findsNothing);
    });
  });

  group('the screen', () {
    // The screen needs a loaded project, a native texture and a platform
    // channel to build, so these read its source — the menu tests' pattern.
    final screen = File('lib/screens/video_editor_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('the playback bar offers keyframes for any keyframe target', () {
      expect(screen,
          contains('showsKeyframeControls: editorState.hasKeyframeTarget'));
      expect(screen, contains(
          'canToggleKeyframe: editorState.keyframeTargetProgress != null'));
    });

    test('the Opacity panel shows what an overlay\'s write will target, and '
        'a drag pauses first', () {
      final start = screen.indexOf('Widget _buildOpacityPanel()');
      final panel = screen.substring(start, screen.indexOf('\n  }\n', start));
      expect(panel, contains('overlayEditValue(OverlayProperty.opacity)'));
      expect(panel, contains('onChangeStart: notifier.beginOverlayEdit'));
      // A clip's opacity slider writes at the playhead too.
      expect(panel, contains('onChangeStart: notifier.beginLiveEdit'));
      expect(panel, isNot(contains('saveStateForUndo')));
    });

    test('the effect intensity slider pauses before it writes', () {
      final effects = File(
        'lib/features/video_editor/widgets/panels/effects_panel.dart',
      ).readAsStringSync();
      expect(effects, contains('notifier.beginLiveEdit()'));
    });
  });

  test('a live edit pauses and takes one snapshot', () {
    // Review Focus 1 for the sliders: a drag writes at the playhead every
    // frame, so a moving playhead would leave a trail of diamonds.
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = const VideoEditorState(isPlaying: true);
    n.beginLiveEdit();
    expect(n.state.isPlaying, isFalse);
    expect(n.state.canUndo, isTrue);
  });
}
