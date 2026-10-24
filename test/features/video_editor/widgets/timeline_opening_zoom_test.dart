import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_zoom.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// The timeline opens zoomed out, the whole project in view; a pinch spreads
/// it out.
///
/// It opened at 50 px a second whatever the project's length, so a minute of
/// video was eight screens of timeline to scroll through before anyone had
/// pinched it smaller.
void main() {
  const width = 800.0;

  AudioTrackModel sound(double seconds) => AudioTrackModel(
        id: 'a',
        filePath: '/a.mp3',
        sourceDuration: seconds,
        sourceStart: 0,
        sourceEnd: seconds,
        timelineStart: 0,
        laneIndex: 0,
      );

  Future<void> pumpTimeline(
    WidgetTester tester,
    AudioTrackModel audio, {
    double playhead = 0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(audioTracks: [audio]);
    await tester.pumpWidget(ProviderScope(
      overrides: [videoEditorProvider.overrideWith((ref) => n)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 400,
            child: ScrollableTimeline(
              onPausePlayback: () {},
              inputPath: '',
              durationSeconds: audio.sourceDuration,
              trimRange: RangeValues(0, audio.sourceDuration),
              timelinePositionSeconds: playhead,
              audioTracks: [audio],
              onTimelinePositionChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Rect bar(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('audio-clip:a')));

  Future<void> pinch(WidgetTester tester, double by) async {
    final centre = Offset(width / 2, tester.getCenter(find.byKey(const ValueKey('audio-clip:a'))).dy);
    final a = await tester.startGesture(centre - const Offset(50, 0));
    final b = await tester.startGesture(centre + const Offset(50, 0));
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await a.moveBy(Offset(-by / 20, 0));
      await b.moveBy(Offset(by / 20, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a long project opens with all of it fitted', (tester) async {
    await pumpTimeline(tester, sound(60));
    // The furthest zoom out: the project across 80% of the screen.
    expect(bar(tester).width, closeTo(width * kZoomOutFitFraction, 1));
  });

  testWidgets('a short project opens at the usual scale', (tester) async {
    await pumpTimeline(tester, sound(6));
    expect(bar(tester).width, closeTo(6 * kDefaultPixelsPerSecond, 1));
  });

  testWidgets('the playhead travels at the fitted scale', (tester) async {
    // The editor opens at 0:00 and moves the playhead from there.
    await pumpTimeline(tester, sound(60));
    await pumpTimeline(tester, sound(60), playhead: 30);
    await tester.pump();
    const fit = width * kZoomOutFitFraction / 60;
    // 30 s is under the playhead, in the middle of the screen.
    expect(width / 2 - bar(tester).left, closeTo(30 * fit, 1));
  });

  testWidgets('from there a pinch spreads it out, and cannot shrink it', (tester) async {
    await pumpTimeline(tester, sound(60));
    final fitted = bar(tester).width;

    await pinch(tester, -60);
    expect(bar(tester).width, closeTo(fitted, 1));

    await pinch(tester, 100); // 100 px apart → 200: ×2
    expect(bar(tester).width, closeTo(2 * fitted, 8));
  });

  testWidgets('an edit after opening does not rescale it', (tester) async {
    await pumpTimeline(tester, sound(60));
    final fitted = bar(tester).width / 60;
    await pumpTimeline(tester, sound(120));
    expect(bar(tester).width / 120, closeTo(fitted, 0.01));
  });

  testWidgets('it opens with frames asked for across all it shows', (tester) async {
    // Fitted, a minute of video shows ~37 s right of the playhead at 0:00.
    // The first build cannot measure the track, and used to assume 12 s were
    // in view; nothing rebuilt it after, so the rest of the strip stayed
    // blank until the timeline was touched.
    final asked = <int>[];
    const channel = MethodChannel('slimshot_ai/video_thumbnails');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getFrames') return null;
      final times = ((call.arguments as Map)['timesMs'] as List).cast<int>();
      asked.addAll(times);
      return List<Uint8List?>.filled(times.length, null);
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    await tester.binding.setSurfaceSize(const Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final clip = VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 60);
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(segments: [clip]);
    await tester.pumpWidget(ProviderScope(
      overrides: [videoEditorProvider.overrideWith((ref) => n)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 400,
            child: ScrollableTimeline(
              onPausePlayback: () {},
              inputPath: '/v.mp4',
              durationSeconds: 60,
              trimRange: const RangeValues(0, 60),
              segments: [clip],
              onTimelinePositionChanged: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(asked, isNotEmpty);
    expect(asked.reduce((a, b) => a > b ? a : b), greaterThan(30000));
  });
}
