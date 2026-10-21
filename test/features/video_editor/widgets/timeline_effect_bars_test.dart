import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_zoom.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/lane_gutter_icons.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// Effect bars on the timeline: drawn at the zoom, in their own colour,
/// selected by a tap, moved by a long-press, trimmed by their handles.
void main() {
  Duration sec(num s) => Duration(milliseconds: (s * 1000).round());

  EffectBarModel bar(String id, String effect, double start, double end,
          {int lane = 0}) =>
      EffectBarModel(
          id: id, effectId: effect, start: start, end: end, laneIndex: lane);

  final taps = <String>[];
  final changes = <(String, Duration, Duration, int?)>[];

  Future<void> pumpTimeline(
    WidgetTester tester, {
    List<EffectBarModel> bars = const [],
    List<TextOverlayModel> texts = const [],
    String? selectedEffectBarId,
    ({double start, double length})? recordingTake,
  }) async {
    taps.clear();
    changes.clear();
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        effectBars: bars,
        textOverlays: texts,
        selectedEffectBarId: selectedEffectBarId,
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
                effectBars: bars,
                selectedEffectBarId: selectedEffectBarId,
                recordingTake: recordingTake,
                onEffectBarTapped: taps.add,
                onEffectBarChanged: (id, start, end, {newLaneIndex}) =>
                    changes.add((id, start, end, newLaneIndex)),
                onTimelinePositionChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder body(String id) => find.byKey(ValueKey('effect-bar:$id'));

  testWidgets('a bar sits at its time, at the zoom, with its effect\'s name',
      (tester) async {
    await pumpTimeline(tester, bars: [
      bar('e', 'blur', 2, 5),
      bar('f', 'vignette', 6, 7, lane: 1),
    ]);
    final e = tester.getRect(body('e'));
    final f = tester.getRect(body('f'));
    expect(e.width, closeTo(3 * kDefaultPixelsPerSecond, 1));
    expect(f.left - e.left, closeTo(4 * kDefaultPixelsPerSecond, 1));
    expect(find.text(videoEffectById('blur')!.label), findsOneWidget);
    expect(find.text('Vignette'), findsOneWidget);
  });

  testWidgets('a bar wears the effects colour, fuller when selected',
      (tester) async {
    await pumpTimeline(
      tester,
      bars: [bar('e', 'blur', 2, 5), bar('f', 'grain', 6, 8)],
      selectedEffectBarId: 'e',
    );
    Color fill(String id) =>
        ((tester.widget<Container>(body(id)).decoration! as BoxDecoration)
                .color)!;
    expect(fill('e'), AppColors.effectTrack);
    expect(fill('f'), AppColors.effectTrack.withValues(alpha: 0.5));
  });

  testWidgets('an effect this build does not know reads as Effect',
      (tester) async {
    await pumpTimeline(tester, bars: [bar('x', 'from_the_future', 2, 5)]);
    expect(find.text('Effect'), findsOneWidget);
  });

  testWidgets('a tap reports the bar', (tester) async {
    await pumpTimeline(tester, bars: [bar('e', 'blur', 2, 5)]);
    await tester.tap(body('e'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, ['e']);
  });

  testWidgets('a long-press drag down moves it a lane', (tester) async {
    await pumpTimeline(
      tester,
      bars: [bar('e', 'blur', 2, 5)],
      texts: [
        TextOverlayModel(
            id: 't', text: 'Hi', startTime: sec(9), endTime: sec(11)),
      ],
    );
    final gesture = await tester.startGesture(tester.getCenter(body('e')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(changes, isNotEmpty);
    expect(changes.last.$1, 'e');
    expect(changes.last.$4, 1);
  });

  testWidgets("a moved bar snaps onto another item's edge", (tester) async {
    await pumpTimeline(
      tester,
      bars: [bar('e', 'blur', 2, 5)],
      texts: [
        TextOverlayModel(
            id: 't', text: 'Hi', startTime: sec(6), endTime: sec(8), laneIndex: 1),
      ],
    );
    final gesture = await tester.startGesture(tester.getCenter(body('e')));
    await tester.pump(const Duration(milliseconds: 600));
    // 0.95s right: the bar's end lands 0.05s short of the text's start,
    // inside the snap's reach.
    await gesture.moveBy(const Offset(0.95 * kDefaultPixelsPerSecond, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final (_, start, end, _) = changes.last;
    expect(end, sec(6), reason: 'the end met the text');
    expect(start, sec(3));
  });

  testWidgets('a selected bar trims from its end handle', (tester) async {
    await pumpTimeline(
      tester,
      bars: [bar('e', 'blur', 2, 5)],
      selectedEffectBarId: 'e',
    );
    await tester.drag(
      find.byKey(const ValueKey('handle:effect:e:end')),
      const Offset(50, 0),
    );
    await tester.pump();
    expect(changes, isNotEmpty);
    final (id, start, end, lane) = changes.last;
    expect((id, start, lane), ('e', sec(2), null));
    expect(end.inMilliseconds / 1000.0, greaterThan(5.5));
  });

  testWidgets('a bar at 0:00 keeps its left handle inside itself',
      (tester) async {
    await pumpTimeline(
      tester,
      bars: [bar('e', 'blur', 0, 3)],
      selectedEffectBarId: 'e',
    );
    final handle = tester.getRect(find.byKey(const ValueKey('handle:effect:e:start')));
    expect(handle.left, greaterThanOrEqualTo(tester.getRect(body('e')).left - 0.5));
  });

  testWidgets('recording mode hides the bars with every other lane',
      (tester) async {
    await pumpTimeline(
      tester,
      bars: [bar('e', 'blur', 2, 5)],
      recordingTake: (start: 0, length: 1),
    );
    expect(body('e'), findsNothing);
  });

  test('the gutter marks a lane that holds an effect', () {
    expect(
      laneGutterKinds(
        lane: 1,
        audios: const [],
        texts: const [],
        images: const [],
        videos: const [],
        effects: [bar('e', 'blur', 0, 2, lane: 1)],
      ),
      [LaneGutterKind.effect],
    );
  });

  test('the effects colour is its own', () {
    expect(AppColors.effectTrack, isNot(AppColors.primaryStart));
    expect(AppColors.effectTrack, isNot(AppColors.soundEffect));
    expect(AppColors.effectTrack.toARGB32(), isNot(Colors.teal.shade400.toARGB32()));
    expect(AppColors.effectTrack.toARGB32(), isNot(Colors.pink.shade400.toARGB32()));
  });
}
