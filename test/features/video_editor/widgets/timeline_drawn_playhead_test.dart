import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// The timeline scrolls to the playhead as drawn, every frame.
///
/// It scrolled only when a position report rebuilt it — every other frame,
/// in steps. Given the drawn playhead it follows that alone: the reports,
/// arriving behind it, would pull it back a little thirty times a second.
void main() {
  const audio = AudioTrackModel(
    id: 'a',
    filePath: '/a.mp3',
    // Short enough to open at the usual scale, 50 px a second.
    sourceDuration: 6,
    sourceStart: 0,
    sourceEnd: 6,
    timelineStart: 0,
    laneIndex: 0,
  );

  Future<void> pumpTimeline(
    WidgetTester tester, {
    required double position,
    ValueNotifier<double>? playhead,
  }) async {
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = const VideoEditorState(audioTracks: [audio]);
    await tester.pumpWidget(ProviderScope(
      overrides: [videoEditorProvider.overrideWith((ref) => n)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: ScrollableTimeline(
              onPausePlayback: () {},
              inputPath: '',
              durationSeconds: 6,
              trimRange: const RangeValues(0, 6),
              timelinePositionSeconds: position,
              playhead: playhead,
              audioTracks: const [audio],
              onTimelinePositionChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  double scrolled(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((s) => s.position.axis == Axis.horizontal)
      .position
      .pixels;

  testWidgets('it scrolls to the drawn playhead without a rebuild', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playhead = ValueNotifier<double>(0);
    addTearDown(playhead.dispose);
    await pumpTimeline(tester, position: 0, playhead: playhead);

    playhead.value = 2.0;
    await tester.pump();
    expect(scrolled(tester), moreOrLessEquals(2.0 * 50, epsilon: 0.01));

    playhead.value = 2.016;
    await tester.pump();
    expect(scrolled(tester), moreOrLessEquals(2.016 * 50, epsilon: 0.01));
  });

  testWidgets('a report behind the drawn playhead does not pull it back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playhead = ValueNotifier<double>(0);
    addTearDown(playhead.dispose);
    await pumpTimeline(tester, position: 0, playhead: playhead);

    playhead.value = 2.04;
    await tester.pump();
    await pumpTimeline(tester, position: 2.0, playhead: playhead);
    expect(scrolled(tester), moreOrLessEquals(2.04 * 50, epsilon: 0.01));
  });

  testWidgets('without a drawn playhead it follows the position it is given', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpTimeline(tester, position: 0);
    await pumpTimeline(tester, position: 3.0);
    expect(scrolled(tester), moreOrLessEquals(3.0 * 50, epsilon: 0.01));
  });
}
