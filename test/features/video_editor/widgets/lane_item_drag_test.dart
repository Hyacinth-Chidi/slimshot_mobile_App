import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// Device-reported: dragging a selected text, photo or video on its lane
/// trimmed it instead of moving it, most of all at the zoom the timeline
/// opens at. Each trim handle's touch area was centred on the item's edge,
/// so half of it — 22 px at each end — lay over the item and claimed the
/// finger the moment it landed; a one-second item at 50 px a second was
/// 50 px wide, 44 of them handle. The handles now reach outward, and only a
/// sliver of a narrow item is theirs.
void main() {
  late List<(String, Duration, Duration)> textCalls;
  late List<(String, Duration, Duration)> imageCalls;
  late List<(String, Duration, Duration)> videoCalls;

  Future<void> pumpTimeline(
    WidgetTester tester, {
    List<TextOverlayModel> texts = const [],
    List<ImageOverlayModel> images = const [],
    List<VideoOverlayModel> videos = const [],
    String? selectedTextId,
    String? selectedImageId,
    String? selectedVideoId,
  }) async {
    textCalls = [];
    imageCalls = [];
    videoCalls = [];
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        textOverlays: texts,
        imageOverlays: images,
        videoOverlays: videos,
      );
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
                timelinePositionSeconds: 0,
                textOverlays: texts,
                imageOverlays: images,
                videoOverlays: videos,
                selectedTextId: selectedTextId,
                selectedImageId: selectedImageId,
                selectedVideoId: selectedVideoId,
                onTimelinePositionChanged: (_) {},
                onTextTrimChanged: (id, start, end, {newLaneIndex}) =>
                    textCalls.add((id, start, end)),
                onImageTrimChanged: (id, start, end, {newLaneIndex}) =>
                    imageCalls.add((id, start, end)),
                onVideoTrimChanged: (id, start, end, {newLaneIndex}) =>
                    videoCalls.add((id, start, end)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder handle(String key) => find.byKey(ValueKey('handle:$key'));

  /// The item's left and right edges, read from where its handle bars sit.
  (double, double) edges(WidgetTester tester, String prefix) => (
        tester.getRect(handle('$prefix:start')).center.dx,
        tester.getRect(handle('$prefix:end')).center.dx,
      );

  /// A long press at [at], then a drag of [by] in small steps.
  Future<void> longPressDrag(WidgetTester tester, Offset at, Offset by) async {
    final gesture = await tester.startGesture(at);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    for (var i = 1; i <= 8; i++) {
      await gesture.moveBy(by / 8);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
  }

  /// A plain drag at [at], no long press: what grabs a handle.
  Future<void> drag(WidgetTester tester, Offset at, Offset by) async {
    final gesture = await tester.startGesture(at);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveBy(by / 8);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
  }

  const second = Duration(seconds: 1);
  final text = TextOverlayModel(
    id: 't',
    text: 'Hi',
    startTime: const Duration(seconds: 4),
    endTime: const Duration(seconds: 5),
  );
  final image = ImageOverlayModel(
    id: 'i',
    imagePath: '/i.png',
    startTime: const Duration(seconds: 4),
    endTime: const Duration(seconds: 5),
  );
  final video = VideoOverlayModel(
    id: 'v',
    videoPath: '/v.mp4',
    timelineStart: const Duration(seconds: 4),
    timelineEnd: const Duration(seconds: 5),
    sourceStart: 0,
    sourceEnd: 1,
  );

  group('a long-press drag on a narrow selected item moves it', () {
    // A quarter of the way in from each end: inside the old 22 px handle zone.
    for (final fraction in [0.25, 0.75]) {
      testWidgets('text, $fraction of the way in', (tester) async {
        await pumpTimeline(tester, texts: [text], selectedTextId: 't');
        final (left, right) = edges(tester, 'text:t');
        final y = tester.getRect(handle('text:t:start')).center.dy;
        await longPressDrag(
          tester,
          Offset(left + (right - left) * fraction, y),
          const Offset(40, 0),
        );
        expect(textCalls, isNotEmpty);
        final (_, start, end) = textCalls.last;
        expect(end - start, second, reason: 'a move keeps the length');
        expect(start, greaterThan(text.startTime));
      });
    }

    testWidgets('photo', (tester) async {
      await pumpTimeline(tester, images: [image], selectedImageId: 'i');
      final (left, right) = edges(tester, 'image:i');
      final y = tester.getRect(handle('image:i:start')).center.dy;
      await longPressDrag(
        tester,
        Offset(left + (right - left) * 0.25, y),
        const Offset(40, 0),
      );
      expect(imageCalls, isNotEmpty);
      final (_, start, end) = imageCalls.last;
      expect(end - start, second, reason: 'a move keeps the length');
      expect(start, greaterThan(image.startTime));
    });

    testWidgets('video', (tester) async {
      await pumpTimeline(tester, videos: [video], selectedVideoId: 'v');
      final (left, right) = edges(tester, 'video:v');
      final y = tester.getRect(handle('video:v:start')).center.dy;
      await longPressDrag(
        tester,
        Offset(left + (right - left) * 0.25, y),
        const Offset(40, 0),
      );
      expect(videoCalls, isNotEmpty);
      final (_, start, end) = videoCalls.last;
      expect(end - start, second, reason: 'a move keeps the length');
      expect(start, greaterThan(video.timelineStart));
    });
  });

  group('the handles still trim from just outside the edge', () {
    testWidgets('start', (tester) async {
      await pumpTimeline(tester, texts: [text], selectedTextId: 't');
      final (left, _) = edges(tester, 'text:t');
      final y = tester.getRect(handle('text:t:start')).center.dy;
      await drag(tester, Offset(left - 10, y), const Offset(-30, 0));
      expect(textCalls, isNotEmpty);
      final (_, start, end) = textCalls.last;
      expect(end, text.endTime, reason: 'the far edge stays');
      expect(start, lessThan(text.startTime));
    });

    testWidgets('end', (tester) async {
      await pumpTimeline(tester, texts: [text], selectedTextId: 't');
      final (_, right) = edges(tester, 'text:t');
      final y = tester.getRect(handle('text:t:end')).center.dy;
      await drag(tester, Offset(right + 10, y), const Offset(30, 0));
      expect(textCalls, isNotEmpty);
      final (_, start, end) = textCalls.last;
      expect(start, text.startTime, reason: 'the far edge stays');
      expect(end, greaterThan(text.endTime));
    });
  });
}
