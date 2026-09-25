import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/clip_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/clip_keyframe_diamonds.dart';

/// The diamonds are drawn **on the filmstrip**, not in a row of their own.
///
/// A row implies one lane per animated property; a diamond here pins every
/// property at once, and costs the timeline no height.
void main() {
  const double widthPx = 200.0;
  const double height = 48.0;

  VideoSegment clip() => VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10);

  VideoEditorNotifier notifierWith(
    VideoSegment segment, {
    double position = 0.0,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [segment],
        selectedSegmentId: segment.id,
        isClipSelected: true,
        currentPlaybackPosition: position,
      );
  }

  Future<VideoEditorNotifier> pump(
    WidgetTester tester,
    VideoEditorNotifier notifier,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: widthPx,
                  height: height,
                  child: ClipKeyframeDiamonds(
                    widthPx: widthPx,
                    height: height,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return notifier;
  }

  testWidgets('an unkeyframed clip draws no diamonds', (tester) async {
    await pump(tester, notifierWith(clip()));
    expect(find.byType(KeyframeDiamond), findsNothing);
  });

  testWidgets('a diamond sits at its progress across the clip width',
      (tester) async {
    final notifier = notifierWith(clip(), position: 2.5); // progress 0.25
    notifier.addKeyframeAtPlayhead();
    await pump(tester, notifier);

    expect(find.byType(KeyframeDiamond), findsOneWidget);
    final centre = tester.getCenter(find.byType(KeyframeDiamond));
    expect(centre.dx, closeTo(0.25 * widthPx, 0.5));
  });

  testWidgets('diamonds are vertically centred on the thumbnail',
      (tester) async {
    final notifier = notifierWith(clip(), position: 5.0);
    notifier.addKeyframeAtPlayhead();
    await pump(tester, notifier);

    final centre = tester.getCenter(find.byType(KeyframeDiamond));
    // The middle of the filmstrip — not above it and not below it.
    expect(centre.dy, closeTo(height / 2, 0.5));
  });

  testWidgets('several diamonds draw at several places, in order',
      (tester) async {
    final notifier = notifierWith(clip());
    for (final seconds in [0.0, 5.0, 10.0]) {
      notifier.updatePlaybackPosition(seconds);
      notifier.addKeyframeAtPlayhead();
    }
    await pump(tester, notifier);

    expect(find.byType(KeyframeDiamond), findsNWidgets(3));
    final xs = tester
        .widgetList(find.byType(KeyframeDiamond))
        .map((w) => tester.getCenter(find.byWidget(w)).dx)
        .toList();
    expect(xs[0], closeTo(0.0, 0.5));
    expect(xs[1], closeTo(0.5 * widthPx, 0.5));
    expect(xs[2], closeTo(widthPx, 0.5));
  });

  testWidgets('tapping a diamond seeks the playhead onto it', (tester) async {
    final notifier = notifierWith(clip(), position: 7.5);
    notifier.addKeyframeAtPlayhead();
    notifier.updatePlaybackPosition(0.0);
    await pump(tester, notifier);

    await tester.tap(find.byType(KeyframeDiamond));
    await tester.pump();

    // Which is what makes the playback bar's control flip to minus.
    expect(notifier.state.currentPlaybackPosition, closeTo(7.5, 1e-6));
    expect(notifier.state.playheadIsOnKeyframe, isTrue);
  });

  testWidgets('a long press and drag moves the diamond, playhead riding along',
      (tester) async {
    // Tap seeks, and a plain drag on the filmstrip scrubs or reorders, so
    // moving a diamond is the long-press-drag those leave free — the same
    // gesture that picks up a clip.
    final notifier = notifierWith(clip(), position: 5.0);
    notifier.addKeyframeAtPlayhead();
    await pump(tester, notifier);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(KeyframeDiamond)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(40, 0)); // 40 of 200px: +0.2
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(keyframeProgresses(notifier.state.segments.single),
        [closeTo(0.7, 1e-6)]);
    // The playhead followed, so the diamond stays the selected one and the
    // canvas shows the instant being placed.
    expect(notifier.state.currentPlaybackPosition, closeTo(7.0, 1e-6));
    expect(notifier.state.playheadIsOnKeyframe, isTrue);

    // One undo step for the whole drag.
    notifier.undo();
    expect(keyframeProgresses(notifier.state.segments.single),
        [closeTo(0.5, 1e-6)]);
  });

  testWidgets('the diamond under the playhead reads as selected',
      (tester) async {
    final notifier = notifierWith(clip());
    for (final seconds in [0.0, 5.0]) {
      notifier.updatePlaybackPosition(seconds);
      notifier.addKeyframeAtPlayhead();
    }
    // Parked on the second one.
    await pump(tester, notifier);

    final diamonds =
        tester.widgetList<KeyframeDiamond>(find.byType(KeyframeDiamond)).toList();
    expect(diamonds, hasLength(2));
    expect(diamonds[0].isSelected, isFalse);
    expect(diamonds[1].isSelected, isTrue);
  });

  testWidgets('a diamond is hittable even though it is drawn small',
      (tester) async {
    // 11px of ink, a 32px target: the same split the trim handles make.
    final notifier = notifierWith(clip(), position: 5.0);
    notifier.addKeyframeAtPlayhead();
    notifier.updatePlaybackPosition(0.0);
    await pump(tester, notifier);

    // Ten pixels off the diamond's centre still lands on it.
    final centre = tester.getCenter(find.byType(KeyframeDiamond));
    await tester.tapAt(centre + const Offset(10, 0));
    await tester.pump();
    expect(notifier.state.currentPlaybackPosition, closeTo(5.0, 1e-6));
  });

  testWidgets('every property contributes to the drawn set', (tester) async {
    // The union, so a draft written by a build that stored fewer properties
    // still shows a diamond the user can remove.
    final notifier = notifierWith(clip(), position: 5.0);
    notifier.addKeyframeAtPlayhead();
    expect(keyframeProgresses(notifier.state.segments.first), hasLength(1));
    await pump(tester, notifier);
    expect(find.byType(KeyframeDiamond), findsOneWidget);
  });
}
