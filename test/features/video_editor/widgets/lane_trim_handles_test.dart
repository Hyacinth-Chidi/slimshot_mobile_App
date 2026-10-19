import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// The trim handles on the lanes: a selected audio clip is framed in white
/// with slim white handles outside it, and an item starting at 0:00 keeps
/// its left handle inside, so nothing is drawn past the timeline's start.
void main() {
  AudioTrackModel audio(double start, {int lane = 0}) => AudioTrackModel(
        id: 'a',
        filePath: '/a.mp3',
        sourceDuration: 4,
        sourceStart: 0,
        sourceEnd: 4,
        timelineStart: start,
        laneIndex: lane,
      );

  Future<void> pumpTimeline(
    WidgetTester tester, {
    List<AudioTrackModel> audios = const [],
    List<TextOverlayModel> texts = const [],
    List<ImageOverlayModel> images = const [],
    List<VideoOverlayModel> videos = const [],
    String? selectedAudioId,
    String? selectedTextId,
    String? selectedImageId,
    String? selectedVideoId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        audioTracks: audios,
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
                audioTracks: audios,
                textOverlays: texts,
                imageOverlays: images,
                videoOverlays: videos,
                selectedAudioId: selectedAudioId,
                selectedTextId: selectedTextId,
                selectedImageId: selectedImageId,
                selectedVideoId: selectedVideoId,
                onTimelinePositionChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder audioBody() => find.byKey(const ValueKey('audio-clip:a'));
  Finder handle(String key) => find.byKey(ValueKey('handle:$key'));

  group('a selected audio clip', () {
    testWidgets('is framed in white', (tester) async {
      await pumpTimeline(tester, audios: [audio(2)], selectedAudioId: 'a');
      final box = tester.widget<Container>(audioBody()).decoration! as BoxDecoration;
      expect((box.border! as Border).top.color, AppColors.textPrimary);
    });

    testWidgets('has slim white handles', (tester) async {
      await pumpTimeline(tester, audios: [audio(2)], selectedAudioId: 'a');
      for (final side in ['start', 'end']) {
        final slab = tester.widget<AnimatedContainer>(handle('audio:a:$side'));
        expect((slab.decoration! as BoxDecoration).color, AppColors.textPrimary);
        expect(tester.getSize(handle('audio:a:$side')).width, lessThanOrEqualTo(8));
      }
    });

    testWidgets('has its handles just outside, touching it', (tester) async {
      await pumpTimeline(tester, audios: [audio(2)], selectedAudioId: 'a');
      final body = tester.getRect(audioBody());
      expect(tester.getRect(handle('audio:a:start')).right, closeTo(body.left, 0.5));
      expect(tester.getRect(handle('audio:a:end')).left, closeTo(body.right, 0.5));
    });
  });

  group('an item starting at 0:00 keeps its left handle inside', () {
    testWidgets('audio', (tester) async {
      await pumpTimeline(tester, audios: [audio(0)], selectedAudioId: 'a');
      final body = tester.getRect(audioBody());
      final start = tester.getRect(handle('audio:a:start'));
      expect(start.left, closeTo(body.left, 0.5));
      expect(start.width, lessThanOrEqualTo(8));
      expect(tester.getRect(handle('audio:a:end')).left, closeTo(body.right, 0.5),
          reason: 'the right handle is where it always was');
    });

    // The overlays' handles straddle their edge; at 0:00 the left one moves
    // in by half. 0:00 is measured from an audio clip there on another lane.
    Future<double> zeroX(WidgetTester tester) async =>
        tester.getRect(audioBody()).left;

    testWidgets('text', (tester) async {
      await pumpTimeline(
        tester,
        audios: [audio(0, lane: 1)],
        texts: [
          TextOverlayModel(
            id: 't',
            text: 'Hi',
            startTime: Duration.zero,
            endTime: const Duration(seconds: 3),
          ),
        ],
        selectedTextId: 't',
      );
      expect(tester.getRect(handle('text:t:start')).left,
          closeTo(await zeroX(tester), 0.5));
    });

    testWidgets('photo', (tester) async {
      await pumpTimeline(
        tester,
        audios: [audio(0, lane: 1)],
        images: [ImageOverlayModel(id: 'i', imagePath: '/i.png')],
        selectedImageId: 'i',
      );
      expect(tester.getRect(handle('image:i:start')).left,
          closeTo(await zeroX(tester), 0.5));
    });

    testWidgets('video', (tester) async {
      await pumpTimeline(
        tester,
        audios: [audio(0, lane: 1)],
        videos: [VideoOverlayModel(id: 'v', videoPath: '/v.mp4')],
        selectedVideoId: 'v',
      );
      expect(tester.getRect(handle('video:v:start')).left,
          closeTo(await zeroX(tester), 0.5));
    });

    testWidgets('away from 0:00 an overlay handle straddles its edge as before',
        (tester) async {
      await pumpTimeline(
        tester,
        audios: [audio(2, lane: 1)],
        texts: [
          TextOverlayModel(
            id: 't',
            text: 'Hi',
            startTime: const Duration(seconds: 2),
            endTime: const Duration(seconds: 5),
          ),
        ],
        selectedTextId: 't',
      );
      final start = tester.getRect(handle('text:t:start'));
      expect(start.center.dx, closeTo(await zeroX(tester), 0.5));
    });
  });
}
