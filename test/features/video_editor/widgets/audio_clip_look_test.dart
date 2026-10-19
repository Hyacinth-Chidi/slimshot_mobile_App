import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// A selected audio clip: a white frame and slim white handles outside it.
void main() {
  const track = AudioTrackModel(
    id: 'a',
    filePath: '/a.mp3',
    sourceDuration: 4,
    sourceStart: 0,
    sourceEnd: 4,
    timelineStart: 2,
  );

  Future<void> pumpTimeline(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = const VideoEditorState(audioTracks: [track]);
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
                timelinePositionSeconds: 3,
                audioTracks: const [track],
                selectedAudioId: 'a',
                onTimelinePositionChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder clip() => find.byKey(const ValueKey('audio-clip:a'));
  Finder handle(String side) => find.byKey(ValueKey('audio-handle:a:$side'));

  testWidgets('a selected audio clip is framed in white', (tester) async {
    await pumpTimeline(tester);
    final box = tester.widget<Container>(clip()).decoration! as BoxDecoration;
    expect((box.border! as Border).top.color, AppColors.textPrimary);
  });

  testWidgets('its handles are slim and white', (tester) async {
    await pumpTimeline(tester);
    for (final side in ['start', 'end']) {
      final slab = tester.widget<AnimatedContainer>(handle(side));
      expect((slab.decoration! as BoxDecoration).color, AppColors.textPrimary);
      expect(tester.getSize(handle(side)).width, lessThanOrEqualTo(8));
    }
  });

  testWidgets('the handles sit just outside the clip, touching it', (tester) async {
    await pumpTimeline(tester);
    final body = tester.getRect(clip());
    expect(tester.getRect(handle('start')).right, closeTo(body.left, 0.5));
    expect(tester.getRect(handle('end')).left, closeTo(body.right, 0.5));
  });
}
