import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// "Mute clip audio" sits where CapCut puts it: just left of the cover card,
/// on the clips' row (the owner's ask, 2026-11-10).
void main() {
  late VideoEditorNotifier n;

  Future<void> pumpTimeline(
    WidgetTester tester, {
    List<VideoSegment>? segments,
    ({double start, double length})? recordingTake,
  }) async {
    const channel = MethodChannel('slimshot_ai/video_thumbnails');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getFrames') return null;
      final times = (call.arguments as Map)['timesMs'] as List;
      return List<Uint8List?>.filled(times.length, null);
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final clips = segments ?? [VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10)];
    n = VideoEditorNotifier(VideoEditorService())..state = VideoEditorState(segments: clips);
    await tester.pumpWidget(ProviderScope(
      overrides: [videoEditorProvider.overrideWith((ref) => n)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: ScrollableTimeline(
              onPausePlayback: () {},
              inputPath: '/v.mp4',
              durationSeconds: 10,
              trimRange: const RangeValues(0, 10),
              segments: clips,
              onTimelinePositionChanged: (_) {},
              recordingTake: recordingTake,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  final toggle = find.byKey(ScrollableTimeline.clipAudioToggleKey);
  final cover = find.byKey(ScrollableTimeline.coverCardKey);

  testWidgets('it sits just left of the cover, on the clips\' row', (tester) async {
    await pumpTimeline(tester);
    final button = tester.getRect(toggle);
    final card = tester.getRect(cover);
    expect(button.right, lessThanOrEqualTo(card.left));
    expect(card.left - button.right, lessThan(16), reason: 'beside it, not across the screen');
    expect(button.center.dy, moreOrLessEquals(card.center.dy, epsilon: 0.5));
    expect(button.left, greaterThanOrEqualTo(0), reason: 'on screen at the start');
  });

  testWidgets('a tap mutes the clips, another brings their sound back', (tester) async {
    await pumpTimeline(tester);
    expect(find.descendant(of: toggle, matching: find.byIcon(LucideIcons.volume2)), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(n.state.isMuted, isTrue);
    expect(find.descendant(of: toggle, matching: find.byIcon(LucideIcons.volumeX)), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(n.state.isMuted, isFalse);
    expect(find.descendant(of: toggle, matching: find.byIcon(LucideIcons.volume2)), findsOneWidget);
  });

  testWidgets('a screen reader hears what a tap will do', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTimeline(tester);
    expect(tester.getSemantics(toggle), matchesSemantics(label: 'Mute clip audio', isButton: true, hasTapAction: true));
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.getSemantics(toggle), matchesSemantics(label: 'Turn on clip audio', isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('it travels with the cover when the timeline scrolls', (tester) async {
    await pumpTimeline(tester);
    final buttonBefore = tester.getRect(toggle);
    final cardBefore = tester.getRect(cover);
    tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.axis == Axis.horizontal)
        .position
        .jumpTo(60);
    await tester.pump();
    final moved = tester.getRect(cover).left - cardBefore.left;
    expect(moved, lessThan(0));
    expect(tester.getRect(toggle).left - buttonBefore.left, moreOrLessEquals(moved, epsilon: 0.5));
  });

  testWidgets('no clips, no button', (tester) async {
    await pumpTimeline(tester, segments: const []);
    expect(toggle, findsNothing);
  });

  testWidgets('while recording it takes no taps, like the rest of the timeline', (tester) async {
    await pumpTimeline(tester, recordingTake: (start: 0, length: 1));
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pump();
    expect(n.state.isMuted, isFalse);
  });
}
