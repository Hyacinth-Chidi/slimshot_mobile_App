import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_zoom.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// Recording mode: the timeline shows only the clips and the growing take,
/// and does not scrub.
void main() {
  const music = AudioTrackModel(
    id: 'a',
    filePath: '/a.mp3',
    sourceDuration: 4,
    sourceStart: 0,
    sourceEnd: 4,
    timelineStart: 1,
  );
  final text = TextOverlayModel(
    id: 't',
    text: 'Hi t',
    startTime: const Duration(seconds: 1),
    endTime: const Duration(seconds: 4),
  );
  final positions = <double>[];

  Future<void> pumpTimeline(
    WidgetTester tester, {
    ({double start, double length})? recordingTake,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(audioTracks: const [music], textOverlays: [text]);
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
                durationSeconds: 20,
                trimRange: const RangeValues(0, 20),
                timelinePositionSeconds: 2,
                audioTracks: const [music],
                textOverlays: [text],
                onTimelinePositionChanged: positions.add,
                recordingTake: recordingTake,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(positions.clear);

  testWidgets('outside recording the lanes are drawn', (tester) async {
    await pumpTimeline(tester);
    expect(find.text('Hi t'), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-clip:a')), findsOneWidget);
  });

  testWidgets('recording mode hides every lane but the clips', (tester) async {
    await pumpTimeline(tester, recordingTake: (start: 2, length: 0));
    expect(find.text('Hi t'), findsNothing);
    expect(find.byKey(const ValueKey('audio-clip:a')), findsNothing);
  });

  testWidgets('the take is drawn from its start for its length', (tester) async {
    await pumpTimeline(tester, recordingTake: (start: 2, length: 3));
    final bar = tester.getRect(find.byKey(const ValueKey('recording-take')));
    expect(bar.width, closeTo(3 * kDefaultPixelsPerSecond, 1));
  });

  testWidgets('a drag does not scrub while recording', (tester) async {
    await pumpTimeline(tester, recordingTake: (start: 2, length: 1));
    positions.clear();
    await tester.drag(find.byType(ScrollableTimeline), const Offset(-200, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(positions, isEmpty);
  });
}
