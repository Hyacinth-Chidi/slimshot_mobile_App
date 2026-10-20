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

/// Pinch to zoom the timeline, and one snapping rule for what moves on it.
void main() {
  const width = 800.0;

  TextOverlayModel text(String id, double start, double end, {int lane = 0}) =>
      TextOverlayModel(
        id: id,
        text: 'Hi $id',
        startTime: Duration(milliseconds: (start * 1000).round()),
        endTime: Duration(milliseconds: (end * 1000).round()),
        laneIndex: lane,
      );

  final positions = <double>[];
  final moves = <(String, Duration, Duration)>[];

  Future<void> pumpTimeline(
    WidgetTester tester,
    List<TextOverlayModel> texts, {
    double playhead = 3.0,
    String? selectedTextId,
    List<AudioTrackModel> audio = const [],
  }) async {
    positions.clear();
    moves.clear();
    await tester.binding.setSurfaceSize(const Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(textOverlays: texts);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 400,
              child: ScrollableTimeline(
                onPausePlayback: () {},
                inputPath: '',
                durationSeconds: 20,
                trimRange: const RangeValues(0, 20),
                timelinePositionSeconds: playhead,
                textOverlays: texts,
                audioTracks: audio,
                selectedTextId: selectedTextId,
                onTimelinePositionChanged: positions.add,
                onTextTrimChanged: (id, start, end, {newLaneIndex}) =>
                    moves.add((id, start, end)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect barOf(WidgetTester tester, String label) => tester.getRect(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );

  /// Two fingers on the track, spread apart (or pinched together) by [by] px.
  Future<void> pinch(WidgetTester tester, Offset centre, double by) async {
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
    // Let the lane item's tap recognisers time out under the lifted fingers.
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the timeline opens at the default scale', (tester) async {
    await pumpTimeline(tester, [text('t', 2, 6)]);
    expect(barOf(tester, 'Hi t').width,
        closeTo(4 * kDefaultPixelsPerSecond, 2));
  });

  testWidgets('spreading two fingers zooms in about the playhead', (tester) async {
    // The playhead reaches 3s the way the editor moves it: a new position.
    await pumpTimeline(tester, [text('t', 2, 6)], playhead: 0);
    await pumpTimeline(tester, [text('t', 2, 6)], playhead: 3.0);
    await tester.pump();
    expect(width / 2 - barOf(tester, 'Hi t').left,
        closeTo(1.0 * kDefaultPixelsPerSecond, 3),
        reason: 'before the pinch, 3s is under the playhead');
    // On the lane row, mid-screen: inside the track, wherever it ends.
    final track = Offset(width / 2, tester.getCenter(find.text('Hi t')).dy);
    await pinch(tester, track, 100); // 100px apart → 200px apart: ×2

    final bar = barOf(tester, 'Hi t');
    final pps = bar.width / 4;
    expect(pps, closeTo(2 * kDefaultPixelsPerSecond, 5));
    // The playhead (the screen's centre, at 3s) still has 3s under it: the
    // bar starting at 2s sits one second's worth of the new scale to its left.
    expect(width / 2 - bar.left, closeTo(1.0 * pps, 3));
    // Nothing reported a different time: a zoom is not a scrub.
    for (final p in positions) {
      expect(p, closeTo(3.0, 1e-6));
    }
  });

  testWidgets('pinching together zooms out, but never past the default for a '
      'short project', (tester) async {
    await pumpTimeline(tester, [text('t', 2, 6)]);
    // On the lane row, mid-screen: inside the track, wherever it ends.
    final track = Offset(width / 2, tester.getCenter(find.text('Hi t')).dy);
    await pinch(tester, track, -60);
    expect(barOf(tester, 'Hi t').width,
        closeTo(4 * kDefaultPixelsPerSecond, 2));
  });

  testWidgets('a sound added while zoomed in is drawn at the zoom', (tester) async {
    // Extract, Record and the library all add while the user is zoomed in:
    // the new bar must take the scale everything else is at, not the default.
    await pumpTimeline(tester, [text('t', 2, 6)]);
    final track = Offset(width / 2, tester.getCenter(find.text('Hi t')).dy);
    await pinch(tester, track, 100);
    final pps = barOf(tester, 'Hi t').width / 4;
    expect(pps, greaterThan(1.5 * kDefaultPixelsPerSecond));

    const added = AudioTrackModel(
      id: 'voice',
      filePath: '/d/voice.m4a',
      sourceDuration: 10,
      sourceStart: 0,
      sourceEnd: 3,
      timelineStart: 3,
      laneIndex: 1,
    );
    await pumpTimeline(tester, [text('t', 2, 6)], audio: [added]);
    final bar = tester.getRect(find.byKey(const ValueKey('audio-clip:voice')));
    expect(bar.width, closeTo(3 * pps, 3), reason: 'three seconds at the zoom');
    expect(bar.left - barOf(tester, 'Hi t').left, closeTo(1 * pps, 3),
        reason: 'it starts a second after the text, at the zoom');
  });

  testWidgets('one finger still scrubs', (tester) async {
    await pumpTimeline(tester, [text('t', 2, 6)]);
    final track = tester.getCenter(find.byType(ScrollableTimeline));
    await tester.dragFrom(track + const Offset(0, -150), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(positions, isNotEmpty);
    expect(positions.last, greaterThan(0.5),
        reason: 'dragging the track left moves the playhead later');
  });

  testWidgets('moving an item onto another item\'s edge snaps to it',
      (tester) async {
    // 'u' starts at 7.3s on the lane below. Dragging 't' (2–6s) right by
    // 1.27s puts its end 0.03s — 1.5px — short of 7.3: within reach.
    await pumpTimeline(
      tester,
      [text('t', 2, 6), text('u', 7.3, 9, lane: 1)],
      playhead: 0,
    );
    final start = tester.getCenter(find.text('Hi t'));
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    const dx = 1.27 * kDefaultPixelsPerSecond;
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(dx / 10, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    expect(moves, isNotEmpty);
    final (_, s, e) = moves.last;
    expect(e.inMilliseconds, 7300);
    expect(s.inMilliseconds, 3300);
  });

  testWidgets('trimming an item end onto another item start snaps to it',
      (tester) async {
    await pumpTimeline(
      tester,
      [text('t', 2, 6), text('u', 7.3, 9, lane: 1)],
      playhead: 0,
      selectedTextId: 't',
    );
    final bar = barOf(tester, 'Hi t');
    final g = await tester.startGesture(Offset(bar.right, bar.center.dy));
    const dx = 1.27 * kDefaultPixelsPerSecond;
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(dx / 10, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    expect(moves, isNotEmpty);
    final (_, s, e) = moves.last;
    expect(s.inMilliseconds, 2000);
    expect(e.inMilliseconds, 7300);
  });
}
