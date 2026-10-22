import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// The playhead points at exactly the instant playback is at.
///
/// It was drawn 4.25 px to the right of it — 85 ms at the default zoom — so a
/// cut on the canvas came after the line had crossed its seam, and a playhead
/// parked on a seam by eye stopped short of it.
void main() {
  testWidgets('the playhead line and its triangle sit on the playback instant', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // A bar starting at 0:00, with the playhead at 0:00: its left edge is
    // where the timeline puts the playback instant.
    const audio = AudioTrackModel(
      id: 'a',
      filePath: '/a.mp3',
      sourceDuration: 4,
      sourceStart: 0,
      sourceEnd: 4,
      timelineStart: 0,
      laneIndex: 0,
    );
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
              durationSeconds: 20,
              trimRange: const RangeValues(0, 20),
              timelinePositionSeconds: 0,
              audioTracks: const [audio],
              onTimelinePositionChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final instantX = tester.getRect(find.byKey(const ValueKey('audio-clip:a'))).left;
    final line = tester.getRect(find.byKey(const ValueKey('timeline-playhead-line')));
    final triangle = tester.getRect(find.byKey(const ValueKey('timeline-playhead-triangle')));

    expect(line.center.dx, moreOrLessEquals(instantX, epsilon: 0.01));
    expect(triangle.center.dx, moreOrLessEquals(instantX, epsilon: 0.01));
  });
}
